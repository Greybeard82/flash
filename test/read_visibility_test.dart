// Read visibility and retirement, against the real database.
//
// Rewritten for schema v13. The previous version covered a 48-hour show-read
// window backed by articles.read_at; that column and that window are gone.
// Read articles are no longer *hidden* — they are retired, which deletes the
// row and tombstones the guid (see tombstone_test.dart). show_read now decides
// only *when* that happens: off retires on scroll, on defers to the next
// refresh.
//
// Covered behaviours:
//  1. Show read off: unread only, plus saved-and-read
//  2. Show read on: everything unblocked
//  3. retireArticles deletes unsaved, keeps and marks saved
//  4. retireAllRead is scoped, and leaves unread alone
//  5. Mixed saved/unsaved batches split correctly
//  6. Read state is global across tabs
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';

late ArticleRepository _repo;
late int _gamingId;
late int _newsId;
late int _gamingFeedId;
late int _newsFeedId;

const int _now = 1750000000000;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  _gamingId = await db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _newsId = await db.insert(TableNames.folders,
      {'name': 'News', 'position': 1, 'created_at': _now});
  _gamingFeedId = await db.insert(TableNames.feeds, {
    'folder_id': _gamingId,
    'title': 'Gaming Feed',
    'url': 'https://gaming.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
  _newsFeedId = await db.insert(TableNames.feeds, {
    'folder_id': _newsId,
    'title': 'News Feed',
    'url': 'https://news.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

Future<int> _insert(int feedId, String guid,
    {bool read = false, bool saved = false}) async {
  final db = await AppDatabase.instance.database;
  return db.insert(TableNames.articles, {
    'feed_id': feedId,
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

List<String> _guids(List<Article> articles) =>
    articles.map((a) => a.guid).toList()..sort();

Future<List<String>> _remaining() async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles, columns: ['guid']);
  return rows.map((r) => r['guid'] as String).toList()..sort();
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('Show read off', () {
    test('the All tab shows unread articles only', () async {
      await _insert(_gamingFeedId, 'unread');
      await _insert(_gamingFeedId, 'read', read: true);

      final visible = await _repo.getAllArticles(showRead: false);
      expect(_guids(visible), ['unread']);
    });

    test('a saved article stays visible after being read', () async {
      await _insert(_gamingFeedId, 'unread');
      await _insert(_gamingFeedId, 'saved_read', read: true, saved: true);

      final visible = await _repo.getAllArticles(showRead: false);
      expect(_guids(visible), ['saved_read', 'unread'],
          reason: 'saved articles are exempt from retirement, so hiding them '
              'once read would make a bookmark vanish from the feed while '
              'still sitting in Bookmarks');
    });

    test('an article read in All is gone from its own category too', () async {
      await _insert(_gamingFeedId, 'unread');
      await _insert(_gamingFeedId, 'read_in_all', read: true);

      final visible =
          await _repo.getArticlesByFolder(_gamingId, showRead: false);
      expect(_guids(visible), ['unread'],
          reason: 'read state lives on the row, so it is the same answer in '
              'every tab');
    });
  });

  group('Show read on', () {
    test('read articles stay visible', () async {
      await _insert(_gamingFeedId, 'unread');
      await _insert(_gamingFeedId, 'read', read: true);

      final visible = await _repo.getAllArticles(showRead: true);
      expect(_guids(visible), ['read', 'unread']);
    });

    test('blocked articles are hidden under either setting', () async {
      final db = await AppDatabase.instance.database;
      await _insert(_gamingFeedId, 'ok');
      final blocked = await _insert(_gamingFeedId, 'blocked');
      await db.update(TableNames.articles, {'is_blocked': 1},
          where: 'id = ?', whereArgs: [blocked]);

      expect(_guids(await _repo.getAllArticles(showRead: true)), ['ok']);
      expect(_guids(await _repo.getAllArticles(showRead: false)), ['ok']);
    });

    test('a folder query is scoped to that folder', () async {
      await _insert(_gamingFeedId, 'gaming');
      await _insert(_newsFeedId, 'news');

      final visible =
          await _repo.getArticlesByFolder(_gamingId, showRead: true);
      expect(_guids(visible), ['gaming']);
    });
  });

  group('retireArticles', () {
    test('deletes unsaved articles', () async {
      final id = await _insert(_gamingFeedId, 'gone');
      await _insert(_gamingFeedId, 'stays');

      final deleted = await _repo.retireArticles([id]);

      expect(deleted, 1);
      expect(await _remaining(), ['stays']);
    });

    test('keeps saved articles and marks them read', () async {
      final id = await _insert(_gamingFeedId, 'saved', saved: true);

      final deleted = await _repo.retireArticles([id]);

      expect(deleted, 0);
      expect(await _remaining(), ['saved']);
      final db = await AppDatabase.instance.database;
      final row = (await db.query(TableNames.articles,
              columns: ['is_read'], where: 'id = ?', whereArgs: [id]))
          .first;
      expect(row['is_read'], 1);
    });

    test('a mixed batch splits correctly', () async {
      final a = await _insert(_gamingFeedId, 'a');
      final b = await _insert(_gamingFeedId, 'b', saved: true);
      final c = await _insert(_gamingFeedId, 'c');

      final deleted = await _repo.retireArticles([a, b, c]);

      expect(deleted, 2);
      expect(await _remaining(), ['b']);
    });

    test('an empty list is a no-op', () async {
      await _insert(_gamingFeedId, 'a');
      expect(await _repo.retireArticles([]), 0);
      expect(await _remaining(), ['a']);
    });
  });

  group('retireAllRead', () {
    test('retires every read unsaved article and leaves unread alone',
        () async {
      await _insert(_gamingFeedId, 'unread');
      await _insert(_gamingFeedId, 'read', read: true);
      await _insert(_gamingFeedId, 'read_saved', read: true, saved: true);

      final deleted = await _repo.retireAllRead();

      expect(deleted, 1);
      expect(await _remaining(), ['read_saved', 'unread']);
    });

    test('is a cheap no-op when nothing is read', () async {
      await _insert(_gamingFeedId, 'a');
      await _insert(_newsFeedId, 'b');

      expect(await _repo.retireAllRead(), 0,
          reason: 'with Show read off nothing is read by the time this runs, '
              'so callers can invoke it unconditionally');
      expect(await _remaining(), ['a', 'b']);
    });

    test('scopes to one folder', () async {
      await _insert(_gamingFeedId, 'gaming_read', read: true);
      await _insert(_newsFeedId, 'news_read', read: true);

      final deleted = await _repo.retireAllRead(folderId: _gamingId);

      expect(deleted, 1);
      expect(await _remaining(), ['news_read'],
          reason: 'clearing one category must not clear another');
    });
  });

  group('mark read', () {
    test('marking read deletes nothing — retirement is separate', () async {
      final id = await _insert(_gamingFeedId, 'a');

      await _repo.markAsRead(id);

      expect(await _remaining(), ['a'],
          reason: 'this is what lets Show read ON defer retirement to the '
              'next refresh instead of removing the row under the reader');
      expect(_guids(await _repo.getAllArticles(showRead: true)), ['a']);
      expect(await _repo.getAllArticles(showRead: false), isEmpty);
    });

    test('markAsUnread returns the article to the unread set', () async {
      final id = await _insert(_gamingFeedId, 'a', read: true);

      await _repo.markAsUnread(id);

      expect(_guids(await _repo.getAllArticles(showRead: false)), ['a']);
    });

    test('markAllAsRead does not delete', () async {
      await _insert(_gamingFeedId, 'a');
      await _insert(_newsFeedId, 'b');

      await _repo.markAllAsRead();

      expect(await _remaining(), ['a', 'b']);
      expect(await _repo.getTotalUnreadCount(), 0);
    });
  });
}
