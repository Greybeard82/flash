import 'package:flutter/material.dart';

// Dark mode accent
const Color darkAccent = Color(0xFFFFD60A);
const Color darkAccentPressed = Color(0xFFFFF176);

// Light mode accent
const Color lightAccent = Color(0xFFB8960A);
const Color lightAccentPressed = Color(0xFFCC5500);

// Dark mode backgrounds
// NB: darkBg is mirrored in android/.../MainActivity.kt (DARK_BG) to paint the
// native window before the first Flutter frame. Keep the two in sync.
const Color darkBg = Color(0xFF0D1B2A);
const Color darkSurface = Color(0xFF162338);

// Light mode backgrounds
const Color lightBg = Color(0xFFFFFFFF);
const Color lightSurface = Color(0xFFF4F4F8);

ThemeData flashLightTheme() {
  const base = ColorScheme.light(
    primary: lightAccent,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF5E9C0),
    onPrimaryContainer: Color(0xFF3A2800),
    secondary: lightAccentPressed,
    onSecondary: Colors.white,
    surface: lightBg,
    onSurface: Color(0xFF1A1A1A),
    surfaceContainerHighest: lightSurface,
    outline: Color(0xFFD0D0D0),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: lightBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBg,
      foregroundColor: Color(0xFF1A1A1A),
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: lightAccent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightSurface,
      selectedItemColor: lightAccent,
      unselectedItemColor: Color(0xFF888888),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: lightBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFEEEEEE),
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: lightAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
