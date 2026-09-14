// The feed's non-populated states: first load, and no feeds yet.
//
// **The shimmer's geometry is the point of half this file.** The skeleton has
// to be the same shape as the card it stands in for, or the list visibly
// reflows the moment real articles arrive — every row changing height at once,
// which is the exact class of movement this app's central invariant forbids.
// So the brief specifies it down to the dp: a 16px dot, source bars at 80 and
// 40, three title lines at 14 with the last one short at 180, and a 72px
// thumbnail. None of that changed in this pass and all of it is asserted here,
// because "unchanged" is only a fact while something checks.
//
// What did change is the greys. The old pair were fixed hexes left over from
// the palette era — #1E2E3E and #2A3E52 are navy, and on Quiet Ink's
// near-neutral dark surface they put a blue cast on every card during boot.
// The base is now the placeholder role, the same fill a missing thumbnail
// uses, so the skeleton and the thing it substitutes for are one colour.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/empty_state.dart';
import 'package:flash/widgets/shimmer_card.dart';

Future<void> _pump(WidgetTester tester, Widget child, ThemeData? theme) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

void main() {
  group('first load: the skeleton is the card, in outline', () {
    testWidgets('the geometry is exactly what the brief specifies',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 400, child: ShimmerCard()),
        flashQuietInkTheme(brightness: Brightness.light),
      );

      final rendered = find.descendant(
        of: find.byType(ShimmerCard),
        matching: find.byType(Container),
      );

      // Tree order: dot, source bar, timestamp bar, three title lines,
      // thumbnail.
      final sizes = [
        for (var i = 0; i < rendered.evaluate().length; i++)
          tester.getSize(rendered.at(i))
      ];

      expect(sizes.length, 7, reason: 'the skeleton draws seven blocks');
      expect(sizes[0], const Size(16, 16), reason: 'the favicon dot');
      expect(sizes[1], const Size(80, 12), reason: 'the source bar');
      expect(sizes[2], const Size(40, 12), reason: 'the timestamp bar');
      expect(sizes[3].height, 14, reason: 'title line 1');
      expect(sizes[4].height, 14, reason: 'title line 2');
      expect(sizes[5], const Size(180, 14),
          reason: 'the last title line is short, so the block reads as text');
      expect(sizes[6], const Size(72, 72), reason: 'the thumbnail');
    });

    testWidgets('the first two title lines run full width', (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 400, child: ShimmerCard()),
        flashQuietInkTheme(brightness: Brightness.light),
      );

      final rendered = find.descendant(
        of: find.byType(ShimmerCard),
        matching: find.byType(Container),
      );
      final one = tester.getSize(rendered.at(3)).width;
      final two = tester.getSize(rendered.at(4)).width;
      final short = tester.getSize(rendered.at(5)).width;

      expect(one, two);
      expect(short, lessThan(one));
    });

    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final name = brightness.name;

      testWidgets('$name: the base grey is the placeholder role',
          (tester) async {
        await _pump(tester, const ShimmerCard(), theme);

        final shimmer = tester.widget<Shimmer>(find.byType(Shimmer));
        final colours = shimmer.gradient.colors;
        expect(colours, contains(theme.flashColors.placeholder),
            reason: '$name: a skeleton and the missing thumbnail it will '
                'become should be the same grey');
      });

      testWidgets('$name: nothing navy survives', (tester) async {
        // The specific values being replaced.
        await _pump(tester, const ShimmerCard(), theme);

        final colours =
            tester.widget<Shimmer>(find.byType(Shimmer)).gradient.colors;
        expect(colours, isNot(contains(const Color(0xFF1E2E3E))));
        expect(colours, isNot(contains(const Color(0xFF2A3E52))));
        expect(colours, isNot(contains(const Color(0xFFE0E0E0))));
        expect(colours, isNot(contains(const Color(0xFFF5F5F5))));
      });

      testWidgets('$name: the sweep is brighter than the block it crosses',
          (tester) async {
        // Which direction that is depends on the theme, and getting it
        // backwards makes the shimmer a dark band travelling over a light
        // one — still animated, and still obviously wrong.
        await _pump(tester, const ShimmerCard(), theme);

        final colours =
            tester.widget<Shimmer>(find.byType(Shimmer)).gradient.colors;
        final base = theme.flashColors.placeholder;
        final highlight =
            colours.firstWhere((c) => c != base, orElse: () => base);

        expect(
            highlight.computeLuminance(), greaterThan(base.computeLuminance()),
            reason: '$name: the highlight must be the lighter of the two');
      });
    }

    testWidgets('Newspaper renders it without throwing', (tester) async {
      await _pump(tester, const ShimmerCard(), flashNewspaperTheme());
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stock ThemeData renders it without throwing',
        (tester) async {
      await _pump(tester, const ShimmerCard(), null);
      expect(tester.takeException(), isNull);
    });
  });

  group('no feeds yet: two ways out, and no FAB', () {
    Widget empty() => EmptyState(onAddFeed: () {}, onAddStarterPack: () {});

    testWidgets('both buttons are offered', (tester) async {
      // The second one is the whole remedy for how the app got pulled from
      // Play: the reviewer reached this screen and the only thing on it sent
      // them to an empty form.
      await _pump(
          tester, empty(), flashQuietInkTheme(brightness: Brightness.light));

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('the copy is the ARB, both lines', (tester) async {
      await _pump(
          tester, empty(), flashQuietInkTheme(brightness: Brightness.light));

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.nothingHereYet), findsOneWidget);
      expect(find.text(l10n.addFirstFeed), findsOneWidget);
    });

    testWidgets('tapping each one fires its own callback', (tester) async {
      var add = 0;
      var pack = 0;
      await _pump(
        tester,
        EmptyState(onAddFeed: () => add++, onAddStarterPack: () => pack++),
        flashQuietInkTheme(brightness: Brightness.light),
      );

      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      expect(add, 1);
      expect(pack, 1);
    });

    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
      ('stock ThemeData', null),
    ]) {
      testWidgets('$name renders it without throwing', (tester) async {
        await _pump(tester, empty(), theme);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
