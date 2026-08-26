// Regression cover for audit finding A1.
//
// database.dart used to open the DB at version 8 while schema.dart seeded a
// `schema_version` settings row reading '3' (and the oldVersion < 5 migration
// rewrote it to '3' too). Nothing ever read the row, so it was a second,
// permanently-wrong answer to "what schema is this database on", sitting
// right next to the real one.
//
// The row is now deleted by the v9 migration and no longer seeded. PRAGMA
// user_version is the single source of truth.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/repositories/settings_repository.dart';

/// Kept in sync by hand with the `version:` passed to openDatabase in
/// database.dart. Bump both together when adding a migration.
const int kExpectedSchemaVersion = 13;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
}

/// Reshapes the freshly-created current-version database back to v10 so the
/// migration chain under test has real work to do.
///
/// [AppDatabase.migrateForTesting] runs `_onUpgrade` against a database
/// `_onCreate` has already built at the current version, so without this the
/// steps only ever exercise their own idempotency guards — worth testing, but
/// not the same thing as testing the upgrade.
///
/// Note there is no `read_at` to drop: v11 added it and v13 removed it again,
/// so a v10-shaped and a v13-shaped `articles` table agree on that column
/// being absent.
Future<void> _reshapeToV10(Database db) async {
  await db.execute('DROP TABLE IF EXISTS deleted_articles');
  await db.delete('settings', where: "key = 'show_read'");
  await db.delete('settings', where: "key = 'mark_all_read_confirm'");
}

Future<Set<String>> _articleColumns(Database db) async {
  final rows = await db.rawQuery('PRAGMA table_info(articles)');
  return {for (final r in rows) r['name'] as String};
}

Future<Set<String>> _articleIndexes(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'articles'",
  );
  return {for (final r in rows) r['name'] as String};
}

