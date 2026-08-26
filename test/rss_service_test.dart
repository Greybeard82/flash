import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/services/rss_service.dart';
import 'package:flash/utils/constants.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Article _art(int i, {DateTime? published, String? guid, String? url}) => Article(
      feedId: 1,
      guid: guid ?? 'guid-$i',
      title: 'Article $i',
      url: url ?? 'https://example.com/$i',
      publishedAt: published?.millisecondsSinceEpoch,
      fetchedAt: 0,
    );

Feed _feed({int? articleLimit}) => Feed(
      id: 1,
      folderId: 1,
      title: 'Test Feed',
      url: 'https://example.com/feed',
      articleLimit: articleLimit,
      createdAt: 0,
    );

final _now = DateTime.now();
final _recent = _now.subtract(const Duration(days: 1));

/// Calls the real [RssService.applyFetchThresholds].
///
/// This used to be a hand-copied reimplementation of the production loop,
/// which is precisely how the "Max articles per feed" setting could stop
/// being respected without a single test failing: the copy still capped at
/// 100 while production did too, and neither consulted the setting. Anything
/// asserting fetch-threshold behaviour must go through the real method.
///
/// Articles are dated relative to now rather than to an injected clock, since
/// the production method reads `DateTime.now()` directly. The margins here are
/// hours or days, so wall-clock drift during a test run is irrelevant.
List<Article> applyThresholds(
  List<Article> articles, {
  int articleLimit = kFetchArticleLimit,
}) =>
    RssService(ArticleRepository(), FeedRepository())
        .applyFetchThresholds(articles, articleLimit: articleLimit);

// ── DB test helpers ────────────────────────────────────────────────────────

late ArticleRepository _repo;


Future<void> _setUpDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  // Seed a folder and feed so foreign keys are satisfied.
  final db = await AppDatabase.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  final folderId = await db.insert(
    TableNames.folders,
    {'name': 'Test', 'position': 0, 'created_at': now},
  );
  await db.insert(
    TableNames.feeds,
    {
      'folder_id': folderId,
      'title': 'Test Feed',
      'url': 'https://example.com/feed',
      'consecutive_failures': 0,
      'is_dead': 0,
      'position': 0,
      'created_at': now,
    },
  );
}

Future<void> _tearDownDb() async {
  await AppDatabase.instance.close();
}

/// Fresh install with two feeds — the original bug report was specifically
/// about a clean DB, not a warm refresh.
late List<int> _twoFeedIds;

Future<void> _setUpTwoFeeds() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  final folderId = await db.insert(
    TableNames.folders,
    {'name': 'Test', 'position': 0, 'created_at': now},
  );
  _twoFeedIds = [
    for (final i in [1, 2])
      await db.insert(TableNames.feeds, {
        'folder_id': folderId,
        'title': 'Feed $i',
        'url': 'https://example.com/feed$i',
        'consecutive_failures': 0,
        'is_dead': 0,
        'position': i,
        'created_at': now,
      }),
  ];
}

/// What one feed's fetch does end to end: parse-sized batch in, thresholds
/// applied, survivors written.
Future<void> _fetchInto(int feedId, int available, {required int limit}) async {
  final parsed = List.generate(
    available,
    (i) => Article(
      feedId: feedId,
      guid: 'feed$feedId-guid-$i',
      title: 'Feed $feedId article $i',
      url: 'https://example.com/$feedId/$i',
      publishedAt: _recent.subtract(Duration(minutes: i)).millisecondsSinceEpoch,
      fetchedAt: 0,
    ),
  );
  await _repo.insertArticles(
    feedId,
    applyThresholds(parsed, articleLimit: limit),
  );
}

