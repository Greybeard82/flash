// Read-visibility tests against the real database.
//
// Written independently of the implementation. Replaces
// session_read_visibility_test.dart, which covered the in-memory
// SessionReadTracker that schema v11 removed. Same question — "which articles
// does the list show?" — asked of a persisted read_at instead.
//
// Covered behaviours:
//  1. Show read off: unread only, in every tab
//  2. Show read on: unread, plus anything read inside the window
//  3. The window has an edge, and articles read before it stay hidden
//  4. Read state is global — a folder query hides an article read in All
//  5. Mark-unread clears read_at and returns the article to the unread set
//  6. Re-marking a read article does not extend its stay
//  7. Mark all as read dismisses permanently; the dwell timer does not
//  8. Rows read before the migration (read_at NULL) stay hidden
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
late int _gamingId;
late int _newsId;
late int _gamingFeedId;
late int _newsFeedId;

const int _now = 1750000000000; // fixed clock, ms
int get _windowStart =>
    _now - const Duration(hours: kShowReadBufferHours).inMilliseconds;

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

Future<int> _insert(int feedId, String guid) async {
  final db = await AppDatabase.instance.database;
  return db.insert(TableNames.articles, {
    'feed_id': feedId,
    'guid': guid,
    'title': 'Article $guid',
    'url': 'https://example.com/$guid',
    'published_at': _now,
    'fetched_at': _now,
    'is_read': 0,
    'is_blocked': 0,
    'is_saved': 0,
  });
}

Future<void> _setReadAt(int id, int? readAt) async {
  final db = await AppDatabase.instance.database;
  await db.update(TableNames.articles, {'is_read': 1, 'read_at': readAt},
      where: 'id = ?', whereArgs: [id]);
}

Future<int?> _readAtOf(int id) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles,
      columns: ['read_at'], where: 'id = ?', whereArgs: [id]);
  return rows.first['read_at'] as int?;
}

List<String> _guids(List<Article> articles) =>
    articles.map((a) => a.guid).toList()..sort();

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('Show read off', () {
    test('the All tab shows unread articles only', () async {
      await _insert(_gamingFeedId, 'unread');
      final read = await _insert(_gamingFeedId, 'read');
      await _setReadAt(read, _now - 1000);

      final visible = await _repo.getAllArticles(readSinceMs: null);
      expect(_guids(visible), ['unread'],
          reason: 'a null cutoff hides every read article, however recent');
    });

    test('an article read in All is gone from its own category too', () async {
      await _insert(_gamingFeedId, 'unread');
      final read = await _insert(_gamingFeedId, 'read_in_all');
      await _setReadAt(read, _now - 1000);

      final visible =
          await _repo.getArticlesByFolder(_gamingId, readSinceMs: null);
      expect(_guids(visible), ['unread'],
          reason: 'read state is global — scrolling past a gaming article in '
              'the All tab must clear it from the Gaming tab as well');
    });
  });

  group('Show read on', () {
    test('recently read articles come back', () async {
      await _insert(_gamingFeedId, 'unread');
      final read = await _insert(_gamingFeedId, 'read_recently');
      await _setReadAt(read, _now - 1000);

      final visible = await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(_guids(visible), ['read_recently', 'unread']);
    });

    test('articles read before the window stay hidden', () async {
      await _insert(_gamingFeedId, 'unread');
      final old = await _insert(_gamingFeedId, 'read_long_ago');
      await _setReadAt(old, _windowStart - 1);

      final visible = await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(_guids(visible), ['unread'],
          reason: 'one millisecond outside the window is outside the window');
    });

    test('an article read exactly at the window edge is visible', () async {
      final edge = await _insert(_gamingFeedId, 'edge');
      await _setReadAt(edge, _windowStart);

      final visible = await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(_guids(visible), ['edge'], reason: 'the comparison is >=');
    });

    test('rows carried over from before the migration stay hidden', () async {
      final legacy = await _insert(_gamingFeedId, 'legacy');
      await _setReadAt(legacy, null); // is_read = 1, read_at NULL

      final visible = await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(visible, isEmpty,
          reason: 'NULL never satisfies >=, and there is no honest timestamp '
              'to invent for articles read before v11');
    });

    test('a folder query is scoped to that folder', () async {
      await _insert(_gamingFeedId, 'gaming');
      await _insert(_newsFeedId, 'news');

      final visible =
          await _repo.getArticlesByFolder(_gamingId, readSinceMs: _windowStart);
      expect(_guids(visible), ['gaming']);
    });
  });

  group('Stamping', () {
    test('markAsRead records when it happened', () async {
      final id = await _insert(_gamingFeedId, 'a');
      await _repo.markAsRead(id, readAt: _now);

      expect(await _readAtOf(id), _now);
    });

    test('re-marking a read article does not extend its stay', () async {
      final id = await _insert(_gamingFeedId, 'a');
      await _repo.markAsRead(id, readAt: _now - 5000);
      await _repo.markAsRead(id, readAt: _now);

      expect(await _readAtOf(id), _now - 5000,
          reason: 'COALESCE keeps the original read time, so an article '
              'cannot be kept alive in the window by touching it again');
    });

    test('markManyRead stamps every id', () async {
      final a = await _insert(_gamingFeedId, 'a');
      final b = await _insert(_gamingFeedId, 'b');
      await _repo.markManyRead([a, b], readAt: _now);

      expect(await _readAtOf(a), _now);
      expect(await _readAtOf(b), _now);
    });

    test('markAsUnread clears read_at', () async {
      final id = await _insert(_gamingFeedId, 'a');
      await _repo.markAsRead(id, readAt: _now);
      await _repo.markAsUnread(id);

      expect(await _readAtOf(id), isNull);
      final visible = await _repo.getAllArticles(readSinceMs: null);
      expect(_guids(visible), ['a'],
          reason: 'an unread article is visible even with read articles '
              'hidden');
    });
  });

  group('Mark all as read vs the end-of-feed dwell timer', () {
    test('mark all as read dismisses permanently', () async {
      await _insert(_gamingFeedId, 'a');
      await _insert(_newsFeedId, 'b');
      await _repo.markAllAsRead(readAt: kDismissedReadAt);

      final visible = await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(visible, isEmpty,
          reason: 'pressing Mark all as read means clear these out — they '
              'must not reappear when Show read is switched on');
    });

    test('mark all as read overwrites an existing read time', () async {
      final id = await _insert(_gamingFeedId, 'a');
      await _repo.markAsRead(id, readAt: _now - 1000);
      await _repo.markAllAsRead(readAt: kDismissedReadAt);

      expect(await _readAtOf(id), kDismissedReadAt,
          reason: 'clearing a tab clears the whole tab, including what was '
              'read ten minutes ago');
    });

    test('mark all as read by folder leaves other folders alone', () async {
      await _insert(_gamingFeedId, 'gaming');
      await _insert(_newsFeedId, 'news');
      await _repo.markAllAsReadByFolder(_gamingId, readAt: kDismissedReadAt);

      final visible = await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(_guids(visible), ['news']);
    });

    test('the dwell timer marks read without dismissing', () async {
      await _insert(_gamingFeedId, 'a');
      await _repo.markAllAsRead(readAt: _now);

      final withReadShown =
          await _repo.getAllArticles(readSinceMs: _windowStart);
      expect(_guids(withReadShown), ['a'],
          reason: 'reaching the end of a feed is passive reading, not '
              'dismissal — those articles stay restorable');

      final withReadHidden = await _repo.getAllArticles(readSinceMs: null);
      expect(withReadHidden, isEmpty);
    });
  });
}
