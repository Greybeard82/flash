// The Filter bubble's two sliders actually filter what the feed shows.
//
// They were wired to storage semantics and appeared to do nothing:
// `article_limit` caps what a *fetch* accepts, so it never touches rows
// already stored, and `cleanup_age_days` only purges articles you have
// already read, on a cold start. Both are invisible from the feed. The same
// values now also filter the visible list, which is what a panel labelled
// "Filter" is expected to do.
//
// Mirrors feed_screen._applyDisplayFilters against a newest-first list, the
// order the repository returns.

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/article.dart';

/// Same logic as feed_screen._applyDisplayFilters.
List<Article> applyDisplayFilters(
  List<Article> newestFirst, {
  required int limit,
  required int ageDays,
  required DateTime now,
}) {
  final cutoffMs = now.subtract(Duration(days: ageDays)).millisecondsSinceEpoch;
  final perFeed = <int, int>{};
  final kept = <Article>[];
  for (final a in newestFirst) {
    if (a.publishedAt != null && a.publishedAt! < cutoffMs) continue;
    final seen = perFeed[a.feedId] ?? 0;
    if (seen >= limit) continue;
    perFeed[a.feedId] = seen + 1;
    kept.add(a);
  }
  return kept;
}

final _now = DateTime(2026, 8, 19, 12);

Article _art({
  required int id,
  required int feedId,
  required int minutesAgo,
}) =>
    Article(
      id: id,
      feedId: feedId,
      guid: 'g$id',
      title: 'Article $id',
      url: 'https://example.com/$id',
      publishedAt:
          _now.subtract(Duration(minutes: minutesAgo)).millisecondsSinceEpoch,
      fetchedAt: 0,
    );

/// `count` articles for one feed, newest first, one minute apart.
List<Article> _feed(int feedId, int count, {int startMinutesAgo = 0}) => [
      for (var i = 0; i < count; i++)
        _art(
          id: feedId * 1000 + i,
          feedId: feedId,
          minutesAgo: startMinutesAgo + i,
        ),
    ];

void main() {
  group('count limit', () {
    test('caps a single feed at the configured number', () {
      final result = applyDisplayFilters(_feed(1, 120),
          limit: 50, ageDays: 15, now: _now);
      expect(result.length, 50);
    });

    test('is per feed, so All is the sum of every feed allowance', () {
      // Three feeds, 80 articles each, capped at 50.
      final all = [
        ..._feed(1, 80),
        ..._feed(2, 80),
        ..._feed(3, 80),
      ]..sort((a, b) => b.publishedAt!.compareTo(a.publishedAt!));

      final result =
          applyDisplayFilters(all, limit: 50, ageDays: 15, now: _now);

      expect(result.length, 150, reason: '3 feeds x 50');
      for (final feedId in [1, 2, 3]) {
        expect(result.where((a) => a.feedId == feedId).length, 50);
      }
    });

    test('one busy feed cannot crowd out a quiet one', () {
      final all = [
        ..._feed(1, 200),
        ..._feed(2, 3),
      ]..sort((a, b) => b.publishedAt!.compareTo(a.publishedAt!));

      final result =
          applyDisplayFilters(all, limit: 20, ageDays: 15, now: _now);

      expect(result.where((a) => a.feedId == 1).length, 20);
      expect(result.where((a) => a.feedId == 2).length, 3,
          reason: 'the cap is a ceiling, not a quota');
    });

    test('keeps the newest, not an arbitrary slice', () {
      final result =
          applyDisplayFilters(_feed(1, 40), limit: 5, ageDays: 15, now: _now);

      expect(result.length, 5);
      final keptAges = result.map((a) => a.publishedAt!).toList();
      expect(keptAges, equals([...keptAges]..sort((a, b) => b.compareTo(a))));
      // The five newest were published 0..4 minutes ago.
      expect(result.map((a) => a.id), [1000, 1001, 1002, 1003, 1004]);
    });

    test('a limit above the available count changes nothing', () {
      final result =
          applyDisplayFilters(_feed(1, 12), limit: 150, ageDays: 15, now: _now);
      expect(result.length, 12);
    });
  });

  group('age filter', () {
    test('drops articles older than the window', () {
      final articles = [
        ..._feed(1, 3), // minutes old
        ..._feed(2, 3, startMinutesAgo: 60 * 24 * 9), // 9 days old
      ];

      final result =
          applyDisplayFilters(articles, limit: 150, ageDays: 7, now: _now);

      expect(result.every((a) => a.feedId == 1), isTrue);
      expect(result.length, 3);
    });

    test('a wider window admits more', () {
      final articles = [
        ..._feed(1, 3),
        ..._feed(2, 3, startMinutesAgo: 60 * 24 * 9),
      ];

      expect(
        applyDisplayFilters(articles, limit: 150, ageDays: 15, now: _now).length,
        6,
      );
    });

    test('the boundary keeps an article just inside the window', () {
      // 6 days 23 hours old, against a 7-day window.
      final article = _art(id: 1, feedId: 1, minutesAgo: 60 * 24 * 7 - 60);
      expect(
        applyDisplayFilters([article], limit: 150, ageDays: 7, now: _now),
        hasLength(1),
      );
    });

    test('an article with no published date is shown, not hidden', () {
      const undated = Article(
        id: 9,
        feedId: 1,
        guid: 'g9',
        title: 'Undated',
        url: 'https://example.com/9',
        fetchedAt: 0,
      );
      expect(
        applyDisplayFilters([undated], limit: 150, ageDays: 2, now: _now),
        hasLength(1),
        reason: 'hiding content because metadata is missing is worse than '
            'showing it',
      );
    });
  });

  group('the two together', () {
    test('age runs first, so the cap counts only articles still in range', () {
      final articles = [
        ..._feed(1, 10), // recent
        ..._feed(1, 10, startMinutesAgo: 60 * 24 * 9), // stale, same feed
      ];

      final result =
          applyDisplayFilters(articles, limit: 8, ageDays: 7, now: _now);

      expect(result.length, 8);
      expect(result.every((a) => a.publishedAt! > 0), isTrue);
      // All eight come from the recent batch, not the stale one.
      expect(result.map((a) => a.id!).every((id) => id < 1010), isTrue);
    });

    test('an empty list stays empty', () {
      expect(
        applyDisplayFilters([], limit: 50, ageDays: 7, now: _now),
        isEmpty,
      );
    });

    test('the widest settings are effectively no filter', () {
      final articles = _feed(1, 140);
      expect(
        applyDisplayFilters(articles, limit: 150, ageDays: 15, now: _now).length,
        140,
      );
    });
  });
}
