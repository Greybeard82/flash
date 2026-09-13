import 'package:flutter/material.dart';

import 'category_colors.dart';

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
/// How long the app takes to move one surface out of the way of another.
///
/// Stock Material is 450ms, which reads as sluggish on a device this fast.
/// Named rather than repeated because page navigation is no longer the only
/// thing moving at this tempo -- swapping the tablet layout's sides slides
/// the columns for exactly as long, and two literals would drift apart.
const Duration kPageTransitionDuration = Duration(milliseconds: 220);

class _SnappyAndroidPageTransitions
    extends PredictiveBackPageTransitionsBuilder {
  const _SnappyAndroidPageTransitions();

  @override
  Duration get transitionDuration => kPageTransitionDuration;

  // Defaults to transitionDuration on the base class, but stated explicitly
  // so a future edit can't leave back navigation at a different tempo.
  @override
  Duration get reverseTransitionDuration => kPageTransitionDuration;
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

// Pre-first-frame native fallback only. Mirrored in
// android/.../MainActivity.kt (DEFAULT_BG), values/styles.xml and
// values/colors.xml — the window background painted before Flutter has even
// read a setting. Keep this in sync with those three.
//
// Nothing in Dart reads it: the live scaffold background is
// `colorScheme.surface`, applied once the first frame lands. It exists so the
// launch cross-fade composites over the right colour instead of flashing.
//
// Was #0D1B2A, a navy left over from an earlier direction. Quiet Ink's dark
// surface is #0D1211, and a navy flash before a near-black app is exactly the
// kind of seam this constant exists to prevent.
const Color darkBg = Color(0xFF0D1211);

// ── Quiet Ink ──────────────────────────────────────────────────────────────
//
// Authored colours, not generated ones.
//
// Until this pass the theme built its whole ColorScheme from one seed hex
// through ColorScheme.fromSeed, once per selectable palette. That is gone, and
// why is worth keeping: **no seed produces the table below.** The teal, the
// teal tint, the hairline and the unread orange are four independent
// decisions, and fromSeed derives all four from one — so every attempt to
// correct one of them moved the other three. What replaces it is more lines
// and no cleverness, which is the point.
//
// Two rules the rest of the app leans on:
//
//   * **Teal is the only interactive colour.** Anything you can press is
//     `primary` or `primaryContainer`.
//   * **Orange means unread, and nothing else.** It lives in `secondary` and
//     should appear exactly once on screen: the unread dot.

// Light
const Color _qiSurfaceLight = Color(0xFFFFFFFF);
const Color _qiSurfaceContainerLight = Color(0xFFF1F5F5);
const Color _qiOnSurfaceLight = Color(0xFF0F1413);
const Color _qiOnSurfaceVariantLight = Color(0xFF5A6361);
const Color _qiOnSurfaceMutedLight = Color(0xFF8A9391);
const Color _qiOnSurfaceReadLight = Color(0xFF79817F);
const Color _qiOutlineVariantLight = Color(0xFFE9ECEB);
const Color _qiPrimaryLight = Color(0xFF0E6A70);
const Color _qiOnPrimaryLight = Color(0xFFFFFFFF);
const Color _qiPrimaryContainerLight = Color(0xFFDCEBEB);
const Color _qiOnPrimaryContainerLight = Color(0xFF0E6A70);
const Color _qiUnreadLight = Color(0xFFBE6530);
const Color _qiPlaceholderLight = Color(0xFFF0F2F2);

// Dark
const Color _qiSurfaceDark = Color(0xFF0D1211);
const Color _qiSurfaceContainerDark = Color(0xFF161D1C);
const Color _qiOnSurfaceDark = Color(0xFFE7EBEA);
const Color _qiOnSurfaceVariantDark = Color(0xFF8C9695);
const Color _qiOnSurfaceMutedDark = Color(0xFF767F7E);
const Color _qiOnSurfaceReadDark = Color(0xFF87908F);
const Color _qiPrimaryDark = Color(0xFF7BD0D3);
const Color _qiOnPrimaryDark = Color(0xFF07201F);
const Color _qiPrimaryContainerDark = Color(0xFF12292A);
const Color _qiOnPrimaryContainerDark = Color(0xFF7BD0D3);
const Color _qiUnreadDark = Color(0xFFE79E62);
const Color _qiPlaceholderDark = Color(0xFF262C2B);

/// The dark hairline is an alpha, not a hex, so it sits correctly over both
/// `surface` and the slightly lighter `surfaceContainer` without banding.
final Color _qiOutlineVariantDark = Colors.white.withValues(alpha: 0.09);

// The error ramp is NOT part of the Quiet Ink spec — it names no error
// colour. These are the Material 3 baseline error tones, kept because the
// alternative is worse: `ColorScheme.light()`'s own default error is the
// Material 2 #B00020, which would drop a purple-era red into an app that has
// just removed every generated colour. The light value is the one
// flashNewspaperTheme already uses, so the two themes agree.
const Color _qiErrorLight = Color(0xFFBA1A1A);
const Color _qiOnErrorLight = Color(0xFFFFFFFF);
const Color _qiErrorContainerLight = Color(0xFFFFDAD6);
const Color _qiOnErrorContainerLight = Color(0xFF410002);
const Color _qiErrorDark = Color(0xFFFFB4AB);
const Color _qiOnErrorDark = Color(0xFF690005);
const Color _qiErrorContainerDark = Color(0xFF93000A);
const Color _qiOnErrorContainerDark = Color(0xFFFFDAD6);

/// Type families. Declared in pubspec.yaml under `fonts:`.
///
/// Literata is vendored as a Latin subset: Google ships it carrying Cyrillic,
/// Greek and Vietnamese, which no Flash locale uses and which alone put it
/// past the per-family size ceiling. The subset keeps both variable axes and
/// every accented glyph the five locales need. See pubspec.yaml for the
/// command that regenerates it.
const String kSerifFamily = 'Literata';
const String kSansFamily = 'Instrument Sans';
const String kMonoFamily = 'JetBrains Mono';

/// Numerals, in the two places Quiet Ink uses them.
///
/// Tabular figures so a count does not twitch as it changes width on refresh —
/// "9" and "11" occupy the same advance, so the row does not shuffle.
///
/// Declared here and **not yet applied**: the unread count belongs to the chip
/// pass and the timestamp to the feed pass, and both are widget-tree changes
/// this pass is explicitly not making.
const TextStyle kNumeralChipStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 11,
  fontFeatures: [FontFeature.tabularFigures()],
);

