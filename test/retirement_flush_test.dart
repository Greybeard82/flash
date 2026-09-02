// The flush half of two-phase retirement.
//
// The queue's own contract is covered in retirement_queue_test.dart. What is
// tested here is the boundary between the queue and the database: that a flush
// with nothing queued touches neither, and that a bookmarked article cannot be
// retired by one.
//
// Both properties are guarded twice in the real code — the screen releases a
// bookmarked id from the queue, and retireArticles scopes its delete to
// is_saved = 0 — so both layers are asserted here. A single guard is one
// refactor away from being the only guard.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/reading/retirement_queue.dart';
import 'package:flash/repositories/article_repository.dart';

late ArticleRepository _repo;
late int _feedId;

const int _now = 1750000000000;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final folderId = await db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _feedId = await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

Future<int> _insert(String guid, {bool saved = false, bool read = true}) async {
  final db = await AppDatabase.instance.database;
  return db.insert(TableNames.articles, {
    'feed_id': _feedId,
    'guid': guid,
    'title': 'Article $guid',
    'url': 'https://example.com/$guid',
    'published_at': _now,
    'fetched_at': _now,
    'is_read': read ? 1 : 0,
    'is_blocked': 0,
    'is_saved': saved ? 1 : 0,
  });
}

Future<int> _articleCount() async {
  final db = await AppDatabase.instance.database;
  return (await db.query(TableNames.articles)).length;
}

Future<int> _tombstoneCount() async {
  final db = await AppDatabase.instance.database;
  return (await db.query(TableNames.deletedArticles)).length;
}

/// The screen's flush, reduced to the part that touches the database.
///
/// Mirrors `FeedScreen._flushRetirementQueue`: the early return on an empty
/// queue is the behaviour under test, so it is reproduced rather than skipped.
Future<int> _flush(RetirementQueue q) async {
  if (q.isEmpty) return 0;
  final ids = q.drain();
  await _repo.retireArticles(ids);
  return ids.length;
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('a flush with an empty queue does nothing', () {
    test('no rows deleted and no tombstones written', () async {
      await _insert('a');
      await _insert('b');
      final q = RetirementQueue();

      final articlesBefore = await _articleCount();
      final tombstonesBefore = await _tombstoneCount();

      final flushed = await _flush(q);

      expect(flushed, 0);
      expect(await _articleCount(), articlesBefore,
          reason: 'an empty flush must not touch the article table');
      expect(await _tombstoneCount(), tombstonesBefore,
          reason: 'nor write a tombstone for an article nobody queued');
      expect(articlesBefore, 2, reason: 'the fixture is doing its job');
    });

    test('a flush straight after a flush is also a no-op', () async {
      final id = await _insert('a');
      await _insert('b');
      final q = RetirementQueue()..enqueue([id]);

      expect(await _flush(q), 1);
      final afterFirst = await _articleCount();
      final tombstonesAfterFirst = await _tombstoneCount();

      expect(await _flush(q), 0);
      expect(await _articleCount(), afterFirst);
      expect(await _tombstoneCount(), tombstonesAfterFirst,
          reason: 'draining leaves the queue empty, so the second flush has '
              'nothing to write — a duplicate tombstone here would mean the '
              'queue was not cleared');
    });
  });

  group('a bookmarked article survives a flush', () {
    test('released from the queue when it is bookmarked', () async {
      final saved = await _insert('saved', saved: true);
      final ordinary = await _insert('ordinary');

      final q = RetirementQueue()..enqueue([saved, ordinary]);
      // What _toggleSaved does the moment the user bookmarks it.
      q.release(saved);

      expect(q.isPending(saved), isFalse);
      expect(await _flush(q), 1, reason: 'only the ordinary article drains');

      final db = await AppDatabase.instance.database;
      final left = (await db.query(TableNames.articles, columns: ['guid']))
          .map((r) => r['guid'])
          .toSet();
      expect(left, {'saved'});
    });

    test('and survives even if it reaches the flush unreleased', () async {
      // The second guard: retireArticles scopes its delete to is_saved = 0, so
      // a bookmark cannot be deleted even by a queue that forgot to release
      // it. PRD 4.9 — saved articles are never deleted, whatever their read
      // state or age.
      final saved = await _insert('saved', saved: true);
      final q = RetirementQueue()..enqueue([saved]);

      await _flush(q);

      final db = await AppDatabase.instance.database;
      final left = (await db.query(TableNames.articles, columns: ['guid']))
          .map((r) => r['guid'])
          .toSet();
      expect(left, {'saved'},
          reason: 'the repository is the backstop for the screen forgetting');
      expect(await _tombstoneCount(), 0,
          reason: 'and no tombstone either — a tombstone for a live article '
              'would block it from ever being re-fetched');
    });
  });
}
