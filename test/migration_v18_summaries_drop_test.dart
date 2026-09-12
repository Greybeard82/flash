// The v17 -> v18 removal of `article_summaries` and three dead settings keys.
//
// `article_summaries` was built by every `_onCreate` since v1 and written to
// by nothing. Summaries are generated on demand and cached in memory for the
// session, deliberately: re-reading a stored summary of an article the
// publisher has since edited is worse than spending a second regenerating it.
// So the table is an empty shape that every future `articles` rebuild would
// have had to tiptoe around, because it carried
// `article_id REFERENCES articles(id) ON DELETE CASCADE`.
//
// The three settings keys are the same species as v17's Drive keys: rows with
// no reader left in `AppSettings.fromMap`. `feedly_api_key` dates from when
// Feedly search was thought to need one; the two `auto_mark_read_at_bottom`
// keys belong to a setting replaced by mark-read-on-scroll.
//
// What this suite is really guarding is the pair of statements that have to
// agree and are written in two places: the migration (for devices that
// upgrade) and `_onCreate`/`defaultSettings` (for devices that install fresh).
// Change one and forget the other and half your users get a different
// database. The last test asserts the two are equal rather than checking
// either against a hand-written list, so it fails whichever half drifts.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';

/// The three keys v18 deletes.
const _deadKeys = [
  'feedly_api_key',
  'auto_mark_read_at_bottom',
  'auto_mark_read_at_bottom_seconds',
];

/// `article_summaries` as it stood before v18, declared locally because it is
/// no longer part of the schema.
const String _createArticleSummaries = '''
  CREATE TABLE article_summaries (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id   INTEGER NOT NULL UNIQUE REFERENCES articles(id) ON DELETE CASCADE,
    summary      TEXT    NOT NULL,
    model        TEXT    NOT NULL,
    generated_at INTEGER NOT NULL
  )
''';

Future<Database> _freshDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  return AppDatabase.instance.database;
}

/// Reshapes a freshly-created v18 database back into a v17 one.
///
/// `_onCreate` builds at the current version, so without this the v18 step
/// only ever exercises its own idempotency — a DROP and a DELETE that match
/// nothing always "pass". Same trick as `_reshapeToV16` in
/// migration_v17_drive_keys_test.dart, and it is the whole reason this suite
/// can tell a working migration from an absent one.
Future<void> _reshapeToV17(Database db) async {
  await db.execute(_createArticleSummaries);
  const values = {
    'feedly_api_key': 'null',
    'auto_mark_read_at_bottom': 'true',
    'auto_mark_read_at_bottom_seconds': '5',
  };
  for (final e in values.entries) {
    await db.insert(
      TableNames.settings,
      {'key': e.key, 'value': e.value, 'updated_at': 1750000000000},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

Future<bool> _hasTable(Database db, String name) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  );
  return rows.isNotEmpty;
}

Future<Set<String>> _settingsKeys(Database db) async {
  final rows = await db.query(TableNames.settings, columns: ['key']);
  return {for (final r in rows) r['key'] as String};
}

Future<Set<String>> _tables(Database db) async {
  final rows =
      await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
  return {for (final r in rows) r['name'] as String};
}

void main() {
  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('upgrading from v17', () {
    test('the table is dropped and the three keys are deleted', () async {
      final db = await _freshDatabase();
      await _reshapeToV17(db);

      // Pre-conditions. Without these the test would pass against a database
      // that never held either, which is exactly the false green worth
      // avoiding.
      expect(await _hasTable(db, 'article_summaries'), isTrue);
      expect(await _settingsKeys(db), containsAll(_deadKeys));

      await AppDatabase.instance.migrateForTesting(fromVersion: 17);

      expect(await _hasTable(db, 'article_summaries'), isFalse,
          reason: 'the table survived the migration');
      final keys = await _settingsKeys(db);
      for (final key in _deadKeys) {
        expect(keys, isNot(contains(key)),
            reason: '$key survived the migration');
      }
    });

    test('everything else is left alone', () async {
      final db = await _freshDatabase();
      await _reshapeToV17(db);

      // A library either side of the things being removed: real user data in
      // the tables, and ordinary settings rows. If the DROP or the DELETE is
      // ever widened, these are what it takes with it.
      final folderId = await db.insert(TableNames.folders,
          {'name': 'World News', 'position': 0, 'created_at': 1750000000000});
      final feedId = await db.insert(TableNames.feeds, {
        'folder_id': folderId,
        'title': 'BBC',
        'url': 'https://bbc.example/rss',
        'position': 0,
        'created_at': 1750000000000,
      });
      await db.insert(TableNames.articles, {
        'feed_id': feedId,
        'guid': 'g1',
        'title': 'A headline',
        'url': 'https://bbc.example/1',
        'published_at': 1750000000000,
        'fetched_at': 1750000000000,
        'is_read': 0,
        'is_saved': 1,
      });
      await db.insert(TableNames.keywordBlocklist,
          {'keyword': 'sponsored', 'whole_word': 0, 'created_at': 1750000000000});

      final tablesBefore = await _tables(db);
      await AppDatabase.instance.migrateForTesting(fromVersion: 17);

      expect((await db.query(TableNames.folders)).single['name'], 'World News');
      expect((await db.query(TableNames.feeds)).single['title'], 'BBC');
      final article = (await db.query(TableNames.articles)).single;
      expect(article['guid'], 'g1');
      expect(article['is_saved'], 1,
          reason: 'a bookmark is the row a user would miss most');
      expect((await db.query(TableNames.keywordBlocklist)).single['keyword'],
          'sponsored');

      // Values, not just presence — a migration that emptied a row it kept
      // would pass a key-set check and still wipe the user's theme.
      final theme = await db.query(TableNames.settings,
          where: 'key = ?', whereArgs: ['theme']);
      expect(theme.single['value'], 'system');

      expect(await _tables(db), tablesBefore.difference({'article_summaries'}),
          reason: 'exactly one table goes, and no table arrives');
    });

    test('running it twice changes nothing the second time', () async {
      // Not idle: `DROP TABLE IF EXISTS` and a `DELETE` that matches nothing
      // both have to be no-ops, because a device can be handed the same
      // migration again after an interrupted upgrade.
      final db = await _freshDatabase();
      await _reshapeToV17(db);
      await AppDatabase.instance.migrateForTesting(fromVersion: 17);
      final after = await _tables(db);
      final keys = await _settingsKeys(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 17);

      expect(await _tables(db), after);
      expect(await _settingsKeys(db), keys);
    });
  });

  group('a fresh install', () {
    test('never builds the table and never seeds the keys', () async {
      final db = await _freshDatabase();

      expect(await _hasTable(db, 'article_summaries'), isFalse,
          reason: '_onCreate still builds a table v18 exists to remove');
      final keys = await _settingsKeys(db);
      for (final key in _deadKeys) {
        expect(keys, isNot(contains(key)),
            reason: '$key is still in defaultSettings');
      }
    });

    test('holds exactly the same shape as an upgraded database', () async {
      // The invariant, both ways, and deliberately not against a literal
      // list: this is what catches a seed-list or _onCreate edit drifting
      // from the migration in either direction.
      final fresh = await _freshDatabase();
      final freshTables = await _tables(fresh);
      final freshKeys = await _settingsKeys(fresh);
      await AppDatabase.instance.close();

      final upgraded = await _freshDatabase();
      await _reshapeToV17(upgraded);
      await AppDatabase.instance.migrateForTesting(fromVersion: 17);

      expect(await _tables(upgraded), equals(freshTables));
      expect(await _settingsKeys(upgraded), equals(freshKeys));
    });
  });
}
