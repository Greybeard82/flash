// The day header's height is not a styling choice. It is an input to the
// read-marking walk, and nothing was asserting it.
//
// **Why 36 matters.** `FeedScreen._onScroll` decides which articles have been
// read by walking the row list and summing heights until it passes the
// viewport top. An article's height is measured from its own render box, but a
// day header's is not — it is taken from `kDayHeaderHeight` as a constant
// (feed_screen.dart:1112), and the same constant feeds `_rowHeight`
// (feed_screen.dart:869), which the retirement planner uses.
//
// So if the painted header and the constant ever disagree, the walk
// accumulates the wrong offset, lands on the wrong article, and marks the
// wrong set read — silently, and further from the top of the list the longer
// the session runs. There is no crash and no visual glitch to notice; the
// first symptom is articles the reader never saw being marked read.
//
// That is why this file asserts the painted box equals the constant rather
// than just asserting the constant's value. A test that only checked
// `kDayHeaderHeight == 36` would pass while the widget drew 44.
//
// This pass changed nothing about the header — it was already the uppercased
// teal small-caps row the mock asks for. What it did not have was a test.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/utils/day_grouping.dart';
import 'package:flash/widgets/day_header.dart';

DayHeaderRow _row([DayBucket bucket = DayBucket.today]) =>
    DayHeaderRow(DateTime(2026, 9, 13), bucket);

Future<void> _pump(WidgetTester tester, {ThemeData? theme}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    theme: theme ?? flashQuietInkTheme(brightness: Brightness.light),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: Column(children: [DayHeader(row: _row())])),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('the height the read walk depends on', () {
    test('the constant is 36', () {
      expect(kDayHeaderHeight, 36.0);
    });

    testWidgets('and the painted header is exactly that', (tester) async {
      // The assertion that actually protects the walk. The constant agreeing
      // with itself proves nothing; the constant agreeing with the pixels is
      // the invariant.
      await _pump(tester);
      expect(tester.getSize(find.byType(DayHeader)).height, kDayHeaderHeight,
          reason: 'if the painted header and kDayHeaderHeight diverge, '
              '_onScroll accumulates the wrong offset and marks the wrong '
              'articles read, with no crash and nothing visible to notice');
    });

    testWidgets('every bucket renders at the same height', (tester) async {
      // Today and Yesterday are l10n strings; the other two are formatted
      // dates of varying length. A longer label must not grow the row.
      for (final bucket in DayBucket.values) {
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          theme: flashQuietInkTheme(brightness: Brightness.light),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Column(children: [DayHeader(row: _row(bucket))]),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(DayHeader)).height, kDayHeaderHeight,
            reason: '${bucket.name} changed the row height');
      }
    });
  });

  group('the label is teal small-caps', () {
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final name = brightness.name;

      testWidgets('$name: uppercased, w700, 0.8 tracking, in primary',
          (tester) async {
        await _pump(tester, theme: theme);

        final text = tester.widget<Text>(find.byType(Text));
        expect(text.data, text.data!.toUpperCase(),
            reason: 'the header is small-caps by uppercasing the string');

        final style = text.style!;
        expect(style.color, theme.colorScheme.primary,
            reason: '$name: the day header is teal, not grey — the design '
                'file corrects itself on this point');
        expect(style.fontWeight, FontWeight.w700);
        expect(style.letterSpacing, 0.8);
        // 11 rather than `theme.textTheme.labelSmall?.fontSize`, which is
        // null on the raw ThemeData: Quiet Ink leaves sizes to Material's
        // ramp, and the ramp is applied during localization, so the size only
        // exists once the widget is in a tree. Comparing against the raw
        // theme here would compare 11 to null and fail on a correct header.
        expect(style.fontSize, 11.0,
            reason: 'it is labelSmall with weight and tracking on top, not a '
                'size of its own');
      });
    }
  });

  testWidgets('Newspaper renders it in its own primary', (tester) async {
    // Newspaper keeps its own look: its primary is _npRed, not Quiet Ink's
    // teal, and the header follows the theme rather than a fixed colour.
    final theme = flashNewspaperTheme();
    await _pump(tester, theme: theme);

    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.byType(Text)).style!.color,
        theme.colorScheme.primary);
    expect(tester.getSize(find.byType(DayHeader)).height, kDayHeaderHeight);
  });
}
