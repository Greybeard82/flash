// Tombstones — the load-bearing half of retirement.
//
// Written independently of the implementation. Dedup used to be
// INSERT OR IGNORE against UNIQUE (feed_id, guid), which worked because a read
// article kept its row and so kept its guid to collide with. Retirement
// deletes the row, and the article is still in the feed's XML and still inside
// the 7-day fetch window — so without a tombstone the next refresh re-inserts
// everything the user just cleared, as unread.
//
// If any test in this file fails, retirement is resurrecting articles and
// nothing else in the pass matters.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/utils/constants.dart';

late ArticleRepository _repo;
late int _feedA;
late int _feedB;

const int _now = 1750000000000;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final folderId = await db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _feedA = await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
  _feedB = await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed B',
    'url': 'https://b.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 1,
    'created_at': _now,
  });
}

Article _article(String guid) => Article(
      feedId: 0, // set by insertArticles
      guid: guid,
      title: 'Article $guid',
      url: 'https://example.com/$guid',
      publishedAt: _now,
      fetchedAt: _now,
    );

Future<List<Map<String, Object?>>> _rows(int feedId) async {
  final db = await AppDatabase.instance.database;
  return db.query(TableNames.articles,
      columns: ['id', 'guid', 'is_saved', 'is_read'],
      where: 'feed_id = ?', whereArgs: [feedId]);
}

Future<int> _tombstoneCount() async {
  final db = await AppDatabase.instance.database;
  final r = await db
      .rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.deletedArticles}');
  return r.first['c'] as int;
}

