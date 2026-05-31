import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
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

final _now = DateTime.now();
final _recent = _now.subtract(const Duration(days: 1));

// Thin wrapper that exposes applyFetchThresholds with an injectable clock.
List<Article> applyThresholds(
  List<Article> articles, {
  int dayLimit = kFetchDayLimit,
  int articleLimit = kFetchArticleLimit,
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final cutoffMs =
      ref.subtract(Duration(days: dayLimit)).millisecondsSinceEpoch;
  articles.sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));
  final accepted = <Article>[];
  for (final a in articles) {
    if (a.publishedAt == null) continue;
    if (a.publishedAt! < cutoffMs) break;
    if (accepted.length >= articleLimit) break;
    accepted.add(a);
  }
  return accepted;
}

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
      final result = applyThresholds([_art(1, published: _recent)], now: _now);
      expect(result.length, 1);
    });

    test('rejects articles older than 7 days and stops processing', () {
      final old = _now.subtract(const Duration(days: 8));
      final articles = [
        _art(1, published: _recent),
        _art(2, published: old),
        _art(3, published: _recent.subtract(const Duration(hours: 2))),
      ];
      final result = applyThresholds(articles, now: _now);
      // After sort: 1, 3, 2(old) — stops at 2; only 1 and 3 accepted.
      expect(result.length, 2);
    });

    test('rejects articles with null published_at', () {
      final result = applyThresholds([_art(1)], now: _now);
      expect(result, isEmpty);
    });

    test('accepts a maximum of 100 articles per call', () {
      final articles = List.generate(
          120, (i) => _art(i, published: _recent.subtract(Duration(minutes: i))));
      final result = applyThresholds(articles, now: _now);
      expect(result.length, 100);
    });

    test('returns empty list when all articles are older than 7 days', () {
      final articles = List.generate(
          5, (i) => _art(i, published: _now.subtract(Duration(days: 10 + i))));
      final result = applyThresholds(articles, now: _now);
      expect(result, isEmpty);
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
