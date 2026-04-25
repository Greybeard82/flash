import 'package:flutter/material.dart';

// Dark mode accent
const Color darkAccent = Color(0xFFFFD60A);
const Color darkAccentPressed = Color(0xFFFFF176);

// Light mode accent
const Color lightAccent = Color(0xFFB8960A);
const Color lightAccentPressed = Color(0xFFCC5500);

// Dark mode backgrounds
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