Future<int> _idOf(int feedId, String guid) async {
  final db = await AppDatabase.instance.database;
  final r = await db.query(TableNames.articles,
      columns: ['id'], where: 'feed_id = ? AND guid = ?',
      whereArgs: [feedId, guid]);
  return r.first['id'] as int;
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  test('a retired article is not resurrected by the next fetch', () async {
    await _repo.insertArticles(_feedA, [_article('g1')]);
    final id = await _idOf(_feedA, 'g1');

    await _repo.retireArticles([id]);
    expect(await _rows(_feedA), isEmpty);

    // The feed still offers it — this is the next refresh.
    await _repo.insertArticles(_feedA, [_article('g1')]);

    expect(await _rows(_feedA), isEmpty,
        reason: 'the whole point of the tombstone table: the user cleared '
            'this article and a re-fetch must not bring it back unread');
  });

  test('a tombstone in one feed does not block the same guid in another',
      () async {
    await _repo.insertArticles(_feedA, [_article('shared')]);
    await _repo.retireArticles([await _idOf(_feedA, 'shared')]);

    await _repo.insertArticles(_feedB, [_article('shared')]);

    expect((await _rows(_feedB)).length, 1,
        reason: 'guids are only unique per feed; two feeds syndicating the '
            'same item must stay independent');
  });

  test('a saved article is never tombstoned and survives a re-fetch',
      () async {
    await _repo.insertArticles(_feedA, [_article('keep')]);
    final id = await _idOf(_feedA, 'keep');
    await _repo.setSaved(id, saved: true);

    await _repo.retireArticles([id]);

    final after = await _rows(_feedA);
    expect(after.length, 1, reason: 'saved articles are exempt from retirement');
    expect(after.first['is_saved'], 1);
    expect(after.first['is_read'], 1,
        reason: 'exempt from deletion, but still marked read');
    expect(await _tombstoneCount(), 0);

    await _repo.insertArticles(_feedA, [_article('keep')]);
    expect((await _rows(_feedA)).length, 1,
        reason: 'still exactly one row — the unique index handles this');
  });

  test('retiring twice writes one tombstone and does not throw', () async {
    await _repo.insertArticles(_feedA, [_article('g1')]);
    final id = await _idOf(_feedA, 'g1');

    await _repo.retireArticles([id]);
    await _repo.retireArticles([id]); // row already gone

    expect(await _tombstoneCount(), 1);
  });

  test('a never-retired article inserts normally', () async {
    await _repo.insertArticles(_feedA, [_article('a'), _article('b')]);
    await _repo.retireArticles([await _idOf(_feedA, 'a')]);

    await _repo.insertArticles(_feedA, [_article('c')]);

    final guids = (await _rows(_feedA)).map((r) => r['guid']).toSet();
    expect(guids, {'b', 'c'},
        reason: 'the NOT EXISTS guard must block only what was retired');
  });

  test('pruneTombstones drops rows past the window and keeps the rest',
      () async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: kTombstoneDayLimit))
        .millisecondsSinceEpoch;

    // Margins of an hour either side, not a millisecond. pruneTombstones
    // computes its own `now`, microseconds after this line, so its cutoff sits
    // slightly later than this one — a row seeded at `cutoff + 1` is already
    // stale by the time it runs. Testing the boundary to the millisecond
    // against a wall clock tests the scheduler, not the query.
    const hour = 3600 * 1000;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'ancient', 'deleted_at': 0});
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'old', 'deleted_at': cutoff - hour});
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'inside', 'deleted_at': cutoff + hour});
    await db.insert(TableNames.deletedArticles, {
      'feed_id': _feedA,
      'guid': 'fresh',
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
    });

    final removed = await _repo.pruneTombstones();

    expect(removed, 2, reason: 'only what fell out of the retention window');
    final left = (await db.query(TableNames.deletedArticles, columns: ['guid']))
        .map((r) => r['guid'])
        .toSet();
    expect(left, {'inside', 'fresh'},
        reason: 'a tombstone inside the window still has to block a re-fetch');
  });

  test('after pruning, the guid can insert again — intended', () async {
    await _repo.insertArticles(_feedA, [_article('g1')]);
    await _repo.retireArticles([await _idOf(_feedA, 'g1')]);

    final db = await AppDatabase.instance.database;
    await db.update(TableNames.deletedArticles, {'deleted_at': 0});
    await _repo.pruneTombstones();

    await _repo.insertArticles(_feedA, [_article('g1')]);

    expect((await _rows(_feedA)).length, 1,
        reason: 'this is deliberate, not a leak. Past kTombstoneDayLimit the '
            'fetch window has moved on, so a feed re-offering the guid means '
            'it genuinely republished — and keeping tombstones forever would '
            'grow without bound');
  });

  test('deleting a feed cascades its tombstones away', () async {
    await _repo.insertArticles(_feedA, [_article('g1')]);
    await _repo.retireArticles([await _idOf(_feedA, 'g1')]);
    expect(await _tombstoneCount(), 1);

    final db = await AppDatabase.instance.database;
    await db.delete(TableNames.feeds, where: 'id = ?', whereArgs: [_feedA]);

    expect(await _tombstoneCount(), 0,
        reason: 'ON DELETE CASCADE, with foreign_keys ON');
  });

  test('retirement is atomic — never a deleted row with no tombstone',
      () async {
    await _repo.insertArticles(
        _feedA, [_article('a'), _article('b'), _article('c')]);
    final ids = [
      await _idOf(_feedA, 'a'),
      await _idOf(_feedA, 'b'),
      await _idOf(_feedA, 'c'),
    ];

    final deleted = await _repo.retireArticles(ids);

    expect(deleted, 3);
    expect(await _tombstoneCount(), 3,
        reason: 'one tombstone per deleted row, written in the same '
            'transaction and before the delete');
    expect(await _rows(_feedA), isEmpty);
  });

  test('1000 ids retire correctly across chunks, and the count is right',
      () async {
    // retireArticles chunks at 200, so this spans five transactions. The
    // return value must be the total across all of them, not the last chunk.
    final batch = [for (var i = 0; i < 1000; i++) _article('c$i')];
    await _repo.insertArticles(_feedA, batch);

    final db = await AppDatabase.instance.database;
    final ids = (await db.query(TableNames.articles, columns: ['id']))
        .map((r) => r['id'] as int)
        .toList();
    expect(ids.length, 1000);

    final deleted = await _repo.retireArticles(ids);

    expect(deleted, 1000, reason: 'summed across every chunk');
    expect(await _tombstoneCount(), 1000);
    expect(await _rows(_feedA), isEmpty);

    // And the tombstones actually work across the chunk boundary.
    await _repo.insertArticles(_feedA, batch);
    expect(await _rows(_feedA), isEmpty,
        reason: 'chunking must not leave a gap a re-fetch can slip through');
  });

  test('a mixed saved/unsaved batch across chunks counts only deletions',
      () async {
    final batch = [for (var i = 0; i < 250; i++) _article('m$i')];
    await _repo.insertArticles(_feedA, batch);

    final db = await AppDatabase.instance.database;
    final ids = (await db.query(TableNames.articles, columns: ['id']))
        .map((r) => r['id'] as int)
        .toList();
    // Save one in the first chunk and one in the second.
    await _repo.setSaved(ids[10], saved: true);
    await _repo.setSaved(ids[210], saved: true);

    final deleted = await _repo.retireArticles(ids);

    expect(deleted, 248, reason: 'the two saved articles are exempt');
    expect((await _rows(_feedA)).length, 2);
  });

  test('a 500-id batch retires without hitting a variable limit', () async {
    final batch = [for (var i = 0; i < 500; i++) _article('g$i')];
    await _repo.insertArticles(_feedA, batch);

    final db = await AppDatabase.instance.database;
    final ids = (await db.query(TableNames.articles, columns: ['id']))
        .map((r) => r['id'] as int)
        .toList();
    expect(ids.length, 500);

    final deleted = await _repo.retireArticles(ids);

    expect(deleted, 500);
    expect(await _tombstoneCount(), 500);
    expect(await _rows(_feedA), isEmpty);
  });
}
