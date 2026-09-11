import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../models/feed.dart';
import '../models/folder.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../utils/folder_matching.dart';
import 'favicon_service.dart';

/// One feed found in an OPML file, already resolved into the shape Flash
/// stores: a folder name, a title, and a fetchable URL.
///
/// Deliberately not a [Feed]: nothing here has an id or a position yet, and
/// the folder is a *name* rather than a foreign key, because the folder it
/// belongs to may not exist until the import runs.
@immutable
class OpmlFeedEntry {
  /// The top-level outline the feed sat under, or the caller's fallback name
  /// when it sat at the root. Never empty.
  final String folderName;
  final String title;
  final String xmlUrl;
  final String? siteUrl;

  const OpmlFeedEntry({
    required this.folderName,
    required this.title,
    required this.xmlUrl,
    this.siteUrl,
  });
}

/// The file was not usable as OPML.
///
/// A distinct type because the Settings screen has to tell "this file is not
/// an OPML document" (show the error banner, change nothing) apart from "this
/// OPML document contains no feeds" (also nothing to do, but not a failure)
/// and from a genuine I/O error.
class OpmlParseException implements Exception {
  final String message;
  const OpmlParseException(this.message);

  @override
  String toString() => 'OpmlParseException: $message';
}

/// What one import actually did.
class OpmlImportResult {
  final int feedsImported;
  final int foldersCreated;

  /// Feeds in the file that Flash already had. Not an error — the expected
  /// outcome of importing a file twice, or of importing a subset.
  final int skipped;

  /// Exactly the feeds this run inserted, for [OpmlService.warmFavicons].
  final List<Feed> addedFeeds;

  const OpmlImportResult({
    required this.feedsImported,
    required this.foldersCreated,
    required this.skipped,
    this.addedFeeds = const [],
  });
}

/// OPML 2.0 import and export.
///
/// The app claimed to support this for months and never did — the PRD listed
/// it under Shipped while nothing in `lib/` implemented it, and the support
/// site told people to export a file from their old reader and import it in
/// Settings, which was a dead end.
///
/// **Import merges, it never replaces.** Backup restore wipes and re-inserts,
/// which is correct for a backup: it is a snapshot of the whole library. An
/// OPML file is not a snapshot — it is another reader's export, or a subset,
/// or something hand-edited — so importing one must be additive or it silently
/// destroys whatever the user already had.
class OpmlService {
  final FeedRepository _feedRepo;
  final FolderRepository _folderRepo;
  final FaviconService _faviconService;

  OpmlService({
    FeedRepository? feedRepo,
    FolderRepository? folderRepo,
    FaviconService? faviconService,
  })  : _feedRepo = feedRepo ?? FeedRepository(),
        _folderRepo = folderRepo ?? FolderRepository(),
        _faviconService = faviconService ?? FaviconService();

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Reads [source] and returns every feed it describes, in document order.
  ///
  /// [fallbackFolderName] names the folder for feeds that sit at the root with
  /// no parent outline — a flat export, which is what a reader produces for an
  /// account with no folders. It is passed in rather than hardcoded because it
  /// is a localised string.
  ///
  /// Permissive about structure, strict about one thing: an outline is a feed
  /// if and only if it carries an `xmlUrl` that Flash can actually fetch.
  /// Every reader nests differently and each emits outlines that are not feeds
  /// (link bookmarks, text notes, empty folders), so structure cannot be
  /// trusted — but a feed Flash cannot fetch is worse than no feed at all,
  /// because it is stored, displayed, and permanently empty.
  ///
  /// Throws [OpmlParseException] on malformed XML or on a well-formed document
  /// that is not OPML.
  static List<OpmlFeedEntry> parse(
    String source, {
    required String fallbackFolderName,
  }) {
    if (source.trim().isEmpty) {
      throw const OpmlParseException('The file is empty.');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } on XmlException catch (e) {
      throw OpmlParseException('The file is not valid XML: ${e.message}');
    }

    final root = document.rootElement;
    if (root.name.local.toLowerCase() != 'opml') {
      throw OpmlParseException(
          'The file is ${root.name.local}, not an OPML document.');
    }

    final body = root.getElement('body');
    if (body == null) {
      throw const OpmlParseException('The OPML document has no <body>.');
    }

    final entries = <OpmlFeedEntry>[];
    // A feed URL already taken, so a file that lists the same feed under two
    // folders yields one entry rather than a duplicate the DB would reject.
    // First occurrence wins: the feed keeps the first folder it appeared
    // under rather than jumping to the last.
    final seen = <String>{};

    for (final top in body.findElements('outline')) {
      // Flash has one level of categories, so the folder is always the *top*
      // outline's name however deep the feed actually sits. Preserving deeper
      // structure would need a schema change, and dropping the feeds would be
      // worse than flattening them.
      final folderName = _outlineName(top) ?? fallbackFolderName;
      _collect(top, folderName, fallbackFolderName, entries, seen);
    }
    return entries;
  }

