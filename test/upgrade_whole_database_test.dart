// Pre-launch QA, section A: does an upgrade keep a real library.
//
// **The 25 testers will upgrade, not install fresh.** Every other migration
// test in this repo checks one step against the table that step touches, which
// is right and is not the same question. This one asks whether a database that
// looks like somebody's actual library — feeds in folders, articles read and
// unread and bookmarked, keyword alerts with matches behind them, settings —
// comes through v18 -> v19 with everything still in it.
//
// It matters more than the narrow tests because migrations run inside a single
// transaction: a failure anywhere in the chain aborts the open, and the app
// then starts on a database that will not load rather than one missing a
// column. The blast radius is the whole library, not the changed table.
//
// The specific worry David raised is category colour. v19 backfills
// `color_index` from `position % 6`. That is a FIRST assignment, not a
// reshuffle — v18 had no colour to lose — and the tests below pin that it is
// deterministic and stable, because "survivable one-time shuffle" and
// "instability" look identical the first time you see them and only one is
// acceptable.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/theme/category_colors.dart';

const String _createFoldersV18 = '''
  CREATE TABLE folders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT    NOT NULL,
    position   INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
''';

/// Names chosen to look like a real library rather than "Category 0".
const _categoryNames = [
  'World News',
  'Tech',
  'Fitness / Health',
  'Football',
  'Long Reads',
  'Local',
  'Science',
];

Future<Database> _open() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  return AppDatabase.instance.database;
}

/// Reshapes a fresh v19 database back to v18 and fills it with a library.
///
/// The reshape is the same trick the v19 test uses and for the same reason:
/// `_onCreate` builds at the current version, so without it the migration
/// would only ever exercise its own idempotency guard.
Future<void> _seedV18Library(Database db, {required int categories}) async {
  await db.execute('PRAGMA foreign_keys = OFF');
  await db.execute('DROP TABLE IF EXISTS folders');
  await db.execute(_createFoldersV18);

  for (var i = 0; i < categories; i++) {
    await db.insert(TableNames.folders, {
      'name': _categoryNames[i % _categoryNames.length],
      'position': i,
      'created_at': 1750000000000 + i,
    });
  }
  await db.execute('PRAGMA foreign_keys = ON');

  // Two feeds per category, four articles per feed. Every article state that
  // a reader can actually be holding is represented.
  for (var f = 1; f <= categories; f++) {
    for (var n = 0; n < 2; n++) {
      final feedId = await db.insert(TableNames.feeds, {
        'folder_id': f,
        'title': 'Feed $f-$n',
        'url': 'https://example.com/$f/$n/rss.xml',
        'consecutive_failures': 0,
        'is_dead': 0,
        'created_at': 1750000000000,
      });
      for (var a = 0; a < 4; a++) {
        await db.insert(TableNames.articles, {
          'feed_id': feedId,
          'guid': 'guid-$f-$n-$a',
          'title': 'Article $f-$n-$a',
          'url': 'https://example.com/$f/$n/$a',
          'fetched_at': 1750000000000,
          'published_at': 1750000000000 + a,
          // a == 0 read, a == 1 saved, a == 2 read AND saved, a == 3 plain.
          'is_read': (a == 0 || a == 2) ? 1 : 0,
          'is_saved': (a == 1 || a == 2) ? 1 : 0,
        });
      }
    }
  }

  await db.insert(TableNames.keywordAlerts, {
    'keyword': 'budget',
    'whole_word': 1,
    'created_at': 1750000000000,
  });
  await db.insert(TableNames.alertMatches, {
    'feed_id': 1,
    'guid': 'guid-1-0-3',
    'keyword': 'budget',
    'title': 'Article 1-0-3',
    'url': 'https://example.com/1/0/3',
    'matched_at': 1750000000000,
  });
  await db.insert(TableNames.settings, {
    'key': 'unread_badge_notification',
    'value': 'true',
    'updated_at': 1750000000000,
  });
}

int _firstInt(List<Map<String, Object?>> rows) =>
    (rows.first.values.first as int?) ?? -1;

Future<int> _count(Database db, String table) async =>
    _firstInt(await db.rawQuery('SELECT COUNT(*) FROM $table'));

