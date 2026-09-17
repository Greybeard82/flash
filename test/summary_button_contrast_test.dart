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

  // ── the save half ─────────────────────────────────────────────────────────
  //
  // **The saved state is a glyph now, not a fill, and this group is the pair
  // that changed.** What it used to assert, so the replacement is readable
  // against it:
  //
  //   dark    `onSecondary` on `secondary`, >= 4.5     — passed at 8.51:1
  //   light   `onSecondary` on `secondary`, == 4.12    — a pinned SHORTFALL,
  //                                                      explicitly < 4.5
  //   both    `secondary` vs `primaryContainer` >= 1.5 — fill-versus-fill,
  //                                                      "saved and unsaved
  //                                                      are told apart by
  //                                                      more than the glyph"
  //
  // None of those pairs is painted any more. The fill is `primaryContainer`
  // in both states, so there is no fill-versus-fill distance left to measure,
  // and `onSecondary` is back to having no consumer at all.
  //
  // Design 2a filled the half to make a saved article scannable down the
  // column. That is what the Bookmarks destination is for, one tap away, so
  // the feed was carrying a solid orange block for a job another screen
  // already does. The glyph does the same work at a fraction of the volume.
  //
  // **The bar moved with it, and downward, which is worth being explicit
  // about.** A filled block with a glyph on it was held to 4.5:1 here. A
  // glyph on a constant tint is a graphical object under WCAG 1.4.11, which
  // is 3:1. So this half and the summary half above it now answer to
  // different bars inside one control — not an oversight: the summary glyph's
  // colour is the whole of its identity, while this one also changes shape,
  // outline to solid, which is the other half of the signal and the reason a
  // colour-only reading is not the only reading available.
  //
  // Light is the near thing at 3.36:1 — over the bar, with about 12% of room.
  // Pinned to the measured value rather than just the threshold, so a nudge
  // in either direction fails instead of drifting toward it.
  group('the save half', () {
    /// Measured, per theme. Pinned as exact values because the light one is
    /// close enough to the bar that "still passes" is not the useful signal.
    const measured = <String, double>{
      'light': 3.36,
      'dark': 6.88,
      'Newspaper': 5.97,
    };

    final themes = <String, ThemeData>{
      'light': flashQuietInkTheme(brightness: Brightness.light),
      'dark': flashQuietInkTheme(brightness: Brightness.dark),
      'Newspaper': flashNewspaperTheme(),
    };

    themes.forEach((name, theme) {
      final scheme = theme.colorScheme;

      test('$name: the saved glyph clears 3:1 on its tint', () {
        final ratio = _contrast(scheme.secondary, scheme.primaryContainer);
        expect(ratio, greaterThanOrEqualTo(minimum),
            reason: '$name paints a saved bookmark at '
                '${ratio.toStringAsFixed(2)}:1 against the tint underneath '
                'it. 3:1 is WCAG 1.4.11 for a graphical object. If this has '
                'dropped below, the fix is the glyph colour — not the bar, '
                'and not a nudge to the hue, which is the unread dot too.');
        expect(ratio, closeTo(measured[name]!, 0.02),
            reason: '$name measured ${ratio.toStringAsFixed(2)}:1 against a '
                'recorded ${measured[name]}. Something moved one of the two '
                'roles; say which, and re-record it deliberately.');
      });
    });

    test('light has the least room, and that is the one to watch', () {
      // Stated as its own assertion so the ordering is on the record rather
      // than implied by three numbers in a map. If dark or Newspaper ever
      // becomes the tightest, the palette has changed shape and this whole
      // group needs re-reading, not just re-recording.
      expect(measured['light']!, lessThan(measured['dark']!));
      expect(measured['light']!, lessThan(measured['Newspaper']!));
      expect(measured['light']! - minimum, lessThan(0.5),
          reason: 'light sits within half a point of the bar. Kept explicit '
              'so nobody reads 3.36 as comfortable.');
    });

    test('the unsaved glyph clears the bar on its teal tint', () {
      // Unchanged by the fill removal — the resting state was always a glyph
      // on `primaryContainer`, and it is held to the stricter 4.5 because
      // nothing about it changes shape to help.
      for (final brightness in Brightness.values) {
        final scheme = flashQuietInkTheme(brightness: brightness).colorScheme;
        final ratio =
            _contrast(scheme.onSurfaceVariant, scheme.primaryContainer);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${brightness.name} paints an unsaved save glyph at '
                '${ratio.toStringAsFixed(2)}:1');
      }
    });

    test('the two states are not the same colour in any theme', () {
      // The replacement for the old fill-versus-fill test, moved to the pair
      // that now carries the distinction. Newspaper is the reason this is not
      // trivially true: its `onSurfaceVariant` and its `_npInk` are the same
      // hex, so a saved glyph painted in ink there would be pixel-identical
      // to an unsaved one and the shape swap would be the only signal left.
      themes.forEach((name, theme) {
        final scheme = theme.colorScheme;
        expect(scheme.secondary, isNot(scheme.onSurfaceVariant),
            reason: '$name paints saved and unsaved in the same colour, which '
                'leaves shape as the only difference');
      });
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

    test('the saved glyph is red, and that is the recommendation', () {
      // Superseding the old assertion here, which measured `onSecondary` on
      // `secondary` at 7.64:1 and flagged as an open design question whether
      // a solid red *block* belonged on every saved card in a theme where red
      // already means nav-selected, FAB and masthead. The block is gone, and
      // the question goes with it: a red glyph is small, appears only when
      // saved, and is the only colour Newspaper has to carry a state with.
      //
      // The alternative was `_npInk`, and it is not viable rather than merely
      // worse: Newspaper's `onSurfaceVariant` — the unsaved glyph — is
      // `#1D1D1B`, and `_npInk` is the same `#1D1D1B`. An ink saved glyph
      // would be the identical colour, leaving the outline-to-solid swap as
      // the sole distinction. That is a real reduction, and it is the reason
      // this went red rather than a preference for red.
      expect(scheme.secondary, scheme.primary,
          reason: 'Newspaper has one spot colour and this is it');
      final ratio = _contrast(scheme.secondary, scheme.primaryContainer);
      expect(ratio, greaterThanOrEqualTo(minimum),
          reason: 'newspaper saved glyph is ${ratio.toStringAsFixed(2)}:1');
    });
  });
}