  /// Walks [outline] and everything under it, appending feeds to [entries].
  ///
  /// [folderName] is the name of the top-level ancestor, fixed by the caller
  /// and carried unchanged down the recursion — that is what makes three
  /// levels of nesting flatten to one.
  static void _collect(
    XmlElement outline,
    String folderName,
    String fallbackFolderName,
    List<OpmlFeedEntry> entries,
    Set<String> seen,
  ) {
    final url = outline.getAttribute('xmlUrl')?.trim() ?? '';
    if (_isFetchable(url) && seen.add(url)) {
      entries.add(OpmlFeedEntry(
        // A top-level outline that is itself a feed has no parent to name it.
        folderName: outline.parentElement?.name.local.toLowerCase() == 'body'
            ? fallbackFolderName
            : folderName,
        title: _feedTitle(outline, url),
        xmlUrl: url,
        siteUrl: _nonEmpty(outline.getAttribute('htmlUrl')),
      ));
    }

    for (final child in outline.findElements('outline')) {
      _collect(child, folderName, fallbackFolderName, entries, seen);
    }
  }

  /// `http` and `https` only.
  ///
  /// `feed://` is common in older exports and `ftp://` turns up occasionally;
  /// `RssService` fetches with `http.get`, so neither can ever produce an
  /// article. A relative URL cannot either.
  static bool _isFetchable(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  /// `title`, else `text`, else the URL's host.
  ///
  /// A nameless feed is still a feed, and showing its host beats showing a
  /// blank row the user cannot identify.
  static String _feedTitle(XmlElement outline, String url) {
    final named = _nonEmpty(outline.getAttribute('title')) ??
        _nonEmpty(outline.getAttribute('text'));
    if (named != null) return named;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }

  /// A folder outline's display name: `text`, else `title`, else null.
  ///
  /// The opposite precedence to a feed's, and deliberately: OPML folders are
  /// conventionally named by `text` (it is the attribute the spec requires on
  /// every outline), while `title` is the optional one readers add. Returning
  /// null hands the feed to the fallback folder rather than creating a
  /// category with no name.
  static String? _outlineName(XmlElement outline) =>
      _nonEmpty(outline.getAttribute('text')) ??
      _nonEmpty(outline.getAttribute('title'));

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  // ── Import ────────────────────────────────────────────────────────────────

  /// Writes [entries] into the database, merging with whatever is already
  /// there.
  ///
  /// Database writes only. No network — the fetch that fills the new feeds is
  /// the one `FeedScreen` already runs when it next becomes visible, triggered
  /// by the `FeedsChangedNotifier.feedAdded()` that `FeedRepository.insert`
  /// pings from inside. Same arrangement as the starter pack.
  Future<OpmlImportResult> importEntries(List<OpmlFeedEntry> entries) async {
    final existingFolders = await _folderRepo.getAll();

    var foldersCreated = 0;
    var feedsImported = 0;
    var skipped = 0;
    final addedFeeds = <Feed>[];

    // Folder name (matched) -> next free feed position in it. Read once per
    // folder rather than once per feed: a reused folder may already hold
    // feeds, and the imported ones go after them.
    final nextPosition = <int, int>{};

    for (final entry in entries) {
      // Reuse before create, by exactly the rule the starter pack uses.
      var folder = findFolderByName(existingFolders, entry.folderName);
      if (folder == null) {
        folder = await _folderRepo.insert(Folder(
          name: entry.folderName,
          // After everything already there, so an import never reshuffles a
          // list the user has arranged.
          position: await _folderRepo.getNextPosition(),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        existingFolders.add(folder);
        foldersCreated++;
      }

      final folderId = folder.id!;
      nextPosition[folderId] ??=
          (await _feedRepo.getByFolder(folderId)).length;

      // `feeds.url` is UNIQUE, so this is a correctness check — but the reason
      // it is a *skip* rather than a move is that the user may have filed this
      // feed somewhere of their own under a name of their own. An import must
      // not undo that.
      if (await _feedRepo.getByUrl(entry.xmlUrl) != null) {
        skipped++;
        continue;
      }

      final inserted = await _feedRepo.insert(Feed(
        folderId: folderId,
        title: entry.title,
        url: entry.xmlUrl,
        siteUrl: entry.siteUrl,
        position: nextPosition[folderId]!,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      nextPosition[folderId] = nextPosition[folderId]! + 1;
      addedFeeds.add(inserted);
      feedsImported++;
    }

    return OpmlImportResult(
      feedsImported: feedsImported,
      foldersCreated: foldersCreated,
      skipped: skipped,
      addedFeeds: addedFeeds,
    );
  }

  /// Fetches and caches a favicon per feed, best effort.
  ///
  /// Never awaited by a caller: an import of fifty feeds is fifty HTTP round
  /// trips, and making the user watch them finish before the banner appears
  /// would trade the import for some icons. Failures are swallowed — the
  /// monogram fallback covers a missing one.
  Future<void> warmFavicons(List<Feed> feeds) async {
    for (final feed in feeds) {
      if (feed.id == null) continue;
      try {
        final host = Uri.tryParse(feed.siteUrl ?? feed.url)?.host ?? '';
        if (host.isEmpty) continue;
        final path = await _faviconService.fetchAndCache(host, feed.id!);
        if (path != null) await _feedRepo.updateFaviconPath(feed.id!, path);
      } catch (_) {
        // Best effort, by design.
      }
    }
  }

  /// Opens the system file picker and imports the chosen file.
  ///
  /// Returns null when the user dismissed the picker — a deliberate act, not
  /// an error. Throws [OpmlParseException] when the file is not usable, which
  /// the caller turns into the error banner.
  ///
  /// [FileType.any] rather than an extension filter: Android's MIME mapping
  /// for `.opml` is unreliable — the Storage Access Framework frequently
  /// reports `application/octet-stream` or nothing at all — and a filter that
  /// greys out the file the user came to pick is worse than validating the
  /// content afterwards, which this does anyway.
  Future<OpmlImportResult?> importFromPicker({
    required String fallbackFolderName,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.first.path;
    if (path == null) {
      throw const OpmlParseException('Could not read the selected file.');
    }

    final String content;
    try {
      content = await File(path).readAsString(encoding: utf8);
    } catch (e) {
      throw OpmlParseException('Could not read the selected file: $e');
    }

    final entries = parse(content, fallbackFolderName: fallbackFolderName);
    return importEntries(entries);
  }

  // ── Export ────────────────────────────────────────────────────────────────

  /// The filename proposed to the system file picker.
  ///
  /// Date only, unlike `LocalBackupService.backupFileName`, which carries the
  /// time as well. That difference is deliberate: a backup is something you
  /// take repeatedly in one sitting — before and after a change you are unsure
  /// about — and a same-day collision there corrupts the file. An OPML export
  /// is a one-off you hand to another reader, so a date is enough to tell two
  /// apart, and a bare date reads better in the file manager.
  @visibleForTesting
  static String opmlFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'flash_feeds_'
        '${now.year}${two(now.month)}${two(now.day)}.opml';
  }

  /// Serialises the library as an OPML 2.0 document.
  ///
  /// One parent outline per folder in [folders]' order, each holding its feeds
  /// in theirs, so the document reads down the page the way the Categories
  /// screen reads down the screen.
  ///
  /// Every feed gets `text` *and* `title` carrying the same value: readers
  /// disagree about which they display, and emitting one leaves the feed
  /// nameless in half of them.
  static String buildOpml({
    required List<Folder> folders,
    required Map<int, List<Feed>> feedsByFolder,
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', nest: () {
      builder.attribute('version', '2.0');
      builder.element('head', nest: () {
        builder.element('title', nest: 'Flash feeds');
        builder.element('dateCreated',
            nest: DateTime.now().toUtc().toIso8601String());
      });
      builder.element('body', nest: () {
        for (final folder in folders) {
          builder.element('outline', nest: () {
            builder.attribute('text', folder.name);
            builder.attribute('title', folder.name);
            for (final feed in feedsByFolder[folder.id] ?? const <Feed>[]) {
              builder.element('outline', nest: () {
                builder.attribute('type', 'rss');
                builder.attribute('text', feed.title);
                builder.attribute('title', feed.title);
                builder.attribute('xmlUrl', feed.url);
                if (feed.siteUrl != null && feed.siteUrl!.isNotEmpty) {
                  builder.attribute('htmlUrl', feed.siteUrl!);
                }
              });
            }
          });
        }
      });
    });
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  /// Writes the library to a file the user chooses.
  ///
  /// Same mechanism as `LocalBackupService.exportBackup`, and for the same
  /// reason: `saveFile` with `bytes` goes through the Storage Access
  /// Framework's `ACTION_CREATE_DOCUMENT`, which is how a file is *saved*
  /// anywhere the user can reach. The share sheet is not that — `ACTION_SEND`
  /// targets apps that accept a file, and offers no way to simply keep one.
  ///
  /// Returns true when the file was written, false when the picker was
  /// dismissed.
  static Future<bool> exportToPicker({
    required List<Folder> folders,
    required Map<int, List<Feed>> feedsByFolder,
    String? dialogTitle,
  }) async {
    final xml = buildOpml(folders: folders, feedsByFolder: feedsByFolder);
    final bytes = Uint8List.fromList(utf8.encode(xml));

    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: opmlFileName(DateTime.now()),
      type: FileType.custom,
      allowedExtensions: ['opml'],
      bytes: bytes,
    );
    return path != null;
  }
}
