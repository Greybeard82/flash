import 'package:flutter/material.dart';

/// Seed colors for the five selectable palettes, keyed by the value stored
/// under `color_palette` in settings. Each is fed to [ColorScheme.fromSeed],
/// which derives a full tonal palette — including every "on-X" pairing — for
/// both brightnesses from this one color, rather than ten hand-tuned
/// [ThemeData]s that could each drift into a contrast bug nobody notices
/// until a tester hits it.
///
/// 'orange' is closest to the gold this app already shipped with, and is the
/// default (`AppSettings.colorPalette`) so nobody already using the app sees
/// a surprise change in color identity.
const Map<String, Color> kPaletteSeeds = {
  'green': Color(0xFF2E7D32),
  'blue': Color(0xFF1565C0),
  'orange': Color(0xFFE07A1F),
  'red': Color(0xFFC62828),
  // Two-hue palette: teal is the seed fromSeed actually derives everything
  // from; orange is applied as a secondary override below. This project's
  // Flutter version's `ColorScheme.fromSeed` has no `secondaryKey` parameter
  // to generate the second hue algorithmically, so it's grafted on afterward
  // rather than hand-rolling the rest of the scheme to compensate.
  'teal_orange': Color(0xFF00695C),
};

/// Second-hue seeds, one per palette above, applied the same way
/// `teal_orange`'s orange half always has been — see
/// [_applyAccentOverride]. `teal_orange` is included here too (unchanged
/// from its own seed) so every palette goes through the same lookup in
/// [paletteColorScheme] rather than one of the five being a special case.
///
/// Picked as a deliberate contrast to each primary rather than a nearby
/// tint: gold against green, terracotta against blue, indigo against red,
/// forest green against orange — the same "two hues, not one hue's shades"
/// character `teal_orange` already had.
const Map<String, Color> kPaletteAccentSeeds = {
  'green': Color(0xFFF9A825),
  'blue': Color(0xFFD84315),
  'red': Color(0xFF283593),
  'orange': Color(0xFF1B5E20),
  'teal_orange': Color(0xFFE07A1F),
};

const String kDefaultPalette = 'orange';

/// [ColorScheme.fromSeed]'s own default is [DynamicSchemeVariant.tonalSpot]
/// — deliberately pastel, low-saturation, and applied uniformly regardless
/// of seed. That default is why every one of the five palettes above reads
/// as muted: it is one systemic knob, not five seeds that each happen to be
/// weak. `vibrant` is the same algorithm at a higher, still-bounded chroma —
/// a step up applied identically everywhere, rather than five hand-tuned
/// seed hexes that would each need re-tuning (and could each drift out of
/// step with the others) the next time a palette changes. Used everywhere
/// [ColorScheme.fromSeed] is called in this file — every primary hue and
/// every accent hue below — so no half of any palette moves by a different
/// amount than the rest.
const DynamicSchemeVariant kPaletteSchemeVariant = DynamicSchemeVariant.vibrant;

/// Applies a two-hue override: every `secondary*` role comes from a full
/// scheme generated off [accentSeed], at the same brightness, rather than a
/// hand-picked pair — so the override gets the same guaranteed on-color
/// contrast [ColorScheme.fromSeed] already gives the primary hue.
///
/// All four roles, not just `secondary`/`onSecondary`. `ColorScheme.fromSeed`
/// derives its own `secondaryContainer`/`onSecondaryContainer` from the
/// *primary* seed — a second tonal palette it generates algorithmically
/// alongside the first, not from anything this override supplies — so
/// leaving those two alone would mean a chip painted with
/// `secondaryContainer` came out tinted like the primary hue's own shade
/// while a button painted with bare `secondary` came out in the accent hue,
/// on the same screen. [accent] is itself a full scheme built from
/// [accentSeed], so its own `primaryContainer`/`onPrimaryContainer` are
/// already the correctly-toned container pair for that hue — reused here
/// rather than re-deriving container tones by hand.
///
/// Was `_applyTealOrangeAccent`, hardcoded to the one palette that had an
/// accent at all; every palette does now, so this takes the seed as a
/// parameter instead of reaching into [kPaletteSeeds] itself.
ColorScheme _applyAccentOverride(
  ColorScheme scheme,
  Brightness brightness,
  Color accentSeed,
) {
  final accent = ColorScheme.fromSeed(
    seedColor: accentSeed,
    brightness: brightness,
    dynamicSchemeVariant: kPaletteSchemeVariant,
  );
  return scheme.copyWith(
    secondary: accent.primary,
    onSecondary: accent.onPrimary,
    secondaryContainer: accent.primaryContainer,
    onSecondaryContainer: accent.onPrimaryContainer,
  );
}

