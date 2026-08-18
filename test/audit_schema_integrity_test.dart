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
const int kExpectedSchemaVersion = 9;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
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
}
