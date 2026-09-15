import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../db/database.dart';
import '../db/schema.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../theme/category_colors.dart' show kCategoryHueCount;
import '../models/article.dart';
import '../models/keyword_block.dart';
import '../services/feeds_changed_notifier.dart';

class BackupSerializer {
  /// The format this build writes.
  ///
  /// **2 adds `bookmarks`.** See [kSupportedVersions] for what it will read.
  static const int kFormatVersion = 2;

  /// Every version this build can restore.
  ///
  /// A v1 file is still perfectly restorable — it simply has no bookmarks —
  /// so refusing it would strand every backup taken before this change for no
  /// reason. Going the other way is the case that must fail loudly: an older
  /// build checks `version != 1` and throws "Not a valid Flash backup file",
  /// which is a clear refusal rather than a crash or a silent partial restore.
  /// That behaviour is why the version field earns its place, and why adding
  /// bookmarks had to bump it rather than just appear.
  static const Set<int> kSupportedVersions = {1, 2};

  /// Serialises folders, feeds, keywords and bookmarks to the backup format.
  ///
  /// **Bookmarks are stored by value, not by reference, and that is the whole
  /// design.** A bookmark written as (feed url, guid) restores nothing unless
  /// the feed still carries that article — and `kFetchDayLimit` is 7, so
  /// anything published more than a week before the restore is discarded at
  /// fetch time and never comes back. Since a backup is usually restored long
  /// after it was taken, a reference would restore an empty Bookmarks tab and
  /// look like data loss. Held by value, a bookmark survives regardless of
  /// what the feed is serving.
  static Map<String, dynamic> toMap({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
    List<Article> bookmarks = const [],
  }) {
    final folderMap = {for (final f in folders) f.id!: f.name};
    final feedUrlById = {for (final f in feeds) f.id!: f.url};
    return {
      'version': kFormatVersion,
      'backedUpAt': DateTime.now().millisecondsSinceEpoch,
      'folders': folders
          .map((f) => {'name': f.name, 'position': f.position})
          .toList(),
      'feeds': feeds
          .map((f) => {
                'title': f.title,
                'url': f.url,
                'folderName': folderMap[f.folderId] ?? '',
                'position': f.position,
                'siteUrl': f.siteUrl,
                'description': f.description,
              })
          .toList(),
      'keywords': keywords
          .map((k) => {'keyword': k.keyword, 'wholeWord': k.wholeWord})
          .toList(),
      // Read state is deliberately NOT here. It can only be stored by
      // reference — nobody is putting two thousand article bodies in a
      // backup — and a reference to an article the feed no longer serves
      // matches nothing. With kFetchDayLimit at 7, a backup restored a week
      // after it was taken matches exactly zero articles, while costing
      // roughly 119 bytes each: ~150-250 KB of file for a library of 1200-2000,
      // against ~4 KB for everything else in here. Measured, and reported to
      // David before it was left out.
      'bookmarks': bookmarks
          .map((a) => {
                'feedUrl': feedUrlById[a.feedId] ?? '',
                'guid': a.guid,
                'title': a.title,
                'url': a.url,
                'publishedAt': a.publishedAt,
                'description': a.description,
                'thumbnailUrl': a.thumbnailUrl,
              })
          .toList(),
    };
  }

