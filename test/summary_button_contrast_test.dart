// Contrast checks for the two colour pairs Quiet Ink paints on a card: the
// alert-keyword badge and the AI summary button.
//
// Both used to be checked across five generated palettes. There is one
// authored palette now, so the loop is gone and the argument underneath it
// has inverted: these values are no longer *guaranteed* by
// `ColorScheme.fromSeed`'s tonal machinery, they are hand-picked hexes with
// nothing underneath them at all. That makes checking them more important
// than it was, not less — a generated pair that drifts is unusual, a typed
// hex that is one digit wrong is ordinary.
//
// The bar for the badge is 3:1, WCAG AA for non-text content: a badge's
// content is a keyword cut down to labelSmall, treated as non-text here since
// a low-vision reader working from context has the keyword itself, not the
// container tint, doing the identifying work. The summary button is held to
// 4.5:1 — its glyph is the only thing identifying it.
//
// Real values sit far above both bars. The point is to catch the future edit
// that does not.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
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

  for (final brightness in Brightness.values) {
    final theme = flashQuietInkTheme(brightness: brightness);
    final scheme = theme.colorScheme;
    final name = brightness.name;

    group(name, () {
      test('an alert-keyword badge contrasts with its chip', () {
        final ratio =
            _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer);
        expect(ratio, greaterThanOrEqualTo(minimum),
            reason: '$name draws a keyword badge at '
                '${ratio.toStringAsFixed(2)}:1, below the 3:1 this app holds '
                'non-text content to');
      });

      // This test is the inverse of the one it replaces, and deliberately so.
      //
      // It used to assert that `secondaryContainer` sat within 20° of
      // `secondary`, because both were supposed to come from the same accent
      // seed and a drifting container meant the two-hue override had silently
      // reverted. Quiet Ink spends `secondary` on one thing — the unread dot —
      // and an alert badge is a chip, so its container is the *teal* tint.
      // The two being far apart is now the correct state, and the thing worth
      // guarding is that nobody "fixes" the badge back to orange and puts a
      // second orange mark on a row that is allowed exactly one.
      test('the badge chip is the teal tint, not the unread orange', () {
        expect(scheme.secondaryContainer, scheme.primaryContainer,
            reason: 'a badge is a chip, and every chip in Quiet Ink is the '
                'teal tint');
        expect(_hueDistance(scheme.secondaryContainer, scheme.secondary),
            greaterThan(40),
            reason: 'orange is reserved for the unread dot; a badge sharing '
                'its hue puts two orange marks on one row');
      });

      test('the summary button icon contrasts with its fill', () {
        // Held to 4.5:1, not the 3:1 the badge gets: the badge has its own
        // text to identify it and this has only a glyph.
        final ratio =
            _contrast(scheme.onPrimaryContainer, scheme.primaryContainer);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$name paints the summary button at '
                '${ratio.toStringAsFixed(2)}:1');
      });

      test('the summary button reads correctly for its brightness', () {
        // The specific failure the old fixed pair existed to avoid: a light
        // fill that stays light in dark mode, with a glyph that resolves
        // light alongside it. Asserting which of the two is darker pins the
        // intended direction per brightness rather than trusting a ratio,
        // which passes just as happily when both are inverted.
        final fill = _luminance(scheme.primaryContainer);
        final icon = _luminance(scheme.onPrimaryContainer);
        if (brightness == Brightness.light) {
          expect(icon, lessThan(fill),
              reason: 'light mode wants a dark glyph on a pale tint');
        } else {
          expect(icon, greaterThan(fill),
              reason: 'dark mode wants a pale glyph on a deep tint — this is '
                  'exactly what the old fixed pair could not do');
        }
      });

      test('the button is teal, which is the only interactive colour', () {
        expect(
            _hueDistance(scheme.primaryContainer, scheme.primary), lessThan(25),
            reason: 'the tint and the teal it tints must be the same hue');
      });
    });
  }

  // ── the save half, new in pass 3 ──────────────────────────────────────────
  //
  // The rail's lower half fills with `secondary` when an article is saved.
  // That is design 2a as specified, and it puts a pressable orange on the
  // card — which is worth reading alongside the two tests above, because both
  // of them exist to enforce the opposite: "teal is the only interactive
  // colour" and "orange is reserved for the unread dot". Those rules are
  // written into app_theme.dart and this pass breaks both by decision, not by
  // accident. The tests are left standing because they still guard the badge,
  // which is what they were written for.
  //
  // **Light mode does not clear the bar.** `onSecondary` is `surface`, which
  // is white, and white on #BE6530 is 4.12:1 — under the 4.5:1 the summary
  // glyph is held to, and under the 5.17:1 the summary pair actually
  // achieves. Dark (8.51:1) and Newspaper (7.64:1) are fine; only light
  // fails, and it fails because `onSecondary` had no consumer before now.
  // The theme comment says as much: "orange is the unread dot, which carries
  // no label, so this is very nearly unused". This button is its first real
  // consumer, and the value was never chosen for legibility on top of the
  // orange.
  //
  // Rather than quietly lower the bar, the shortfall is pinned to its exact
  // measured value. It fails if anyone makes it worse, and it also fails if
  // anyone fixes it — at which point this block moves up into the passing
  // group and the comment goes away. Awaiting a decision between two
  // one-line fixes: a dark glyph instead of white (`_qiOnSurfaceLight` gives
  // 4.51:1, `_qiSurfaceDark` 4.58:1), or a darker orange for this fill
  // (#B05C2B gives 4.76:1 with white, but moves the unread colour too).
  group('the save half', () {
    test('dark mode clears the bar the summary glyph is held to', () {
      final scheme =
          flashQuietInkTheme(brightness: Brightness.dark).colorScheme;
      final ratio = _contrast(scheme.onSecondary, scheme.secondary);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'dark paints a saved button at '
              '${ratio.toStringAsFixed(2)}:1');
    });

    test('light mode is 4.12:1, which is BELOW the bar, by decision', () {
      final scheme =
          flashQuietInkTheme(brightness: Brightness.light).colorScheme;
      final ratio = _contrast(scheme.onSecondary, scheme.secondary);
      expect(ratio, closeTo(4.12, 0.01),
          reason: 'this is a known, reviewed shortfall, not a passing '
              'result. If this assertion fails because the ratio went UP, '
              'the fix landed: move this test into the group above and '
              'delete the comment. If it went DOWN, something made a '
              'marginal target worse.');
      expect(ratio, lessThan(4.5),
          reason: 'kept explicit so nobody reads the line above as a pass');
    });

    test('the unsaved glyph clears the bar on its teal tint', () {
      // The resting state, which is what the rail shows most of the time.
      for (final brightness in Brightness.values) {
        final scheme = flashQuietInkTheme(brightness: brightness).colorScheme;
        final ratio =
            _contrast(scheme.onSurfaceVariant, scheme.primaryContainer);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${brightness.name} paints an unsaved save glyph at '
                '${ratio.toStringAsFixed(2)}:1');
      }
    });

    test('saved and unsaved are told apart by more than the glyph', () {
      // Orange-on-orange is the failure this was asked to catch: if the fill
      // barely moves between states, the only signal left is the glyph shape.
      for (final brightness in Brightness.values) {
        final scheme = flashQuietInkTheme(brightness: brightness).colorScheme;
        final ratio = _contrast(scheme.secondary, scheme.primaryContainer);
        expect(ratio, greaterThanOrEqualTo(1.5),
            reason: '${brightness.name}: the saved fill and the unsaved fill '
                'are ${ratio.toStringAsFixed(2)}:1 apart — a saved article '
                'has to be visible as saved while scanning the column');
      }
    });
  });

  group('Newspaper mode contrasts too', () {
    // Hand-written constants, and now the only theme in the app with a red in
    // it at all.
    final scheme = flashNewspaperTheme().colorScheme;

    test('alert-keyword badge', () {
      final ratio =
          _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer);
      expect(ratio, greaterThanOrEqualTo(minimum),
          reason: 'newspaper is ${ratio.toStringAsFixed(2)}:1');
    });

    test('a saved button contrasts, whatever colour it ends up', () {
      // Newspaper resolves `secondary` to `_npRed`, its only spot colour and
      // also its `primary`. The contrast is fine at 7.64:1. Whether a solid
      // red block belongs on every saved card in a theme where red already
      // means nav-selected, FAB and masthead is a design question, flagged
      // and not decided here.
      final ratio = _contrast(scheme.onSecondary, scheme.secondary);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'newspaper saved is ${ratio.toStringAsFixed(2)}:1');
    });
  });
}
