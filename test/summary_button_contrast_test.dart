// The AI-summary button's colours, across every palette and both brightnesses.
//
// The button paints `onPrimaryContainer` on `primaryContainer`, taken straight
// from the active ColorScheme, on the argument that `ColorScheme.fromSeed`
// already guarantees the pair contrasts. That is the right argument, and this
// checks it rather than trusting it — the app ships five seeds plus a
// hand-adjusted two-hue override for `teal_orange` and a separate Newspaper
// scheme, and an override is exactly the kind of thing that can quietly break
// a generated guarantee.
//
// The bar is 3:1, WCAG AA for non-text content: the button's content is an
// 18dp icon, not body text. Real values are far above it — the point of the
// test is to catch a future palette or override that is not.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
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

void main() {
  const minimum = 3.0;

  for (final palette in kPaletteKeys) {
    for (final brightness in Brightness.values) {
      test('$palette/${brightness.name}: the summary icon contrasts with its '
          'button', () {
        final scheme =
            paletteColorScheme(palette: palette, brightness: brightness);
        final ratio =
            _contrast(scheme.onPrimaryContainer, scheme.primaryContainer);

        expect(ratio, greaterThanOrEqualTo(minimum),
            reason: '$palette/${brightness.name} draws the summary icon at '
                '${ratio.toStringAsFixed(2)}:1, below the 3:1 this app holds '
                'non-text content to');
      });
    }
  }

  test('Newspaper mode contrasts too', () {
    // Hand-written constants, not generated from a seed, so the guarantee the
    // others lean on does not apply here at all.
    final scheme = flashNewspaperTheme().colorScheme;
    final ratio =
        _contrast(scheme.onPrimaryContainer, scheme.primaryContainer);
    expect(ratio, greaterThanOrEqualTo(minimum),
        reason: 'newspaper is ${ratio.toStringAsFixed(2)}:1');
  });
}