void main() {
  tearDown(() async => AppDatabase.instance.close());

  group('a realistic library survives v18 -> v19', () {
    late List<Map<String, Object?>> foldersAfter;
    late Database db;

    Future<void> upgradeWith(int categories) async {
      db = await _open();
      await _seedV18Library(db, categories: categories);
      // Pre-condition, so this cannot pass against an already-migrated
      // database -- the false green rule 10.1 exists for.
      final before = await db.rawQuery('PRAGMA table_info(folders)');
      expect(before.any((c) => c['name'] == 'color_index'), isFalse);

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);
      foldersAfter =
          await db.query(TableNames.folders, orderBy: 'position');
    }

    test('nothing is lost: every table keeps its rows', () async {
      await upgradeWith(4);
      expect(await _count(db, TableNames.folders), 4);
      expect(await _count(db, TableNames.feeds), 8);
      expect(await _count(db, TableNames.articles), 32);
      expect(await _count(db, TableNames.keywordAlerts), 1);
      expect(await _count(db, TableNames.alertMatches), 1);
    });

    test('bookmarks and read state come through exactly', () async {
      await upgradeWith(4);
      // 8 feeds x 1 read-only + 1 read-and-saved = 16 read, 16 saved.
      final read = _firstInt(await db.rawQuery(
          'SELECT COUNT(*) FROM ${TableNames.articles} WHERE is_read = 1'));
      final saved = _firstInt(await db.rawQuery(
          'SELECT COUNT(*) FROM ${TableNames.articles} WHERE is_saved = 1'));
      expect(read, 16, reason: 'read state is the thing testers notice losing');
      expect(saved, 16, reason: 'bookmarks are the thing they cannot rebuild');

      // And the combination, which is the one a naive rebuild flattens.
      final both = _firstInt(await db.rawQuery(
          'SELECT COUNT(*) FROM ${TableNames.articles} '
          'WHERE is_read = 1 AND is_saved = 1'));
      expect(both, 8);
    });

    test('feeds stay attached to the right categories', () async {
      await upgradeWith(4);
      for (final folder in foldersAfter) {
        final n = _firstInt(await db.rawQuery(
            'SELECT COUNT(*) FROM ${TableNames.feeds} WHERE folder_id = ?',
            [folder['id']]));
        expect(n, 2, reason: 'category "${folder['name']}" lost its feeds');
      }
    });

    test('alert matches still resolve to a real article', () async {
      await upgradeWith(4);
      final rows = await db.rawQuery(
        'SELECT a.title FROM ${TableNames.alertMatches} m '
        'JOIN ${TableNames.articles} a '
        '  ON a.feed_id = m.feed_id AND a.guid = m.guid',
      );
      expect(rows, hasLength(1),
          reason: 'an alert whose article vanished is a dead row in the '
              'Alerts tab');
    });

    test('settings survive', () async {
      await upgradeWith(4);
      final rows = await db.query(TableNames.settings,
          where: 'key = ?', whereArgs: ['unread_badge_notification']);
      expect(rows.single['value'], 'true');
    });
  });

  group('category names, order and colour — the question David asked', () {
    test('names and order are untouched, and colour is a FIRST assignment',
        () async {
      final db = await _open();
      await _seedV18Library(db, categories: 7);
      final before = await db.query(TableNames.folders, orderBy: 'position');

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);
      final after = await db.query(TableNames.folders, orderBy: 'position');

      expect(after.map((f) => f['name']).toList(),
          before.map((f) => f['name']).toList(),
          reason: 'a renamed category would be the loudest possible bug');
      expect(after.map((f) => f['position']).toList(),
          before.map((f) => f['position']).toList(),
          reason: 'reordered categories would look like data loss');
      expect(after.map((f) => f['id']).toList(),
          before.map((f) => f['id']).toList(),
          reason: 'ids move only in a table rebuild, and v19 is an ALTER');
    });

    test('the colour assignment is deterministic, not random', () async {
      // **This is the distinction that matters.** A one-time assignment is
      // survivable; instability is not. Run the same upgrade twice from
      // scratch and the same category must land on the same hue.
      final first = <Object?>[];
      final second = <Object?>[];

      for (final sink in [first, second]) {
        final db = await _open();
        await _seedV18Library(db, categories: 7);
        await AppDatabase.instance.migrateForTesting(fromVersion: 18);
        sink.addAll((await db.query(TableNames.folders, orderBy: 'position'))
            .map((f) => f['color_index']));
        await AppDatabase.instance.close();
      }
      expect(first, second,
          reason: 'two identical libraries upgrading must get identical '
              'colours, or the hue is not stable for a given category');
      expect(first, [0, 1, 2, 3, 4, 5, 0],
          reason: 'position % $kCategoryHueCount, spelled out so a change to '
              'the rule is visible here rather than on a device');
    });

    test('and it is stable: a second open does not reassign', () async {
      final db = await _open();
      await _seedV18Library(db, categories: 7);
      await AppDatabase.instance.migrateForTesting(fromVersion: 18);

      // Simulate the user having changed one, as a future "change category
      // colour" screen would.
      await db.update(TableNames.folders, {'color_index': 5},
          where: 'position = ?', whereArgs: [0]);

      // Then hand the device the same migration again, which is what an
      // interrupted upgrade does.
      await AppDatabase.instance.migrateForTesting(fromVersion: 18);
      final again = await db.query(TableNames.folders, orderBy: 'position');
      expect(again.first['color_index'], 5,
          reason: 'the backfill is a one-time spread, not a rule. If this is '
              '0 again the migration is re-running and every deliberate '
              'colour choice is erased on every launch.');
    });
  });

  group('the edges', () {
    test('an empty database upgrades cleanly', () async {
      final db = await _open();
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE IF EXISTS folders');
      await db.execute(_createFoldersV18);
      await db.execute('PRAGMA foreign_keys = ON');

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);
      expect(await _count(db, TableNames.folders), 0);
      final cols = await db.rawQuery('PRAGMA table_info(folders)');
      expect(cols.any((c) => c['name'] == 'color_index'), isTrue,
          reason: 'an empty library still has to end up on the new schema, or '
              'the next upgrade starts from the wrong version');
    });

    test('a realistically large library upgrades', () async {
      // 20 categories, 40 feeds, 160 articles. Not a stress test — a check
      // that nothing in the step is accidentally O(rows) in a way that would
      // time out the open on a real device.
      final db = await _open();
      await _seedV18Library(db, categories: 20);

      await AppDatabase.instance.migrateForTesting(fromVersion: 18);
      expect(await _count(db, TableNames.folders), 20);
      expect(await _count(db, TableNames.articles), 160);
      final hues = (await db.query(TableNames.folders, orderBy: 'position'))
          .map((f) => f['color_index'])
          .toSet();
      expect(hues, hasLength(kCategoryHueCount),
          reason: 'twenty categories should still use all six hues');
    });
  });
}