  /// Throws [FormatException] unless [data] is a backup this version can
  /// actually restore.
  ///
  /// Checked before any deletion, and checked to the depth the restore loops
  /// read — not just that the keys exist. The previous version accepted
  /// `{"version":1,"folders":{},"feeds":{}}`, wiped the library, and only then
  /// threw on the cast. A backup file that fails validation must leave the
  /// user exactly as they were.
  ///
  /// The optional fields are type-checked too, not just the required ones:
  /// the loops read them through casts like `as int?` and `as String?`, which
  /// tolerate *null* but throw on a value of the wrong type. A `position` of
  /// `"0"` would have passed a null-only check and blown up mid-restore.
  static void validate(Map<String, dynamic> data) {
    if (!kSupportedVersions.contains(data['version'] as int?)) {
      throw const FormatException('Not a valid Flash backup file');
    }

    final folders = data['folders'];
    final feeds = data['feeds'];
    final keywords = data['keywords'];

    if (folders is! List || feeds is! List) {
      throw const FormatException('Backup file is malformed');
    }
    if (keywords != null && keywords is! List) {
      throw const FormatException('Backup file is malformed');
    }

    for (final f in folders) {
      if (f is! Map || f['name'] is! String) {
        throw const FormatException('Backup file has a malformed category');
      }
      if (f['position'] != null && f['position'] is! int) {
        throw const FormatException('Backup file has a malformed category');
      }
    }
    for (final f in feeds) {
      if (f is! Map || f['url'] is! String || f['title'] is! String) {
        throw const FormatException('Backup file has a malformed feed');
      }
      if (f['folderName'] != null && f['folderName'] is! String) {
        throw const FormatException('Backup file has a malformed feed');
      }
      if (f['siteUrl'] != null && f['siteUrl'] is! String) {
        throw const FormatException('Backup file has a malformed feed');
      }
      if (f['description'] != null && f['description'] is! String) {
        throw const FormatException('Backup file has a malformed feed');
      }
      if (f['position'] != null && f['position'] is! int) {
        throw const FormatException('Backup file has a malformed feed');
      }
    }
    for (final k in (keywords as List? ?? const [])) {
      if (k is! Map || k['keyword'] is! String) {
        throw const FormatException('Backup file has a malformed keyword');
      }
      if (k['wholeWord'] != null && k['wholeWord'] is! bool) {
        throw const FormatException('Backup file has a malformed keyword');
      }
    }

    // Absent in every v1 file, so its absence is not an error. Present and
    // wrong is, and it is checked to the depth the restore loop reads it —
    // the same lesson as the folders/feeds check above, which was written
    // after a file that validated and then threw mid-restore with the library
    // already deleted.
    final bookmarks = data['bookmarks'];
    if (bookmarks != null && bookmarks is! List) {
      throw const FormatException('Backup file is malformed');
    }
    for (final b in (bookmarks as List? ?? const [])) {
      if (b is! Map ||
          b['guid'] is! String ||
          b['title'] is! String ||
          b['url'] is! String) {
        throw const FormatException('Backup file has a malformed bookmark');
      }
      if (b['feedUrl'] != null && b['feedUrl'] is! String) {
        throw const FormatException('Backup file has a malformed bookmark');
      }
      if (b['publishedAt'] != null && b['publishedAt'] is! int) {
        throw const FormatException('Backup file has a malformed bookmark');
      }
    }
  }