/// Android page transitions, at a snappier tempo than stock.
///
/// [MaterialPageRoute.transitionDuration] delegates to whichever
/// [PageTransitionsBuilder] the theme supplies for the current platform
/// (`page.dart`'s `_getPageTransitionBuilder`), so overriding the getter here
/// really does shorten navigation rather than just the visual curve.
///
/// Deliberately subclasses [PredictiveBackPageTransitionsBuilder] rather than
/// [FadeForwardsPageTransitionsBuilder]: predictive back is already Flutter's
/// Android default, and it *already* falls back to FadeForwards for anything
/// that isn't a back gesture. Swapping to plain FadeForwards would look
/// identical for ordinary navigation while quietly dropping predictive-back
/// support on Android 14+.
class _SnappyAndroidPageTransitions
    extends PredictiveBackPageTransitionsBuilder {
  const _SnappyAndroidPageTransitions();

  // Stock is 450ms, which reads as sluggish on a device this fast.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  // Defaults to transitionDuration on the base class, but stated explicitly
  // so a future edit can't leave back navigation at a different tempo.
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);
}

const PageTransitionsTheme kFlashPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: _SnappyAndroidPageTransitions(),
    // Left at Flutter's defaults; Flash ships on Android.
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
  },
);

// Pre-first-frame native fallback only (android/.../MainActivity.kt DARK_BG,
// styles.xml, colors.xml) — the window background painted before Flutter has
// even read the persisted palette. Keep this in sync with those, but nothing
// in this file uses it any more: every palette's actual scaffold background
// is its generated `colorScheme.surface`, applied once the first frame lands.
const Color darkBg = Color(0xFF0D1B2A);

/// The generated [ColorScheme] for [palette] at [brightness], including its
/// two-hue accent override. Exposed separately from [flashPaletteTheme] so a
/// caller that only needs the colors — like the Quick Settings palette
/// picker's own preview swatches — isn't stuck building a whole [ThemeData]
/// just to read them off it.
ColorScheme paletteColorScheme({
  required String palette,
  required Brightness brightness,
}) {
  final seed = kPaletteSeeds[palette] ?? kPaletteSeeds[kDefaultPalette]!;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: kPaletteSchemeVariant,
  );
  // Every current palette has an accent seed, but this stays a lookup with
  // a fallback rather than an assumption that always holds — an
  // unrecognised palette key already falls back to kDefaultPalette above
  // for its primary seed, and this keeps that same "never throw on an
  // unfamiliar key" stance for the accent half too.
  final accentSeed = kPaletteAccentSeeds[palette];
  return accentSeed == null
      ? scheme
      : _applyAccentOverride(scheme, brightness, accentSeed);
}

