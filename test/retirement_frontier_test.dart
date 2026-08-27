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

RowMetric _article(int id, double h, {bool saved = false, bool built = false}) =>
    RowMetric(height: h, articleId: id, isSaved: saved, isBuilt: built);

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
      // This test previously asserted the defect fixed in pass 06: it expected
      // the *second* header to be removed too, even though a4 and a5 survive
      // under it. Its own reason text described that as intended. It was not —
      // it left the list opening on an article with no date above it.
      final rows = [
        _header, _article(1, 100), _article(2, 100),
        _header, _article(3, 100), _article(4, 100), _article(5, 100),
      ];
      // Through index 4 (a3): 36+100+100+36+100 = 372.
      final plan = planRetirement(rows: rows, scrollOffset: 372, bufferCards: 0);

      expect(plan.articleIds, [1, 2, 3]);
      expect(plan.rowIndices, [0, 1, 2, 4],
          reason: 'the first header has no articles left beneath it and goes; '
              'the second still leads a4 and a5, so it stays and index 3 is '
              'absent from an otherwise contiguous block');
      expect(plan.removedHeight, 336.0,
          reason: '372 less the surviving header, so the offset correction '
              'still lands on the pixel');
    });

    test('a frontier inside a day group keeps that group header',
        () {
      // The bug shipped in fb3fb10: rows [H, A1, A2, A3, A4] with the frontier
      // at A2 removed the header along with A1 and A2, leaving A3 and A4 at
      // the top of the list with no date label above them.
      final rows = [
        _header,
        _article(1, 100),
        _article(2, 110),
        _article(3, 120),
        _article(4, 130),
      ];
      // Cumulative through index 2 (A2): 36 + 100 + 110 = 246.
      final plan = planRetirement(rows: rows, scrollOffset: 246, bufferCards: 0);

      expect(plan.articleIds, [1, 2]);
      expect(plan.rowIndices, isNot(contains(0)),
          reason: 'A3 and A4 survive and still belong to that day, so the '
              'header has to survive with them');
      expect(plan.rowIndices, [1, 2]);
      expect(plan.removedHeight, 210.0,
          reason: '100 + 110 only — the header stays, so its 36 must not be '
              'subtracted from the scroll offset');
    });

    test('the frontier exactly at a day boundary removes that header', () {
      // Here the next surviving row IS a header, so the removed group has no
      // survivors and its own header goes with it.
      final rows = [
        _header,
        _article(1, 100),
        _article(2, 110),
        _header,
        _article(3, 120),
        _article(4, 130),
      ];
      // Cumulative through index 2 (A2): 36 + 100 + 110 = 246.
      final plan = planRetirement(rows: rows, scrollOffset: 246, bufferCards: 0);

      expect(plan.rowIndices, [0, 1, 2]);
      expect(plan.removedHeight, 246.0, reason: '36 + 100 + 110');
      expect(plan.articleIds, [1, 2]);
    });

    test('first group fully removed, second group partly removed', () {
      final rows = [
        _header,
        _article(1, 100),
        _article(2, 110),
        _header,
        _article(3, 120),
        _article(4, 130),
        _article(5, 140),
      ];
      // Cumulative through index 4 (A3): 36+100+110+36+120 = 402.
      final plan = planRetirement(rows: rows, scrollOffset: 402, bufferCards: 0);

      expect(plan.articleIds, [1, 2, 3]);
      expect(plan.rowIndices, [0, 1, 2, 4],
          reason: 'the first header goes with its whole group; the second '
              'stays because A4 and A5 still sit under it');
      expect(plan.removedHeight, 366.0,
          reason: '36 + 100 + 110 + 120 — the surviving header excluded');
    });

    test('whenever an article survives, the surviving rows start with a header',
        () {
      final rows = [
        _header,
        _article(1, 100),
        _article(2, 110),
        _article(3, 120),
        _header,
        _article(4, 130),
      ];
      for (final offset in [100.0, 210.0, 246.0, 330.0, 366.0, 402.0]) {
        final plan =
            planRetirement(rows: rows, scrollOffset: offset, bufferCards: 0);
        final removed = plan.rowIndices.toSet();
        final survivors = [
          for (var i = 0; i < rows.length; i++)
            if (!removed.contains(i)) rows[i],
        ];
        if (survivors.any((r) => !r.isHeader)) {
          expect(survivors.first.isHeader, isTrue,
              reason: 'at offset $offset the list would open on an article '
                  'with no date above it');
        }
      }
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

  group('the built-row ceiling', () {
    test('nothing built: everything below the buffer is eligible', () {
      final rows = [for (var i = 1; i <= 10; i++) _article(i, 100)];
      final plan = planRetirement(rows: rows, scrollOffset: 600, bufferCards: 2);

      expect(plan.articleIds, [1, 2, 3, 4]);
      expect(plan.clampedByBuiltRows, isFalse,
          reason: 'the buffer, not the ceiling, is doing the work here');
    });

    test('the first built row caps the frontier', () {
      // Rows 5..9 are built; without the ceiling the frontier would be 8.
      final rows = [
        for (var i = 0; i < 10; i++) _article(i + 1, 100, built: i >= 5),
      ];
      final plan =
          planRetirement(rows: rows, scrollOffset: 1100, bufferCards: 0);

      expect(plan.rowIndices.every((i) => i < 5), isTrue,
          reason: 'nothing at or after the first built row may be removed');
      expect(plan.rowIndices, [0, 1, 2, 3, 4]);
      expect(plan.clampedByBuiltRows, isTrue);
    });

    test('every row built: the plan is empty', () {
      final rows = [for (var i = 1; i <= 6; i++) _article(i, 100, built: true)];
      final plan =
          planRetirement(rows: rows, scrollOffset: 500, bufferCards: 0);

      expect(plan.isEmpty, isTrue,
          reason: 'a short fully-built list retires nothing at all');
    });

    test('a built header does not raise the ceiling', () {
      // Headers are isBuilt:false by construction, so a header sitting among
      // disposed rows must not act as the boundary — the article after it
      // does.
      final rows = [
        _article(1, 100),
        _article(2, 100),
        _header,
        _article(3, 100, built: true),
        _article(4, 100, built: true),
      ];
      final plan =
          planRetirement(rows: rows, scrollOffset: 500, bufferCards: 0);

      expect(plan.rowIndices, [0, 1],
          reason: 'the ceiling is article 3 at index 3; the header at index 2 '
              'is dropped anyway because articles below it survive');
      expect(plan.clampedByBuiltRows, isTrue);
    });

    test('height drift cannot reach a built row', () {
      // THE REGRESSION COVER FOR PASS 07. Disposed rows are given heights far
      // smaller than reality, exactly as the 120.0 fallback did against real
      // 96.8dp and 121.9dp cards. The naive frontier therefore runs way past
      // the visible region. The ceiling must stop it dead — a height bug
      // anywhere in this file must never be able to delete something the user
      // can see.
      final rows = [
        for (var i = 0; i < 20; i++) _article(i + 1, 10, built: i >= 12),
      ];
      final plan =
          planRetirement(rows: rows, scrollOffset: 100000, bufferCards: 2);

      expect(plan.rowIndices.every((i) => i < 12), isTrue,
          reason: 'THE regression cover: with heights wrong by an order of '
              'magnitude the arithmetic wants to retire the entire list, '
              'including rows on screen. Only the built-row ceiling stops it.');
      expect(plan.clampedByBuiltRows, isTrue);
    });

    test('removedHeight is still exact after clamping', () {
      final rows = [
        _article(1, 101),
        _article(2, 137),
        _article(3, 88),
        _article(4, 212, built: true),
        _article(5, 96, built: true),
      ];
      final plan =
          planRetirement(rows: rows, scrollOffset: 5000, bufferCards: 0);

      var expected = 0.0;
      for (final i in plan.rowIndices) {
        expected += rows[i].height;
      }
      expect(plan.removedHeight, expected);
      expect(plan.removedHeight, 326.0, reason: '101 + 137 + 88');
      expect(plan.clampedByBuiltRows, isTrue);
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
