// Which side the navigation bar sits on, and where every column lands
// because of it.
//
// "Swap sides" is a pure mirror: the order of the columns reverses and
// nothing else changes. That claim is worth pinning here rather than only on
// a device, because two thirds of it are easy to get wrong and invisible
// until someone is holding a tablet:
//
//   1. A mirror must not resize anything. Reordering columns by rebuilding
//      the Row with different widths would be indistinguishable at a glance
//      and wrong the moment the divider had been dragged.
//   2. The bar has to end up flush against its new screen edge, with the
//      centred content group keeping its gutters on the other side of it.
//      Mirroring the *group* and leaving the bar inside it is the bug that
//      produced the "one enormous gutter" the sidebar already had once.
//
// The last third — dragging the divider the right way round once the feed is
// to the right of the reading pane — is one sign, so it gets one function and
// four short tests rather than a device session.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/app.dart';
import 'package:flash/models/settings.dart';

/// The two emulator targets, in dp.
const double _largeTabletLandscape = 1707;
const double _smallTabletLandscape = 960;

/// Width left for the two content columns once the bar, its rule and the
/// drag handle have taken theirs.
double _available(double total) =>
    total - kSectionsColumnWidth - 1 - kResizeHandleWidth;

/// Both states of the same layout, so a test can compare them directly.
({ThreeColumnSlots normal, ThreeColumnSlots swapped}) _bothStates(
  double total, {
  double? manualMiddle,
}) {
  final columns = resolvedColumnWidths(_available(total), manualMiddle);
  ThreeColumnSlots at(bool swapped) => threeColumnSlots(
        total: total,
        middleWidth: columns.middle,
        detailWidth: columns.detail,
        swapped: swapped,
      );
  return (normal: at(false), swapped: at(true));
}

List<ShellSlot> _allSlots(ThreeColumnSlots s) =>
    [s.bar, s.rule, s.content, s.divider, s.detail];

double _right(ShellSlot slot) => slot.left + slot.width;