/// Builds a palette's [ThemeData] for one brightness. Replaces the old
/// separate `flashLightTheme()` / `flashDarkTheme()`: rather than ten
/// hand-tuned color blocks (five palettes × two brightnesses), the
/// [ColorScheme] comes entirely from [ColorScheme.fromSeed] — the same
/// tonal-palette algorithm behind Android's own wallpaper-based Material You
/// theming — and every structural block below (app bar, bottom nav, card
/// radius, filled button, switch, snackbar, progress indicator) references
/// its roles rather than a fixed hex, so the app's *shape* is identical
/// across all ten combinations and only the colors change.
///
/// [palette] is a key into [kPaletteSeeds]; an unrecognised value falls back
/// to [kDefaultPalette] rather than throwing, since it may be read back from
/// a settings row written by a future version this one doesn't know about.
ThemeData flashPaletteTheme({
  required String palette,
  required Brightness brightness,
}) {
  final scheme = paletteColorScheme(palette: palette, brightness: brightness);

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: kFlashPageTransitions,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scheme.surface,
      // The accent, not the primary hue: this is the single most-touched
      // surface in the app — every tab switch — and the most natural place
      // for the palette's second colour to actually show up in daily use,
      // rather than being confined to a settings swatch and a swipe gesture
      // nobody lingers on.
      selectedItemColor: scheme.secondary,
      unselectedItemColor: scheme.onSurface.withValues(alpha: 0.6),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    // Phones get BottomNavigationBarTheme above; the rail is what tablets
    // and TV use instead (see form_factor.dart), and Flutter's own default
    // rail styling leans on `primary` the same way the bottom nav's old
    // default did — mirrored here so the two nav surfaces this app actually
    // ships agree on the accent rather than only one of them getting fixed.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      selectedIconTheme: IconThemeData(color: scheme.secondary),
      selectedLabelTextStyle: TextStyle(color: scheme.secondary),
      unselectedIconTheme:
          IconThemeData(color: scheme.onSurface.withValues(alpha: 0.6)),
      unselectedLabelTextStyle:
          TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: 0.4);
        }
        return null;
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
    ),
  );
}

// ── Newspaper palette ──────────────────────────────────────────────────────
const Color _npPaper    = Color(0xFFF2F1EE); // newsprint background
const Color _npInk      = Color(0xFF1D1D1B); // ink text
const Color _npRed      = Color(0xFFA0231A); // spot-colour accent
const Color _npSurface2 = Color(0xFFE7E7E3); // nav / secondary surface
const Color _npHairline = Color(0xFFC7C7C1); // rule / outline

ThemeData flashNewspaperTheme() {
  const base = ColorScheme.light(
    primary: _npRed,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFADDD9),
    onPrimaryContainer: Color(0xFF410E09),
    secondary: _npRed,
    onSecondary: Colors.white,
    surface: _npPaper,
    onSurface: _npInk,
    surfaceContainerHighest: _npSurface2,
    outline: _npHairline,
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
  );

  // PT Serif for body/label/title; Playfair Display for display/headline.
  const ptSerif = 'PT Serif';
  const playfair = 'Playfair Display';

  final baseText = const TextTheme().copyWith(
    displayLarge:   const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
    displayMedium:  const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
    displaySmall:   const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
    headlineLarge:  const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
    headlineMedium: const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
    headlineSmall:  const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
    titleLarge:   const TextStyle(fontFamily: ptSerif, fontWeight: FontWeight.w700),
    titleMedium:  const TextStyle(fontFamily: ptSerif, fontWeight: FontWeight.w700),
    titleSmall:   const TextStyle(fontFamily: ptSerif),
    bodyLarge:    const TextStyle(fontFamily: ptSerif),
    bodyMedium:   const TextStyle(fontFamily: ptSerif),
    bodySmall:    const TextStyle(fontFamily: ptSerif),
    labelLarge:   const TextStyle(fontFamily: ptSerif),
    labelMedium:  const TextStyle(fontFamily: ptSerif),
    labelSmall:   const TextStyle(fontFamily: ptSerif),
  ).apply(
    bodyColor: _npInk,
    displayColor: _npInk,
  );

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: kFlashPageTransitions,
    colorScheme: base,
    scaffoldBackgroundColor: _npPaper,
    textTheme: baseText,
    appBarTheme: AppBarTheme(
      backgroundColor: _npPaper,
      foregroundColor: _npInk,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: _npRed,
      titleTextStyle: baseText.titleLarge?.copyWith(color: _npInk),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _npSurface2,
      selectedItemColor: _npRed,
      unselectedItemColor: Color(0xFF888880),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: _npPaper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: _npHairline,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _npRed,
        foregroundColor: Colors.white,
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(fontFamily: ptSerif),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _npRed;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _npRed.withValues(alpha: 0.4);
        }
        return null;
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _npInk,
      contentTextStyle: const TextStyle(
        color: _npPaper,
        fontFamily: ptSerif,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _npRed,
    ),
  );
}

