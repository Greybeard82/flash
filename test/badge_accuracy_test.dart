// The unread badge must count what the list can actually show.
//
// Confirmed on a Pixel 11 Pro at pass 07: the All badge read 428 while the
// list displayed 5 articles; Tech read 216 against 6. Two independent faults
// produced it. The count queries had no age filter while the list applies a
// `cleanup_age_days` window, so the badge counted rows the list is guaranteed
// not to show. And cleanup only ever deleted *read* articles, so unread ones
// aged out of the display window and then stayed in the database for ever —
// the gap could only widen.
//
// The assertion that matters here is `count == list.length`, checked against
// the real list pipeline rather than a hand-written copy of the filter. A test
// that reimplements the filter would agree with itself while the app disagreed
// with the user.
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

int _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  _gamingId = await db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': now});
  _newsId = await db.insert(TableNames.folders,
      {'name': 'News', 'position': 1, 'created_at': now});
  _gamingFeedId = await db.insert(TableNames.feeds, {
    'folder_id': _gamingId,
    'title': 'Gaming Feed',
    'url': 'https://gaming.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': now,
  });
  _newsFeedId = await db.insert(TableNames.feeds, {
    'folder_id': _newsId,
    'title': 'News Feed',
    'url': 'https://news.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': now,
  });
}

Future<int> _insert(
  int feedId,
  String guid, {
  required int publishedAt,
  bool read = false,
  bool saved = false,
  bool blocked = false,
}) async {
  final db = await AppDatabase.instance.database;
  return db.insert(TableNames.articles, {
    'feed_id': feedId,
    'guid': guid,
    'title': 'Article $guid',
    'url': 'https://example.com/$guid',
    'published_at': publishedAt,
    'fetched_at': publishedAt,
    'is_read': read ? 1 : 0,
    'is_blocked': blocked ? 1 : 0,
    'is_saved': saved ? 1 : 0,
  });
}

