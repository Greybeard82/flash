// 3 — the banner becomes visible, without becoming loud.
//
// The first attempt made the fill quiet (about 1.10:1 off the page) and David
// marked everything read and saw nothing at all. Quiet had become absent. The
// fill stays; the icon and the border now do the seeing.
//
// Two things are held to a real number here rather than to an opinion:
//
//   * The **border** is what defines the component's edge now, which makes it
//     a non-text graphical object under WCAG 1.4.11 at **3:1** — against both
//     the fill it sits on AND the page behind it. `outlineVariant` measured
//     1.08 / 1.09 and was nowhere near.
//   * The **icon** is a graphical object on the same footing.
//
// And one thing is deliberately NOT colour: the confirmation/failure split is
// carried by the glyph. No red is introduced anywhere.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/notification_banner.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

final _themes = <String, ThemeData>{
  'Quiet Ink light': flashQuietInkTheme(brightness: Brightness.light),
  'Quiet Ink dark': flashQuietInkTheme(brightness: Brightness.dark),
  'Newspaper': flashNewspaperTheme(),
};

Future<NotificationBannerState> _pump(
  WidgetTester tester,
  ThemeData theme, {
  required BannerKind kind,
  String message = 'All marked as read',
}) async {
  final key = GlobalKey<NotificationBannerState>();
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      // A real page colour behind it, so "against the page" is measurable
      // rather than assumed.
      backgroundColor: theme.colorScheme.surface,
      body: NotificationBanner(key: key),
    ),
  ));
  key.currentState!.show(message, kind: kind);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return key.currentState!;
}

void main() {
  group('the border carries the edge, and meets 1.4.11', () {
    _themes.forEach((name, theme) {
      test('$name: 3:1 against both the fill and the page', () {
        final border = theme.flashColors.bannerBorder;
        final fill = theme.flashColors.bannerSurface;
        final page = theme.colorScheme.surface;

        expect(_contrast(border, fill), greaterThanOrEqualTo(3.0),
            reason: '$name: the border is the component boundary now');
        expect(_contrast(border, page), greaterThanOrEqualTo(3.0),
            reason: '$name: it has to be visible where the banner ends and '
                'the list begins, too');
      });

    });

    test('Quiet Ink light: outlineVariant would NOT have met it', () {
      // The regression guard with teeth, kept as a measurement so swapping
      // the border back to outlineVariant is visibly a cost.
      //
      // **Asserted for light only, on purpose.** Quiet Ink dark's
      // outlineVariant is `Colors.white.withValues(alpha: 0.09)`, and
      // `computeLuminance()` ignores alpha — so measuring it this way
      // reports pure white and a nonsense 17:1 against a dark fill. The
      // number would be meaningless, not merely wrong, and a test asserting
      // it either way would be measuring nothing. Newspaper never declares
      // the role at all and inherits a Material default.
      //
      // Worth knowing beyond this file: any contrast assertion against a
      // translucent token in this codebase is invalid for the same reason.
      // Nothing else currently makes one.
      final light = flashQuietInkTheme(brightness: Brightness.light);
      expect(
          _contrast(
              light.colorScheme.outlineVariant, light.flashColors.bannerSurface),
          lessThan(3.0));
      expect(
          _contrast(
              light.colorScheme.outlineVariant, light.colorScheme.surface),
          lessThan(3.0));
    });
  });

  group('the icon is what makes it findable', () {
    _themes.forEach((name, theme) {
      testWidgets('$name: there is one, and it clears 3:1 on the fill',
          (tester) async {
        await _pump(tester, theme, kind: BannerKind.confirmation);

        final icon = tester.widget<Icon>(find
            .descendant(
                of: find.byType(NotificationBanner), matching: find.byType(Icon))
            .first);
        expect(icon.color, theme.colorScheme.primary);
        expect(_contrast(icon.color!, theme.flashColors.bannerSurface),
            greaterThanOrEqualTo(3.0),
            reason: '$name: a glyph nobody can see is the bug being fixed');
      });
    });
  });

  group('confirmation and failure are told apart by shape, not colour', () {
    _themes.forEach((name, theme) {
      testWidgets('$name: different glyphs, identical colour', (tester) async {
        await _pump(tester, theme, kind: BannerKind.confirmation);
        final ok = tester.widget<Icon>(find
            .descendant(
                of: find.byType(NotificationBanner), matching: find.byType(Icon))
            .first);

        await _pump(tester, theme,
            kind: BannerKind.failure, message: 'Couldn\'t refresh');
        final bad = tester.widget<Icon>(find
            .descendant(
                of: find.byType(NotificationBanner), matching: find.byType(Icon))
            .first);

        expect(ok.icon, isNot(bad.icon),
            reason: '$name: if the glyphs match, the split does nothing');
        expect(ok.color, bad.color,
            reason: '$name: **4.2** — the split must NOT depend on colour. '
                'In Newspaper primary is the spot red already doing four '
                'other jobs, so a colour-coded failure would either collide '
                'with it or introduce a second red.');
      });

      testWidgets('$name: no red is introduced', (tester) async {
        // In Quiet Ink red means exactly one thing: broken. The failure
        // variant is a refusal, not a malfunction, and must not borrow it.
        await _pump(tester, theme,
            kind: BannerKind.failure, message: 'Couldn\'t refresh');
        final icon = tester.widget<Icon>(find
            .descendant(
                of: find.byType(NotificationBanner), matching: find.byType(Icon))
            .first);
        expect(icon.color, isNot(theme.colorScheme.error),
            reason: '$name: error red is for broken, not for "nothing to do"');
      });
    });

    testWidgets('Newspaper: the split survives its single spot colour',
        (tester) async {
      // 4.2, asserted rather than assumed. Newspaper has one accent and it is
      // already the nav selection, the FAB, the switch and the masthead. The
      // icons therefore share it, and only their shape differs — which is
      // exactly why the split was built on glyphs.
      final theme = flashNewspaperTheme();
      await _pump(tester, theme, kind: BannerKind.confirmation);
      final ok = tester.widget<Icon>(find
          .descendant(
              of: find.byType(NotificationBanner), matching: find.byType(Icon))
          .first);
      await _pump(tester, theme, kind: BannerKind.failure);
      final bad = tester.widget<Icon>(find
          .descendant(
              of: find.byType(NotificationBanner), matching: find.byType(Icon))
          .first);

      expect(ok.icon, isNot(bad.icon));
      expect(ok.color, const Color(0xFFA0231A),
          reason: 'it is the spot red, shared by both, so red does not come '
              'to mean failure');
    });
  });

  test('confirmation is the default, and that is the safe direction', () {
    // A failure wearing a tick is misleading; a confirmation wearing a tick is
    // merely unremarkable. Ten of the eighteen messages are confirmations, so
    // the default is also the larger half.
    expect(BannerKind.values, hasLength(2));
    expect(BannerKind.confirmation, BannerKind.values.first);
  });
}