void main() {
  group('three-column, normal', () {
    final s = _bothStates(_largeTabletLandscape).normal;

    test('the bar is flush to the left edge', () {
      expect(s.bar.left, 0);
      expect(s.bar.width, kSectionsColumnWidth);
    });

    test('the rule sits between the bar and the content', () {
      expect(s.rule.left, kSectionsColumnWidth);
      expect(s.rule.width, 1);
      expect(s.content.left, greaterThanOrEqualTo(_right(s.rule)));
    });

    test('feed, divider and reading pane run left to right in that order', () {
      expect(s.divider.left, s.content.left + s.content.width);
      expect(s.detail.left, s.divider.left + kResizeHandleWidth);
    });

    test('nothing lands outside the display', () {
      for (final slot in _allSlots(s)) {
        expect(slot.left, greaterThanOrEqualTo(0));
        expect(_right(slot), lessThanOrEqualTo(_largeTabletLandscape + 0.01));
      }
    });
  });

  group('three-column, swapped', () {
    final s = _bothStates(_largeTabletLandscape).swapped;

    test('the bar is flush to the right edge', () {
      expect(_right(s.bar), closeTo(_largeTabletLandscape, 0.01));
      expect(s.bar.width, kSectionsColumnWidth);
    });

    test('the rule is still between the bar and the content', () {
      expect(_right(s.rule), closeTo(s.bar.left, 0.01));
      expect(_right(s.content), lessThanOrEqualTo(s.rule.left + 0.01));
    });

    test('the reading pane is now leftmost and the feed sits beside the bar',
        () {
      expect(s.detail.left, lessThan(s.divider.left));
      expect(s.divider.left, lessThan(s.content.left));
      expect(s.content.left, lessThan(s.rule.left));
      expect(s.rule.left, lessThan(s.bar.left));
    });

    test('the divider still touches both columns it separates', () {
      expect(_right(s.detail), closeTo(s.divider.left, 0.01));
      expect(_right(s.divider), closeTo(s.content.left, 0.01));
    });

    test('nothing lands outside the display', () {
      for (final slot in _allSlots(s)) {
        expect(slot.left, greaterThanOrEqualTo(-0.01));
        expect(_right(slot), lessThanOrEqualTo(_largeTabletLandscape + 0.01));
      }
    });
  });

  group('a swap is a pure mirror', () {
    // The whole feature in one property: every slot keeps its width, and its
    // left edge reflects about the middle of the display.
    for (final total in <double>[
      kThreeColumnBreakpoint,
      _smallTabletLandscape,
      1067, // large tablet, portrait
      _largeTabletLandscape,
    ]) {
      test('$total dp: widths are untouched', () {
        final both = _bothStates(total);
        final normal = _allSlots(both.normal);
        final swapped = _allSlots(both.swapped);
        for (var i = 0; i < normal.length; i++) {
          expect(swapped[i].width, normal[i].width,
              reason: 'a swap reorders columns, it does not resize them');
        }
      });

      test('$total dp: every left edge is the mirror of its own', () {
        final both = _bothStates(total);
        final normal = _allSlots(both.normal);
        final swapped = _allSlots(both.swapped);
        for (var i = 0; i < normal.length; i++) {
          expect(swapped[i].left,
              closeTo(total - normal[i].left - normal[i].width, 0.01));
        }
      });
    }

    test('a dragged divider width survives the swap', () {
      // The manual width is the reader's, not the layout's. Swapping has to
      // hand it back unchanged rather than reset to the automatic split.
      final both = _bothStates(_largeTabletLandscape, manualMiddle: 520);
      expect(both.normal.content.width, 520);
      expect(both.swapped.content.width, 520);
    });
  });

  group('the centred composition keeps its gutters', () {
    // On a wide tablet the two content columns stop growing and the leftover
    // becomes margin. Mirroring has to move the bar to the far edge and leave
    // that margin where it was relative to the content — putting the bar
    // inside the centred group is what once produced a 161dp gutter that read
    // as one enormous rail.
    double groupLeft(ThreeColumnSlots s) =>
        math.min(s.content.left, s.detail.left);
    double groupRight(ThreeColumnSlots s) =>
        math.max(_right(s.content), _right(s.detail));

    test('normal: the group is centred in the space right of the bar', () {
      final s = _bothStates(_largeTabletLandscape).normal;
      const regionStart = kSectionsColumnWidth + 1;
      expect(groupLeft(s) - regionStart,
          closeTo(_largeTabletLandscape - groupRight(s), 0.01));
      expect(groupLeft(s) - regionStart, greaterThan(0),
          reason: 'this test is pointless unless a gutter exists here');
    });

    test('swapped: the group is centred in the space left of the bar', () {
      final s = _bothStates(_largeTabletLandscape).swapped;
      const regionEnd = _largeTabletLandscape - kSectionsColumnWidth - 1;
      expect(groupLeft(s), closeTo(regionEnd - groupRight(s), 0.01));
    });

    test('a dragged split fills the width, so the bar stays flush', () {
      // With a manual width the two columns take everything available, the
      // gutter goes to zero, and the mirrored pane starts at the very edge.
      final s = _bothStates(_largeTabletLandscape, manualMiddle: 520).swapped;
      expect(s.detail.left, closeTo(0, 0.01));
      expect(_right(s.bar), closeTo(_largeTabletLandscape, 0.01));
    });
  });

  group('the rail tier', () {
    // The rail measures its own width rather than being told one, so the
    // geometry takes it as given instead of assuming Flutter's 80dp: the
    // `trailing` slot carries the section actions, whose labels are phrases.
    const total = 600.0; // the boundary itself: an 8" tablet in portrait
    const barWidth = 80.0;

    test('normal: rail, rule, content', () {
      final s = railSlots(total: total, barWidth: barWidth, swapped: false);
      expect(s.bar.left, 0);
      expect(s.rule.left, barWidth);
      expect(s.content.left, barWidth + 1);
      expect(s.content.width, total - barWidth - 1);
    });

    test('swapped: content, rule, rail', () {
      final s = railSlots(total: total, barWidth: barWidth, swapped: true);
      expect(s.content.left, 0);
      expect(s.rule.left, total - barWidth - 1);
      expect(s.bar.left, total - barWidth);
      expect(_right(s.bar), total);
    });

    test('the content column is the same width either way', () {
      final normal =
          railSlots(total: total, barWidth: barWidth, swapped: false);
      final swapped =
          railSlots(total: total, barWidth: barWidth, swapped: true);
      expect(swapped.content.width, normal.content.width);
      expect(swapped.bar.width, normal.bar.width);
      expect(swapped.rule.width, normal.rule.width);
    });

    test('an extended rail (TV) mirrors the same way', () {
      // TV never swaps, but the geometry must not assume a slim rail.
      final s = railSlots(total: 1280, barWidth: 256, swapped: true);
      expect(s.content.left, 0);
      expect(s.content.width, 1280 - 256 - 1);
      expect(_right(s.bar), 1280);
    });

    test('the three pieces tile the width exactly, in both states', () {
      for (final swapped in [false, true]) {
        final s = railSlots(total: total, barWidth: barWidth, swapped: swapped);
        expect(s.bar.width + s.rule.width + s.content.width,
            closeTo(total, 0.01));
      }
    });

    test('a rail wider than the display degrades instead of crashing', () {
      // A rail is as wide as its widest label, and labels grow with the
      // locale and the font scale. A content column of negative width is not
      // a cramped layout, it is an assertion failure in the middle of a
      // layout pass.
      for (final swapped in [false, true]) {
        final s = railSlots(total: 600, barWidth: 900, swapped: swapped);
        expect(s.content.width, greaterThanOrEqualTo(0));
        expect(s.bar.width, lessThanOrEqualTo(600));
        expect(s.bar.left, greaterThanOrEqualTo(0));
      }
    });
  });

  group('the divider drags the right way round', () {
    // Swapped, the feed sits to the *right* of the reading pane, so dragging
    // right has to take width off it. Without the inversion the divider runs
    // away from the finger.
    test('normal: dragging right widens the feed', () {
      expect(dividerDragDelta(12, swapped: false), 12);
    });

    test('swapped: dragging right narrows the feed', () {
      expect(dividerDragDelta(12, swapped: true), -12);
    });

    test('and the mirror holds for the other direction too', () {
      expect(dividerDragDelta(-12, swapped: false), -12);
      expect(dividerDragDelta(-12, swapped: true), 12);
    });

    test('a drag applied to a manual width moves it towards the finger', () {
      const start = 400.0;
      expect(start + dividerDragDelta(30, swapped: false), 430);
      expect(start + dividerDragDelta(30, swapped: true), 370);
    });
  });

  group('the setting', () {
    // A missing key is the whole migration story: nobody upgrading has this
    // row, and everybody upgrading expects the layout they already had.
    test('a missing key means not swapped', () {
      expect(const AppSettings().layoutSwapped, isFalse);
      expect(AppSettings.fromMap(const {}).layoutSwapped, isFalse);
    });

    test("'true' means swapped", () {
      expect(AppSettings.fromMap(const {'layout_swapped': 'true'}).layoutSwapped,
          isTrue);
    });

    test("'false', and anything that is not 'true', means not swapped", () {
      for (final value in const ['false', 'yes', '1', '']) {
        expect(AppSettings.fromMap({'layout_swapped': value}).layoutSwapped,
            isFalse,
            reason: '"$value" is not the persisted true value');
      }
    });

    test('copyWith carries it, and leaves it alone when unset', () {
      const swapped = AppSettings(layoutSwapped: true);
      expect(swapped.copyWith().layoutSwapped, isTrue);
      expect(swapped.copyWith(layoutSwapped: false).layoutSwapped, isFalse);
      expect(const AppSettings().copyWith(layoutSwapped: true).layoutSwapped,
          isTrue);
    });
  });
}
