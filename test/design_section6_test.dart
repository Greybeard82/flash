// Design section 6: the answers that closed the ink allowlist.
//
// Six rulings, four of which were about where a colour comes from rather than
// what it is. Their combined effect is that `onSurface` at an alpha is no
// longer how this app expresses ink anywhere — `ink_roles_guard_test.dart`
// now polices an empty allowlist.
//
//   6.1  Drag affordances are onSurfaceMuted, matching the resize grip.
//   6.2  inert gets an authored dark value, one step lighter than
//        illustration so the two roles differ where it is easiest to see.
//   6.3  A read search result follows the card, elementwise.
//   6.4  The keyword row tick is onSurfaceMuted, not an illustration.
//   6.5  Disabled and inert are one role, and the 8% wash goes away.
//   6.6  Newspaper is authored with no pixel moves; the fallback stays
//        computed, because authoring it would imply a fourth theme exists.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';

/// The 8-bit pixel a Color actually rasterises to.
///
/// Needed because `Color.lerp` keeps sub-byte precision — mixing #1D1D1B
/// toward #F2F1EE at 0.62 gives a red channel of 161.06, not 161 — so the
/// authored hex below is the same *pixel* as the lerp it replaced without
/// being the same *Color*. "No pixel moves" is a claim about what the screen
/// shows, and the screen shows bytes.
List<int> _px(Color c) => [
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
    ];

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('6.2 inert is its own colour now, not a borrowed one', () {
    test('dark is the authored value', () {
      expect(flashQuietInkTheme(brightness: Brightness.dark).flashColors.inert,
          const Color(0xFF464E4D));
    });

    test('light still shares illustration, and that is deliberate', () {
      final light = flashQuietInkTheme(brightness: Brightness.light);
      expect(light.flashColors.inert, light.flashColors.illustration,
          reason: 'only dark was authored apart; light was already right');
    });

    test('dark separates the two roles visibly', () {
      // The point of authoring it. Two roles that always resolve to the same
      // value are one role with extra steps, and the next change to either
      // would silently move the other.
      final dark = flashQuietInkTheme(brightness: Brightness.dark);
      expect(dark.flashColors.inert, isNot(dark.flashColors.illustration));
      expect(_contrast(dark.flashColors.inert, dark.flashColors.illustration),
          greaterThan(1.1),
          reason: 'a difference too small to see is not a difference');
    });

    test('it sits below text contrast on purpose', () {
      // Around 2.2:1 is intended rather than tolerated. WCAG exempts disabled
      // controls, and one that meets text contrast does not read as disabled.
      // Asserted as a band so it cannot drift into either failure: legible
      // enough to find, faint enough to read as unavailable.
      for (final brightness in Brightness.values) {
        final theme = flashQuietInkTheme(brightness: brightness);
        final ratio =
            _contrast(theme.flashColors.inert, theme.colorScheme.surface);
        expect(ratio, lessThan(3.0),
            reason: '${brightness.name}: at ${ratio.toStringAsFixed(2)}:1 an '
                'inert control is loud enough to look available');
        expect(ratio, greaterThan(1.6),
            reason: '${brightness.name}: at ${ratio.toStringAsFixed(2)}:1 it '
                'has faded into the page and cannot be found at all');
      }
    });
  });

  group('6.6 Newspaper is authored, and nothing moved', () {
    // The values were lerps from _npInk toward _npPaper. Authoring them was
    // meant to change who chose them, not what they are — so these assert the
    // exact pixels the lerps produced.
    const ink = Color(0xFF1D1D1B);
    const paper = Color(0xFFF2F1EE);

    final flash = flashNewspaperTheme().flashColors;

    test('onSurfaceMuted is the old 0.62 mix, to the byte', () {
      expect(_px(flash.onSurfaceMuted), _px(Color.lerp(ink, paper, 0.62)!));
      expect(flash.onSurfaceMuted, const Color(0xFFA1A09E));
    });

    test('onSurfaceRead is the old 0.55 mix, to the byte', () {
      expect(_px(flash.onSurfaceRead), _px(Color.lerp(ink, paper, 0.55)!));
      expect(flash.onSurfaceRead, const Color(0xFF92928F));
    });

    test('illustration is the 0.78 mix, not the hex the document prints', () {
      // The document says #C3C2BF in three sections, under the guarantee that
      // authoring these values changes no pixel. Those disagree by one unit of
      // blue, and the document settles it against itself: on the blue channel
      // the lerps give 157.82 / 143.05 / 191.58 at 0.62 / 0.55 / 0.78, and the
      // document writes 9E, 8F, BF — the first two rounded, only the third
      // truncated. One value converted the other way from its neighbours,
      // under a promise of no pixel change, is a slip.
      //
      // The guarantee wins. If the document is later corrected to #C3C2C0 this
      // test is already right; if Design instead rules that BF was deliberate,
      // this fails and says so rather than the change passing unnoticed.
      expect(_px(flash.illustration), _px(Color.lerp(ink, paper, 0.78)!));
      expect(flash.illustration, const Color(0xFFC3C2C0));
      expect(flash.inert, const Color(0xFFC3C2C0));
      expect(flash.illustration, isNot(const Color(0xFFC3C2BF)),
          reason: 'adopting the printed hex would move the one pixel the '
              'document promises not to move');
    });

    test('Newspaper keeps its two greys equal; only Quiet Ink dark splits them',
        () {
      expect(flash.illustration, flash.inert,
          reason: '6.6 said no pixel moves, and separating them here would '
              'have been one');
    });

    test('the hierarchy still holds after authoring', () {
      // The thing the lerp ratios were chosen for in the first place: a read
      // title stands further from the page than a timestamp does.
      final surface = flashNewspaperTheme().colorScheme.surface;
      expect(_contrast(flash.onSurfaceRead, surface),
          greaterThan(_contrast(flash.onSurfaceMuted, surface)));
    });

    test('the fallback stays computed', () {
      // Deliberately not authored. Hard-coding it would put a fourth set of
      // values in the file and imply a fourth theme, when all it is is what
      // a ThemeData carrying no extension falls back to — which in practice
      // means a widget test.
      final a = ThemeData().flashColors;
      final b = ThemeData.dark().flashColors;
      expect(a.onSurfaceMuted, isNot(b.onSurfaceMuted),
          reason: 'it derives from whatever scheme it is handed, which is the '
              'whole point of it');
    });
  });

  group('the roles the closures leaned on are distinct', () {
    // 6.1, 6.3 and 6.4 all route to onSurfaceMuted, and 6.5 to inert. If any
    // of those collapsed onto a neighbouring role the sites would still
    // compile and still look wrong.
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final ink = theme.flashColors;
      final name = brightness.name;

      test('$name: onSurfaceMuted, onSurfaceVariant and inert all differ', () {
        final values = {
          ink.onSurfaceMuted,
          theme.colorScheme.onSurfaceVariant,
          ink.inert,
        };
        expect(values, hasLength(3),
            reason: '$name: two of the three roles resolve to one colour');
      });

      test('$name: a grabber is quieter than body text but louder than inert',
          () {
        final surface = theme.colorScheme.surface;
        expect(_contrast(ink.onSurfaceMuted, surface),
            lessThan(_contrast(theme.colorScheme.onSurfaceVariant, surface)));
        expect(_contrast(ink.onSurfaceMuted, surface),
            greaterThan(_contrast(ink.inert, surface)),
            reason: '$name: a drag handle you can use must outrank a control '
                'you cannot');
      });
    }
  });
}
