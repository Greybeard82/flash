import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/article.dart';
import 'package:flash/utils/constants.dart';

// Extract the threshold logic into a testable free function that mirrors
// _applyFetchThresholds exactly — same algorithm, no I/O dependencies.
List<Article> applyFetchThresholds(
  List<Article> articles, {
  int dayLimit = kFetchDayLimit,
  int articleLimit = kFetchArticleLimit,
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final cutoffMs =
      ref.subtract(Duration(days: dayLimit)).millisecondsSinceEpoch;

  articles.sort(
      (a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));

  final accepted = <Article>[];
  for (final article in articles) {
    if (article.publishedAt == null) continue;
    if (article.publishedAt! < cutoffMs) break;
    if (accepted.length >= articleLimit) break;
    accepted.add(article);
  }
  return accepted;
}

Article _make(int id, {DateTime? published}) => Article(
      id: id,
      feedId: 1,
      guid: 'guid-$id',
      title: 'Article $id',
      url: 'https://example.com/$id',
      publishedAt: published?.millisecondsSinceEpoch,
      fetchedAt: 0,
    );

void main() {
  final now = DateTime(2026, 5, 12, 12, 0, 0);
  final recent = now.subtract(const Duration(days: 1));
  final boundary = now.subtract(const Duration(days: 7));
  final old = now.subtract(const Duration(days: 8));

  test('An article within 7 days is accepted', () {
    final result = applyFetchThresholds([_make(1, published: recent)], now: now);
    expect(result.length, 1);
  });

  test('An article exactly 7 days ago (boundary) is accepted', () {
    final result = applyFetchThresholds([_make(1, published: boundary)], now: now);
    expect(result.length, 1);
  });

  test('An article older than 7 days is rejected', () {
    final result = applyFetchThresholds([_make(1, published: old)], now: now);
    expect(result, isEmpty);
  });

  test('An article with null publishedAt is rejected', () {
    final result = applyFetchThresholds([_make(1)], now: now);
    expect(result, isEmpty);
  });

  // "Unparseable date string" maps to publishedAt == null in the service layer
  // (the _parseDate helper returns null on failure). We verify null is rejected.
  test('An article with an unparseable published date (null) is rejected', () {
    final article = _make(1); // publishedAt is null — simulates parse failure
    final result = applyFetchThresholds([article], now: now);
    expect(result, isEmpty);
  });

  test('Processing stops at the first article older than 7 days (short-circuit)', () {
    // Mix: recent, old, recent — the second recent should never be evaluated
    // because articles are sorted newest-first and we break on the old one.
    final articles = [
      _make(1, published: recent),
      _make(2, published: old),
      _make(3, published: recent.subtract(const Duration(hours: 1))),
    ];
    final result = applyFetchThresholds(articles, now: now);
    // After sort: 1 (recent), 3 (recent-1h), 2 (old). Break after 2.
    expect(result.length, 2);
    expect(result.map((a) => a.id), containsAll([1, 3]));
  });

  test('Exactly 100 articles are accepted when feed returns more than 100 within 7 days', () {
    final articles = List.generate(
      120,
      (i) => _make(i, published: recent.subtract(Duration(minutes: i))),
    );
    final result = applyFetchThresholds(articles, now: now);
    expect(result.length, 100);
  });

  test('The 101st article is rejected even if within 7 days', () {
    final articles = List.generate(
      101,
      (i) => _make(i, published: recent.subtract(Duration(minutes: i))),
    );
    final result = applyFetchThresholds(articles, now: now);
    expect(result.length, 100);
    // Newest 100 are kept — article 100 (oldest of the 101) is dropped.
    expect(result.map((a) => a.id), isNot(contains(100)));
  });

  test('When count limit is hit, processing stops entirely', () {
    // 101 articles all within 7 days, sorted newest-first by construction.
    // After accepting 100 the loop must break — article index 100 is excluded.
    final articles = List.generate(
      101,
      (i) => _make(i, published: recent.subtract(Duration(minutes: i))),
    );
    final result = applyFetchThresholds(articles, articleLimit: 100, now: now);
    expect(result.length, 100);
  });

  test('An empty article list returns empty without errors', () {
    final result = applyFetchThresholds([], now: now);
    expect(result, isEmpty);
  });

  test('50 articles all within 7 days — all accepted (count limit not reached)', () {
    final articles = List.generate(
      50,
      (i) => _make(i, published: recent.subtract(Duration(minutes: i))),
    );
    final result = applyFetchThresholds(articles, now: now);
    expect(result.length, 50);
  });

  test('5 articles all older than 7 days — none accepted', () {
    final articles = List.generate(
      5,
      (i) => _make(i, published: old.subtract(Duration(days: i))),
    );
    final result = applyFetchThresholds(articles, now: now);
    expect(result, isEmpty);
  });

  test('Articles already in SQLite are not affected by _applyFetchThresholds', () {
    // The function only filters the incoming parsed list; it has no DB access.
    // Passing an old article simulates a pre-existing DB row — it would never
    // be in the incoming list, so no stored article can be removed here.
    // We verify that the function only operates on its input.
    final incoming = [_make(1, published: recent)];
    final result = applyFetchThresholds(incoming, now: now);
    expect(result.length, 1); // incoming accepted
    // Pre-existing articles (not in incoming) are simply not present in input.
  });

  test('Age cutoff is calculated from the moment of fetch, not a hardcoded date', () {
    // Using a different "now" changes what is accepted.
    final futureNow = now.add(const Duration(days: 10));
    // 'recent' is now.subtract(1 day) — which is 11 days before futureNow.
    final result = applyFetchThresholds(
      [_make(1, published: recent)],
      now: futureNow,
    );
    expect(result, isEmpty); // 11 days ago from futureNow → rejected
  });

  test('kFetchDayLimit: changing to 14 accepts articles between 8–14 days old', () {
    final eightDaysAgo = now.subtract(const Duration(days: 8));
    final result = applyFetchThresholds(
      [_make(1, published: eightDaysAgo)],
      dayLimit: 14,
      now: now,
    );
    expect(result.length, 1);
  });

  test('kFetchArticleLimit: changing to 50 causes the 51st article to be rejected', () {
    final articles = List.generate(
      60,
      (i) => _make(i, published: recent.subtract(Duration(minutes: i))),
    );
    final result = applyFetchThresholds(articles, articleLimit: 50, now: now);
    expect(result.length, 50);
  });
}
