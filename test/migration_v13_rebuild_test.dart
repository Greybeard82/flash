// The v13 articles rebuild.
//
// v13 used to run `ALTER TABLE articles DROP COLUMN read_at`. DROP COLUMN
// needs SQLite 3.35 (March 2021); Android 12 ships 3.32 and min SDK 26 is
// older still, so on most of the range the PRD claims to support the statement
// threw inside the migration transaction, the open failed, main() died, and
// the app was a permanently blank screen. The only recovery was clearing app
// data, which destroys the library — the backup format covers neither articles
// nor read state nor bookmarks.
//
// **This suite cannot reproduce that failure**: sqflite_common_ffi links a
// modern SQLite, so DROP COLUMN would have worked here. What it can prove is
// that the replacement rebuild is correct, which is where the risk now lives —
// a rebuild that loses a column, a row, or an index is a quieter version of
// the same disaster.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';

const int _now = 1750000000000;

late Database _db;
late int _feedId;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _db = await AppDatabase.instance.database;

  final folderId = await _db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _feedId = await _db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

/// Runs the real migration the way production runs it.
///
/// sqflite wraps onCreate/onUpgrade in a transaction, and `PRAGMA
/// foreign_keys` is a silent no-op inside one — so production sets it in
/// onConfigure (before) and restores it in onOpen (after). `migrateForTesting`
/// runs against an already-open database, where onOpen has re-enabled
/// enforcement, so the pragma is mirrored here. Without it this exercises a
/// configuration production never uses.
Future<void> _migrate({required int from}) async {
  await _db.execute('PRAGMA foreign_keys = OFF');
  await AppDatabase.instance.migrateForTesting(fromVersion: from);
  await _db.execute('PRAGMA foreign_keys = ON');
}

Future<int> _insertArticle(String guid,
    {bool read = false, bool saved = false, String? blockedKeyword}) async {
  return _db.insert(TableNames.articles, {
    'feed_id': _feedId,
    'guid': guid,
    'title': 'Title $guid',
    'url': 'https://example.com/$guid',
    'description': 'Body $guid',
    'thumbnail_url': 'https://example.com/$guid.png',
    'thumbnail_path': '/tmp/$guid.png',
    'published_at': _now,
    'fetched_at': _now + 1,
    'is_read': read ? 1 : 0,
    'is_blocked': 0,
    'is_saved': saved ? 1 : 0,
    'blocked_keyword': blockedKeyword,
  });
}

Future<List<String>> _columns(String table) async {
  final rows = await _db.rawQuery('PRAGMA table_info($table)');
  return [for (final r in rows) r['name'] as String];
}

/// Index name -> its SQL definition, for `articles`.
Future<Map<String, String?>> _indexes() async {
  final rows = await _db.rawQuery(
    "SELECT name, sql FROM sqlite_master "
    "WHERE type = 'index' AND tbl_name = '${TableNames.articles}'",
  );
  return {
    for (final r in rows)
      r['name'] as String: (r['sql'] as String?)?.replaceAll(RegExp(r'\s+'), ' ').trim(),
  };
}

/// Puts read_at back, as a database arriving from v11 or v12 would have it.
Future<void> _addReadAt() async {
  await _db.execute(
      'ALTER TABLE ${TableNames.articles} ADD COLUMN read_at INTEGER');
  await _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_articles_read_at ON articles(read_at)');
}


