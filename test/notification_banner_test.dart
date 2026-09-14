// The notification banner, verified against the spec rather than rewritten.
//
// Pass 4 listed this as a component to build. It already existed, and it
// already matched: full-bleed with no radius and no margin, 16/10 padding,
// centred 13px text on `inverseSurface`, sliding in from above, dismissing on
// tap or after four seconds, and taking a string and nothing else. This file
// is the test it did not have.
//
// **Why `inverseSurface` is the right role and not a fixed dark.** It inverts
// with the theme by construction: Quiet Ink aliases `inverseSurface` to
// `onSurface` and `onInverseSurface` to `surface`, so the bar is near-black
// with white text in light mode and pale with dark text in dark mode. That
// second case is not a bug to fix — a dark strip on a dark page would
// disappear into it. Newspaper never declares either role, and ColorScheme
// falls them back to `onSurface`/`surface` too, which lands it on ink over
// newsprint without anyone having chosen a value.
//
// **No icon, no action slot.** `show()` takes a String. A "Retry" button was
// considered and dropped, because that is a new widget capability rather than
// a new string, and the FAB is already the retry. The test below asserts the
// absence, since absence is the kind of thing that erodes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/notification_banner.dart';

final _key = GlobalKey<NotificationBannerState>();

Future<void> _pump(WidgetTester tester, ThemeData? theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Column(children: [NotificationBanner(key: _key)]),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester,
    [String message = 'Refresh failed']) async {
  _key.currentState!.show(message);
  await tester.pumpAndSettle();
}

Container _barOf(WidgetTester tester) => tester.widget<Container>(
      find.descendant(
        of: find.byType(NotificationBanner),
        matching: find.byType(Container),
      ),
    );

void main() {
  group('shape', () {
    testWidgets('full-bleed: no radius, no margin, full width', (tester) async {
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      final bar = _barOf(tester);
      expect(bar.margin, isNull, reason: 'a margin would break the full bleed');
      expect(bar.decoration, isNull,
          reason: 'the colour is a plain `color`, not a BoxDecoration — a '
              'decoration is how a radius gets in');
      expect(tester.getSize(find.byType(NotificationBanner)).width,
          tester.getSize(find.byType(Scaffold)).width);
    });

    testWidgets('padding is 16 across and 10 down', (tester) async {
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      expect(_barOf(tester).padding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10));
    });

    testWidgets('the text is 13px and centred', (tester) async {
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      final text = tester.widget<Text>(find.text('Refresh failed'));
      expect(text.style!.fontSize, 13);
      expect(text.textAlign, TextAlign.center);
    });

    testWidgets('it collapses to nothing when there is no message',
        (tester) async {
      // The regression the widget's own comment records: clearing only
      // `_visible` left the Container laid out at full height, merely slid
      // off-screen, and put a permanent blank strip above the article list.
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      expect(tester.getSize(find.byType(NotificationBanner)).height, 0);
    });
  });

  group('it carries a sentence and nothing else', () {
    testWidgets('no icon, no button, no action slot', (tester) async {
      // A "Retry" was considered and dropped: that is a widget capability,
      // not a string, and the FAB is already the retry. Absence erodes, so it
      // is asserted.
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      final inside = find.descendant(
        of: find.byType(NotificationBanner),
        matching: find.byType(Icon),
      );
      expect(inside, findsNothing);
      expect(
          find.descendant(
              of: find.byType(NotificationBanner),
              matching: find.byType(ButtonStyleButton)),
          findsNothing);
      expect(find.text('Refresh failed'), findsOneWidget);
    });

    testWidgets('a second message replaces the first', (tester) async {
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester, 'First');
      await _show(tester, 'Second');

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  group('it goes away', () {
    testWidgets('on tap', (tester) async {
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      await tester.tap(find.text('Refresh failed'));
      await tester.pumpAndSettle();

      expect(find.text('Refresh failed'), findsNothing);
      expect(tester.getSize(find.byType(NotificationBanner)).height, 0);
    });

    testWidgets('and after four seconds if it is not tapped', (tester) async {
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Refresh failed'), findsOneWidget,
          reason: 'three seconds is not four');

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Refresh failed'), findsNothing);
    });
  });

  group('it inverts with the theme', () {
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
    ]) {
      testWidgets('$name: bar and text take the inverse roles', (tester) async {
        await _pump(tester, theme);
        await _show(tester);

        final scheme = theme.colorScheme;
        expect(_barOf(tester).color, scheme.inverseSurface);
        expect(tester.widget<Text>(find.text('Refresh failed')).style!.color,
            scheme.onInverseSurface);
      });

      testWidgets('$name: the bar contrasts with the page behind it',
          (tester) async {
        // The point of using an inverse role at all. A banner the same tone
        // as the surface it sits on is not a banner.
        await _pump(tester, theme);
        await _show(tester);

        expect(_barOf(tester).color, isNot(theme.colorScheme.surface));
      });
    }

    testWidgets('dark mode is pale, and that is correct', (tester) async {
      // Stated explicitly because it looks wrong in a screenshot and is not.
      // A dark strip on a near-black page would vanish into it.
      final light = flashQuietInkTheme(brightness: Brightness.light);
      final dark = flashQuietInkTheme(brightness: Brightness.dark);

      expect(dark.colorScheme.inverseSurface, dark.colorScheme.onSurface);
      expect(light.colorScheme.inverseSurface, light.colorScheme.onSurface);

      double luminance(Color c) => c.computeLuminance();
      expect(luminance(dark.colorScheme.inverseSurface),
          greaterThan(luminance(light.colorScheme.inverseSurface)),
          reason: 'the dark theme banner must be the paler of the two');
    });

    testWidgets('Newspaper lands on its own ink and paper', (tester) async {
      // It declares neither inverse role; ColorScheme falls them back to
      // onSurface/surface, which is _npInk over _npPaper. On-palette by
      // accident of the fallback rather than by choice, but on-palette.
      final theme = flashNewspaperTheme();
      await _pump(tester, theme);
      await _show(tester);

      expect(_barOf(tester).color, const Color(0xFF1D1D1B));
      expect(tester.widget<Text>(find.text('Refresh failed')).style!.color,
          const Color(0xFFF2F1EE));
    });
  });

  testWidgets('a stock ThemeData renders it without throwing', (tester) async {
    await _pump(tester, null);
    await _show(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Refresh failed'), findsOneWidget);
  });
}
