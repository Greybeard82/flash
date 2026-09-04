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
    // Represents an article that was already retired at some point in the
    // past: the row is gone, the tombstone remains. Seeded directly rather
    // than by retiring a live row here — the repository method that once
    // did that (retireArticles) is gone; retireAllRead is exercised in
    // read_visibility_test.dart, and what this file is actually pinning is
    // the NOT EXISTS guard in insertArticles, which does not care how the
    // tombstone got there.
    final db = await AppDatabase.instance.database;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'g1', 'deleted_at': _now});

    // The feed still offers it — this is the next refresh.
    await _repo.insertArticles(_feedA, [_article('g1')]);

    expect(await _rows(_feedA), isEmpty,
        reason: 'the whole point of the tombstone table: once a guid is '
            'tombstoned, a re-fetch must not bring it back unread');
  });

  test('a tombstone in one feed does not block the same guid in another',
      () async {
    final db = await AppDatabase.instance.database;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'shared', 'deleted_at': _now});

    await _repo.insertArticles(_feedB, [_article('shared')]);

    expect((await _rows(_feedB)).length, 1,
        reason: 'guids are only unique per feed; two feeds syndicating the '
            'same item must stay independent');
  });

  test('a never-retired article inserts normally', () async {
    final db = await AppDatabase.instance.database;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'a', 'deleted_at': _now});

    await _repo.insertArticles(_feedA, [_article('b'), _article('c')]);

    final guids = (await _rows(_feedA)).map((r) => r['guid']).toSet();
    expect(guids, {'b', 'c'},
        reason: 'the NOT EXISTS guard must block only what was tombstoned');
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
    final db = await AppDatabase.instance.database;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'g1', 'deleted_at': 0});
    await _repo.pruneTombstones();

    await _repo.insertArticles(_feedA, [_article('g1')]);

    expect((await _rows(_feedA)).length, 1,
        reason: 'this is deliberate, not a leak. Past kTombstoneDayLimit the '
            'fetch window has moved on, so a feed re-offering the guid means '
            'it genuinely republished — and keeping tombstones forever would '
            'grow without bound');
  });

  test('clearing every tombstone lets a retired guid insert again', () async {
    // The recovery action in Settings. Retirement is irreversible by design,
    // so this is the only route back for a user who scrolled faster than they
    // meant to.
    final db = await AppDatabase.instance.database;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'g1', 'deleted_at': _now});
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'g2', 'deleted_at': _now});
    expect(await _repo.tombstoneCount(), 2);

    final cleared = await _repo.clearAllTombstones();

    expect(cleared, 2);
    expect(await _repo.tombstoneCount(), 0);

    // The feeds still carry them, so the next fetch brings them back.
    await _repo.insertArticles(_feedA, [_article('g1'), _article('g2')]);
    expect((await _rows(_feedA)).length, 2,
        reason: 'this is the whole point of the recovery action');
  });

  test('clearing tombstones touches nothing but the tombstone table',
      () async {
    final db = await AppDatabase.instance.database;

    // A library around the tombstones: a keyword, a saved article, a
    // surviving unread article, one tombstone, plus the folders and feeds
    // from setUp. The tombstoned guid needs no article row of its own —
    // clearAllTombstones only ever touches deleted_articles.
    await db.insert(TableNames.keywordBlocklist,
        {'keyword': 'sponsored', 'whole_word': 0, 'created_at': _now});
    await _repo.insertArticles(_feedA, [_article('keep'), _article('saved')]);
    await _repo.setSaved(await _idOf(_feedA, 'saved'), saved: true);
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'doomed', 'deleted_at': _now});

    final foldersBefore = await db.query(TableNames.folders);
    final feedsBefore = await db.query(TableNames.feeds);
    final keywordsBefore = await db.query(TableNames.keywordBlocklist);
    final articlesBefore = await db.query(TableNames.articles);
    expect(await _repo.tombstoneCount(), 1);

    await _repo.clearAllTombstones();

    expect(await db.query(TableNames.folders), foldersBefore);
    expect(await db.query(TableNames.feeds), feedsBefore);
    expect(await db.query(TableNames.keywordBlocklist), keywordsBefore);
    expect(await db.query(TableNames.articles), articlesBefore,
        reason: 'recovery clears tombstones only — surviving articles and '
            'bookmarks are not touched, and nothing is resurrected until the '
            'next fetch actually re-inserts it');
    expect(await _repo.tombstoneCount(), 0);
  });

  test('deleting a feed cascades its tombstones away', () async {
    final db = await AppDatabase.instance.database;
    await db.insert(TableNames.deletedArticles,
        {'feed_id': _feedA, 'guid': 'g1', 'deleted_at': _now});
    expect(await _tombstoneCount(), 1);

    await db.delete(TableNames.feeds, where: 'id = ?', whereArgs: [_feedA]);

    expect(await _tombstoneCount(), 0,
        reason: 'ON DELETE CASCADE, with foreign_keys ON');
  });
}