/// Turns the freshly-created v13 database back into the shape a v1 database
/// actually had, so the migration chain can be exercised end to end.
///
/// Derived from the migration steps rather than guessed: v2 adds `is_saved`,
/// v3 adds `keyword_alerts`, v4 and v5 add three indexes, v11 adds `read_at`,
/// v13 adds `deleted_articles`. Removing exactly those leaves v1.
///
/// This uses DROP COLUMN, which is the very statement the fix exists to avoid
/// — legitimate here because it builds the fixture and never runs on a user's
/// device, and because the test SQLite is modern enough to support it.
Future<void> _shapeAsV1() async {
  await _db.execute('DROP TABLE IF EXISTS ${TableNames.keywordAlerts}');
  await _db.execute('DROP TABLE IF EXISTS ${TableNames.deletedArticles}');
  await _db.execute('DROP INDEX IF EXISTS idx_articles_read_published');
  await _db.execute('DROP INDEX IF EXISTS idx_articles_feed_read_published');
  await _db.execute('DROP INDEX IF EXISTS idx_articles_guid_feed');
  await _db.execute(
      'ALTER TABLE ${TableNames.articles} DROP COLUMN is_saved');
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('the rebuild preserves the table', () {
    test('row count is identical before and after', () async {
      await _addReadAt();
      for (var i = 0; i < 25; i++) {
        await _insertArticle('a$i', read: i.isEven, saved: i % 5 == 0);
      }
      final before = (await _db.query(TableNames.articles)).length;

      await _migrate(from: 12);

      expect((await _db.query(TableNames.articles)).length, before);
      expect(before, 25, reason: 'the fixture is doing its job');
    });

    test('read_at is gone afterwards, and nothing else is', () async {
      await _addReadAt();
      await _insertArticle('a');
      final before = await _columns(TableNames.articles);
      expect(before, contains('read_at'));

      await _migrate(from: 12);

      final after = await _columns(TableNames.articles);
      expect(after, isNot(contains('read_at')));
      expect(after, before.where((c) => c != 'read_at').toList(),
          reason: 'every other column survives, in the same order');
    });

    test('every value survives, read state and the saved flag included',
        () async {
      await _addReadAt();
      final readSavedId =
          await _insertArticle('keep', read: true, saved: true,
              blockedKeyword: 'spoiler');
      final plainId = await _insertArticle('plain');
      // A read_at value present on the way in, to prove the copy does not
      // shift columns when the source table has one more than the target.
      await _db.rawUpdate(
          'UPDATE ${TableNames.articles} SET read_at = ? WHERE id = ?',
          [_now + 999, readSavedId]);

      await _migrate(from: 12);

      final kept = (await _db.query(TableNames.articles,
              where: 'id = ?', whereArgs: [readSavedId]))
          .single;
      expect(kept['guid'], 'keep');
      expect(kept['title'], 'Title keep');
      expect(kept['url'], 'https://example.com/keep');
      expect(kept['description'], 'Body keep');
      expect(kept['thumbnail_url'], 'https://example.com/keep.png');
      expect(kept['thumbnail_path'], '/tmp/keep.png');
      expect(kept['published_at'], _now);
      expect(kept['fetched_at'], _now + 1);
      expect(kept['is_read'], 1, reason: 'read state is not recoverable');
      expect(kept['is_saved'], 1, reason: 'a lost bookmark is a lost bookmark');
      expect(kept['is_blocked'], 0);
      expect(kept['blocked_keyword'], 'spoiler');
      expect(kept['feed_id'], _feedId);

      final plain = (await _db.query(TableNames.articles,
              where: 'id = ?', whereArgs: [plainId]))
          .single;
      expect(plain['is_read'], 0);
      expect(plain['is_saved'], 0);
      expect(plain['id'], plainId, reason: 'ids are carried, not reassigned');
    });

    test('rows referencing articles are not cascade-deleted', () async {
      // article_summaries.article_id REFERENCES articles(id) ON DELETE
      // CASCADE. DROP TABLE with enforcement on would take every summary with
      // it — silently, and with no way back.
      await _addReadAt();
      final id = await _insertArticle('a');
      await _db.insert(TableNames.articleSummaries, {
        'article_id': id,
        'summary': 'a summary',
        'model': 'gemini-nano',
        'generated_at': _now,
      });

      await _migrate(from: 12);

      final summaries = await _db.query(TableNames.articleSummaries);
      expect(summaries.length, 1,
          reason: 'the summary must survive its article being rebuilt');
      expect(summaries.single['article_id'], id);
    });
  });

  group('the rebuild preserves the indexes', () {
    test('every index present before is present after, same definition',
        () async {
      await _addReadAt();
      await _insertArticle('a');
      final before = await _indexes();
      // read_at's own index goes with its column and is excluded.
      before.remove('idx_articles_read_at');

      await _migrate(from: 12);

      final after = await _indexes();
      expect(after.keys.toSet(), before.keys.toSet(),
          reason: 'DROP TABLE takes every index with it silently — a missing '
              'one shows up as a slow query, or as duplicate articles when '
              'UNIQUE(feed_id, guid) is the one that vanished');
      for (final name in before.keys) {
        expect(after[name], before[name], reason: 'definition of $name');
      }
      expect(after.containsKey('idx_articles_read_at'), isFalse);
    });

    test('the named indexes are all there', () async {
      await _addReadAt();
      await _migrate(from: 12);
      expect(
        (await _indexes()).keys.where((k) => k.startsWith('idx_')).toSet(),
        {
          'idx_articles_guid_feed',
          'idx_articles_feed_id',
          'idx_articles_is_read',
          'idx_articles_is_blocked',
          'idx_articles_published_at',
          'idx_articles_read_published',
          'idx_articles_feed_read_published',
        },
      );
    });

    test('the unique guid index still rejects a duplicate', () async {
      await _addReadAt();
      await _insertArticle('dupe');
      await _migrate(from: 12);

      expect(() => _insertArticle('dupe'), throwsA(isA<DatabaseException>()),
          reason: 'dedup depends on this index; losing it in the rebuild '
              'would resurrect duplicate articles in production');
    });
  });

  group('integrity', () {
    test('foreign_key_check returns nothing after the rebuild', () async {
      await _addReadAt();
      final id = await _insertArticle('a');
      await _db.insert(TableNames.articleSummaries, {
        'article_id': id,
        'summary': 's',
        'model': 'm',
        'generated_at': _now,
      });

      await _migrate(from: 12);

      expect(await _db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });

    test('no leftover scratch table', () async {
      await _addReadAt();
      await _migrate(from: 12);
      final tables = await _db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='articles_new'");
      expect(tables, isEmpty);
    });
  });

  group('idempotence and the full path', () {
    test('running the migration twice is a no-op the second time', () async {
      await _addReadAt();
      await _insertArticle('a', read: true, saved: true);

      await _migrate(from: 12);
      final afterFirst = await _db.query(TableNames.articles);
      final indexesAfterFirst = await _indexes();

      await _migrate(from: 12);

      expect(await _db.query(TableNames.articles), afterFirst,
          reason: 'the column-existence guard keeps the step idempotent');
      expect((await _indexes()).keys.toSet(), indexesAfterFirst.keys.toSet());
    });

    test('a v1 database upgrades cleanly all the way to v13', () async {
      await _insertArticle('a', read: true, saved: true);
      await _insertArticle('b');
      await _shapeAsV1();

      await _migrate(from: 1);

      final cols = await _columns(TableNames.articles);
      expect(cols, isNot(contains('read_at')),
          reason: 'the v13 rebuild removed it');
      expect(cols, contains('is_saved'),
          reason: 'the v2 step added it back on the way through');
      expect((await _db.query(TableNames.articles)).length, 2);
      expect(await _db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // v13 also creates the tombstone table.
      expect(
        await _db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='deleted_articles'"),
        hasLength(1),
      );
    });

    test('a migrated database has the same articles columns as a fresh one',
        () async {
      // Pins SchemaStatements.createArticlesRebuildV13 to createArticles. They
      // are written out separately for readability, so drift between them has
      // to fail here rather than in somebody's library.
      await _addReadAt();
      await _migrate(from: 12);
      final migrated = await _columns(TableNames.articles);

      await AppDatabase.instance.close();
      AppDatabase.useForTesting();
      _db = await AppDatabase.instance.database;
      final fresh = await _columns(TableNames.articles);

      expect(migrated, fresh);
    });
  });
}
