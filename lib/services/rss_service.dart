import 'package:dart_rss/dart_rss.dart';
import 'package:http/http.dart' as http;
import '../models/article.dart';
import '../models/feed.dart';
import '../models/keyword_block.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import '../utils/html_utils.dart';

class RssService {
  final ArticleRepository _articleRepo;
  final FeedRepository _feedRepo;
  final SettingsRepository _settingsRepo;

  RssService(this._articleRepo, this._feedRepo, this._settingsRepo);

  Future<({Feed feed, int newCount})> fetchAndStore(
    Feed feed, {
    List<KeywordBlock> keywords = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final response = await http.get(Uri.parse(feed.url)).timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body = response.body;
      var articles = _parse(body, feed);

      if (keywords.isNotEmpty) {
        articles = articles.map((a) {
          final match = KeywordRepository.findMatch(a.title, a.description, keywords);
          if (match != null) return a.copyWith(isBlocked: true, blockedKeyword: match.keyword);
          return a;
        }).toList();
      }

      await _articleRepo.insertMany(articles);

      // Auto-cleanup
      final globalLimit = int.tryParse(
              await _settingsRepo.get('article_limit') ?? '100') ??
          100;
      final effectiveLimit = feed.articleLimit ?? globalLimit;
      await _articleRepo.runAutoCleanup(feed.id!, effectiveLimit);

      final updatedFeed = feed.copyWith(
        lastFetchedAt: now,
        lastFetchError: null,
        consecutiveFailures: 0,
        isDead: false,
      );
      await _feedRepo.updateFetchResult(
        feedId: feed.id!,
        lastFetchedAt: now,
        lastFetchError: null,
        consecutiveFailures: 0,
        isDead: false,
      );
      return (feed: updatedFeed, newCount: articles.length);
    } catch (e) {
      final failures = feed.consecutiveFailures + 1;
      final isDead = failures >= 7;
      await _feedRepo.updateFetchResult(
        feedId: feed.id!,
        lastFetchedAt: feed.lastFetchedAt,
        lastFetchError: e.toString(),
        consecutiveFailures: failures,
        isDead: isDead,
      );
      return (
        feed: feed.copyWith(
          consecutiveFailures: failures,
          lastFetchError: e.toString(),
          isDead: isDead,
        ),
        newCount: 0
      );
    }
  }

  List<Article> _parse(String body, Feed feed) {
    // Try RSS 2.0 first
    try {
      final channel = RssFeed.parse(body);
      if (channel.items.isNotEmpty) {
        return _fromRssItems(channel.items, feed);
      }
    } catch (_) {}

    // Fallback to Atom
    try {
      final atom = AtomFeed.parse(body);
      if (atom.items.isNotEmpty) {
        return _fromAtomItems(atom.items, feed);
      }
    } catch (_) {}

    return [];
  }

  List<Article> _fromRssItems(List<RssItem> items, Feed feed) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final articles = <Article>[];
    for (final item in items) {
      final guid = item.guid ?? item.link ?? '';
      if (guid.isEmpty) continue;

      final thumbnailUrl = _extractRssThumbnail(item);
      final publishedAt = item.pubDate != null
          ? _parseDate(item.pubDate!)?.millisecondsSinceEpoch
          : null;

      articles.add(Article(
        feedId: feed.id!,
        guid: guid,
        title: stripHtml(item.title),
        url: item.link ?? '',
        description: stripHtml(item.description),
        thumbnailUrl: thumbnailUrl,
        publishedAt: publishedAt,
        fetchedAt: now,
      ));
    }
    return articles;
  }

  List<Article> _fromAtomItems(List<AtomItem> items, Feed feed) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final articles = <Article>[];
    for (final item in items) {
      final guid = item.id ?? '';
      if (guid.isEmpty) continue;

      final url = item.links.isNotEmpty ? item.links.first.href ?? '' : '';
      final publishedAt = item.published != null
          ? _parseDate(item.published!)?.millisecondsSinceEpoch
          : item.updated != null
              ? _parseDate(item.updated!)?.millisecondsSinceEpoch
              : null;

      String? thumbnailUrl;
      if (item.media != null) {
        thumbnailUrl = item.media!.contents.isNotEmpty
            ? item.media!.contents.first.url
            : item.media!.thumbnails.isNotEmpty
                ? item.media!.thumbnails.first.url
                : null;
      }

      articles.add(Article(
        feedId: feed.id!,
        guid: guid,
        title: stripHtml(item.title),
        url: url,
        description: stripHtml(item.summary ?? item.content),
        thumbnailUrl: thumbnailUrl,
        publishedAt: publishedAt,
        fetchedAt: now,
      ));
    }
    return articles;
  }

  String? _extractRssThumbnail(RssItem item) {
    // media:content or media:thumbnail
    if (item.media != null) {
      if (item.media!.contents.isNotEmpty) {
        return item.media!.contents.first.url;
      }
      if (item.media!.thumbnails.isNotEmpty) {
        return item.media!.thumbnails.first.url;
      }
    }
    // enclosure
    if (item.enclosure?.url != null) {
      final mime = item.enclosure!.type ?? '';
      if (mime.startsWith('image/')) {
        return item.enclosure!.url;
      }
    }
    return null;
  }

  DateTime? _parseDate(String dateStr) {
    try {
      // Try RFC 822 / RFC 2822 (RSS pub dates)
      return _parseRfc822(dateStr);
    } catch (_) {}
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseRfc822(String s) {
    // Example: "Mon, 02 Jan 2006 15:04:05 -0700"
    // or "Mon, 02 Jan 2006 15:04:05 GMT"
    final months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final parts = s.trim().split(RegExp(r'[\s,]+'));
    if (parts.length < 6) return DateTime.tryParse(s);

    // [DayName,] DD Mon YYYY HH:MM:SS TZ
    int idx = 0;
    if (parts[0].endsWith(',') || RegExp(r'^[A-Za-z]{3},$').hasMatch(parts[0])) {
      idx = 1;
    }
    final day = int.tryParse(parts[idx]) ?? 1;
    final month = months[parts[idx + 1]] ?? 1;
    final year = int.tryParse(parts[idx + 2]) ?? 2000;
    final timeParts = parts[idx + 3].split(':');
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    final second = timeParts.length > 2 ? int.tryParse(timeParts[2]) ?? 0 : 0;

    return DateTime.utc(year, month, day, hour, minute, second);
  }

  /// Validate a URL is a parseable feed
  Future<({String title, String? siteUrl, String? description})?> validateFeedUrl(
      String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) return null;
      final body = response.body;

      try {
        final channel = RssFeed.parse(body);
        if (channel.title != null) {
          return (
            title: channel.title!,
            siteUrl: channel.link,
            description: channel.description,
          );
        }
      } catch (_) {}

      try {
        final atom = AtomFeed.parse(body);
        if (atom.title != null) {
          final siteUrl = atom.links.isNotEmpty ? atom.links.first.href : null;
          return (
            title: atom.title!,
            siteUrl: siteUrl,
            description: atom.subtitle,
          );
        }
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }
}
