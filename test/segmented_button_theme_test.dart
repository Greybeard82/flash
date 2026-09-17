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
// **Two of 1.7's lines are not in the theme, for two different reasons, and
// the last group here is the one that nearly went wrong.**
//
// `showSelectedIcon: false` cannot be expressed in `SegmentedButtonThemeData`
// at all — it has two fields, `style` and `selectedIcon`, and the flag is a
// constructor argument. That reads like an unclosable item right up until you
// open the call sites, where **all three already pass it**. The app was never
// wrong; only the mechanism was missing. So the guard reads the call sites,
// because a widget test can only prove things about the SegmentedButton it
// built itself — and the risk is a fourth one, added elsewhere, inheriting a
// default of `true`.
//
// "Height 40" is different: expressible, and not applied, because it costs
// 8dp of touch target. See the height test.

import 'dart:io';

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

  group('showSelectedIcon, which the theme cannot carry', () {
    // **This was nearly written as a gap, and it is not one.**
    //
    // `showSelectedIcon` is a `SegmentedButton` constructor argument with no
    // theme override, so 1.7's "showSelectedIcon: false" cannot be expressed
    // in `segmentedButtonTheme` — which reads like an unclosable item until
    // you look at the call sites. All three already pass it. The app has been
    // correct all along; only the *mechanism* was missing.
    //
    // So the guard is on the call sites rather than on a rendered widget. A
    // widget test can only prove things about the SegmentedButton it built
    // itself, which is exactly the wrong subject: the risk is a fourth one
    // added somewhere else without the flag, and the default is `true`.

    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (
              path: f.path.replaceAll(r'\', '/'),
              text: f.readAsStringSync(),
            ))
        .where((f) => f.text.contains('SegmentedButton<'))
        .toList();

    test('there are exactly three SegmentedButtons in the app', () {
      // 1.7 says three. If that number moves, the two tests below are
      // covering a set that has changed shape and this one says so first.
      final count = sources.fold<int>(
          0, (n, f) => n + RegExp(r'SegmentedButton<').allMatches(f.text).length);
      expect(count, 3,
          reason: 'found $count across '
              '${sources.map((f) => f.path).join(', ')} — 1.7 describes three '
              '(sort order, theme, summary length)');
    });

    test('every one of them passes showSelectedIcon: false', () {
      for (final file in sources) {
        final buttons = RegExp(r'SegmentedButton<').allMatches(file.text).length;
        final flags =
            RegExp(r'showSelectedIcon:\s*false').allMatches(file.text).length;
        expect(flags, buttons,
            reason: '${file.path} builds $buttons SegmentedButton(s) and '
                'passes the flag $flags time(s). The default is TRUE, so a '
                'missing flag puts a checkmark in the selected segment and '
                'shifts its label — and the theme cannot fix it for you.');
      }
    });

    testWidgets('and the default really is the checkmark, so this matters',
        (tester) async {
      // The tripwire under the two tests above. If Material ever changed the
      // default to false, they would both be guarding nothing and should be
      // deleted rather than left reading as protection.
      await tester.pumpWidget(_host(
        flashQuietInkTheme(brightness: Brightness.light),
      ));
      expect(find.byIcon(Icons.check), findsOneWidget,
          reason: 'a SegmentedButton with no flag shows a check — which is '
              'why the call sites have to pass one');
    });
  });
}
