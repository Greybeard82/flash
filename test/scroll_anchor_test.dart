import 'package:flutter_test/flutter_test.dart';
import 'package:flash/reading/scroll_anchor.dart';

void main() {
  const anchor = ScrollAnchor(
    articleId: 30,
    fallbackIds: [20, 10],
    pixelsIntoItem: 12.0,
  );

  group('ScrollAnchorResolver.resolve', () {
    test('resolves to the anchor article when it survived', () {
      final t = ScrollAnchorResolver.resolve(anchor, const [50, 40, 30, 20, 10]);
      expect(t.index, 2);
      expect(t.pixelsIntoItem, 12.0);
      expect(t.exact, isTrue);
    });

    test('resolves to the anchor after new articles were inserted above it', () {
      final t =
          ScrollAnchorResolver.resolve(anchor, const [70, 60, 50, 40, 30, 20, 10]);
      expect(t.index, 4);
      expect(t.pixelsIntoItem, 12.0);
      expect(t.exact, isTrue);
    });

    test('falls back to the nearest surviving article below the anchor', () {
      final t = ScrollAnchorResolver.resolve(anchor, const [50, 40, 20, 10]);
      expect(t.index, 2);
      expect(t.pixelsIntoItem, 0.0);
      expect(t.exact, isFalse);
    });

    test('walks the fallback chain in order', () {
      final t = ScrollAnchorResolver.resolve(anchor, const [50, 40, 10]);
      expect(t.index, 2);
      expect(t.exact, isFalse);
    });

    test('returns the top of the list when nothing in the chain survived', () {
      final t = ScrollAnchorResolver.resolve(anchor, const [50, 40]);
      expect(t.index, 0);
      expect(t.pixelsIntoItem, 0.0);
      expect(t.exact, isFalse);
    });

    test('returns the top of the list when the list is empty', () {
      final t = ScrollAnchorResolver.resolve(anchor, const []);
      expect(t.index, 0);
      expect(t.exact, isFalse);
    });

    test('an inexact resolution never carries the old intra-item offset', () {
      final t = ScrollAnchorResolver.resolve(anchor, const [50, 40, 10]);
      expect(t.pixelsIntoItem, 0.0);
    });
  });
}
