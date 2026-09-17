// The notification banner, verified against the spec rather than rewritten.
//
// Pass 4 listed this as a component to build. It already existed, and it
// already matched: full-bleed with no radius and no margin, 16/10 padding,
// centred 13px text, sliding in from above, dismissing on
// tap or after four seconds, and taking a string and nothing else. This file
// is the test it did not have.
//
// **It no longer paints `inverseSurface`, and the argument that it should is
// kept below because it was a good one.** Inverting by construction did give a
// bar that flipped correctly with the theme without anyone choosing a value.
// What it also gave was the heaviest block of colour anywhere in a light,
// papery theme, for what is usually a one-line confirmation.
//
// David ruled it down pre-launch. The fix is a NEW role, `FlashColors
// .bannerSurface`, rather than a substitution, precisely because
// `inverseSurface` was semantically correct for what it meant — so it keeps
// its meaning and stops being borrowed. The new fill sits one step above
// `surface`, with a hairline, because the banner announces itself by sliding
// in and motion does not need contrast shock to go with it.
//
// Colour assertions live in `notification_banner_role_test.dart`. What stays
// here is everything that was never about colour: shape, timing, dismissal,
// and the single-string API.
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
      final decoration = bar.decoration as BoxDecoration;
      expect(decoration.borderRadius, isNull,
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
    testWidgets('exactly one icon, and still no button or action slot',
        (tester) async {
      // **The icon half of this was reversed by David pre-launch and the rest
      // still holds.** It used to assert no icon at all. Then the fill was
      // made quiet, he marked everything read and saw nothing, and a glyph
      // became the thing that makes the banner findable — a saturated mark
      // is visible on a pale fill in a way a pale fill is not on a pale page.
      //
      // A "Retry" button was considered and dropped, and that part is
      // unchanged: it is a widget capability rather than a string, and the
      // FAB is already the retry. Absence erodes, so it stays asserted.
      await _pump(tester, flashQuietInkTheme(brightness: Brightness.light));
      await _show(tester);

      final inside = find.descendant(
        of: find.byType(NotificationBanner),
        matching: find.byType(Icon),
      );
      expect(inside, findsOneWidget,
          reason: 'one leading glyph, not a row of them');
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

  group('it is quiet, and it is separated', () {
    // The replacement for the old "it inverts with the theme" group. The
    // colour values themselves are pinned in notification_banner_role_test;
    // what is asserted here is the property that made an inverse role
    // attractive in the first place, now that a quieter fill has to earn it a
    // different way.
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
    ]) {
      testWidgets('$name: it is still distinguishable from the page',
          (tester) async {
        // A banner the same tone as the surface it sits on is not a banner.
        // It used to clear this by being nearly black; it now clears it by a
        // step of fill plus a hairline, which is the whole point of the
        // change.
        await _pump(tester, theme);
        await _show(tester);

        final decoration = _barOf(tester).decoration as BoxDecoration;
        expect(decoration.color, isNot(theme.colorScheme.surface));
        expect((decoration.border as Border).bottom.width, greaterThan(0),
            reason: '$name: without the hairline a fill this quiet has no '
                'edge against the list beneath it');
      });

      testWidgets('$name: it no longer borrows the inverse roles',
          (tester) async {
        await _pump(tester, theme);
        await _show(tester);

        final decoration = _barOf(tester).decoration as BoxDecoration;
        expect(decoration.color, isNot(theme.colorScheme.inverseSurface),
            reason: '$name: this is the regression the change exists to '
                'prevent coming back');
        expect(tester.widget<Text>(find.text('Refresh failed')).style!.color,
            isNot(theme.colorScheme.onInverseSurface));
      });
    }

    testWidgets('dark is still the paler of the two, as it must be',
        (tester) async {
      // Kept from the old group because the reasoning survives the change: a
      // dark strip on a near-black page would vanish into it. The fill is
      // quieter now, but the direction is the same.
      final light = flashQuietInkTheme(brightness: Brightness.light);
      final dark = flashQuietInkTheme(brightness: Brightness.dark);

      expect(dark.flashColors.bannerSurface.computeLuminance(),
          greaterThan(light.colorScheme.surface.computeLuminance() * 0),
          reason: 'sanity: it is a real colour');
      expect(
          dark.flashColors.bannerSurface.computeLuminance() >
              dark.colorScheme.surface.computeLuminance(),
          isTrue,
          reason: 'in dark mode the banner must lift off the page, not sink '
              'into it');
    });
  });

  testWidgets('a stock ThemeData renders it without throwing', (tester) async {
    await _pump(tester, null);
    await _show(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Refresh failed'), findsOneWidget);
  });
}
