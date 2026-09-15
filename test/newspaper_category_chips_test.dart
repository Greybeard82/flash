// 1.3 — Newspaper draws categories without hue.
//
// This closes 6.8, which had been parked since pass 7 waiting on Newspaper
// hues from Design. The reason they never arrived is that the right answer was
// that there should not be any: a newspaper names its sections, it does not
// colour-code them, and six greys standing in for six hues is a colour system
// with the colour taken out.
//
// The tests that matter here are the NEGATIVE ones. It is easy to write a
// theme test that passes because it re-derives the same expression the widget
// uses. So the assertions below are mostly "this is NOT a category hue" and
// "Quiet Ink did not change", which a re-derivation cannot satisfy by accident.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/theme/category_colors.dart';

void main() {
  final newspaper = flashNewspaperTheme();
  final light = flashQuietInkTheme(brightness: Brightness.light);
  final dark = flashQuietInkTheme(brightness: Brightness.dark);

  group('the flag', () {
    test('Newspaper opts out of hue; Quiet Ink does not', () {
      expect(newspaper.flashColors.monochromeCategories, isTrue);
      expect(light.flashColors.monochromeCategories, isFalse);
      expect(dark.flashColors.monochromeCategories, isFalse);
    });

    test('a theme with no extension at all defaults to hued', () {
      // The fallback path. Defaulting to monochrome would silently strip
      // colour from any theme that forgot to register the extension.
      expect(ThemeData().flashColors.monochromeCategories, isFalse);
    });

    test('it survives copyWith and snaps rather than blends in lerp', () {
      final ink = light.flashColors;
      expect(ink.copyWith(monochromeCategories: true).monochromeCategories,
          isTrue);
      expect(ink.copyWith().monochromeCategories, isFalse,
          reason: 'copyWith with no argument must not flip it');

      final paper = newspaper.flashColors;
      // A half-hued chip is not a thing; it snaps with brightness.
      expect(ink.lerp(paper, 0.2).monochromeCategories,
          isFalse);
      expect(ink.lerp(paper, 0.8).monochromeCategories,
          isTrue);
    });

    test('it participates in equality, so a theme change rebuilds', () {
      // If this were left out of == and hashCode, switching into Newspaper
      // could reuse the old extension and the chips would not repaint.
      final ink = light.flashColors;
      expect(ink == ink.copyWith(monochromeCategories: true), isFalse);
      expect(ink.hashCode == ink.copyWith(monochromeCategories: true).hashCode,
          isFalse);
    });
  });

  group('the tones Newspaper actually uses', () {
    final scheme = newspaper.colorScheme;

    test('unselected is the paper tint with ink text', () {
      expect(scheme.surfaceContainerHighest, const Color(0xFFE7E7E3));
      expect(scheme.onSurface, const Color(0xFF1D1D1B));
    });

    test('selected inverts to ink fill with paper text', () {
      expect(scheme.surface, const Color(0xFFF2F1EE));
    });

    test('selected does NOT use the red spot colour', () {
      // The point of the change. `primary` is _npRed and is already the nav
      // selection, the FAB and the masthead tint; a red chip row on top of
      // that is the loudest thing on the screen.
      expect(scheme.onSurface, isNot(scheme.primary));
      expect(scheme.primary, const Color(0xFFA0231A),
          reason: 'if primary stopped being the spot red, the reasoning above '
              'needs rereading rather than the test updating');
    });

    test('both chip states clear 4.5:1 for their own text', () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      // 1.2 just removed this app's last two text contrast exceptions. This
      // must not open a third.
      expect(contrast(scheme.onSurface, scheme.surfaceContainerHighest),
          greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.surface, scheme.onSurface),
          greaterThanOrEqualTo(4.5));
    });

    test('none of the six category hues is any of those tones', () {
      // The real assertion: whatever a chip paints in Newspaper, it is not a
      // hue. Checked against every index rather than a sample.
      final chipTones = {
        newspaper.colorScheme.surfaceContainerHighest,
        newspaper.colorScheme.onSurface,
        newspaper.colorScheme.surface,
      };
      for (var i = 0; i < kCategoryHueCount; i++) {
        final hue = categoryPalette(i, Brightness.light);
        expect(chipTones.contains(hue.chipBackground), isFalse,
            reason: 'hue $i background leaked into the Newspaper chip tones');
      }
    });
  });

  test('Quiet Ink keeps its hues, in both brightnesses', () {
    // The other half. Making Newspaper monochrome must not quietly drain
    // colour out of the theme the hues were designed for.
    for (final (name, theme) in [('light', light), ('dark', dark)]) {
      final seen = <Color>{};
      for (var i = 0; i < kCategoryHueCount; i++) {
        seen.add(theme.flashColors.category(i).chipBackground);
      }
      expect(seen, hasLength(kCategoryHueCount),
          reason: '$name: six categories must still be six distinct chips');
    }
  });
}