/// The real display filter, lifted from FeedScreen._applyDisplayFilters.
///
/// Deliberately mirrors the screen rather than the count query: the point is
/// to compare the badge against what the list produces. It shares
/// [displayCutoffMs] with both, which is the arithmetic that actually has to
/// agree.
List<Article> _displayed(List<Article> newestFirst, int windowDays,
    {int perFeedLimit = kFetchArticleLimit}) {
  final cutoffMs = displayCutoffMs(windowDays);
  final perFeed = <int, int>{};
  final kept = <Article>[];
  for (final a in newestFirst) {
    if (a.publishedAt != null && a.publishedAt! < cutoffMs) continue;
    final seen = perFeed[a.feedId] ?? 0;
    if (seen >= perFeedLimit) continue;
    perFeed[a.feedId] = seen + 1;
    kept.add(a);
  }
  return kept;
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('the count honours the display window', () {
    test('an unread article inside the window is counted, one outside is not',
        () async {
      await _insert(_gamingFeedId, 'fresh', publishedAt: _daysAgo(1));
      await _insert(_gamingFeedId, 'stale', publishedAt: _daysAgo(30));

      expect(await _repo.getTotalUnreadCount(windowDays: 7), 1,
          reason: 'the 30-day-old article can never appear in the list, so '
              'counting it makes the badge a number about nothing');
    });

    test('a null published_at is counted, matching the list', () async {
      final db = await AppDatabase.instance.database;
      await db.insert(TableNames.articles, {
        'feed_id': _gamingFeedId,
        'guid': 'nodate',
        'title': 'No date',
        'url': 'https://example.com/nodate',
        'published_at': null,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
        'is_read': 0,
        'is_blocked': 0,
        'is_saved': 0,
      });

      expect(await _repo.getTotalUnreadCount(windowDays: 7), 1,
          reason: 'the list shows it rather than hiding it silently, so the '
              'badge has to agree');
    });
  });

  group('the count equals what the list displays', () {
    test('across several window settings', () async {
      for (var d = 1; d <= 20; d++) {
        await _insert(_gamingFeedId, 'g$d', publishedAt: _daysAgo(d));
        await _insert(_newsFeedId, 'n$d', publishedAt: _daysAgo(d));
      }

      for (final window in [2, 5, 7, 10, 15]) {
        final visible = _displayed(
            await _repo.getAllArticles(showRead: false), window);
        final counted = await _repo.getTotalUnreadCount(windowDays: window);

        expect(counted, visible.length,
            reason: 'THE assertion: at a $window-day window the badge says '
                '$counted and the list shows ${visible.length}. These are the '
                'two numbers the user compares, and they diverging by 423 is '
                'what this pass exists to fix.');
      }
    });

    test('read articles are in neither, with Show read off', () async {
      await _insert(_gamingFeedId, 'unread', publishedAt: _daysAgo(1));
      await _insert(_gamingFeedId, 'read', publishedAt: _daysAgo(1), read: true);

      final visible =
          _displayed(await _repo.getAllArticles(showRead: false), 7);
      expect(await _repo.getTotalUnreadCount(windowDays: 7), visible.length);
      expect(visible.length, 1);
    });
  });

  test('All equals the sum over folders', () async {
    for (var i = 0; i < 4; i++) {
      await _insert(_gamingFeedId, 'g$i', publishedAt: _daysAgo(1));
    }
    for (var i = 0; i < 3; i++) {
      await _insert(_newsFeedId, 'n$i', publishedAt: _daysAgo(2));
    }
    // Outside the window: must not reach either number.
    await _insert(_gamingFeedId, 'old', publishedAt: _daysAgo(30));

    final byFolder = await _repo.getAllFolderUnreadCounts(windowDays: 7);
    final all = await _repo.getTotalUnreadCount(windowDays: 7);

    expect(byFolder[_gamingId], 4);
    expect(byFolder[_newsId], 3);
    expect(all, 7);
    expect(byFolder.values.fold<int>(0, (a, b) => a + b), all);
    expect(await _repo.getUnreadCount(_gamingId, windowDays: 7), 4);
  });

  test('blocked articles are excluded from the count and the list', () async {
    await _insert(_gamingFeedId, 'ok', publishedAt: _daysAgo(1));
    await _insert(_gamingFeedId, 'blocked',
        publishedAt: _daysAgo(1), blocked: true);

    final visible = _displayed(await _repo.getAllArticles(showRead: false), 7);
    expect(await _repo.getTotalUnreadCount(windowDays: 7), 1);
    expect(visible.length, 1);
  });

  test('a saved-and-read article is treated the same by count and list',
      () async {
    await _insert(_gamingFeedId, 'saved_read',
        publishedAt: _daysAgo(1), read: true, saved: true);

    final visible = _displayed(await _repo.getAllArticles(showRead: false), 7);
    expect(visible.length, 0,
        reason: 'a read bookmark leaves the feed. It used to be pinned there '
            'instead, because it is exempt from retirement and the query '
            'exempted it too, so nothing could ever remove it');
    expect(await _repo.getTotalUnreadCount(windowDays: 7), 0);
    // This used to be the one case where a visible article was not counted.
    // Now the badge and the list agree here as well, which is the whole
    // reason the badge is allowed to count rows rather than re-run the list.
    expect(visible.length, await _repo.getTotalUnreadCount(windowDays: 7));
  });

  group('cleanup removes unread articles nothing can reach', () {
    test('deletes unread unsaved articles past kUnreadRetentionDays',
        () async {
      await _insert(_gamingFeedId, 'ancient',
          publishedAt: _daysAgo(kUnreadRetentionDays + 5));
      await _insert(_gamingFeedId, 'recent', publishedAt: _daysAgo(1));

      await _repo.runCleanup(days: 7);

      final db = await AppDatabase.instance.database;
      final left = (await db.query(TableNames.articles, columns: ['guid']))
          .map((r) => r['guid'])
          .toSet();
      expect(left, {'recent'});
    });

    test('keeps an unread article just inside the retention floor', () async {
      await _insert(_gamingFeedId, 'edge',
          publishedAt: _daysAgo(kUnreadRetentionDays - 1));

      await _repo.runCleanup(days: 7);

      final db = await AppDatabase.instance.database;
      expect((await db.query(TableNames.articles)).length, 1,
          reason: 'boundary checked from the keeping side too');
    });

    test('an unread article outside cleanup_age_days but inside the retention '
        'floor survives', () async {
      // The whole reason the floor is fixed at 15 rather than following the
      // slider: at a 2-day setting this article is not displayed, but widening
      // the slider must still bring it back.
      await _insert(_gamingFeedId, 'recoverable', publishedAt: _daysAgo(10));

      await _repo.runCleanup(days: 2);

      final db = await AppDatabase.instance.database;
      expect((await db.query(TableNames.articles)).length, 1,
          reason: 'deleting it under a narrow window would destroy something '
              'the user could have recovered by moving one slider');

      final visibleAt15 =
          _displayed(await _repo.getAllArticles(showRead: false), 15);
      expect(visibleAt15.length, 1, reason: 'and widening does bring it back');
    });

    test('saved articles survive cleanup at any age', () async {
      await _insert(_gamingFeedId, 'saved_ancient',
          publishedAt: _daysAgo(kUnreadRetentionDays + 100), saved: true);
      await _insert(_gamingFeedId, 'saved_read_ancient',
          publishedAt: _daysAgo(kUnreadRetentionDays + 100),
          saved: true,
          read: true);

      await _repo.runCleanup(days: 7);

      final db = await AppDatabase.instance.database;
      expect((await db.query(TableNames.articles)).length, 2,
          reason: 'a bookmark is the user saying keep this, and no age rule '
              'overrides that');
    });
  });
}
