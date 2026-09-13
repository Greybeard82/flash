// The Quiet Ink colour system, asserted token by token.
//
// These values are authored, not derived. That is the whole point of the pass:
// the theme used to build its entire ColorScheme from one seed hex through
// ColorScheme.fromSeed, and no seed produces this table — the teal, the tint,
// the hairline and the orange are four independent choices, and fromSeed
// derives all four from one. So every token below is pinned here, because a
// generated scheme that drifts one step closer to "nearly right" is exactly
// the failure this file exists to catch.
//
// Written before the implementation, deliberately, so the implementation
// cannot rationalise its own output as correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';

/// Compares against the authored hex rather than another expression of it.
void expectColor(Color actual, int argb, String token) {
  expect(actual.toARGB32(), argb,
      reason: '$token should be #${argb.toRadixString(16).toUpperCase()}, '
          'was #${actual.toARGB32().toRadixString(16).toUpperCase()}');
}

void main() {
  final light = flashQuietInkTheme(brightness: Brightness.light);
  final dark = flashQuietInkTheme(brightness: Brightness.dark);

  group('light tokens', () {
    final s = light.colorScheme;

    test('surfaces', () {
      expectColor(s.surface, 0xFFFFFFFF, 'surface');
      expectColor(s.surfaceContainer, 0xFFF1F5F5, 'surfaceContainer');
    });

    test('ink', () {
      expectColor(s.onSurface, 0xFF0F1413, 'onSurface');
      expectColor(s.onSurfaceVariant, 0xFF5A6361, 'onSurfaceVariant');
    });

    test('hairline', () {
      expectColor(s.outlineVariant, 0xFFE9ECEB, 'outlineVariant');
    });

    test('teal is the only interactive colour', () {
      expectColor(s.primary, 0xFF0E6A70, 'primary');
      expectColor(s.onPrimary, 0xFFFFFFFF, 'onPrimary');
      expectColor(s.primaryContainer, 0xFFDCEBEB, 'primaryContainer');
      expectColor(s.onPrimaryContainer, 0xFF0E6A70, 'onPrimaryContainer');
    });

    test('orange is the unread indicator and nothing else', () {
      expectColor(s.secondary, 0xFFBE6530, 'secondary (unread)');
    });

    test('roles Material has no slot for', () {
      final f = light.extension<FlashColors>()!;
      expectColor(f.onSurfaceMuted, 0xFF8A9391, 'onSurfaceMuted');
      expectColor(f.onSurfaceRead, 0xFF79817F, 'onSurfaceRead');
      expectColor(f.placeholder, 0xFFF0F2F2, 'placeholder');
    });
  });

  group('dark tokens', () {
    final s = dark.colorScheme;

    test('surfaces', () {
      expectColor(s.surface, 0xFF0D1211, 'surface');
      expectColor(s.surfaceContainer, 0xFF161D1C, 'surfaceContainer');
    });

    test('ink', () {
      expectColor(s.onSurface, 0xFFE7EBEA, 'onSurface');
      expectColor(s.onSurfaceVariant, 0xFF8C9695, 'onSurfaceVariant');
    });

    test('hairline is white at 9%, not a flat grey', () {
      // Authored as an alpha rather than a hex, because it has to sit over
      // both surface and surfaceContainer without banding.
      expect(s.outlineVariant.a, closeTo(0.09, 0.005),
          reason: 'dark outlineVariant should be 9% opaque');
      expect(s.outlineVariant.r, 1.0);
      expect(s.outlineVariant.g, 1.0);
      expect(s.outlineVariant.b, 1.0);
    });

    test('teal is the only interactive colour', () {
      expectColor(s.primary, 0xFF7BD0D3, 'primary');
      expectColor(s.onPrimary, 0xFF07201F, 'onPrimary');
      expectColor(s.primaryContainer, 0xFF12292A, 'primaryContainer');
      expectColor(s.onPrimaryContainer, 0xFF7BD0D3, 'onPrimaryContainer');
    });

    test('orange is the unread indicator and nothing else', () {
      expectColor(s.secondary, 0xFFE79E62, 'secondary (unread)');
    });

    test('roles Material has no slot for', () {
      final f = dark.extension<FlashColors>()!;
      expectColor(f.onSurfaceMuted, 0xFF767F7E, 'onSurfaceMuted');
      expectColor(f.onSurfaceRead, 0xFF87908F, 'onSurfaceRead');
      expectColor(f.placeholder, 0xFF262C2B, 'placeholder');
    });
  });

  group('the navigation bar is visible', () {
    // The bar used to take scheme.surface, which is the same colour as the
    // scaffold behind it — so on both themes it simply vanished. This is the
    // regression, and it is worth its own test because "the bar is missing"
    // reads as a layout bug and sends you looking in the wrong file.
    for (final (name, theme) in [('light', light), ('dark', dark)]) {
      test('$name: bottom nav does not disappear into the scaffold', () {
        final bar = theme.bottomNavigationBarTheme.backgroundColor;
        expect(bar, isNotNull);
        expect(bar, isNot(theme.colorScheme.surface));
        expect(bar, theme.colorScheme.surfaceContainer);
      });

      test('$name: the rail does not either', () {
        final rail = theme.navigationRailTheme.backgroundColor;
        expect(rail, isNotNull);
        expect(rail, isNot(theme.colorScheme.surface));
        expect(rail, theme.colorScheme.surfaceContainer);
      });
    }
  });

  group('orange lost the navigation', () {
    // A deliberate reversal. The old theme put the accent on the bottom nav's
    // selected item on the reasoning that it is the most-touched surface in
    // the app. Quiet Ink reserves orange for the unread dot and nothing else,
    // so selection becomes teal. Pinned in both directions: it must BE primary
    // and must NOT be secondary, so that a future "restore the accent" edit
    // fails here rather than silently reintroducing orange chrome.
    for (final (name, theme) in [('light', light), ('dark', dark)]) {
      test('$name: the selected bottom-nav item is teal', () {
        expect(theme.bottomNavigationBarTheme.selectedItemColor,
            theme.colorScheme.primary);
        expect(theme.bottomNavigationBarTheme.selectedItemColor,
            isNot(theme.colorScheme.secondary));
      });

      test('$name: so is the selected rail destination', () {
        expect(theme.navigationRailTheme.selectedIconTheme?.color,
            theme.colorScheme.primary);
        expect(theme.navigationRailTheme.selectedLabelTextStyle?.color,
            theme.colorScheme.primary);
      });

      test('$name: unselected nav is the named muted role, not alpha ink', () {
        // 60% ink over a tinted surfaceContainer is not #5A6361, which is why
        // the alpha version could never match the spec.
        expect(theme.bottomNavigationBarTheme.unselectedItemColor,
            theme.colorScheme.onSurfaceVariant);
        expect(theme.navigationRailTheme.unselectedIconTheme?.color,
            theme.colorScheme.onSurfaceVariant);
        expect(theme.navigationRailTheme.unselectedLabelTextStyle?.color,
            theme.colorScheme.onSurfaceVariant);
      });
    }
  });

  group('FlashColors is a real ThemeExtension', () {
    test('it is registered on both brightnesses', () {
      expect(light.extension<FlashColors>(), isNotNull);
      expect(dark.extension<FlashColors>(), isNotNull);
    });

    test('lerp returns its endpoints exactly', () {
      // The half of ThemeExtension people skip. Without it a theme animation
      // snaps instead of crossfading, and the endpoints are where that shows.
      final a = light.extension<FlashColors>()!;
      final b = dark.extension<FlashColors>()!;
      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
    });

    test('lerp moves between them in the middle', () {
      final a = light.extension<FlashColors>()!;
      final b = dark.extension<FlashColors>()!;
      final mid = a.lerp(b, 0.5);
      expect(mid, isNot(a));
      expect(mid, isNot(b));
    });

    test('copyWith replaces only what it is given', () {
      final a = light.extension<FlashColors>()!;
      final changed = a.copyWith(placeholder: const Color(0xFF123456));
      expect(changed.placeholder, const Color(0xFF123456));
      expect(changed.onSurfaceMuted, a.onSurfaceMuted);
      expect(changed.onSurfaceRead, a.onSurfaceRead);
    });
  });

  group('the type system', () {
    // The old theme declared no textTheme at all — every family and size came
    // from Flutter's defaults, and only Newspaper mode had a type system. So
    // this is the first one the ordinary themes have had, and the split is the
    // whole of it: a serif for what you read, one grotesque for what you
    // operate.
    final text = light.textTheme;

    test('Literata sets everything that is read', () {
      for (final (name, style) in [
        ('displayLarge', text.displayLarge),
        ('displayMedium', text.displayMedium),
        ('displaySmall', text.displaySmall),
        ('headlineLarge', text.headlineLarge),
        ('headlineMedium', text.headlineMedium),
        ('headlineSmall', text.headlineSmall),
        ('titleLarge', text.titleLarge),
      ]) {
        expect(style?.fontFamily, kSerifFamily, reason: '\$name');
      }
    });

    test('Instrument Sans sets everything you operate', () {
      for (final (name, style) in [
        ('titleMedium', text.titleMedium),
        ('titleSmall', text.titleSmall),
        ('bodyLarge', text.bodyLarge),
        ('bodyMedium', text.bodyMedium),
        ('bodySmall', text.bodySmall),
        ('labelLarge', text.labelLarge),
        ('labelMedium', text.labelMedium),
        ('labelSmall', text.labelSmall),
      ]) {
        expect(style?.fontFamily, kSansFamily, reason: '\$name');
      }
    });

    test('numerals are monospaced with tabular figures', () {
      // Declared, and not yet applied to a widget — the unread count belongs
      // to the chip pass and the timestamp to the feed pass. Pinned now so
      // the tabular figure feature cannot be dropped on the way there: it is
      // what stops a count changing width, and shuffling its row, on refresh.
      for (final style in [kNumeralChipStyle, kNumeralTimestampStyle]) {
        expect(style.fontFamily, kMonoFamily);
        expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      expect(kNumeralChipStyle.fontSize, 11);
      expect(kNumeralTimestampStyle.fontSize, 12.5);
    });

    test('the dark theme uses the same families', () {
      expect(dark.textTheme.titleLarge?.fontFamily, kSerifFamily);
      expect(dark.textTheme.bodyMedium?.fontFamily, kSansFamily);
    });

    test('Newspaper keeps its own pair, untouched', () {
      final paper = flashNewspaperTheme().textTheme;
      expect(paper.headlineLarge?.fontFamily, 'Playfair Display');
      expect(paper.bodyMedium?.fontFamily, 'PT Serif');
    });
  });
  group('Newspaper mode is untouched', () {
    // Newspaper is now the only place red appears in the app and the only
    // theme with elevation, and both of those are deliberate. This pass must
    // not "harmonise" it, so its three most distinctive values are pinned.
    final paper = flashNewspaperTheme();

    test('its spot red survives', () {
      expectColor(paper.colorScheme.primary, 0xFFA0231A, 'newspaper primary');
    });

    test('it keeps the only elevated nav in the app', () {
      expect(paper.bottomNavigationBarTheme.elevation, 8);
    });

    test('it keeps its 2px cards', () {
      final shape = paper.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(2));
    });
  });
}
