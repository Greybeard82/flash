// The v18 -> v19 addition of `folders.color_index`.
//
// **This is v19, not the v18 the Quiet Ink brief asks for.** v18 shipped two
// days earlier — it drops `article_summaries` and three dead settings keys —
// so the number was already taken and already on devices. Re-using it would
// mean every install that had reached 18 never ran this step at all, which is
// the one failure mode a migration chain cannot recover from on its own.
//
// Why a column rather than a derivation. The hue shows up in three places at
// once (the row tick, the Categories block, the chip), so getting it from the
// category's name means every colour in the app reshuffles the first time
// someone renames one, and getting it from position means the same on every
// reorder. Worse, starter-pack names are resolved from ARB keys at seeding
// time and then become ordinary user data — "Tech" on an English device is
// "Technik" on a German one — so a name-derived rule gives two installs of the
// same pack different colours. A stored integer has none of those problems and
// buys a "change category colour" setting for free later.
//
// The backfill is `position % 6`: a one-time spread at migration, so an
// existing library comes out of the upgrade looking deliberate instead of
// showing six identical grey categories. It is emphatically NOT a rule — once
// assigned, the value is the category's own and reordering does not touch it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/theme/category_colors.dart';

/// The folders table as it stood at v18, without the colour column.
const String _createFoldersV18 = '''
  CREATE TABLE folders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT    NOT NULL,
    position   INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
''';

Future<Database> _freshDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  return AppDatabase.instance.database;
}

/// Reshapes a freshly-created v19 database back into a v18 one.
///
/// `_onCreate` builds at the current version, so without this the v19 step
/// only ever exercises its own idempotency — an ALTER guarded by a PRAGMA
/// check that finds the column already present always "passes".
///
/// Foreign keys are switched off around the rebuild because `feeds` references
/// `folders` with ON DELETE CASCADE, and dropping the parent table with
/// enforcement on would take every feed with it.
Future<void> _reshapeToV18(Database db, {required int folderCount}) async {
  await db.execute('PRAGMA foreign_keys = OFF');
  await db.execute('DROP TABLE IF EXISTS folders');
  await db.execute(_createFoldersV18);
  for (var i = 0; i < folderCount; i++) {
    await db.insert(TableNames.folders, {
      'name': 'Category $i',
      'position': i,
      'created_at': 1750000000000 + i,
    });
  }
  await db.execute('PRAGMA foreign_keys = ON');
}

Future<List<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return [for (final r in rows) r['name'] as String];
}

Future<List<Map<String, Object?>>> _folders(Database db) =>
    db.query(TableNames.folders, orderBy: 'position');

void main() {
  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('upgrading from v18', () {
    test('the column arrives', () async {
      final db = await _freshDatabase();
      await _reshapeToV18(db, folderCount: 3);

      // Pre-condition. Without it this would pass against a database that
      // already had the column, which is the false green worth avoiding.
      expect(await _columns(db, 'folders'), isNot(contains('color_index')));

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);

      expect(await _columns(db, 'folders'), contains('color_index'));
    });

    test('every existing category is spread across the six hues', () async {
      final db = await _freshDatabase();
      await _reshapeToV18(db, folderCount: 8);

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);

      final rows = await _folders(db);
      expect(rows, hasLength(8));
      for (final r in rows) {
        final position = r['position'] as int;
        expect(r['color_index'], position % kCategoryHueCount,
            reason: 'category at position $position should have taken hue '
                '${position % kCategoryHueCount}');
      }
    });

    test('the first six categories all get different hues', () async {
      // The point of the backfill. A DEFAULT 0 alone would leave an existing
      // library as six identical grey categories after the upgrade.
      final db = await _freshDatabase();
      await _reshapeToV18(db, folderCount: 6);

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);

      final hues = {for (final r in await _folders(db)) r['color_index']};
      expect(hues, hasLength(6));
    });

    test('names, positions and timestamps are untouched', () async {
      final db = await _freshDatabase();
      await _reshapeToV18(db, folderCount: 4);
      final before = await _folders(db);

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);

      final after = await _folders(db);
      for (var i = 0; i < before.length; i++) {
        expect(after[i]['id'], before[i]['id']);
        expect(after[i]['name'], before[i]['name']);
        expect(after[i]['position'], before[i]['position']);
        expect(after[i]['created_at'], before[i]['created_at']);
      }
    });

    test('running it twice does not throw', () async {
      // ALTER TABLE ADD COLUMN is not idempotent on its own — the second run
      // throws "duplicate column name". A device handed the same migration
      // again after an interrupted upgrade must survive it, which is what the
      // PRAGMA table_info guard is for. It is the same guard the v2 step uses.
      final db = await _freshDatabase();
      await _reshapeToV18(db, folderCount: 2);

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);
      await expectLater(
        AppDatabase.instance.migrateForTesting(fromVersion: 18),
        completes,
      );

      expect(await _columns(db, 'folders'), contains('color_index'));
      expect(await _folders(db), hasLength(2));
    });

    test('a database with no categories at all survives it', () async {
      final db = await _freshDatabase();
      await _reshapeToV18(db, folderCount: 0);

      await expectLater(
        AppDatabase.instance.migrateForTesting(fromVersion: 18),
        completes,
      );
      expect(await _columns(db, 'folders'), contains('color_index'));
    });
  });

  group('a fresh install', () {
    test('has the column already', () async {
      final db = await _freshDatabase();
      expect(await _columns(db, 'folders'), contains('color_index'));
    });

    test('and the same folders shape as an upgraded database', () async {
      final fresh = await _freshDatabase();
      final freshColumns = await _columns(fresh, 'folders');
      await AppDatabase.instance.close();

      final upgraded = await _freshDatabase();
      await _reshapeToV18(upgraded, folderCount: 1);
      await AppDatabase.instance.migrateForTesting(fromVersion: 18);

      expect(await _columns(upgraded, 'folders'), equals(freshColumns),
          reason: 'the DDL and the migration are two statements of the same '
              'fact, and nothing forces them to agree');
    });
  });
}
