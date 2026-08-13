import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/summary_cache.dart';

void main() {
  setUp(SummaryCache.instance.clear);

  group('basic storage', () {
    test('starts empty', () {
      expect(SummaryCache.instance.length, 0);
      expect(SummaryCache.instance.get('https://example.com/a'), isNull);
      expect(SummaryCache.instance.contains('https://example.com/a'), isFalse);
    });

    test('stores and retrieves by URL', () {
      SummaryCache.instance.put('https://example.com/a', 'A summary.');

      expect(SummaryCache.instance.get('https://example.com/a'), 'A summary.');
      expect(SummaryCache.instance.contains('https://example.com/a'), isTrue);
      expect(SummaryCache.instance.length, 1);
    });

    test('distinct URLs do not collide', () {
      SummaryCache.instance.put('https://example.com/a', 'Summary A.');
      SummaryCache.instance.put('https://example.com/b', 'Summary B.');

      expect(SummaryCache.instance.get('https://example.com/a'), 'Summary A.');
      expect(SummaryCache.instance.get('https://example.com/b'), 'Summary B.');
    });

    test('URL matching is exact', () {
      SummaryCache.instance.put('https://example.com/a', 'Summary A.');
      expect(SummaryCache.instance.get('https://example.com/a?utm=x'), isNull);
    });
  });

  group('failures are never cached', () {
    test('put with an empty summary is a no-op', () {
      SummaryCache.instance.put('https://example.com/a', '');

      expect(SummaryCache.instance.length, 0);
      expect(SummaryCache.instance.contains('https://example.com/a'), isFalse);
    });

    test('put with a whitespace-only summary is a no-op', () {
      SummaryCache.instance.put('https://example.com/a', '   \n\t ');
      expect(SummaryCache.instance.length, 0);
    });

    test('an empty put does not evict an existing good entry', () {
      SummaryCache.instance.put('https://example.com/a', 'Good summary.');
      SummaryCache.instance.put('https://example.com/a', '');

      expect(SummaryCache.instance.get('https://example.com/a'), 'Good summary.');
    });
  });

  group('replacement', () {
    test('re-putting an existing URL replaces without duplicating', () {
      SummaryCache.instance.put('https://example.com/a', 'First.');
      SummaryCache.instance.put('https://example.com/a', 'Second.');

      expect(SummaryCache.instance.get('https://example.com/a'), 'Second.');
      expect(SummaryCache.instance.length, 1);
    });
  });

  group('bounded size', () {
    test('holds 50 entries without evicting', () {
      for (var i = 0; i < 50; i++) {
        SummaryCache.instance.put('https://example.com/$i', 'Summary $i.');
      }

      expect(SummaryCache.instance.length, 50);
      expect(SummaryCache.instance.get('https://example.com/0'), 'Summary 0.');
    });

    test('evicts the oldest entry on the 51st insert', () {
      for (var i = 0; i < 51; i++) {
        SummaryCache.instance.put('https://example.com/$i', 'Summary $i.');
      }

      expect(SummaryCache.instance.length, 50);
      expect(SummaryCache.instance.get('https://example.com/0'), isNull);
      expect(SummaryCache.instance.get('https://example.com/1'), 'Summary 1.');
      expect(SummaryCache.instance.get('https://example.com/50'), 'Summary 50.');
    });

    test('re-putting an existing URL refreshes its position', () {
      for (var i = 0; i < 50; i++) {
        SummaryCache.instance.put('https://example.com/$i', 'Summary $i.');
      }

      SummaryCache.instance.put('https://example.com/0', 'Refreshed.');
      SummaryCache.instance.put('https://example.com/new', 'New.');

      expect(SummaryCache.instance.get('https://example.com/0'), 'Refreshed.');
      expect(SummaryCache.instance.get('https://example.com/1'), isNull);
    });
  });

  group('clear', () {
    test('empties the cache', () {
      SummaryCache.instance.put('https://example.com/a', 'A.');
      SummaryCache.instance.clear();

      expect(SummaryCache.instance.length, 0);
      expect(SummaryCache.instance.get('https://example.com/a'), isNull);
    });
  });
}