const TextStyle kNumeralTimestampStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: 12.5,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// The colour roles Material has no slot for.
///
/// Deliberately an extension rather than four more `ColorScheme` members bent
/// out of shape. `tertiary` is not "the colour of a timestamp", and a reader
/// who finds it used that way has to discover the lie before they can fix
/// anything near it.
@immutable
class FlashColors extends ThemeExtension<FlashColors> {
  /// Timestamps and day headers. Quieter than `onSurfaceVariant`.
  final Color onSurfaceMuted;

  /// A read article's title. Read state is carried by colour, never by
  /// anything that can change layout.
  final Color onSurfaceRead;

  /// Fill behind a thumbnail that is missing or still loading.
  final Color placeholder;

  /// Which brightness this instance belongs to, so [category] can answer
  /// without every caller threading a `Brightness` through.
  final Brightness brightness;

  const FlashColors({
    required this.onSurfaceMuted,
    required this.onSurfaceRead,
    required this.placeholder,
    required this.brightness,
  });

  /// The stored hue for a category, resolved for this theme.
  CategoryPalette category(int colorIndex) =>
      categoryPalette(colorIndex, brightness);

  @override
  FlashColors copyWith({
    Color? onSurfaceMuted,
    Color? onSurfaceRead,
    Color? placeholder,
    Brightness? brightness,
  }) {
    return FlashColors(
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      onSurfaceRead: onSurfaceRead ?? this.onSurfaceRead,
      placeholder: placeholder ?? this.placeholder,
      brightness: brightness ?? this.brightness,
    );
  }

