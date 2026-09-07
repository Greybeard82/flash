// Contrast checks for `_applyAccentOverride`'s two colour pairs, across
// every palette and both brightnesses.
//
// The alert-keyword badges paint `onSecondaryContainer` on
// `secondaryContainer`, straight from the active ColorScheme, on the
// argument that `ColorScheme.fromSeed` already guarantees each pair
// contrasts. That is the right argument, and this checks it rather than
// trusting it — every palette carries a hand-adjusted two-hue accent
// override (`_applyAccentOverride` in app_theme.dart), and an override is
// exactly the kind of thing that can quietly break a generated guarantee.
// It already did once, here: the override used to touch only
// `secondary`/`onSecondary`, leaving `secondaryContainer`/
// `onSecondaryContainer` derived from the *primary* seed's own algorithmic
// secondary palette — invisible while nothing painted with it, and wrong the
// moment the alert badges started using it.
//
// The summary button used to be checked the same way, off the same accent
// pair. It no longer is: it paints two fixed hex values now, so it has no
// ColorScheme guarantee behind it at all and is checked separately, below,
// against a higher bar.
//
// The bar for the generated pairs is 3:1, WCAG AA for non-text content: a
// badge's content is a wordmark cut down to labelSmall, treated as non-text
// here since a low-vision reader working from context has the keyword text
// itself, not the container tint, doing the identifying work. Real values
// are far above the bar; the point is to catch a future palette or override
// that is not.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart'
    show kSummaryButtonFill, kSummaryButtonIcon;
import 'package:flash/widgets/quick_settings_bubble.dart' show kPaletteKeys;

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel((c.r * 255).roundToDouble()) +
      0.7152 * channel((c.g * 255).roundToDouble()) +
      0.0722 * channel((c.b * 255).roundToDouble());
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// How far apart two colours' hues are, in degrees on the 360° wheel —
/// wrapping the short way round, so 350° and 10° are 20° apart, not 340°.
double _hueDistance(Color a, Color b) {
  final diff = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
  return diff > 180 ? 360 - diff : diff;
}

void main() {
  const minimum = 3.0;

  for (final palette in kPaletteKeys) {
    for (final brightness in Brightness.values) {
      final scheme = paletteColorScheme(palette: palette, brightness: brightness);

      test('$palette/${brightness.name}: an alert-keyword badge contrasts '
          'with its chip', () {
        final ratio =
            _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer);
        expect(ratio, greaterThanOrEqualTo(minimum),
            reason: '$palette/${brightness.name} draws a keyword badge at '
                '${ratio.toStringAsFixed(2)}:1, below the 3:1 this app holds '
                'non-text content to');
      });

      // A contrast ratio alone would not have caught the bug this pins: a
      // secondaryContainer left undertouched by the override is still
      // internally well-contrasted against its own onSecondaryContainer —
      // it is just the *wrong colour entirely*, tinted like the primary
      // seed's own algorithmic secondary palette instead of the accent seed.
      // Hue proximity to `secondary` (which is unambiguously accent-derived)
      // is what actually distinguishes "fixed" from "reverted."
      test('$palette/${brightness.name}: the badge chip shares its hue with '
          'the summary button, not the primary seed', () {
        final distance = _hueDistance(scheme.secondaryContainer, scheme.secondary);
        expect(distance, lessThan(20),
            reason: '$palette/${brightness.name}: secondaryContainer is '
                '${distance.toStringAsFixed(1)}° from secondary — that far '
                'apart means secondaryContainer is still coming from the '
                'primary seed\'s own generated palette, not the accent seed');
      });
    }
  }

  // The summary button left the ColorScheme behind: it paints two fixed hex
  // values now, because pulling the active palette's accent in that position
  // read as garish. That trades one risk for another — a fixed *light* fill
  // paired with a theme role would be light-on-light in dark mode — so the
  // pair is pinned here, against the same constants the button paints.
  group('the summary button is a fixed pair, checked as one', () {
    test('the icon contrasts with the fill', () {
      final ratio = _contrast(kSummaryButtonIcon, kSummaryButtonFill);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'held to 4.5:1, not the 3:1 used for the generated pairs '
              'above: these two are chosen by hand, so there is no '
              'ColorScheme guarantee underneath them — it is ${ratio.toStringAsFixed(2)}:1');
    });

    test('neither colour varies with palette or brightness', () {
      // The point of fixing them. If either ever became theme-derived again,
      // it would have to stop being a const to do it.
      expect(kSummaryButtonFill, const Color(0xFFB0EBFF));
      expect(kSummaryButtonIcon, const Color(0xFF0A2540));
    });

    test('the icon is the darker of the two', () {
      // Guards the specific dark-mode failure: a light icon on this light
      // fill still passes a naive ratio check only if the fill is dark, so
      // asserting which one is darker pins the intended direction.
      expect(_luminance(kSummaryButtonIcon),
          lessThan(_luminance(kSummaryButtonFill)));
    });
  });

  group('Newspaper mode contrasts too', () {
    // Hand-written constants, not generated from a seed, so the guarantee the
    // others lean on does not apply here at all.
    final scheme = flashNewspaperTheme().colorScheme;

    test('alert-keyword badge', () {
      final ratio =
          _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer);
      expect(ratio, greaterThanOrEqualTo(minimum),
          reason: 'newspaper is ${ratio.toStringAsFixed(2)}:1');
    });
  });
}
