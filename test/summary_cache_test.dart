import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/summary_cache.dart';
import 'package:flash/services/summary_formatter.dart';

/// The tier the pre-existing cases run at; cross-tier behaviour has its own
/// group below.
const _t = kSummaryLengthStandard;

void main() {
  setUp(SummaryCache.instance.clear);

  group('basic storage', () {
    test('starts empty', () {
      expect(SummaryCache.instance.length, 0);
      expect(SummaryCache.instance.get('https://example.com/a', _t), isNull);
      expect(SummaryCache.instance.contains('https://example.com/a', _t), isFalse);
    });

    test('stores and retrieves by URL', () {
      SummaryCache.instance.put('https://example.com/a', _t, 'A summary.');

      expect(SummaryCache.instance.get('https://example.com/a', _t), 'A summary.');
      expect(SummaryCache.instance.contains('https://example.com/a', _t), isTrue);
      expect(SummaryCache.instance.length, 1);
    });

    test('distinct URLs do not collide', () {
      SummaryCache.instance.put('https://example.com/a', _t, 'Summary A.');
      SummaryCache.instance.put('https://example.com/b', _t, 'Summary B.');

      expect(SummaryCache.instance.get('https://example.com/a', _t), 'Summary A.');
      expect(SummaryCache.instance.get('https://example.com/b', _t), 'Summary B.');
    });

    test('URL matching is exact', () {
      SummaryCache.instance.put('https://example.com/a', _t, 'Summary A.');
      expect(SummaryCache.instance.get('https://example.com/a?utm=x', _t), isNull);
    });
  });

  group('failures are never cached', () {
    test('put with an empty summary is a no-op', () {
      SummaryCache.instance.put('https://example.com/a', _t, '');

      expect(SummaryCache.instance.length, 0);
      expect(SummaryCache.instance.contains('https://example.com/a', _t), isFalse);
    });

    test('put with a whitespace-only summary is a no-op', () {
      SummaryCache.instance.put('https://example.com/a', _t, '   \n\t ');
      expect(SummaryCache.instance.length, 0);
    });

    test('an empty put does not evict an existing good entry', () {
      SummaryCache.instance.put('https://example.com/a', _t, 'Good summary.');
      SummaryCache.instance.put('https://example.com/a', _t, '');

      expect(SummaryCache.instance.get('https://example.com/a', _t), 'Good summary.');
    });
  });

  group('replacement', () {
    test('re-putting an existing URL replaces without duplicating', () {
      SummaryCache.instance.put('https://example.com/a', _t, 'First.');
      SummaryCache.instance.put('https://example.com/a', _t, 'Second.');

      expect(SummaryCache.instance.get('https://example.com/a', _t), 'Second.');
      expect(SummaryCache.instance.length, 1);
    });
  });

  group('bounded size', () {
    test('holds 50 entries without evicting', () {
      for (var i = 0; i < 50; i++) {
        SummaryCache.instance.put('https://example.com/$i', _t, 'Summary $i.');
      }

      expect(SummaryCache.instance.length, 50);
      expect(SummaryCache.instance.get('https://example.com/0', _t), 'Summary 0.');
    });

    test('evicts the oldest entry on the 51st insert', () {
      for (var i = 0; i < 51; i++) {
        SummaryCache.instance.put('https://example.com/$i', _t, 'Summary $i.');
      }

      expect(SummaryCache.instance.length, 50);
      expect(SummaryCache.instance.get('https://example.com/0', _t), isNull);
      expect(SummaryCache.instance.get('https://example.com/1', _t), 'Summary 1.');
      expect(SummaryCache.instance.get('https://example.com/50', _t), 'Summary 50.');
    });

    test('re-putting an existing URL refreshes its position', () {
      for (var i = 0; i < 50; i++) {
        SummaryCache.instance.put('https://example.com/$i', _t, 'Summary $i.');
      }

      SummaryCache.instance.put('https://example.com/0', _t, 'Refreshed.');
      SummaryCache.instance.put('https://example.com/new', _t, 'New.');

      expect(SummaryCache.instance.get('https://example.com/0', _t), 'Refreshed.');
      expect(SummaryCache.instance.get('https://example.com/1', _t), isNull);
    });
  });

  group('the tier is part of the key', () {
    // The bug this fixes: keyed on URL alone, a summary generated at
    // Standard was handed straight back after the reader switched to
    // Detailed. The new tier appeared to do nothing on any article already
    // summarised once, and nothing errored — it just quietly served stale
    // text, which is the kind of failure only a test like this catches.
    const url = 'https://example.com/a';

    test('the same article at two tiers does not collide', () {
      SummaryCache.instance.put(url, kSummaryLengthStandard, 'Standard text.');
      SummaryCache.instance.put(url, kSummaryLengthDetailed, 'Detailed text.');

      expect(SummaryCache.instance.get(url, kSummaryLengthStandard),
          'Standard text.');
      expect(SummaryCache.instance.get(url, kSummaryLengthDetailed),
          'Detailed text.');
      expect(SummaryCache.instance.length, 2,
          reason: 'the two tiers are independent entries, not one overwritten');
    });

    test('a tier with no entry yet misses, even when another tier has one',
        () {
      SummaryCache.instance.put(url, kSummaryLengthStandard, 'Standard text.');

      expect(SummaryCache.instance.get(url, kSummaryLengthDetailed), isNull,
          reason: 'this miss is what makes the switch regenerate rather than '
              'show the old length');
      expect(SummaryCache.instance.contains(url, kSummaryLengthDetailed),
          isFalse);
    });

    test('writing one tier does not evict another tier of the same article',
        () {
      SummaryCache.instance.put(url, kSummaryLengthShort, 'Short text.');
      SummaryCache.instance.put(url, kSummaryLengthStandard, 'Standard text.');
      SummaryCache.instance.put(url, kSummaryLengthDetailed, 'Detailed text.');

      // Switching back and forth should be free, not a regeneration each way.
      expect(SummaryCache.instance.get(url, kSummaryLengthShort), 'Short text.');
      expect(SummaryCache.instance.get(url, kSummaryLengthStandard),
          'Standard text.');
      expect(SummaryCache.instance.get(url, kSummaryLengthDetailed),
          'Detailed text.');
      expect(SummaryCache.instance.length, 3);
    });

    test('replacing within one tier leaves the others alone', () {
      SummaryCache.instance.put(url, kSummaryLengthStandard, 'First.');
      SummaryCache.instance.put(url, kSummaryLengthDetailed, 'Detailed.');
      SummaryCache.instance.put(url, kSummaryLengthStandard, 'Second.');

      expect(SummaryCache.instance.get(url, kSummaryLengthStandard), 'Second.');
      expect(SummaryCache.instance.get(url, kSummaryLengthDetailed),
          'Detailed.');
      expect(SummaryCache.instance.length, 2);
    });

    test('the same tier on two articles does not collide either', () {
      SummaryCache.instance
          .put('https://example.com/a', kSummaryLengthShort, 'A.');
      SummaryCache.instance
          .put('https://example.com/b', kSummaryLengthShort, 'B.');

      expect(SummaryCache.instance.get('https://example.com/a',
          kSummaryLengthShort), 'A.');
      expect(SummaryCache.instance.get('https://example.com/b',
          kSummaryLengthShort), 'B.');
    });

    test('a url and tier cannot be confused for a different pair', () {
      // Guards the composite key against being assembled in a way where one
      // (url, tier) pair can spell another — the classic concatenation bug.
      SummaryCache.instance.put('https://example.com/a', 'b', 'First.');
      SummaryCache.instance.put('https://example.com/a::b', 'c', 'Second.');

      expect(SummaryCache.instance.get('https://example.com/a', 'b'), 'First.');
      expect(SummaryCache.instance.get('https://example.com/a::b', 'c'),
          'Second.');
      expect(SummaryCache.instance.length, 2);
    });
  });

  group('clear', () {
    test('empties the cache', () {
      SummaryCache.instance.put('https://example.com/a', _t, 'A.');
      SummaryCache.instance.clear();

      expect(SummaryCache.instance.length, 0);
      expect(SummaryCache.instance.get('https://example.com/a', _t), isNull);
    });
  });
}