Future<int> _countForFeed(int feedId) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM ${TableNames.articles} WHERE feed_id = ?',
    [feedId],
  );
  return rows.first['c'] as int;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ── resolveGuid ──────────────────────────────────────────────────────────

  group('resolveGuid', () {
    test('returns feed guid when present', () {
      expect(RssService.resolveGuid('feed-guid-123', 'https://x.com'), 'feed-guid-123');
    });

    test('falls back to article URL when feed guid is absent', () {
      expect(RssService.resolveGuid(null, 'https://x.com/article'), 'https://x.com/article');
    });

    test('produces identical output on two calls with same inputs', () {
      final a = RssService.resolveGuid('g', 'u');
      final b = RssService.resolveGuid('g', 'u');
      expect(a, b);
    });

    test('throws when both guid and url are absent', () {
      expect(() => RssService.resolveGuid(null, null), throwsException);
    });

    test('throws when guid is empty string and url is null', () {
      expect(() => RssService.resolveGuid('  ', null), throwsException);
    });
  });

  // ── applyFetchThresholds ─────────────────────────────────────────────────

  group('applyFetchThresholds', () {
    test('accepts articles within 7 days', () {
      final result = applyThresholds([_art(1, published: _recent)]);
      expect(result.length, 1);
    });

    test('rejects articles older than 7 days and stops processing', () {
      final old = _now.subtract(const Duration(days: 8));
      final articles = [
        _art(1, published: _recent),
        _art(2, published: old),
        _art(3, published: _recent.subtract(const Duration(hours: 2))),
      ];
      final result = applyThresholds(articles);
      // After sort: 1, 3, 2(old) — stops at 2; only 1 and 3 accepted.
      expect(result.length, 2);
    });

    test('rejects articles with null published_at', () {
      final result = applyThresholds([_art(1)]);
      expect(result, isEmpty);
    });

    test('accepts a maximum of 100 articles per call at the default limit', () {
      final articles = List.generate(
          120, (i) => _art(i, published: _recent.subtract(Duration(minutes: i))));
      final result = applyThresholds(articles);
      expect(result.length, 100);
    });

    test('returns empty list when all articles are older than 7 days', () {
      final articles = List.generate(
          5, (i) => _art(i, published: _now.subtract(Duration(days: 10 + i))));
      final result = applyThresholds(articles);
      expect(result, isEmpty);
    });
  });

  // ── The "Max articles per feed" setting is actually enforced ──────────────
  //
  // This setting was stored and displayed for a long time while nothing read
  // it: every feed kept 100 articles no matter what the dropdown said. The
  // cap now comes from the caller, so these pin that it is the caller's
  // number — not kFetchArticleLimit — that decides.

  group('the configured article limit is what caps a feed', () {
    List<Article> manyRecent(int count) => List.generate(
          count,
          (i) => _art(i, published: _recent.subtract(Duration(minutes: i))),
        );

    test('a limit of 50 keeps 50, not 100', () {
      expect(applyThresholds(manyRecent(120), articleLimit: 50).length, 50);
    });

    test('every option the Settings dropdown offers is honoured', () {
      // 999999 is the dropdown's "Unlimited".
      for (final limit in [50, 100, 200, 500, 999999]) {
        final result = applyThresholds(manyRecent(600), articleLimit: limit);
        expect(result.length, limit < 600 ? limit : 600,
            reason: 'a limit of $limit should cap at ${limit < 600 ? limit : 600}');
      }
    });

    test('the limit never invents articles that were not fetched', () {
      expect(applyThresholds(manyRecent(12), articleLimit: 500).length, 12);
    });

    test('the age cutoff still wins over the count limit', () {
      final articles = [
        ...manyRecent(3),
        ...List.generate(
            5, (i) => _art(100 + i, published: _now.subtract(Duration(days: 9 + i)))),
      ];
      expect(applyThresholds(articles, articleLimit: 500).length, 3,
          reason: 'a generous count limit must not let 9-day-old articles in');
    });

    test('the newest articles are the ones kept', () {
      final articles = manyRecent(20);
      final result = applyThresholds(articles, articleLimit: 5);

      expect(result.length, 5);
      final keptTimes = result.map((a) => a.publishedAt!).toList();
      expect(keptTimes, equals([...keptTimes]..sort((a, b) => b.compareTo(a))),
          reason: 'kept articles should be in newest-first order');
      final droppedNewest = articles
          .where((a) => !result.contains(a))
          .map((a) => a.publishedAt!)
          .reduce((a, b) => a > b ? a : b);
      expect(keptTimes.last, greaterThan(droppedNewest),
          reason: 'every kept article must be newer than every dropped one');
    });

    test('a per-feed override beats the global setting', () {
      final feed = _feed(articleLimit: 25);
      expect(RssService.effectiveArticleLimit(feed, 100), 25);
    });

    test('no per-feed override falls back to the global setting', () {
      expect(RssService.effectiveArticleLimit(_feed(), 50), 50);
    });
  });

  // ── Fresh install, setting at 50 ──────────────────────────────────────────

  group('a fresh fetch on an empty DB respects the setting per feed', () {
    setUp(_setUpTwoFeeds);
    tearDown(_tearDownDb);

    test('each feed independently retains at most the configured limit',
        () async {
      // Both feeds offer far more than the cap.
      for (final id in _twoFeedIds) {
        await _fetchInto(id, 200, limit: 50);
      }

      for (final id in _twoFeedIds) {
        expect(await _countForFeed(id), 50,
            reason: 'feed $id should have stopped at the configured 50');
      }
    });

    test('the All tab is the uncapped sum of every feed, not a fourth limit',
        () async {
      for (final id in _twoFeedIds) {
        await _fetchInto(id, 200, limit: 50);
      }

      final all = await _repo.getAllArticles(showRead: true);
      final perFeed = <int>[
        for (final id in _twoFeedIds) await _countForFeed(id),
      ];

      expect(perFeed, [50, 50]);
      expect(all.length, perFeed.reduce((a, b) => a + b),
          reason: 'All must equal the sum of the feeds — 100 here, which is '
              'deliberately above the per-feed cap of 50');
    });

    test('feeds with different offerings each land on their own count',
        () async {
      await _fetchInto(_twoFeedIds[0], 200, limit: 50); // more than the cap
      await _fetchInto(_twoFeedIds[1], 12, limit: 50); // fewer than the cap

      expect(await _countForFeed(_twoFeedIds[0]), 50);
      expect(await _countForFeed(_twoFeedIds[1]), 12,
          reason: 'the cap is a ceiling, not a quota to fill');

      final all = await _repo.getAllArticles(showRead: true);
      expect(all.length, 62);
    });

    test('raising the limit lets a later fetch bring more in', () async {
      final id = _twoFeedIds[0];
      await _fetchInto(id, 200, limit: 50);
      expect(await _countForFeed(id), 50);

      // User raises the setting; the next fetch offers the same 200 articles.
      // INSERT OR IGNORE means the 50 already stored are not duplicated.
      await _fetchInto(id, 200, limit: 200);
      expect(await _countForFeed(id), 200);
    });

    test('lowering the limit does not retroactively delete stored articles',
        () async {
      // Documented behaviour, not an oversight: the cap governs what a fetch
      // accepts. Pruning what is already stored belongs to the age-based
      // cleanup path, which this change deliberately leaves alone.
      final id = _twoFeedIds[0];
      await _fetchInto(id, 200, limit: 200);
      expect(await _countForFeed(id), 200);

      await _fetchInto(id, 200, limit: 50);
      expect(await _countForFeed(id), 200,
          reason: 'existing rows stay until cleanup removes them by age');
    });
  });

  // ── DB deduplication ─────────────────────────────────────────────────────

  group('DB deduplication', () {
    setUp(_setUpDb);
    tearDown(_tearDownDb);

    test('fetching the same feed twice does not produce duplicate rows', () async {
      final article = _art(1, published: _recent);
      await _repo.insertArticles(1, [article]);
      await _repo.insertArticles(1, [article]);

      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles, where: 'guid = ?', whereArgs: ['guid-1']);
      expect(rows.length, 1);
    });

    test('an article already in DB as read is not reset to unread on re-fetch', () async {
      final article = _art(2, published: _recent);
      await _repo.insertArticles(1, [article]);
      await _repo.markAsRead((await _getOnlyId())!);

      // Re-insert the same article.
      await _repo.insertArticles(1, [article]);

      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles, where: 'guid = ?', whereArgs: ['guid-2']);
      expect(rows.length, 1);
      expect(rows.first['is_read'], 1);
    });

    test('an article already in DB as unread is not duplicated on re-fetch', () async {
      final article = _art(3, published: _recent);
      await _repo.insertArticles(1, [article]);
      await _repo.insertArticles(1, [article]);

      final db = await AppDatabase.instance.database;
      final rows =
          await db.query(TableNames.articles, where: 'guid = ?', whereArgs: ['guid-3']);
      expect(rows.length, 1);
      expect(rows.first['is_read'], 0);
    });

    test('INSERT OR IGNORE confirmed: row count unchanged after duplicate insert', () async {
      final article = _art(4, published: _recent);
      await _repo.insertArticles(1, [article]);

      final db = await AppDatabase.instance.database;
      final before =
          (await db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.articles}')).first['c'];

      await _repo.insertArticles(1, [article]);

      final after =
          (await db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.articles}')).first['c'];
      expect(after, before);
    });
  });
}

Future<int?> _getOnlyId() async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles, limit: 1);
  if (rows.isEmpty) return null;
  return rows.first['id'] as int?;
}
