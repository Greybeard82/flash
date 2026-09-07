// How the reading layout's two content columns divide the width left over
// after the sections rail.
//
// The bug this pins: the middle column used to be a fixed SizedBox and the
// reading pane a plain Expanded, so the middle never yielded a pixel and the
// pane absorbed the entire shortfall. That looked fine on a large tablet and
// left the pane badly cramped at real phone-landscape widths, which are the
// tightest this layout ever sees — a Pixel 11 Pro is ~923dp and a Galaxy M51
// ~977dp, against the 1085dp and 1751dp the tablet AVDs report.
//
// So the cases that matter are the two real phone widths, the floors, and
// the wide end where the columns stop growing and the leftover becomes
// margin instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/app.dart';

/// Width left for the two columns on a device of [deviceWidth] dp, once the
/// rail and the two dividers have taken theirs.
double _available(double deviceWidth) =>
    deviceWidth - kSectionsColumnWidth - 2;

void main() {
  group('at or above the preferred total', () {
    test('both columns sit at their preferred width', () {
      final w = threeColumnWidths(kSectionColumnMaxWidth + kDetailPaneMaxWidth);
      expect(w.middle, kSectionColumnMaxWidth);
      expect(w.detail, kDetailPaneMaxWidth);
    });

    test('extra width past the preferred total is not absorbed', () {
      // A large tablet: the columns stop growing and Center turns the rest
      // into margins. Without this the reading pane stretches a web page
      // across the full width of the display.
      final w = threeColumnWidths(_available(1751));
      expect(w.middle, kSectionColumnMaxWidth);
      expect(w.detail, kDetailPaneMaxWidth);
    });
  });

  group('real phone landscape widths', () {
    test('Pixel 11 Pro (~923dp): both columns shrink, neither hits its floor',
        () {
      final w = threeColumnWidths(_available(923));

      expect(w.middle, lessThan(kSectionColumnMaxWidth),
          reason: 'the middle column must give something up too — it staying '
              'rigid is the bug being fixed');
      expect(w.middle, greaterThan(kSectionColumnMinWidth));
      expect(w.detail, greaterThan(kDetailPaneMinWidth));

      // The whole point: the pane is materially wider than the old
      // fixed-middle arithmetic left it (923 - 96 - 2 - 420 = 405).
      expect(w.detail, greaterThan(405),
          reason: 'the fix has to actually buy the reading pane width');
    });

    test('Galaxy M51 (~977dp): same, with more room', () {
      final w = threeColumnWidths(_available(977));
      expect(w.middle, lessThan(kSectionColumnMaxWidth));
      expect(w.middle, greaterThan(kSectionColumnMinWidth));
      expect(w.detail, greaterThan(kDetailPaneMinWidth));
      expect(w.detail, greaterThan(977 - 96 - 2 - 420));
    });

    test('the wider phone gives the pane more than the narrower one', () {
      expect(threeColumnWidths(_available(977)).detail,
          greaterThan(threeColumnWidths(_available(923)).detail));
    });
  });

  group('the columns always fit the width they were given', () {
    // Nothing here may overflow: a Row that does not fit paints the striped
    // overflow banner over the UI.
    for (final deviceWidth in <double>[840, 860, 900, 923, 977, 1085, 1280, 1751]) {
      test('$deviceWidth dp: the two columns sum to at most what is available',
          () {
        final available = _available(deviceWidth);
        final w = threeColumnWidths(available);
        expect(w.middle + w.detail, lessThanOrEqualTo(available + 0.01),
            reason: 'columns must never exceed the space they are given');
        expect(w.middle, greaterThan(0));
        expect(w.detail, greaterThan(0));
      });
    }
  });

  group('below both floors', () {
    // 840dp — the breakpoint itself — leaves 742dp, which is less than the
    // 340 + 420 the two floors want. It has to degrade rather than overflow.
    test('the breakpoint width still fits, even though the floors do not', () {
      final available = _available(kThreeColumnBreakpoint);
      expect(available, lessThan(kSectionColumnMinWidth + kDetailPaneMinWidth),
          reason: 'this test is pointless if the floors already fit here');

      final w = threeColumnWidths(available);
      expect(w.middle + w.detail, lessThanOrEqualTo(available + 0.01));
      expect(w.detail, greaterThan(w.middle),
          reason: 'the pane keeps the larger share even when squeezed');
    });
  });

  group('shrinking is shared, not dumped on one column', () {
    test('both columns give up width as the display narrows', () {
      final wide = threeColumnWidths(_available(1200));
      final narrow = threeColumnWidths(_available(900));

      expect(narrow.middle, lessThan(wide.middle));
      expect(narrow.detail, lessThan(wide.detail));
    });

    test('the pane yields more than the middle column, having more to give',
        () {
      final w = threeColumnWidths(_available(923));
      final middleGiven = kSectionColumnMaxWidth - w.middle;
      final detailGiven = kDetailPaneMaxWidth - w.detail;
      expect(detailGiven, greaterThan(middleGiven),
          reason: 'the pane has far more slack between its cap and floor, so '
              'it should absorb proportionally more of the shortfall');
    });
  });
}
