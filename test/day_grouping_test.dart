// Day-grouping tests.
//
// Written independently of the implementation. Turns a display-ordered
// article list into rows with day headers interleaved, and decides which
// label each header gets.
//
// Covered behaviours:
//  1. Buckets: today, yesterday, within the week, older — and their edges
//  2. A header precedes each new day, and only a new day
//  3. Correct for both sort orders without being told which is in use
//  4. Articles with no publish date fall back to fetched_at
//  5. Empty in, empty out

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/article.dart';
import 'package:flash/utils/day_grouping.dart';

final DateTime _now = DateTime(2026, 8, 26, 14, 30);

Article _article(String guid, DateTime? published, {DateTime? fetched}) =>
    Article(
      id: guid.hashCode,
      feedId: 1,
      guid: guid,
      title: 'Article $guid',
      url: 'https://example.com/$guid',
      publishedAt: published?.millisecondsSinceEpoch,
      fetchedAt: (fetched ?? _now).millisecondsSinceEpoch,
    );

List<String> _shape(List<FeedRow> rows) => [
      for (final r in rows)
        if (r is DayHeaderRow) 'H:${r.bucket.name}' else 'A:${(r as ArticleRow).article.guid}',
    ];

void main() {
  group('bucketFor', () {
    test('the same calendar day is today', () {
      expect(bucketFor(DateTime(2026, 8, 26, 0, 1), _now), DayBucket.today);
      expect(bucketFor(DateTime(2026, 8, 26, 23, 59), _now), DayBucket.today);
    });

    test('a future date is treated as today', () {
      expect(bucketFor(DateTime(2026, 8, 27), _now), DayBucket.today,
          reason: 'a feed with a clock-skewed publish date must not get a '
              'header the app has no label for');
    });

    test('one calendar day back is yesterday', () {
      expect(bucketFor(DateTime(2026, 8, 25), _now), DayBucket.yesterday);
    });

    test('two to six days back is within the week', () {
      expect(bucketFor(DateTime(2026, 8, 24), _now), DayBucket.withinWeek);
      expect(bucketFor(DateTime(2026, 8, 20), _now), DayBucket.withinWeek);
    });

    test('seven days back is older', () {
      expect(bucketFor(DateTime(2026, 8, 19), _now), DayBucket.older,
          reason: 'a weekday name seven days out is ambiguous with today');
    });

    test('buckets are by calendar day, not elapsed hours', () {
      // 23:50 yesterday to 14:30 today is under 24 hours, but it is still
      // yesterday.
      final lateLastNight = DateTime(2026, 8, 25, 23, 50);
      expect(bucketFor(lateLastNight, _now), DayBucket.yesterday);
    });
  });

  group('groupByDay', () {
    test('empty in, empty out', () {
      expect(groupByDay(const [], now: _now), isEmpty);
    });

    test('one header per day, newest first', () {
      final rows = groupByDay([
        _article('a', DateTime(2026, 8, 26, 9)),
        _article('b', DateTime(2026, 8, 26, 8)),
        _article('c', DateTime(2026, 8, 25, 18)),
        _article('d', DateTime(2026, 8, 20, 12)),
      ], now: _now);

      expect(_shape(rows), [
        'H:today', 'A:a', 'A:b',
        'H:yesterday', 'A:c',
        'H:withinWeek', 'A:d',
      ]);
    });

    test('oldest-first ordering produces headers in reverse', () {
      final rows = groupByDay([
        _article('d', DateTime(2026, 8, 20, 12)),
        _article('c', DateTime(2026, 8, 25, 18)),
        _article('a', DateTime(2026, 8, 26, 9)),
      ], now: _now);

      expect(_shape(rows), [
        'H:withinWeek', 'A:d',
        'H:yesterday', 'A:c',
        'H:today', 'A:a',
      ], reason: 'grouping walks the list as given and never re-sorts, so it '
          'is correct for either sort order without being told which');
    });

    test('several articles on one day get one header', () {
      final rows = groupByDay([
        for (var h = 20; h > 0; h--)
          _article('a$h', DateTime(2026, 8, 26, h)),
      ], now: _now);

      expect(rows.whereType<DayHeaderRow>().length, 1);
      expect(rows.whereType<ArticleRow>().length, 20);
    });

    test('a clock-skewed future article does not create a second header', () {
      // Found on device: one feed publishes an hour into tomorrow, and the
      // list showed two headers both reading "Today", one above the other.
      // bucketFor clamps a future date to today for the *label*, so the
      // grouping key has to be clamped to match.
      final rows = groupByDay([
        _article('skewed', DateTime(2026, 8, 27, 1)),
        _article('a', DateTime(2026, 8, 26, 12)),
        _article('b', DateTime(2026, 8, 26, 9)),
      ], now: _now);

      expect(_shape(rows), ['H:today', 'A:skewed', 'A:a', 'A:b'],
          reason: 'there is only one today, so there is one Today header');
    });

    test('a missing publish date falls back to fetched_at', () {
      final rows = groupByDay([
        _article('no_date', null, fetched: DateTime(2026, 8, 25, 10)),
      ], now: _now);

      expect(_shape(rows), ['H:yesterday', 'A:no_date'],
          reason: 'every article must land in exactly one group, or the row '
              'list and the scroll height accounting disagree');
    });

    test('every article is preceded by a header', () {
      final rows = groupByDay([
        _article('a', DateTime(2026, 8, 26)),
        _article('b', DateTime(2026, 8, 25)),
        _article('c', DateTime(2026, 8, 1)),
      ], now: _now);

      for (var i = 0; i < rows.length; i++) {
        if (rows[i] is ArticleRow) {
          expect(rows.sublist(0, i).whereType<DayHeaderRow>(), isNotEmpty);
        }
      }
      expect(rows.first, isA<DayHeaderRow>());
    });
  });
}
