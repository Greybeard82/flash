// The v16 -> v17 removal of the three Google Drive / Google Sign-In settings
// keys.
//
// Drive backup is gone: it duplicated a strict subset of what Android Auto
// Backup already restores from `flash.db`, and it dragged an OAuth consent
// screen — and therefore brand verification and a verified homepage domain —
// behind it. `drive_backup_enabled`, `drive_last_backup_at` and
// `google_account_email` lost their last reader when AppSettings.fromMap
// stopped parsing them, so on every device that ever ran v3-v16 they are three
// rows nothing will ever look at again.
//
// The failure this suite exists to catch is divergence. A seed-list edit and a
// migration are two separate statements of the same fact, and nothing forces
// them to agree — delete the rows from `defaultSettings` and forget the
// migration and an upgraded device keeps them forever; write the migration and
// forget the seed list and a fresh install re-creates what the migration just
// removed. The third test asserts the two key sets are equal rather than
// checking either one against a hand-written list, so it fails whichever half
// drifts.
//
// The second test is the guard against the obvious shortcut. A
// `LIKE 'google%'` or `LIKE 'drive%'` sweep would read as tidier and would be
// one typo away from taking `feedly_api_key` — or anything added later that
// happens to share a prefix — with it. The migration names three keys and the
// test pins that it named exactly three.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';

/// The three keys v17 deletes.
const _driveKeys = [
  'drive_backup_enabled',
  'drive_last_backup_at',
  'google_account_email',
];

Future<Database> _freshDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  return AppDatabase.instance.database;
}

/// Reshapes the freshly-created v17 database back to v16 so the migration has
/// real work to do.
///
/// `_onCreate` builds at the current version, so without this the v17 step only
/// ever exercises its own idempotency — a DELETE that matches nothing always
/// "passes". Same trick as `_reshapeToV10` in audit_schema_integrity_test.dart,
/// and it is the whole reason these tests can tell a working migration from an
/// absent one.
/// [ConflictAlgorithm.replace] so this stays honest while the seed list still
/// carries the keys — a reshape that threw on a duplicate key would make the
/// suite red for the wrong reason.
Future<void> _reshapeToV16(Database db) async {
  const values = {
    'drive_backup_enabled': 'true',
    'drive_last_backup_at': '1750000000000',
    'google_account_email': 'someone@example.com',
  };
  for (final e in values.entries) {
    await db.insert(
      TableNames.settings,
      {'key': e.key, 'value': e.value, 'updated_at': 1750000000000},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

Future<Set<String>> _settingsKeys(Database db) async {
  final rows = await db.query(TableNames.settings, columns: ['key']);
  return {for (final r in rows) r['key'] as String};
}

void main() {
  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('the three Drive keys are gone, and the rest of settings is not',
      () async {
    final db = await _freshDatabase();
    await _reshapeToV16(db);

    // Pre-condition: without this the test would pass against a database that
    // never held the keys, which is exactly the false green worth avoiding.
    expect(await _settingsKeys(db), containsAll(_driveKeys));

    await AppDatabase.instance.migrateForTesting(fromVersion: 16);

    final keys = await _settingsKeys(db);
    for (final key in _driveKeys) {
      expect(keys, isNot(contains(key)), reason: '$key survived the migration');
    }

    // Three ordinary settings the user can see the effect of. If the DELETE is
    // ever widened, these are what it takes with it.
    expect(keys, containsAll(['theme', 'refresh_interval_minutes', 'color_palette']));

    // Values, not just presence — a migration that emptied a row it kept would
    // pass a key-set check and still wipe the user's theme.
    final theme = await db.query(TableNames.settings,
        where: 'key = ?', whereArgs: ['theme']);
    expect(theme.single['value'], 'system');
    final interval = await db.query(TableNames.settings,
        where: 'key = ?', whereArgs: ['refresh_interval_minutes']);
    expect(interval.single['value'], '180');
  });

  test('feedly_api_key survives — the migration names keys, it does not sweep',
      () async {
    final db = await _freshDatabase();
    await _reshapeToV16(db);

    // It sits between drive_last_backup_at and google_account_email in the seed
    // list, and it is unused, so it is the row a careless wildcard is likeliest
    // to reach and the least likely to be missed by hand.
    expect(await _settingsKeys(db), contains('feedly_api_key'));

    await AppDatabase.instance.migrateForTesting(fromVersion: 16);

    expect(await _settingsKeys(db), contains('feedly_api_key'));
  });

  test('an upgraded database and a fresh install hold the same key set',
      () async {
    // Fresh v17: whatever defaultSettings seeds today.
    final fresh = await _freshDatabase();
    final freshKeys = await _settingsKeys(fresh);
    await AppDatabase.instance.close();

    // v16 reshaped and walked forward through the real _onUpgrade path.
    final upgraded = await _freshDatabase();
    await _reshapeToV16(upgraded);
    await AppDatabase.instance.migrateForTesting(fromVersion: 16);
    final upgradedKeys = await _settingsKeys(upgraded);

    // Equality both ways, and deliberately not against a literal list: this is
    // the invariant, and it catches a seed-list edit that drifts from the
    // migration in either direction.
    expect(upgradedKeys, equals(freshKeys));
    for (final key in _driveKeys) {
      expect(freshKeys, isNot(contains(key)),
          reason: '$key is still seeded on a fresh install');
    }
  });
}
