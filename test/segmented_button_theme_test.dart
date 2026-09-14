// Handoff 1.7: the last capsules in the app.
//
// Three SegmentedButtons ship — sort order in the filter bubble, theme and
// summary length in Quick Settings — and all three were stock M3 at radius 20
// while everything around them had settled on r9 chips and an r14 nav pill.
// One theme entry, three surfaces, no widget changes.
//
// **Values are asserted exactly, never as comparisons.** A test saying the
// selected fill "differs from" the unselected one passes just as happily when
// both are wrong.
//
// **What is deliberately absent.** 1.7 also asks for `showSelectedIcon: false`.
// That is a `SegmentedButton` constructor argument and
// `SegmentedButtonThemeData` has no override for it — the class carries two
// fields, `style` and `selectedIcon`. It is reported rather than guessed at,
// and the last test here pins the gap so it cannot be quietly forgotten: it
// asserts the checkmark IS still shown, which is the current truth, and will
// fail the day someone threads the flag through the three call sites, at which
// point this block is the thing to read.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';

/// The numbers 1.7 names.
const double kSegmentRadius = 9;
// 1.7 asks for 40. It renders at 48 and the difference is a touch target —
// see the height test for why it is reported rather than applied.
const double kSegmentRenderedHeight = 48;
const double kSegmentLabelSize = 13;

enum _Sort { newest, oldest }

Widget _host(ThemeData theme, {bool showSelectedIcon = true}) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SegmentedButton<_Sort>(
            segments: const [
              ButtonSegment(value: _Sort.newest, label: Text('Newest')),
              ButtonSegment(value: _Sort.oldest, label: Text('Oldest')),
            ],
            selected: const {_Sort.newest},
            showSelectedIcon: showSelectedIcon,
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    );

/// The resolved style the theme hands a SegmentedButton, read the way the
/// widget reads it rather than off the ThemeData object.
ButtonStyle _styleOf(WidgetTester tester) => SegmentedButtonTheme.of(
      tester.element(find.byType(SegmentedButton<_Sort>)),
    ).style!;

