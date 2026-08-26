// planRetirement — the arithmetic that keeps the list still.
//
// Written independently of the implementation. Two things must be exactly
// right: which rows are eligible (an off-by-one retires an article the user
// can still see) and removedHeight (an error moves the list under them). Both
// are invisible in a widget test and obvious on a device, which is why this is
// a pure function with its own tests.
//
// Heights are deliberately unequal in most cases — equal heights hide
// off-by-one errors, because the wrong row has the right height.

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/utils/retirement_frontier.dart';

RowMetric _article(int id, double h, {bool saved = false}) =>
    RowMetric(height: h, articleId: id, isSaved: saved);

const RowMetric _header = RowMetric(height: 36);

void main() {
  group('nothing to do', () {
    test('an empty list plans nothing', () {
      expect(planRetirement(rows: const [], scrollOffset: 999).isEmpty, isTrue);
    });

    test('offset 0 plans nothing', () {
      final rows = [for (var i = 0; i < 10; i++) _article(i, 100)];
      expect(planRetirement(rows: rows, scrollOffset: 0).isEmpty, isTrue,
          reason: 'nothing is above the viewport at the top of the list');
    });

    test('a negative offset (overscroll bounce) plans nothing', () {
      final rows = [for (var i = 0; i < 10; i++) _article(i, 100)];
      expect(planRetirement(rows: rows, scrollOffset: -50).isEmpty, isTrue,
          reason: 'a bounce at the top must never eat rows');
    });

    test('fewer rows above the viewport than the buffer plans nothing', () {
      final rows = [_article(1, 100), _article(2, 100), _article(3, 100)];
      // Two rows above the viewport, buffer of two — nothing left over.
      expect(planRetirement(rows: rows, scrollOffset: 200, bufferCards: 2)
          .isEmpty, isTrue);
    });
  });

  group('the buffer boundary', () {
    // Heights: 100, 110, 120, 130, 140 — cumulative 100/210/330/460/600.
    List<RowMetric> rows() => [
          _article(1, 100),
          _article(2, 110),
          _article(3, 120),
          _article(4, 130),
          _article(5, 140),
        ];

    test('exactly three rows above the viewport retires the first', () {
      // offset 330 -> rows 1,2,3 are fully above. Buffer keeps 2 and 3.
      final plan = planRetirement(
          rows: rows(), scrollOffset: 330, bufferCards: 2);

      expect(plan.articleIds, [1]);
      expect(plan.rowIndices, [0]);
      expect(plan.removedHeight, 100.0);
    });

    test('one pixel short of three rows retires nothing', () {
      final plan = planRetirement(
          rows: rows(), scrollOffset: 329, bufferCards: 2);

      expect(plan.isEmpty, isTrue,
          reason: 'row 3 is still straddling the viewport top, so only two '
              'rows are above it and the buffer consumes both');
    });

    test('four rows above the viewport retires the first two', () {
      final plan = planRetirement(
          rows: rows(), scrollOffset: 460, bufferCards: 2);

      expect(plan.articleIds, [1, 2]);
      expect(plan.removedHeight, 210.0,
          reason: '100 + 110 — the exact height of what was removed, which is '
              'what the scroll offset is reduced by');
    });

    test('a partially visible row is never removed', () {
      // offset 400: row 4 spans 330..460, so it straddles the top edge.
      final plan = planRetirement(
          rows: rows(), scrollOffset: 400, bufferCards: 2);

      expect(plan.articleIds, isNot(contains(4)));
      expect(plan.articleIds, [1],
          reason: 'the walk stops at the straddling row, so rows above it are '
              '1,2,3 and the buffer keeps 2 and 3');
    });

    test('bufferCards 0 retires everything fully above the viewport', () {
      final plan = planRetirement(
          rows: rows(), scrollOffset: 330, bufferCards: 0);

      expect(plan.articleIds, [1, 2, 3]);
      expect(plan.removedHeight, 330.0);
    });
  });

  group('day headers', () {
    test('headers do not consume the buffer', () {
      // H a1 H a2 H a3 H a4 — offset past all of them.
      final rows = [
        _header, _article(1, 100),
        _header, _article(2, 100),
        _header, _article(3, 100),
        _header, _article(4, 100),
      ];
      // Cumulative through index 5 (a3) = 36+100+36+100+36+100 = 408.
      final plan = planRetirement(rows: rows, scrollOffset: 408, bufferCards: 2);

      expect(plan.articleIds, [1],
          reason: 'the buffer must count a2 and a3 — if headers counted, it '
              'would stop one article too early and retire nothing');
    });

    test('a header whose articles all go, goes with them', () {
      final rows = [
        _header, _article(1, 100), _article(2, 100),
        _header, _article(3, 100), _article(4, 100), _article(5, 100),
      ];
      // Through index 4 (a3): 36+100+100+36+100 = 372.
      final plan = planRetirement(rows: rows, scrollOffset: 372, bufferCards: 0);

      expect(plan.articleIds, [1, 2, 3]);
      expect(plan.rowIndices, [0, 1, 2, 3, 4],
          reason: 'the first header has no articles left beneath it, and the '
              'second still leads a4 and a5 — but it is inside the block, so '
              'it goes only because its own article a3 went');
      expect(plan.removedHeight, 372.0);
    });

    test('a trailing header with survivors beneath it stays', () {
      final rows = [
        _header, _article(1, 100), _article(2, 100),
        _header, _article(3, 100),
      ];
      // Through index 3 (the second header): 36+100+100+36 = 272.
      final plan = planRetirement(rows: rows, scrollOffset: 272, bufferCards: 0);

      expect(plan.rowIndices, [0, 1, 2],
          reason: 'the frontier landed on a header whose article survives — '
              'removing it would leave a3 with no date above it');
      expect(plan.removedHeight, 236.0, reason: '36 + 100 + 100');
      expect(plan.articleIds, [1, 2]);
    });
  });

  group('saved articles', () {
    test('a saved article above the frontier blocks the whole block', () {
      final rows = [
        _article(1, 100),
        _article(2, 110, saved: true),
        _article(3, 120),
        _article(4, 130),
        _article(5, 140),
      ];
      final plan = planRetirement(rows: rows, scrollOffset: 460, bufferCards: 2);

      expect(plan.isEmpty, isTrue,
          reason: 'removing rows either side of a survivor would leave it in '
              'the wrong place, and the offset arithmetic assumes one '
              'contiguous block at the top');
    });

    test('a saved article below the frontier does not block', () {
      final rows = [
        _article(1, 100),
        _article(2, 110),
        _article(3, 120, saved: true),
        _article(4, 130),
        _article(5, 140),
      ];
      final plan = planRetirement(rows: rows, scrollOffset: 460, bufferCards: 2);

      expect(plan.articleIds, [1, 2],
          reason: 'the saved row is inside the buffer, not the removed block');
      expect(plan.removedHeight, 210.0);
    });
  });

  test('removedHeight always equals the summed heights of removed rows', () {
    final rows = [
      _header,
      _article(1, 101),
      _article(2, 137),
      _article(3, 88),
      _header,
      _article(4, 212),
      _article(5, 96),
      _article(6, 143),
    ];
    final plan = planRetirement(
        rows: rows, scrollOffset: 10000, bufferCards: 2);

    var expected = 0.0;
    for (final i in plan.rowIndices) {
      expected += rows[i].height;
    }
    expect(plan.removedHeight, expected);
    expect(plan.removedHeight, greaterThan(0));
  });
}
