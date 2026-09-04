import 'package:flutter/material.dart';

// Dark mode accent
const Color darkAccent = Color(0xFFFFD60A);
const Color darkAccentPressed = Color(0xFFFFF176);

// ── Light palette ──────────────────────────────────────────────────────────
// Sampled from the reference mockup. Hardcoded for now: a user-facing theme
// colour editor is planned next, and these stay centralised here — one file,
// named constants, referenced through the ColorScheme — so swapping them for
// per-user values later is a change to this block, not a hunt through widgets.
const Color lightAccent = Color(0xFFD9A860);        // warm gold
const Color lightAccentPressed = Color(0xFFC0904A); // deeper gold, pressed
const Color lightInk = Color(0xFF2E2B27);           // soft near-black text
const Color lightMuted = Color(0xFF8B8A85);         // secondary text, idle icons
const Color lightBorder = Color(0xFFDDD3C0);        // chip / card hairlines

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

// Dark mode backgrounds
// NB: darkBg is mirrored in android/.../MainActivity.kt (DARK_BG) to paint the
// native window before the first Flutter frame. Keep the two in sync.
const Color darkBg = Color(0xFF0D1B2A);
const Color darkSurface = Color(0xFF162338);

// Light mode backgrounds
const Color lightBg = Color(0xFFF5F1E8);      // warm cream: scaffold, app bar
const Color lightSurface = Color(0xFFFBFAF6); // fractionally whiter: cards

ThemeData flashLightTheme() {
  const base = ColorScheme.light(
    primary: lightAccent,
    // Dark label on the gold, as in the mockup's selected chip.
    onPrimary: lightInk,
    primaryContainer: Color(0xFFF1E3C6),
    onPrimaryContainer: lightInk,
    secondary: lightAccentPressed,
    onSecondary: lightInk,
    surface: lightBg,
    onSurface: lightInk,
    surfaceContainerHighest: lightSurface,
    outline: lightBorder,
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: kFlashPageTransitions,
    colorScheme: base,
    scaffoldBackgroundColor: lightBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBg,
      foregroundColor: lightInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightBg,
      selectedItemColor: lightAccent,
      unselectedItemColor: lightMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: lightBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: lightBorder,
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: lightAccent,
        foregroundColor: lightInk,
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return lightAccent;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return lightAccent.withValues(alpha: 0.4);
        }
        return null;
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2D2D2D),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: darkAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: lightAccent,
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

ThemeData flashDarkTheme() {
  const base = ColorScheme.dark(
    primary: darkAccent,
    onPrimary: Color(0xFF1A1500),
    primaryContainer: Color(0xFF2A2200),
    onPrimaryContainer: darkAccentPressed,
    secondary: darkAccentPressed,
    onSecondary: Color(0xFF1A1500),
    surface: darkBg,
    onSurface: Color(0xFFE8E8E8),
    surfaceContainerHighest: darkSurface,
    outline: Color(0xFF3A4A5A),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
  );

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: kFlashPageTransitions,
    colorScheme: base,
    scaffoldBackgroundColor: darkBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBg,
      foregroundColor: Color(0xFFE8E8E8),
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: darkAccent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      selectedItemColor: darkAccent,
      unselectedItemColor: Color(0xFF7A8A9A),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF253040),
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: darkAccent,
        foregroundColor: const Color(0xFF1A1500),
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return darkAccent;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return darkAccent.withValues(alpha: 0.4);
        }
        return null;
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A3A4A),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: darkAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: darkAccent,
    ),
  );
}
