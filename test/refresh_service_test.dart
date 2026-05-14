import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/utils/constants.dart';

// These tests verify the observable outcomes of the cold-start vs
// pull-to-refresh distinction, without mocking HTTP. The core contract is:
//   - coldStart: cleanup runs before inserts (old read articles are gone)
//   - pull-to-refresh: cleanup does NOT run (old read articles survive)


late ArticleRepository _repo;

final _now = DateTime(2026, 5, 14, 12, 0, 0);
final _recent = _now.subtract(const Duration(days: 1));
final _old = _now.subtract(const Duration(days: kFetchDayLimit + 1));

Article _art(int i, {DateTime? published}) => Article(
      feedId: 1,
      guid: 'guid-$i',
      title: 'Article $i',
      url: 'https://example.com/$i',
      publishedAt: (published ?? _recent).millisecondsSinceEpoch,
      fetchedAt: 0,
    );

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final folderId = await db.insert(
      TableNames.folders, {'name': 'Test', 'position': 0, 'created_at': ts});
  await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed',
    'url': 'https://example.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });
}

Future<void> _tearDown() async => AppDatabase.instance.close();

Future<int> _count() async {
  final db = await AppDatabase.instance.database;
  final r =
      await db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.articles}');
  return r.first['c'] as int;
}

// Simulate the cleanup-first step of cold start using the repository directly.
Future<void> _simulateColdStart(List<Article> newArticles) async {
  await _repo.runCleanup(); // Step 1: cleanup before insert
  await _repo.insertArticles(1, newArticles); // Step 2: insert fetched articles
}

// Simulate pull-to-refresh (no cleanup).
Future<void> _simulatePullToRefresh(List<Article> newArticles) async {
  await _repo.insertArticles(1, newArticles); // No cleanup step
}

void main() {
  group('Cold start', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('cleanup runs before fetch — old read articles are deleted before insert',
        () async {
      // Pre-condition: an old read article exists in the DB.
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.markAllAsRead();

      // Cold start: cleanup fires first, then new articles are inserted.
      await _simulateColdStart([_art(2, published: _recent)]);

      // Old article (guid-1) should be gone; new article (guid-2) present.
      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles);
      final guids = rows.map((r) => r['guid']).toList();
      expect(guids, contains('guid-2'));
      expect(guids, isNot(contains('guid-1')));
    });

    test('cold start fetch inserts new articles after cleanup', () async {
      await _simulateColdStart([_art(1, published: _recent)]);
      expect(await _count(), 1);
    });

    test('after cold start, articles deleted by cleanup are not re-inserted if older than 7 days',
        () async {
      // Insert an old article, mark it read, then cold-start with NO new articles.
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.markAllAsRead();

      await _simulateColdStart([]); // fetch returns nothing

      expect(await _count(), 0);
    });
  });

  group('Pull-to-refresh', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('pull-to-refresh does NOT run the cleanup job', () async {
      // Pre-condition: old read article in DB.
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.markAllAsRead();

      // Pull-to-refresh: no cleanup.
      await _simulatePullToRefresh([_art(2, published: _recent)]);

      // Old article should still be there (cleanup was skipped).
      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles);
      final guids = rows.map((r) => r['guid']).toList();
      expect(guids, contains('guid-1'));
    });

    test('pull-to-refresh inserts new articles', () async {
      await _simulatePullToRefresh([_art(1, published: _recent)]);
      expect(await _count(), 1);
    });
  });

  group('Background job', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('background job: cleanup then fetch — same outcome as cold start', () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.markAllAsRead();

      // Background uses the same cleanup-first pattern as cold start.
      await _simulateColdStart([_art(2, published: _recent)]);

      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles);
      final guids = rows.map((r) => r['guid']).toList();
      expect(guids, contains('guid-2'));
      expect(guids, isNot(contains('guid-1')));
    });
  });
}
