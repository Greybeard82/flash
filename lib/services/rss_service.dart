import 'dart:convert';
import 'package:dart_rss/dart_rss.dart';
import 'package:http/http.dart' as http;
import '../models/alert_match.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/keyword_alert.dart';
import '../models/keyword_block.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import '../repositories/keyword_repository.dart';
import '../utils/constants.dart';
import '../utils/html_utils.dart';

class RssService {
  final ArticleRepository _articleRepo;
  final FeedRepository _feedRepo;
  final AlertMatchRepository _alertMatchRepo = AlertMatchRepository();

  RssService(this._articleRepo, this._feedRepo);

  // ── GUID resolution ────────────────────────────────────────────────────────

  static String resolveGuid(String? feedGuid, String? articleUrl) {
    if (feedGuid != null && feedGuid.trim().isNotEmpty) return feedGuid.trim();
    if (articleUrl != null && articleUrl.trim().isNotEmpty) return articleUrl.trim();
    throw Exception('Article has no guid or url — discard');
  }

  // ── Fetch threshold filter ─────────────────────────────────────────────────

  /// Filters one feed's freshly-parsed articles down to what gets written to
  /// the database.
  ///
  /// [articleLimit] is the caller's *effective* cap for this feed — see
  /// [effectiveArticleLimit]. It used to be the hardcoded [kFetchArticleLimit],
  /// which is why the "Max articles per feed" setting appeared to do nothing:
  /// it was stored and displayed, but every feed kept 100 regardless.
  ///
  /// The age cutoff is still the hardcoded [kFetchDayLimit] and is deliberately
  /// left alone here — see the note on that constant.
  List<Article> applyFetchThresholds(
    List<Article> articles, {
    required int articleLimit,
  }) {
    final cutoffMs = DateTime.now()
        .subtract(const Duration(days: kFetchDayLimit))
        .millisecondsSinceEpoch;

    articles.sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));

    final accepted = <Article>[];
    for (final article in articles) {
      if (article.publishedAt == null) continue;
      if (article.publishedAt! < cutoffMs) break;
      if (accepted.length >= articleLimit) break;
      accepted.add(article);
    }
    return accepted;
  }

  /// The cap that actually applies to [feed]: its own override when set,
  /// otherwise the global "Max articles per feed" setting.
  ///
  /// `Feed.articleLimit` is currently never written by any screen, so in
  /// practice this always resolves to [globalLimit]. It is honoured anyway
  /// because the column exists and a value in it should mean something rather
  /// than being silently ignored.
  static int effectiveArticleLimit(Feed feed, int globalLimit) =>
      feed.articleLimit ?? globalLimit;

  // ── Fetch and store ────────────────────────────────────────────────────────

  Future<({Feed feed, int newCount, List<AlertMatch> newAlertMatches})>
      fetchAndStore(
    Feed feed, {
    List<KeywordBlock> keywords = const [],
    List<KeywordAlert> alerts = const [],
    required int articleLimit,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final response = await http.get(Uri.parse(feed.url)).timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      var articles = applyFetchThresholds(
        _parse(body, feed),
        articleLimit: effectiveArticleLimit(feed, articleLimit),
      );

      if (keywords.isNotEmpty) {
        articles = articles.map((a) {
          final match = KeywordRepository.findMatch(a.title, a.description, keywords);
          if (match != null) return a.copyWith(isBlocked: true, blockedKeyword: match.keyword);
          return a;
        }).toList();
      }

      // What insertArticles actually wrote as new this pass — not every
      // parsed-and-thresholded article, most of which are the feed re-serving
      // items it already offered on the last fetch. newCount and the alert
      // matches below both depend on this, which is what stops an alert
      // re-firing on the same article every refresh forever.
      final newArticles = await _articleRepo.insertArticles(feed.id!, articles);

      await _feedRepo.updateFetchResult(
        feedId: feed.id!,
        lastFetchedAt: now,
        lastFetchError: null,
        consecutiveFailures: 0,
        isDead: false,
      );

      // Alert matching runs *after* the insert, and the order is the whole
      // mechanism rather than an implementation detail: "genuinely new" is
      // something only insertArticles can answer, and it is the one thing
      // standing between a single notification per article and one per refresh
      // for as long as the feed keeps re-serving it. The article itself is not
      // touched — no keyword column, no auto-bookmark — because the match is
      // now its own row in `alert_matches`, which is what makes it survive
      // retirement and cleanup instead of needing is_saved to shelter it.
      //
      // Accepted limitation: applyFetchThresholds has already run above, so an
      // article dropped by the per-feed cap or the 7-day fetch window never
      // reaches this point and never produces an alert at all. The snapshot
      // protects a match from being deleted later; it cannot recover one that
      // was never made.
      final newAlertMatches = <AlertMatch>[];
      if (alerts.isNotEmpty) {
        // Only what the insert reports as actually written counts as new: it
        // is this list the notification planner fires on.
        newAlertMatches.addAll(await _alertMatchRepo.insertMatches(
            buildAlertCandidates(
                feed: feed, articles: articles, alerts: alerts, now: now)));
      }

      return (
        feed: feed.copyWith(
          lastFetchedAt: now,
          lastFetchError: null,
          consecutiveFailures: 0,
          isDead: false,
        ),
        newCount: newArticles.length,
        newAlertMatches: newAlertMatches,
      );
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
        newCount: 0,
        newAlertMatches: const <AlertMatch>[],
      );
    }
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  List<Article> _parse(String body, Feed feed) {
    try {
      final channel = RssFeed.parse(body);
      if (channel.items.isNotEmpty) return _fromRssItems(channel.items, feed);
    } catch (_) {}
    try {
      final atom = AtomFeed.parse(body);
      if (atom.items.isNotEmpty) return _fromAtomItems(atom.items, feed);
    } catch (_) {}
    return [];
  }

  List<Article> _fromRssItems(List<RssItem> items, Feed feed) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final articles = <Article>[];
    for (final item in items) {
      final String guid;
      try {
        guid = resolveGuid(item.guid, item.link);
      } catch (_) {
        continue;
      }
      final publishedAt = item.pubDate != null
          ? _parseDate(item.pubDate!)?.millisecondsSinceEpoch
          : null;
      articles.add(Article(
        feedId: feed.id!,
        guid: guid,
        title: stripHtml(item.title),
        url: item.link ?? '',
        description: stripHtml(item.description),
        thumbnailUrl: _extractRssThumbnail(item),
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
      final url = item.links.isNotEmpty ? item.links.first.href ?? '' : '';
      final String guid;
      try {
        guid = resolveGuid(item.id, url.isNotEmpty ? url : null);
      } catch (_) {
        continue;
      }
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
    if (item.media != null) {
      if (item.media!.contents.isNotEmpty) return item.media!.contents.first.url;
      if (item.media!.thumbnails.isNotEmpty) return item.media!.thumbnails.first.url;
    }
    if (item.enclosure?.url != null) {
      final mime = item.enclosure!.type ?? '';
      if (mime.startsWith('image/')) return item.enclosure!.url;
    }
    return null;
  }

  DateTime? _parseDate(String dateStr) {
    try {
      return _parseRfc822(dateStr);
    } catch (_) {}
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseRfc822(String s) {
    final months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final parts = s.trim().split(RegExp(r'[\s,]+'));
    if (parts.length < 6) return DateTime.tryParse(s);
    int idx = 0;
    if (int.tryParse(parts[0]) == null) idx = 1;
    final day = int.tryParse(parts[idx]) ?? 1;
    final month = months[parts[idx + 1]] ?? 1;
    final year = int.tryParse(parts[idx + 2]) ?? 2000;
    final timeParts = parts[idx + 3].split(':');
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    final second = timeParts.length > 2 ? int.tryParse(timeParts[2]) ?? 0 : 0;
    final utc = DateTime.utc(year, month, day, hour, minute, second);
    // The wall-clock fields above are in the feed's own zone; subtracting the
    // stated offset converts them to real UTC. Dropping the offset (as this
    // did before) skewed every non-UTC feed by up to ±14h, which reordered
    // articles against feeds in other zones and shifted their cleanup age.
    final offset = idx + 4 < parts.length ? _rfc822Offset(parts[idx + 4]) : null;
    return offset == null ? utc : utc.subtract(offset);
  }

  /// Parses an RFC-822 zone token: a numeric offset (`+0200`, `-0530`) or one
  /// of the named zones the spec allows. Returns null when the token is
  /// absent or unrecognised, in which case the timestamp is treated as UTC.
  static Duration? _rfc822Offset(String token) {
    final numeric = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(token);
    if (numeric != null) {
      final sign = numeric.group(1) == '-' ? -1 : 1;
      final hours = int.parse(numeric.group(2)!);
      final minutes = int.parse(numeric.group(3)!);
      return Duration(hours: sign * hours, minutes: sign * minutes);
    }
    const named = {
      'UT': 0, 'UTC': 0, 'GMT': 0, 'Z': 0,
      'EST': -5, 'EDT': -4, 'CST': -6, 'CDT': -5,
      'MST': -7, 'MDT': -6, 'PST': -8, 'PDT': -7,
    };
    final hours = named[token.toUpperCase()];
    return hours == null ? null : Duration(hours: hours);
  }

  // ── Feed validation ────────────────────────────────────────────────────────

  Future<({String title, String? siteUrl, String? description})?> validateFeedUrl(
    String url,
  ) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
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
          return (
            title: atom.title!,
            siteUrl: atom.links.isNotEmpty ? atom.links.first.href : null,
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

/// Every (article, keyword) pair in this batch that deserves an alert row.
///
/// Pulled out of [RssService.fetchAndStore] so the one rule it enforces can be
/// tested without an HTTP round trip: **the blocklist wins.** An alert firing
/// on an article the user asked to have hidden would be confusing, not
/// helpful. That used to be true only on this path — `getAlertMatches` and the
/// retroactive matcher both ignored `is_blocked`, so a blocked article was
/// hidden everywhere except the alerts panel. This rework settles it the same
/// way in every path: here, in [AlertMatchRepository.backfillKeyword], and in
/// the v16 migration.
///
/// One article can yield several rows — one per matching keyword — which is
/// the whole reason matches stopped being a single column on the article.
List<AlertMatch> buildAlertCandidates({
  required Feed feed,
  required List<Article> articles,
  required List<KeywordAlert> alerts,
  required int now,
}) {
  final candidates = <AlertMatch>[];
  for (final article in articles) {
    if (article.isBlocked) continue;
    for (final alert in KeywordAlertRepository.findAllMatches(
        article.title, article.description, alerts)) {
      candidates.add(AlertMatch(
        feedId: feed.id!,
        guid: article.guid,
        keyword: alert.keyword,
        title: article.title,
        url: article.url,
        description: article.description,
        thumbnailUrl: article.thumbnailUrl,
        thumbnailPath: article.thumbnailPath,
        // Feed identity is copied from the Feed in hand rather than joined
        // back later: the snapshot has to keep naming its source after the
        // feed is renamed, moved between folders, or deleted.
        feedTitle: feed.title,
        feedFaviconPath: feed.faviconPath,
        folderId: feed.folderId,
        publishedAt: article.publishedAt,
        matchedAt: now,
      ));
    }
  }
  return candidates;
}