/// Articles carry a foreign key to feeds, and foreign_keys is ON.
Future<int> _seedFeed(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final folderId = await db.insert(
      'folders', {'name': 'Gaming', 'position': 0, 'created_at': now});
  return db.insert('feeds', {
    'folder_id': folderId,
    'title': 'Feed',
    'url': 'https://example.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': now,
  });
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  test('a fresh install reports the real schema version via PRAGMA user_version',
      () async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('PRAGMA user_version');
    expect(rows.first.values.first, kExpectedSchemaVersion);
  });

  test('a fresh install seeds no schema_version settings row', () async {
    await AppDatabase.instance.database;
    final stored = await SettingsRepository().get('schema_version');

    expect(
      stored,
      isNull,
      reason: 'the row duplicated PRAGMA user_version and had drifted '
          'permanently to "3". Nothing reads it; a second, always-wrong '
          'answer is worse than none. If it ever comes back it must track '
          'the real version, not a literal.',
    );
  });

  test('upgrading an existing v8 database drops the stale row', () async {
    // Build a v8-shaped settings table carrying the old row, then let the
    // real migration run against it.
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('settings', {
      'key': 'schema_version',
      'value': '3',
      'updated_at': now,
    });
    expect(await SettingsRepository().get('schema_version'), '3');

    await AppDatabase.instance.migrateForTesting(fromVersion: 8);

    expect(await SettingsRepository().get('schema_version'), isNull,
        reason: 'the v9 migration must clear the row for users upgrading, '
            'not just for fresh installs');
  });

  test('the v9 migration leaves every other table and setting intact',
      () async {
    final db = await AppDatabase.instance.database;
    final before = await SettingsRepository().get('theme');

    await AppDatabase.instance.migrateForTesting(fromVersion: 8);

    final rows = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final tables = rows.map((r) => r['name'] as String).toSet();

    for (final expected in [
      'folders',
      'feeds',
      'articles',
      'keyword_blocklist',
      'keyword_alerts',
      'article_summaries',
      'settings',
    ]) {
      expect(tables, contains(expected),
          reason: 'the v9 step only deletes one settings row; it must not '
              'disturb the schema');
    }
    expect(await SettingsRepository().get('theme'), before,
        reason: 'unrelated settings must survive the migration');
  });

  group('v10 → v13 in one hop', () {
    // This group used to assert that v11 added `read_at` and its index. It no
    // longer can: v13 removes both, so the end of the chain is the same shape
    // as its start for that column. What is still worth pinning is that a v10
    // database walked all the way forward lands correctly — the settings the
    // intermediate steps seed, and idempotency across the whole run.

    test('seeds show_read without a read_at column surviving', () async {
      final db = await AppDatabase.instance.database;
      await _reshapeToV10(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 10);

      expect(await SettingsRepository().get('show_read'), 'true');
      expect(await _articleColumns(db), isNot(contains('read_at')),
          reason: 'v11 adds it, v13 drops it again — a user upgrading from '
              'v10 in one hop must not be left carrying it');
      expect(await _articleIndexes(db), isNot(contains('idx_articles_read_at')));
    });

    test('an existing show_read choice survives the whole chain', () async {
      final db = await AppDatabase.instance.database;
      await _reshapeToV10(db);
      await SettingsRepository().set('show_read', 'false');

      await AppDatabase.instance.migrateForTesting(fromVersion: 10);

      expect(await SettingsRepository().get('show_read'), 'false',
          reason: 'INSERT OR IGNORE seeds a default; it must never overwrite '
              'a choice the user already made');
    });

    test('articles read before the upgrade are still there afterwards',
        () async {
      final db = await AppDatabase.instance.database;
      await _reshapeToV10(db);
      final feedId = await _seedFeed(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('articles', {
        'feed_id': feedId,
        'guid': 'g1',
        'title': 'Read before the upgrade',
        'url': 'https://example.com/1',
        'published_at': now,
        'fetched_at': now,
        'is_read': 1,
        'is_blocked': 0,
        'is_saved': 0,
      });

      await AppDatabase.instance.migrateForTesting(fromVersion: 10);

      final rows = await db.query('articles', columns: ['is_read']);
      expect(rows.length, 1,
          reason: 'no migration step may destroy the user\'s library');
      expect(rows.first['is_read'], 1);
    });

    test('re-running the whole chain is a no-op', () async {
      final db = await AppDatabase.instance.database;
      await _reshapeToV10(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 10);
      await AppDatabase.instance.migrateForTesting(fromVersion: 10);

      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'deleted_articles'"))
          .length;
      expect(tables, 1);
      expect(await SettingsRepository().get('show_read'), 'true');
    });
  });

  group('v12 → v13 (retirement)', () {
    /// Reshapes a fresh v13 database back to v12: read_at present, no
    /// tombstone table, no mark_all_read_confirm.
    Future<void> reshapeToV12(Database db) async {
      await db.execute('DROP TABLE IF EXISTS deleted_articles');
      final cols = await _articleColumns(db);
      if (!cols.contains('read_at')) {
        await db.execute('ALTER TABLE articles ADD COLUMN read_at INTEGER');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_articles_read_at ON articles(read_at)');
      }
      await db.delete('settings', where: "key = 'mark_all_read_confirm'");
    }

    test('creates the tombstone table and both its indexes', () async {
      final db = await AppDatabase.instance.database;
      await reshapeToV12(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 12);

      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, contains('deleted_articles'));

      final indexes = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND tbl_name = 'deleted_articles'"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes, contains('idx_deleted_articles_guid_feed'));
      expect(indexes, contains('idx_deleted_articles_deleted_at'));
    });

    test('drops read_at and its index', () async {
      final db = await AppDatabase.instance.database;
      await reshapeToV12(db);
      expect(await _articleColumns(db), contains('read_at'));

      await AppDatabase.instance.migrateForTesting(fromVersion: 12);

      expect(await _articleColumns(db), isNot(contains('read_at')));
      expect(await _articleIndexes(db), isNot(contains('idx_articles_read_at')));
    });

    test('seeds mark_all_read_confirm', () async {
      final db = await AppDatabase.instance.database;
      await reshapeToV12(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 12);

      expect(await SettingsRepository().get('mark_all_read_confirm'), 'true');
    });

    test('an existing mark_all_read_confirm choice is not overwritten',
        () async {
      final db = await AppDatabase.instance.database;
      await reshapeToV12(db);
      await SettingsRepository().set('mark_all_read_confirm', 'false');

      await AppDatabase.instance.migrateForTesting(fromVersion: 12);

      expect(await SettingsRepository().get('mark_all_read_confirm'), 'false',
          reason: 'INSERT OR IGNORE seeds a default; it must never overwrite '
              'a choice the user already made');
    });

    test('articles already read are NOT retired by the migration', () async {
      final db = await AppDatabase.instance.database;
      await reshapeToV12(db);
      final feedId = await _seedFeed(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('articles', {
        'feed_id': feedId,
        'guid': 'read-before-upgrade',
        'title': 'Read before the upgrade',
        'url': 'https://example.com/1',
        'published_at': now,
        'fetched_at': now,
        'is_read': 1,
        'is_blocked': 0,
        'is_saved': 0,
      });

      await AppDatabase.instance.migrateForTesting(fromVersion: 12);

      final rows = await db.query('articles', columns: ['guid', 'is_read']);
      expect(rows.length, 1,
          reason: 'a migration that silently destroys several hundred '
              'articles on first launch is indistinguishable from a bug. The '
              'first refresh retires them through the normal path instead.');
      expect(rows.first['is_read'], 1);

      final tombstones = await db.query('deleted_articles');
      expect(tombstones, isEmpty,
          reason: 'nothing was retired, so nothing is tombstoned');
    });

    test('re-running the migration is a no-op', () async {
      final db = await AppDatabase.instance.database;
      await reshapeToV12(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 12);
      await AppDatabase.instance.migrateForTesting(fromVersion: 12);

      expect(await _articleColumns(db), isNot(contains('read_at')));
      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'deleted_articles'"))
          .length;
      expect(tables, 1,
          reason: 'CREATE TABLE IF NOT EXISTS and the PRAGMA guard both have '
              'to hold, or an interrupted upgrade throws on the retry');
    });
  });

  group('v11 → v12 (dead Anthropic key)', () {
    test('drops the settings row for upgrading users', () async {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('settings', {
        'key': 'anthropic_api_key_set',
        'value': 'true',
        'updated_at': now,
      });
      expect(await SettingsRepository().get('anthropic_api_key_set'), 'true');

      await AppDatabase.instance.migrateForTesting(fromVersion: 11);

      expect(await SettingsRepository().get('anthropic_api_key_set'), isNull,
          reason: 'a fresh install no longer seeds it; upgrading users must '
              'lose it too, or the row survives as a second stale answer the '
              'way schema_version did');
    });

    test('a fresh install does not seed it', () async {
      await AppDatabase.instance.database;
      expect(await SettingsRepository().get('anthropic_api_key_set'), isNull);
    });

    test('unrelated settings survive', () async {
      final before = await SettingsRepository().get('show_read');
      await AppDatabase.instance.migrateForTesting(fromVersion: 11);
      expect(await SettingsRepository().get('show_read'), before);
    });
  });
}
