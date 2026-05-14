import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/rss_service.dart';
import '../repositories/article_repository.dart';

class OpmlService {
  // ── Export ──────────────────────────────────────────────────────────────

  static String generateOpml({
    required List<Folder> folders,
    required List<Feed> feeds,
  }) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<opml version="2.0">');
    buf.writeln('  <head><title>Flash Feeds</title></head>');
    buf.writeln('  <body>');

    // Group feeds by folder
    final grouped = <int?, List<Feed>>{};
    for (final feed in feeds) {
      grouped.putIfAbsent(feed.folderId, () => []).add(feed);
    }

    // Feeds inside folders
    for (final folder in folders) {
      final folderFeeds = grouped[folder.id] ?? [];
      if (folderFeeds.isEmpty) continue;
      buf.writeln('    <outline text="${_esc(folder.name)}" title="${_esc(folder.name)}">');
      for (final feed in folderFeeds) {
        buf.writeln('      <outline type="rss"'
            ' text="${_esc(feed.title)}"'
            ' title="${_esc(feed.title)}"'
            ' xmlUrl="${_esc(feed.url)}"'
            '${feed.siteUrl != null ? ' htmlUrl="${_esc(feed.siteUrl!)}"' : ''}/>');
      }
      buf.writeln('    </outline>');
    }

    // Uncategorised feeds
    final uncategorised = feeds.where((f) {
      final folderIds = folders.map((fo) => fo.id).toSet();
      return !folderIds.contains(f.folderId);
    }).toList();
    for (final feed in uncategorised) {
      buf.writeln('    <outline type="rss"'
          ' text="${_esc(feed.title)}"'
          ' title="${_esc(feed.title)}"'
          ' xmlUrl="${_esc(feed.url)}"'
          '${feed.siteUrl != null ? ' htmlUrl="${_esc(feed.siteUrl!)}"' : ''}/>');
    }

    buf.writeln('  </body>');
    buf.writeln('</opml>');
    return buf.toString();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static Future<void> exportToFile({
    required List<Folder> folders,
    required List<Feed> feeds,
  }) async {
    final opml = generateOpml(folders: folders, feeds: feeds);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/flash_feeds.opml');
    await file.writeAsString(opml);
    await FilePicker.platform.saveFile(
      dialogTitle: 'Save OPML',
      fileName: 'flash_feeds.opml',
      bytes: file.readAsBytesSync(),
    );
  }

  // ── Import ──────────────────────────────────────────────────────────────

  /// Returns count of feeds actually added.
  static Future<int> importFromFile({
    required FolderRepository folderRepo,
    required FeedRepository feedRepo,
    required SettingsRepository settingsRepo,
    required ArticleRepository articleRepo,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return -1;

    final bytes = result.files.first.bytes;
    if (bytes == null) return -1;
    final content = String.fromCharCodes(bytes);

    // Parse outlines
    final entries = _parseOpml(content);
    if (entries.isEmpty) return 0;

    final rssService = RssService(articleRepo, feedRepo);
    int added = 0;

    for (final entry in entries) {
      final url = entry['xmlUrl'];
      if (url == null || url.isEmpty) continue;

      // Validate feed
      final info = await rssService.validateFeedUrl(url);
      if (info == null) continue;

      // Ensure folder exists if specified
      int? folderId;
      if (entry['folder'] != null && entry['folder']!.isNotEmpty) {
        final existing = await folderRepo.getAll();
        final match = existing.where((f) => f.name == entry['folder']).firstOrNull;
        if (match != null) {
          folderId = match.id!;
        } else {
          final now = DateTime.now().millisecondsSinceEpoch;
          final pos = await folderRepo.getNextPosition();
          final folder = await folderRepo.insert(
            Folder(name: entry['folder']!, position: pos, createdAt: now),
          );
          folderId = folder.id!;
        }
      }

      if (folderId == null) {
        // Use first folder or create default
        final existing = await folderRepo.getAll();
        if (existing.isNotEmpty) {
          folderId = existing.first.id!;
        } else {
          final now = DateTime.now().millisecondsSinceEpoch;
          final folder = await folderRepo.insert(
            Folder(name: 'My News', position: 0, createdAt: now),
          );
          folderId = folder.id!;
        }
      }

      // Check if feed already exists
      final allFeeds = await feedRepo.getAll();
      if (allFeeds.any((f) => f.url == url)) continue;

      final now = DateTime.now().millisecondsSinceEpoch;
      final folderFeeds = await feedRepo.getByFolder(folderId);
      final pos = folderFeeds.length;
      await feedRepo.insert(Feed(
        folderId: folderId,
        title: entry['text'] ?? info.title,
        url: url,
        siteUrl: info.siteUrl,
        position: pos,
        createdAt: now,
      ));
      added++;
    }

    return added;
  }

  static List<Map<String, String?>> _parseOpml(String opml) {
    final results = <Map<String, String?>>[];
    // Match folder outlines (with children)
    final folderPattern = RegExp(
      r'<outline\b([^>]*?)>\s*(.*?)\s*</outline>',
      dotAll: true,
      caseSensitive: false,
    );
    // Match leaf rss outlines
    final feedPattern = RegExp(
      r'<outline\b([^>]*?)/?>',
      caseSensitive: false,
    );

    String? attr(String attrs, String name) {
      final r = RegExp('$name="([^"]*)"', caseSensitive: false);
      return r.firstMatch(attrs)?.group(1);
    }

    // First, find folder outlines
    for (final folderMatch in folderPattern.allMatches(opml)) {
      final folderAttrs = folderMatch.group(1) ?? '';
      final folderName = attr(folderAttrs, 'text') ?? attr(folderAttrs, 'title');
      final inner = folderMatch.group(2) ?? '';
      for (final feedMatch in feedPattern.allMatches(inner)) {
        final attrs = feedMatch.group(1) ?? '';
        final xmlUrl = attr(attrs, 'xmlUrl');
        if (xmlUrl == null) continue;
        results.add({
          'xmlUrl': xmlUrl,
          'text': attr(attrs, 'text') ?? attr(attrs, 'title'),
          'folder': folderName,
        });
      }
    }

    // Then root-level feeds (not inside folders)
    // Strip folder sections to avoid double-counting
    final stripped = opml.replaceAll(folderPattern, '');
    for (final feedMatch in feedPattern.allMatches(stripped)) {
      final attrs = feedMatch.group(1) ?? '';
      final xmlUrl = attr(attrs, 'xmlUrl');
      if (xmlUrl == null) continue;
      results.add({
        'xmlUrl': xmlUrl,
        'text': attr(attrs, 'text') ?? attr(attrs, 'title'),
        'folder': null,
      });
    }

    return results;
  }
}