void main() {
  final themes = <String, ThemeData>{
    'light': flashQuietInkTheme(brightness: Brightness.light),
    'dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  themes.forEach((name, theme) {
    final scheme = theme.colorScheme;

    group(name, () {
      testWidgets('the outer shape is radius 9, not the M3 capsule',
          (tester) async {
        await tester.pumpWidget(_host(theme));
        final shape = _styleOf(tester).shape!.resolve({})!;

        expect(shape, isA<RoundedRectangleBorder>());
        expect((shape as RoundedRectangleBorder).borderRadius,
            BorderRadius.circular(kSegmentRadius),
            reason: '$name: 1.7 replaces the stock r20 capsule with the r9 '
                'the chips and bubbles already use');
      });

      testWidgets('one 1dp outlineVariant side, which is border and divider',
          (tester) async {
        // Not two entries. `ButtonStyle.side` is used for the group's outer
        // border *and* the rules between segments, which is why 1.7 names one
        // value for both and why there is no divider override to look for.
        await tester.pumpWidget(_host(theme));
        final side = _styleOf(tester).side!.resolve({})!;

        expect(side.color, scheme.outlineVariant,
            reason: '$name: the border is the same hairline every divider in '
                'the app draws');
        expect(side.width, 1.0);
      });

      testWidgets('selected is primaryContainer under onPrimaryContainer',
          (tester) async {
        await tester.pumpWidget(_host(theme));
        final style = _styleOf(tester);
        const selected = <WidgetState>{WidgetState.selected};

        expect(style.backgroundColor!.resolve(selected),
            scheme.primaryContainer);
        expect(style.foregroundColor!.resolve(selected),
            scheme.onPrimaryContainer);
      });

      testWidgets('unselected is onSurfaceVariant on nothing at all',
          (tester) async {
        // The null background is the assertion, not an omission: these sit on
        // two different host surfaces — the filter bubble and Quick Settings —
        // and a fill declared here would be wrong on one of them.
        await tester.pumpWidget(_host(theme));
        final style = _styleOf(tester);

        expect(style.backgroundColor!.resolve(const <WidgetState>{}), isNull,
            reason: '$name: an unselected segment takes the surface under it');
        expect(style.foregroundColor!.resolve(const <WidgetState>{}),
            scheme.onSurfaceVariant);
      });

      testWidgets('13/w600 selected, 13/w500 unselected, theme family kept',
          (tester) async {
        await tester.pumpWidget(_host(theme));
        final style = _styleOf(tester);

        final sel =
            style.textStyle!.resolve(const <WidgetState>{WidgetState.selected})!;
        final un = style.textStyle!.resolve(const <WidgetState>{})!;

        expect(sel.fontSize, kSegmentLabelSize);
        expect(un.fontSize, kSegmentLabelSize);
        expect(sel.fontWeight, FontWeight.w600);
        expect(un.fontWeight, FontWeight.w500);

        // Derived from the theme's own labelLarge rather than written as a
        // bare TextStyle, so Newspaper keeps its serif instead of inheriting
        // Quiet Ink's grotesque through a shared helper.
        expect(sel.fontFamily, theme.textTheme.labelLarge?.fontFamily);
        expect(sel.fontFamily, isNotNull,
            reason: '$name: a null family here means the helper stopped '
                'reading the theme and the assertion above is comparing two '
                'nulls');
      });

      testWidgets('it renders at 48dp, not the 40 1.7 asks for', (tester) async {
        // **The second thing 1.7 asks for that is not done, and the reason is
        // a touch target rather than a limitation.**
        //
        // Measured: the segment paints at 48, not 40 — and 48 is the painted
        // fill, not a transparent tap halo around a 40dp body. Flutter's
        // `MaterialTapTargetSize.padded` normally adds hit area outside the
        // Material, but `_SegmentedButtonRenderObject` lays every segment out
        // at a uniform tight height, so the padding is inside the paint.
        //
        // Reaching 40 therefore means `tapTargetSize: shrinkWrap` (or a
        // negative `visualDensity`), and both take the **touch target** to 40
        // with the paint. That is 8dp under the 48 this app holds itself to,
        // and the two places it already goes under — the 36dp folder chip and
        // the 36dp rail halves — each have a written justification and a test
        // saying so. 1.7 does not mention touch targets at all.
        //
        // So the height is reported, not applied: a number that costs an
        // accessibility floor is a decision, not a value. Everything else in
        // 1.7 lands. Pinned at the real 48 so the gap is visible rather than
        // implied, and so that applying it later is a deliberate edit here.
        await tester.pumpWidget(_host(theme));
        expect(tester.takeException(), isNull);

        final height =
            tester.getSize(find.byType(SegmentedButton<_Sort>)).height;
        expect(height, 48.0,
            reason: '$name: rendered $height. If this is 40, the tap target '
                'went to 40 with it — which may well be the right call, but '
                'it wants saying out loud and this comment rewritten.');
        expect(height, greaterThanOrEqualTo(48.0),
            reason: 'kept explicit: this is the Material touch floor, and '
                'dropping under it is what 1.7 costs');
      });
    });
  });

  test('both themes resolve the same shape, side and sizes', () {
    // The helper is shared so the two themes cannot drift on geometry while
    // each keeps its own colours. Pinning that here means a future
    // Newspaper-only override shows up as a failure rather than as a
    // difference nobody is looking at.
    final shapes = <Object?>{};
    final widths = <double?>{};
    for (final theme in themes.values) {
      final style = theme.segmentedButtonTheme.style!;
      shapes.add(style.shape!.resolve({}));
      widths.add(style.side!.resolve({})!.width);
    }
    expect(shapes, hasLength(1));
    expect(widths, hasLength(1));
  });

  testWidgets('the selected checkmark is still shown — the 1.7 gap',
      (tester) async {
    // Pinning what is NOT done. `showSelectedIcon` has no theme override, so
    // the selected segment still carries M3's check. Closing it means three
    // widget edits at the three call sites, which 1.7's own "no widget
    // changes" rules out — so it is reported, not guessed.
    //
    // This fails the day someone threads the flag, which is the correct
    // moment to come back and delete it.
    await tester
        .pumpWidget(_host(flashQuietInkTheme(brightness: Brightness.light)));
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: 'if this is gone, showSelectedIcon: false landed at the call '
            'sites — update the theme comment and delete this test');
  });
}