  /// Wipes all existing folders/feeds/keywords then restores from [data].
  /// Returns the number of feeds imported.
  ///
  /// Two guarantees, and both matter because this is the app's only operation
  /// that destroys the whole library:
  ///
  /// 1. [validate] runs first and checks the payload to the depth the loops
  ///    below read it, so a malformed file is rejected before anything is
  ///    deleted.
  /// 2. The wipe and the re-insert share **one transaction**, so a failure
  ///    part-way — a constraint violation, a full disk, the process dying —
  ///    rolls back to the library the user already had rather than leaving
  ///    them with half of one.
  ///
  /// The SQL is inline rather than going through the repositories. The
  /// repositories each resolve `AppDatabase.instance.database`, which is a
  /// single shared connection: calling them inside `db.transaction` would
  /// queue their statements behind the very transaction that is waiting for
  /// them. Threading an optional transaction handle through every repository
  /// write would change six public signatures for the benefit of this one
  /// caller, so the statements live here instead and the models' own `toMap`
  /// keeps the column mapping single-sourced.
  static Future<int> restoreFromMap(Map<String, dynamic> data) async {
    validate(data);

    final db = await AppDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final feedCount = await db.transaction<int>((txn) async {
      // Read before the wipe: which feed id each alert snapshot is keyed to.
      //
      // `alert_matches` deliberately has no foreign key on feed_id, so it
      // survives the cascade below — that is the point of the table. But
      // feeds.id is AUTOINCREMENT, so a feed re-inserted from the backup comes
      // back under a *new* id, and the snapshot's identity is
      // (feed_id, guid, keyword). Left alone, every alert card would be
      // orphaned onto a feed that no longer exists and the next fetch of the
      // same feed would write a second, duplicate set of rows under the new id
      // — doubling the Alerts tab and re-notifying the user about articles
      // they were alerted about before the restore. feeds.url is UNIQUE, so it
      // is the stable identity to re-key through.
      final previousFeeds =
          await txn.query(TableNames.feeds, columns: ['id', 'url']);
      final oldFeedIdByUrl = {
        for (final row in previousFeeds) row['url'] as String: row['id'] as int,
      };

      // Wipe existing — folder cascade deletes feeds + articles via FK.
      await txn.delete(TableNames.folders);
      await txn.delete(TableNames.feeds);
      await txn.delete(TableNames.keywordBlocklist);

      final nameToId = <String, int>{};
      // Format version 1 carries no colour, and adding one would make every
      // existing backup file unreadable by an older build for no gain. So
      // restored categories are spread across the six hues by their order in
      // the file, the same one-time assignment the v19 migration makes for an
      // in-place upgrade.
      var folderOrdinal = 0;
      for (final f in (data['folders'] as List)) {
        final folder = Folder(
          name: f['name'] as String,
          position: f['position'] as int? ?? 0,
          createdAt: now,
          colorIndex: folderOrdinal++ % kCategoryHueCount,
        );
        final id = await txn.insert(TableNames.folders, folder.toMap());
        nameToId[folder.name] = id;
      }

      var inserted = 0;
      // Bookmarks are attached by feed url, the same stable identity the alert
      // re-keying above uses, because feeds.id is AUTOINCREMENT and every feed
      // comes back under a new one.
      final newFeedIdByUrl = <String, int>{};
      for (final f in (data['feeds'] as List)) {
        final folderName = f['folderName'] as String? ?? '';
        final folderId = nameToId[folderName];
        if (folderId == null) continue;
        final feed = Feed(
          folderId: folderId,
          title: f['title'] as String,
          url: f['url'] as String,
          siteUrl: f['siteUrl'] as String?,
          description: f['description'] as String?,
          position: f['position'] as int? ?? 0,
          createdAt: now,
        );
        final newFeedId = await txn.insert(TableNames.feeds, feed.toMap());
        newFeedIdByUrl[feed.url] = newFeedId;
        // Re-point this feed's alert snapshots at the id it came back under,
        // and at the folder it came back in — the snapshot's folder_id is what
        // mark-folder-read and folder scoping read. AUTOINCREMENT never reuses
        // an id, so newFeedId is greater than every id in oldFeedIdByUrl and
        // this can never collide with a feed that has not been re-keyed yet.
        final oldFeedId = oldFeedIdByUrl[feed.url];
        if (oldFeedId != null && oldFeedId != newFeedId) {
          await txn.update(
            TableNames.alertMatches,
            {'feed_id': newFeedId, 'folder_id': folderId},
            where: 'feed_id = ?',
            whereArgs: [oldFeedId],
          );
        }
        inserted++;
      }

      for (final k in (data['keywords'] as List? ?? const [])) {
        final keyword = KeywordBlock(
          keyword: k['keyword'] as String,
          wholeWord: k['wholeWord'] as bool? ?? false,
          createdAt: now,
        );
        await txn.insert(TableNames.keywordBlocklist, keyword.toMap());
      }

      // Bookmarks last, because they need the feeds to exist.
      //
      // Written as ordinary article rows with is_saved = 1, so the Bookmarks
      // tab, the reader and the saved-state notifier all see them with no
      // special case anywhere. `fetched_at` is now rather than the original,
      // which is honest: this is when this device got them.
      //
      // A bookmark whose feed is not in the backup is skipped rather than
      // invented — an article with no feed has nothing to open from and
      // nowhere to sit in the list.
      for (final b in (data['bookmarks'] as List? ?? const [])) {
        final feedId = newFeedIdByUrl[b['feedUrl'] as String? ?? ''];
        if (feedId == null) continue;
        await txn.insert(
          TableNames.articles,
          {
            'feed_id': feedId,
            'guid': b['guid'] as String,
            'title': b['title'] as String,
            'url': b['url'] as String,
            'description': b['description'] as String?,
            'thumbnail_url': b['thumbnailUrl'] as String?,
            'published_at': b['publishedAt'] as int?,
            'fetched_at': now,
            'is_read': 0,
            'is_saved': 1,
          },
          // The next refresh of the same feed will meet this guid again. The
          // article row is keyed (feed_id, guid) by a unique index, so an
          // ignore here would silently drop the incoming copy and a replace
          // would clear is_saved. Neither is wanted: this insert happens
          // first, and the fetch path's own upsert preserves is_saved.
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      return inserted;
    });

    // The repository writes this replaced each pinged on their own; fire once
    // here instead, after the commit, so the feed screen re-queries a library
    // that actually exists.
    FeedsChangedNotifier.instance.structureChanged();
    return feedCount;
  }
}
