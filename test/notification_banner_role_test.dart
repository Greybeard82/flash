// 1.5 — the notification banner gets a role of its own.
//
// It used to paint `inverseSurface`. That is semantically correct for what a
// full inversion means, which is exactly why it needed a NEW role rather than
// a substitution: `inverseSurface` keeps its meaning and stops being borrowed
// for a one-line confirmation strip.
//
// The role is deliberately quiet — about 1.10:1 off the page — because the
// banner slides in, and motion is what catches the eye. Something that moves
// does not need contrast shock as well. The hairline is what keeps the edge
// legible once it has settled, so it is asserted rather than assumed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/notification_banner.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  final themes = <String, ThemeData>{
    'Quiet Ink light': flashQuietInkTheme(brightness: Brightness.light),
    'Quiet Ink dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  group('the role', () {
    themes.forEach((name, theme) {
      test('$name: text on the banner clears 4.5:1', () {
        // 1.2 removed this app's last two text contrast exceptions in the same
        // pass. Opening a third here would have been absurd.
        expect(
            _contrast(theme.colorScheme.onSurface,
                theme.flashColors.bannerSurface),
            greaterThanOrEqualTo(4.5),
            reason: name);
      });

      test('$name: it sits above surface but nowhere near inverseSurface', () {
        final banner = theme.flashColors.bannerSurface;
        final surface = theme.colorScheme.surface;
        final inverse = theme.colorScheme.inverseSurface;

        expect(banner, isNot(surface),
            reason: '$name: identical to the page means no strip at all');
        expect(banner, isNot(inverse),
            reason: '$name: this is the substitution the change exists to '
                'avoid');

        // Quantified rather than described: one step off the page, not a slab.
        expect(_contrast(banner, surface), lessThan(1.5),
            reason: '$name: the banner should be quiet; it is announced by '
                'motion, not by weight');
        expect(_contrast(inverse, surface),
            greaterThan(_contrast(banner, surface)),
            reason: '$name: the old treatment must remain the heavy one, or '
                'the roles have been swapped rather than separated');
      });

      test('$name: it reuses an authored tone rather than a new hex', () {
        // Named values, so a future edit has to argue with a specific token
        // instead of nudging an anonymous grey.
        final expected = switch (name) {
          'Quiet Ink light' => const Color(0xFFF1F5F5),
          'Quiet Ink dark' => const Color(0xFF161D1C),
          _ => const Color(0xFFE7E7E3),
        };
        expect(theme.flashColors.bannerSurface, expected);
      });
    });

    test('it participates in copyWith, lerp and equality', () {
      final ink = flashQuietInkTheme(brightness: Brightness.light).flashColors;
      const other = Color(0xFF123456);
      expect(ink.copyWith(bannerSurface: other).bannerSurface, other);
      expect(ink.copyWith().bannerSurface, ink.bannerSurface);
      expect(ink == ink.copyWith(bannerSurface: other), isFalse,
          reason: 'left out of ==, a theme change would not repaint the strip');
      expect(ink.hashCode == ink.copyWith(bannerSurface: other).hashCode,
          isFalse);
    });

    test('a theme with no extension still gets a usable banner tone', () {
      final fallback = ThemeData().flashColors;
      expect(fallback.bannerSurface, isNotNull);
      expect(_contrast(fallback.bannerSurface, ThemeData().colorScheme.surface),
          lessThan(1.5));
    });
  });

  group('what the widget actually paints', () {
    // Per harness rule 10.2: assert against the real widget, not a rebuilt
    // copy of the expression.
    for (final entry in themes.entries) {
      testWidgets('${entry.key}: fill, hairline and text colour',
          (tester) async {
        final key = GlobalKey<NotificationBannerState>();
        await tester.pumpWidget(MaterialApp(
          theme: entry.value,
          home: Scaffold(body: NotificationBanner(key: key)),
        ));
        key.currentState!.show('Marked all as read');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final container = tester.widget<Container>(find
            .descendant(
                of: find.byType(NotificationBanner),
                matching: find.byType(Container))
            .first);
        final decoration = container.decoration as BoxDecoration;

        expect(decoration.color, entry.value.flashColors.bannerSurface,
            reason: '${entry.key}: the widget must read the role');
        expect(decoration.color, isNot(entry.value.colorScheme.inverseSurface),
            reason: '${entry.key}: still borrowing inverseSurface');

        // The hairline is load-bearing: without it a fill this quiet has no
        // edge against the list beneath it.
        final border = decoration.border as Border;
        expect(border.bottom.color, entry.value.colorScheme.outlineVariant);
        expect(border.bottom.width, greaterThan(0));

        final text = tester.widget<Text>(find.text('Marked all as read'));
        expect(text.style!.color, entry.value.colorScheme.onSurface);
      });
    }
  });
}
