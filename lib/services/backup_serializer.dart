import '../db/database.dart';
import '../db/schema.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../models/keyword_block.dart';
import '../services/feeds_changed_notifier.dart';

class BackupSerializer {
  /// Serialises folders, feeds and keywords to the shared Flash backup format.
  static Map<String, dynamic> toMap({
    required List<Folder> folders,
    required List<Feed> feeds,
    required List<KeywordBlock> keywords,
  }) {
    final folderMap = {for (final f in folders) f.id!: f.name};
    return {
      'version': 1,
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
    if ((data['version'] as int?) != 1) {
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
      // Wipe existing — folder cascade deletes feeds + articles via FK.
      await txn.delete(TableNames.folders);
      await txn.delete(TableNames.feeds);
      await txn.delete(TableNames.keywordBlocklist);

      final nameToId = <String, int>{};
      for (final f in (data['folders'] as List)) {
        final folder = Folder(
          name: f['name'] as String,
          position: f['position'] as int? ?? 0,
          createdAt: now,
        );
        final id = await txn.insert(TableNames.folders, folder.toMap());
        nameToId[folder.name] = id;
      }

      var inserted = 0;
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
        await txn.insert(TableNames.feeds, feed.toMap());
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

      return inserted;
    });

    // The repository writes this replaced each pinged on their own; fire once
    // here instead, after the commit, so the feed screen re-queries a library
    // that actually exists.
    FeedsChangedNotifier.instance.structureChanged();
    return feedCount;
  }
}
