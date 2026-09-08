import 'package:flutter_test/flutter_test.dart';

import 'package:flash/models/content_block.dart';
import 'package:flash/services/clean_article_cache.dart';

List<ContentBlock> _blocks(String text) => [ParagraphBlock(text)];

void main() {
  setUp(CleanArticleCache.instance.clear);

  group('basic storage', () {
    test('starts empty', () {
      expect(CleanArticleCache.instance.length, 0);
      expect(CleanArticleCache.instance.get('https://example.com/a'), isNull);
      expect(
          CleanArticleCache.instance.contains('https://example.com/a'), isFalse);
    });

    test('stores and retrieves by URL', () {
      CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));

      final got = CleanArticleCache.instance.get('https://example.com/a');
      expect(got, isNotNull);
      expect((got!.single as ParagraphBlock).text, 'A');
      expect(
          CleanArticleCache.instance.contains('https://example.com/a'), isTrue);
      expect(CleanArticleCache.instance.length, 1);
    });

    test('distinct URLs do not collide', () {
      CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));
      CleanArticleCache.instance.put('https://example.com/b', _blocks('B'));

      expect(
          (CleanArticleCache.instance.get('https://example.com/a')!.single
                  as ParagraphBlock)
              .text,
          'A');
      expect(
          (CleanArticleCache.instance.get('https://example.com/b')!.single
                  as ParagraphBlock)
              .text,
          'B');
    });

    test('URL matching is exact', () {
      CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));
      expect(
          CleanArticleCache.instance.get('https://example.com/a?utm=x'), isNull);
      expect(CleanArticleCache.instance.contains('https://example.com/a?utm=x'),
          isFalse);
    });

    test('re-putting a URL replaces rather than duplicating', () {
      CleanArticleCache.instance.put('https://example.com/a', _blocks('first'));
      CleanArticleCache.instance.put('https://example.com/a', _blocks('second'));

      expect(CleanArticleCache.instance.length, 1);
      expect(
          (CleanArticleCache.instance.get('https://example.com/a')!.single
                  as ParagraphBlock)
              .text,
          'second');
    });

    test('clear empties it', () {
      CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));
      CleanArticleCache.instance.clear();
      expect(CleanArticleCache.instance.length, 0);
    });
  });

  group('eviction', () {
    test('holds 50 entries without evicting', () {
      for (var i = 0; i < 50; i++) {
        CleanArticleCache.instance.put('https://example.com/$i', _blocks('$i'));
      }
      expect(CleanArticleCache.instance.length, 50);
      expect(CleanArticleCache.instance.contains('https://example.com/0'),
          isTrue);
    });

    test('the 51st evicts the oldest', () {
      for (var i = 0; i < 51; i++) {
        CleanArticleCache.instance.put('https://example.com/$i', _blocks('$i'));
      }
      expect(CleanArticleCache.instance.length, 50);
      expect(CleanArticleCache.instance.contains('https://example.com/0'),
          isFalse);
      expect(CleanArticleCache.instance.contains('https://example.com/50'),
          isTrue);
    });

    test('re-putting refreshes an entry\'s position', () {
      for (var i = 0; i < 50; i++) {
        CleanArticleCache.instance.put('https://example.com/$i', _blocks('$i'));
      }
      // Touch the oldest, so it is no longer first out.
      CleanArticleCache.instance.put('https://example.com/0', _blocks('again'));
      CleanArticleCache.instance.put('https://example.com/new', _blocks('new'));

      expect(CleanArticleCache.instance.contains('https://example.com/0'),
          isTrue);
      expect(CleanArticleCache.instance.contains('https://example.com/1'),
          isFalse);
    });
  });

  // The deliberate divergence from SummaryCache, which drops its failures.
  // See CleanArticleCache's doc comment for why extraction failures are worth
  // remembering and summary failures are not.
  group('failures are remembered', () {
    test('a null verdict is recorded, not dropped', () {
      CleanArticleCache.instance.put('https://example.com/a', null);

      expect(
          CleanArticleCache.instance.contains('https://example.com/a'), isTrue);
      expect(CleanArticleCache.instance.get('https://example.com/a'), isNull);
      expect(CleanArticleCache.instance.length, 1);
    });

    test('an empty block list is recorded as a failure', () {
      CleanArticleCache.instance.put('https://example.com/a', []);

      expect(
          CleanArticleCache.instance.contains('https://example.com/a'), isTrue);
      expect(CleanArticleCache.instance.get('https://example.com/a'), isNull);
    });

    test('a recorded failure counts toward the entry bound', () {
      for (var i = 0; i < 51; i++) {
        CleanArticleCache.instance.put('https://example.com/$i', null);
      }
      expect(CleanArticleCache.instance.length, 50);
      expect(CleanArticleCache.instance.contains('https://example.com/0'),
          isFalse);
    });

    test('a later success upgrades a recorded failure in place', () {
      CleanArticleCache.instance.put('https://example.com/a', null);
      CleanArticleCache.instance.put('https://example.com/a', _blocks('now ok'));

      expect(CleanArticleCache.instance.length, 1);
      expect(
          (CleanArticleCache.instance.get('https://example.com/a')!.single
                  as ParagraphBlock)
              .text,
          'now ok');
    });
  });
}