  /// Crossfades between two instances during a theme change.
  ///
  /// Endpoints are returned exactly rather than lerped-to, so `lerp(other, 0)`
  /// is this instance and `lerp(other, 1)` is the other one. Brightness is an
  /// enum and cannot be interpolated, so it snaps at the halfway point — which
  /// only decides which category hues are read mid-animation.
  @override
  FlashColors lerp(ThemeExtension<FlashColors>? other, double t) {
    if (other is! FlashColors) return this;
    if (t == 0) return this;
    if (t == 1) return other;
    return FlashColors(
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      onSurfaceRead: Color.lerp(onSurfaceRead, other.onSurfaceRead, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlashColors &&
          other.onSurfaceMuted == onSurfaceMuted &&
          other.onSurfaceRead == onSurfaceRead &&
          other.placeholder == placeholder &&
          other.brightness == brightness;

  @override
  int get hashCode =>
      Object.hash(onSurfaceMuted, onSurfaceRead, placeholder, brightness);
}

const FlashColors _flashColorsLight = FlashColors(
  onSurfaceMuted: _qiOnSurfaceMutedLight,
  onSurfaceRead: _qiOnSurfaceReadLight,
  placeholder: _qiPlaceholderLight,
  brightness: Brightness.light,
);

const FlashColors _flashColorsDark = FlashColors(
  onSurfaceMuted: _qiOnSurfaceMutedDark,
  onSurfaceRead: _qiOnSurfaceReadDark,
  placeholder: _qiPlaceholderDark,
  brightness: Brightness.dark,
);

/// Roles the spec does not name are set from roles it does, never invented:
///
/// * `onSecondary` is `surface`. Orange is the unread dot, which carries no
///   label, so this is very nearly unused — but it must not be left at the
///   Material 2 default.
/// * `secondaryContainer` / `onSecondaryContainer` are the **teal** tint, not
///   an orange one. Their only consumer is the alert-keyword badge on a card,
///   and a badge is a chip: orange is reserved for unread and a second orange
///   thing on the same row would break the one rule this palette has.
/// * `surfaceContainerHighest` is the placeholder tone. Its consumers are the
///   missing-thumbnail fill, the radial menu and the refresh field — all
///   neutral blocks — so this keeps them correct without touching a widget.
/// * `outline` is `onSurfaceVariant`; it is only ever read at 30–40% alpha,
///   as a soft border. `outlineVariant` stays the true hairline.
/// * `inverseSurface` / `onInverseSurface` are `onSurface` / `surface`, which
///   is what "inverse" means. They paint the notification banner.
ColorScheme _quietInkScheme(Brightness brightness) {
  return brightness == Brightness.light
      ? const ColorScheme.light(
          primary: _qiPrimaryLight,
          onPrimary: _qiOnPrimaryLight,
          primaryContainer: _qiPrimaryContainerLight,
          onPrimaryContainer: _qiOnPrimaryContainerLight,
          secondary: _qiUnreadLight,
          onSecondary: _qiSurfaceLight,
          secondaryContainer: _qiPrimaryContainerLight,
          onSecondaryContainer: _qiOnPrimaryContainerLight,
          tertiary: _qiPrimaryLight,
          onTertiary: _qiOnPrimaryLight,
          tertiaryContainer: _qiPrimaryContainerLight,
          onTertiaryContainer: _qiOnPrimaryContainerLight,
          surface: _qiSurfaceLight,
          onSurface: _qiOnSurfaceLight,
          surfaceContainer: _qiSurfaceContainerLight,
          surfaceContainerHighest: _qiPlaceholderLight,
          onSurfaceVariant: _qiOnSurfaceVariantLight,
          outline: _qiOnSurfaceVariantLight,
          outlineVariant: _qiOutlineVariantLight,
          inverseSurface: _qiOnSurfaceLight,
          onInverseSurface: _qiSurfaceLight,
          inversePrimary: _qiPrimaryContainerLight,
          error: _qiErrorLight,
          onError: _qiOnErrorLight,
          errorContainer: _qiErrorContainerLight,
          onErrorContainer: _qiOnErrorContainerLight,
        )
      : ColorScheme.dark(
          primary: _qiPrimaryDark,
          onPrimary: _qiOnPrimaryDark,
          primaryContainer: _qiPrimaryContainerDark,
          onPrimaryContainer: _qiOnPrimaryContainerDark,
          secondary: _qiUnreadDark,
          onSecondary: _qiSurfaceDark,
          secondaryContainer: _qiPrimaryContainerDark,
          onSecondaryContainer: _qiOnPrimaryContainerDark,
          tertiary: _qiPrimaryDark,
          onTertiary: _qiOnPrimaryDark,
          tertiaryContainer: _qiPrimaryContainerDark,
          onTertiaryContainer: _qiOnPrimaryContainerDark,
          surface: _qiSurfaceDark,
          onSurface: _qiOnSurfaceDark,
          surfaceContainer: _qiSurfaceContainerDark,
          surfaceContainerHighest: _qiPlaceholderDark,
          onSurfaceVariant: _qiOnSurfaceVariantDark,
          outline: _qiOnSurfaceVariantDark,
          outlineVariant: _qiOutlineVariantDark,
          inverseSurface: _qiOnSurfaceDark,
          onInverseSurface: _qiSurfaceDark,
          inversePrimary: _qiPrimaryContainerDark,
          error: _qiErrorDark,
          onError: _qiOnErrorDark,
          errorContainer: _qiErrorContainerDark,
          onErrorContainer: _qiOnErrorContainerDark,
        );
}

/// Editorial serif for headlines, one grotesque for everything you operate.
///
/// The old theme declared no `textTheme` at all, so every size and family came
/// from Flutter's defaults; only Newspaper mode had a type system. This is the
/// first one the ordinary themes have had.
///
/// Sizes are left to Material's own ramp on purpose. This pass changes family
/// and colour; resizing the type is a layout change, and layout belongs to the
/// screen passes that follow.
TextTheme _quietInkTextTheme(ColorScheme scheme) {
  const serif = TextStyle(fontFamily: kSerifFamily);
  const sans = TextStyle(fontFamily: kSansFamily);

  return const TextTheme()
      .copyWith(
        // Literata: anything that is being *read* rather than operated.
        displayLarge: serif,
        displayMedium: serif,
        displaySmall: serif,
        headlineLarge: serif,
        headlineMedium: serif,
        headlineSmall: serif,
        titleLarge: serif,
        // Instrument Sans: every label, source name, chip, button and row.
        titleMedium: sans,
        titleSmall: sans,
        bodyLarge: sans,
        bodyMedium: sans,
        bodySmall: sans,
        labelLarge: sans,
        labelMedium: sans,
        labelSmall: sans,
      )
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
}

/// Builds the Quiet Ink [ThemeData] for one brightness.
///
/// Replaces `flashPaletteTheme`, which took a palette key. There is one visual
/// direction now, so there is one function and no key.
ThemeData flashQuietInkTheme({required Brightness brightness}) {
  final scheme = _quietInkScheme(brightness);
  final text = _quietInkTextTheme(scheme);
  final flash =
      brightness == Brightness.light ? _flashColorsLight : _flashColorsDark;

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: kFlashPageTransitions,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    extensions: <ThemeExtension<dynamic>>[flash],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      // surfaceContainer, not surface. The bar used to take the same colour
      // as the scaffold behind it and simply disappeared — which reads as a
      // layout bug and sends you looking in the wrong file.
      backgroundColor: scheme.surfaceContainer,
      // Teal, not the accent. This reverses a deliberate older decision that
      // put the second hue on the most-touched surface in the app. Quiet Ink
      // spends orange on one thing only, the unread dot, so selection is
      // teal like every other interactive mark.
      selectedItemColor: scheme.primary,
      // A named role, not 60% ink. 60% of onSurface over a tinted
      // surfaceContainer is not #5A6361, which is why the alpha version could
      // never match the spec however it was nudged.
      unselectedItemColor: scheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    // Phones get the bottom bar above; the rail is what tablets and TV use
    // instead (see form_factor.dart). Same three decisions, same reasons.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      // 14, down from 20, and no outline. Quiet Ink has no cards in the feed
      // at all — rows are separated by one hairline and nothing else — but
      // this theme still dresses bubbles and sheets, which is what the radius
      // is now for. Converting the article row away from a Card is the feed
      // pass; it interacts with scroll offset and retirement, which have a
      // documented regression history here.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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

