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
//   * **Orange means the article is in your queue.** It has exactly two
//     jobs and no others: the unread dot on a feed row (`secondary`), and the
//     saved bookmark glyph on the action rail (`secondary`, on the same
//     `primaryContainer` tint the unsaved glyph sits on).
//
//     There was a third — the swipe-to-unread reveal on Bookmarks — until
//     swipe-to-mark-read was removed from `ArticleCard` outright.
//
//     The second of those was a `savedFill` block under an `onSavedFill`
//     glyph until the fill was removed. Both roles are deleted; see the
//     block above `navPill` for why they are not being kept warm.
//
//     This used to read "orange means unread, and nothing else", which
//     described a UI that never shipped — there is no unread dot in the code
//     yet, and `secondary` was for a long time painted only by the swipe
//     reveal, which no longer exists.
//     Faults are not orange: an invalid URL in the add-feed sheet and the
//     stale-feed warning in Categories are `error`.

// Light
const Color _qiSurfaceLight = Color(0xFFFFFFFF);
const Color _qiSurfaceContainerLight = Color(0xFFF1F5F5);
const Color _qiOnSurfaceLight = Color(0xFF0F1413);
const Color _qiOnSurfaceVariantLight = Color(0xFF5A6361);
const Color _qiOnSurfaceMutedLight = Color(0xFF717877);
const Color _qiOnSurfaceReadLight = Color(0xFF6A7270);
const Color _qiOutlineVariantLight = Color(0xFFE9ECEB);
const Color _qiPrimaryLight = Color(0xFF0E6A70);
const Color _qiOnPrimaryLight = Color(0xFFFFFFFF);
const Color _qiPrimaryContainerLight = Color(0xFFDCEBEB);
const Color _qiOnPrimaryContainerLight = Color(0xFF0E6A70);
const Color _qiUnreadLight = Color(0xFFBE6530);
const Color _qiPlaceholderLight = Color(0xFFF0F2F2);

/// Empty-state glyphs, in both brightnesses.
const Color _qiIllustrationLight = Color(0xFFC3CAC9);
const Color _qiIllustrationDark = Color(0xFF3A4241);

/// Controls that are present with nothing to act on, and controls that are
/// disabled — 6.5 ruled those one thing, not two.
///
/// Light still shares illustration's value; dark is authored one step lighter,
/// so the two roles are visibly different in the theme where the difference is
/// easiest to see. Around 2.2:1 against the surface is intended rather than
/// tolerated: WCAG exempts disabled controls, and a disabled control that
/// meets text contrast does not read as disabled.
const Color _qiInertLight = _qiIllustrationLight;
const Color _qiInertDark = Color(0xFF464E4D);

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

/// The clean view's reading measure, from handoff 3's restyle list.
///
/// Declared here rather than in `clean_article_view.dart` because they are type
/// decisions and this is where the type system lives — and because a test that
/// pins them should not have to reach into a widget's private constants to do
/// it.
///
/// **1.62 is not 1.6 rounded up.** It is the value the restyle list names, and
/// the second decimal is the kind of thing that gets "tidied" by someone who
/// reads it as noise: at 17px it is the difference between a 27.5px line and a
/// 27.2px one, which is small per line and visible down a column of forty.
/// `clean_view_type_test.dart` pins it for exactly that reason.
///
/// 17 rather than the 16 the Material ramp gives `bodyLarge`: this is the one
/// surface in the app whose entire job is sustained reading, and it is the one
/// place the ramp is the wrong authority.
const double kCleanBodySize = 17;
const double kCleanBodyHeight = 1.62;

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

  // **`savedFill` and `onSavedFill` were here, and this is why they
  // went.**
  //
  // They painted the action rail's lower half when an article was saved:
  // an `#BE6530` block under a near-black glyph, `_npInk` under
  // `_npPaper` in Newspaper. Design 2a asked for the fill so a saved
  // article would be scannable down the feed, and that justification did
  // not survive contact with the app — scanning for saved
  // articles is what the Bookmarks destination is for, one tap from
  // every screen. The feed was carrying a solid orange block on every
  // saved row to duplicate a screen that already exists, on its
  // quietest surface.
  //
  // The saved state is a glyph now: `bookmark_rounded` in `secondary`,
  // on the same `primaryContainer` tint the unsaved glyph sits on.
  //
  // **Deleted rather than kept warm for a future consumer.** A role with
  // no call site is still lerped on every theme animation, compared in
  // every `==` and hashed in every `hashCode` — but the real
  // cost is that it reads as an available answer. The next person
  // needing a saved treatment would find two roles here and assume the
  // decision had already been made. It had, and it was reversed.
  // Restoring the fill means restoring these two deliberately, which is
  // the right amount of friction.
  //
  // `_qiOnSavedFill` went with them. It was `#0D1211`, and it existed
  // only because `onSecondary` gave 4.12:1 on the orange — under
  // the 4.5:1 this app holds a lone glyph to. A whole authored constant
  // written to solve a contrast problem that the fill had created.

  /// The fill behind the selected bottom-navigation item.
  ///
  /// A role rather than `primaryContainer` read directly, because it is how
  /// Newspaper opts out of the pill without a second widget. Newspaper sets
  /// this to [Colors.transparent], and the nav then renders exactly as it
  /// always has — its own red on its own surface, no pill, no shape change —
  /// while the widget stays ignorant of which theme it is drawing.
  final Color navPill;

  /// The large glyph above an empty state's message.
  ///
  /// Its own role because no ink level describes it. These sit well below
  /// `onSurfaceMuted` — they are a picture standing in for content that is not
  /// there, not text that has been quietened — and reading them as ink at 20%
  /// meant every empty state in the app was a different grey depending on
  /// which surface it happened to sit on.
  final Color illustration;

  /// A control that is present but has nothing to act on — the feed's filter
  /// and quick-settings icons before the first feed arrives.
  ///
  /// Also the role for a *disabled* control: 6.5 ruled that inert and
  /// disabled are one thing, not two, and the faint wash that used to sit
  /// behind a disabled glyph went away entirely rather than changing value.
  ///
  /// Light shares [illustration]'s value; dark is authored a step lighter, so
  /// the two roles differ visibly where that is easiest to see. It sits around
  /// 2.2:1 against the surface on purpose — WCAG exempts disabled controls,
  /// and one that meets text contrast does not read as disabled.
  final Color inert;

  /// Which brightness this instance belongs to, so [category] can answer
  /// without every caller threading a `Brightness` through.
  final Brightness brightness;

  /// The fill behind a transient message strip.
  ///
  /// The banner used to paint `inverseSurface`, which is semantically correct
  /// for what a full inversion means and produced the heaviest block of colour
  /// anywhere in a light, papery theme for what is usually a one-line
  /// confirmation. So this is a new role rather than a substitution:
  /// `inverseSurface` keeps its meaning and stops being borrowed.
  ///
  /// **It sits one step above `surface` and far below `inverseSurface`.** That
  /// is deliberately subtle -- about 1.10:1 against the page in both
  /// brightnesses -- because a banner *slides in*, and motion is what catches
  /// the eye. Something that moves does not also need contrast shock. The
  /// hairline under it is what makes the edge legible once it has settled.
  ///
  /// Not a new hex anywhere: it is the theme's own `surfaceContainer` in Quiet
  /// Ink and `_npSurface2` in Newspaper, both already authored as the
  /// one-step-off-the-page tone. Text on it is `onSurface`, which measures
  /// 16.92:1 light, 14.24:1 dark and 13.62:1 in Newspaper.
  final Color bannerSurface;

  /// The banner's edge.
  ///
  /// **Load-bearing, and held to 3:1.** `bannerSurface` is about 1.10:1
  /// against the page, so the border is what actually defines where the
  /// component starts and stops — which makes it a non-text graphical object
  /// under WCAG 1.4.11 and puts it on a 3:1 floor against **both** the fill it
  /// sits on and the page behind it.
  ///
  /// `outlineVariant` was tried first and is nowhere near: 1.08 against the
  /// fill and 1.19 against the page in Quiet Ink light. It is a hairline for
  /// separating list rows that already differ; it cannot carry an edge on its
  /// own. Newspaper's `outline` fails the same way at 1.37 / 1.50.
  ///
  /// Measured, per theme: 5.64 / 6.19 light, 5.63 / 6.22 dark, 4.56 / 5.00 in
  /// Newspaper. Newspaper takes `onSurfaceMuted` rather than its ink, which
  /// clears 13.62 and would draw a heavy black rule rather than an edge.
  final Color bannerBorder;

  /// Whether categories are drawn without hue.
  ///
  /// Newspaper only. A newspaper identifies its sections by name, not by
  /// colour: six greys standing in for six hues would be a colour system with
  /// the colour taken out, which is worse than no colour system. So in
  /// Newspaper a chip carries the paper tint with ink text, and the selected
  /// one inverts to ink with paper text — the same two tones the rest of the
  /// theme is built from.
  ///
  /// It lives here rather than being read off the scheme because there is no
  /// token that means "this theme is Newspaper", and inferring it from a font
  /// family or a spot colour would be a guess that silently changes meaning
  /// the first time either is edited.
  final bool monochromeCategories;

  const FlashColors({
    required this.onSurfaceMuted,
    required this.onSurfaceRead,
    required this.placeholder,
    required this.navPill,
    required this.illustration,
    required this.inert,
    required this.brightness,
    required this.bannerSurface,
    required this.bannerBorder,
    this.monochromeCategories = false,
  });

  /// The stored hue for a category, resolved for this theme.
  CategoryPalette category(int colorIndex) =>
      categoryPalette(colorIndex, brightness);

  @override
  FlashColors copyWith({
    Color? onSurfaceMuted,
    Color? onSurfaceRead,
    Color? placeholder,
    Color? navPill,
    Color? illustration,
    Color? inert,
    Brightness? brightness,
    Color? bannerSurface,
    Color? bannerBorder,
    bool? monochromeCategories,
  }) {
    return FlashColors(
      bannerSurface: bannerSurface ?? this.bannerSurface,
      bannerBorder: bannerBorder ?? this.bannerBorder,
      monochromeCategories:
          monochromeCategories ?? this.monochromeCategories,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      onSurfaceRead: onSurfaceRead ?? this.onSurfaceRead,
      placeholder: placeholder ?? this.placeholder,
      navPill: navPill ?? this.navPill,
      illustration: illustration ?? this.illustration,
      inert: inert ?? this.inert,
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
      navPill: Color.lerp(navPill, other.navPill, t)!,
      illustration: Color.lerp(illustration, other.illustration, t)!,
      inert: Color.lerp(inert, other.inert, t)!,
      bannerSurface: Color.lerp(bannerSurface, other.bannerSurface, t)!,
      bannerBorder: Color.lerp(bannerBorder, other.bannerBorder, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
      // A half-hued chip is not a thing, so this snaps with brightness.
      monochromeCategories:
          t < 0.5 ? monochromeCategories : other.monochromeCategories,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlashColors &&
          other.onSurfaceMuted == onSurfaceMuted &&
          other.onSurfaceRead == onSurfaceRead &&
          other.placeholder == placeholder &&
          other.navPill == navPill &&
          other.illustration == illustration &&
          other.inert == inert &&
          other.brightness == brightness &&
          other.bannerSurface == bannerSurface &&
          other.bannerBorder == bannerBorder &&
          other.monochromeCategories == monochromeCategories;

  @override
  int get hashCode => Object.hash(onSurfaceMuted, onSurfaceRead, placeholder,
      navPill, illustration, inert, brightness, bannerSurface, bannerBorder,
      monochromeCategories);
}

/// The ink roles for a theme that does not carry the extension.
///
/// Every theme this app builds registers one, so in production this is never
/// reached. It exists because the alternative was a null check, and a widget
/// that throws when it cannot find a colour is a far worse failure than one
/// that paints a reasonable grey — a stock `ThemeData()`, which is what most
/// widget tests pump, has no extensions at all.
///
/// The levels are blended from the scheme's own ink toward its own surface, at
/// the same ratios the alpha values they replaced used, so a theme that never
/// opted in still gets a sane three-level hierarchy rather than one flat grey.
FlashColors _fallbackFlashColors(ColorScheme scheme) {
  Color mix(double t) => Color.lerp(scheme.onSurface, scheme.surface, t)!;
  return FlashColors(
    // 0.62, not 0.5. At 0.5 muted sat closer to the ink than onSurfaceRead at
    // 0.55 did, which inverted the hierarchy: a read title receded behind the
    // timestamp beneath it. Blending further toward the surface means less
    // contrast, so muted has to take the larger number. This was the last
    // inverted pair left after Newspaper was corrected.
    onSurfaceMuted: mix(0.62),
    onSurfaceRead: mix(0.55),
    placeholder: mix(0.92),
    navPill: scheme.primaryContainer,
    illustration: mix(0.78),
    inert: mix(0.78),
    brightness: scheme.brightness,
    // One step off the page, matching what the real themes do.
    bannerSurface: mix(0.94),
    bannerBorder: scheme.onSurfaceVariant,
  );
}

/// Reads the Flash ink roles off any [ThemeData].
///
/// Use this rather than `theme.extension<FlashColors>()!`. The null-check form
/// crashed under two themes that really occur: `flashNewspaperTheme()` before
/// it registered its own, and any stock `ThemeData`.
extension FlashInk on ThemeData {
  FlashColors get flashColors =>
      extension<FlashColors>() ?? _fallbackFlashColors(colorScheme);
}

const FlashColors _flashColorsLight = FlashColors(
  onSurfaceMuted: _qiOnSurfaceMutedLight,
  onSurfaceRead: _qiOnSurfaceReadLight,
  placeholder: _qiPlaceholderLight,
  navPill: _qiPrimaryContainerLight,
  illustration: _qiIllustrationLight,
  inert: _qiInertLight,
  brightness: Brightness.light,
  bannerSurface: _qiSurfaceContainerLight,
  bannerBorder: _qiOnSurfaceVariantLight,
);

const FlashColors _flashColorsDark = FlashColors(
  onSurfaceMuted: _qiOnSurfaceMutedDark,
  onSurfaceRead: _qiOnSurfaceReadDark,
  placeholder: _qiPlaceholderDark,
  navPill: _qiPrimaryContainerDark,
  illustration: _qiIllustrationDark,
  inert: _qiInertDark,
  brightness: Brightness.dark,
  bannerSurface: _qiSurfaceContainerDark,
  bannerBorder: _qiOnSurfaceVariantDark,
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

/// Handoff 1.7, and the whole of it: three SegmentedButtons ship — sort order
/// in the filter bubble, theme and summary length in Quick Settings — and all
/// three were stock M3 capsules at radius 20, the last capsules in an app that
/// had settled on r9 chips and an r14 nav pill.
///
/// Shared by both themes rather than written twice, so the two cannot drift
/// into disagreeing about what a segmented button is. Each is handed its own
/// scheme and text theme, so Newspaper keeps PT Serif and its own roles
/// without a special case here.
///
/// **Two things in 1.7 are not set here, and neither is an oversight.**
///
///   * **`showSelectedIcon: false`** cannot live in a theme —
///     `SegmentedButtonThemeData` has exactly two fields, `style` and
///     `selectedIcon`, and the flag is a widget constructor argument. It does
///     not need to: **all three shipping call sites already pass it**, in
///     `filter_bubble.dart` and twice in `quick_settings_bubble.dart`. The
///     only thing that could get it wrong is a fourth SegmentedButton added
///     without the flag, which `segmented_button_theme_test.dart` guards by
///     reading the call sites rather than by rendering one.
///   * **Height 40** is reported rather than applied, because it costs 8dp of
///     touch target. Measured, a segment paints at **48** — and that is the
///     fill, not a tap halo around a 40dp body, because
///     `_SegmentedButtonRenderObject` lays every segment out at a uniform
///     tight height and Material's tap padding ends up inside the paint.
///     Reaching 40 means `tapTargetSize: shrinkWrap` or a negative
///     `visualDensity`, and both take the touch target down with the paint.
///     The two places this app already goes under 48 — the 36dp folder chip,
///     the 36dp rail halves — each carry a written justification and a test.
///     1.7 does not mention touch targets at all.
///
/// Everything else lands:
///
///   * **Radius 9 outer, 0 between** falls straight out of one `shape`. The
///     same `segmentStyleFor` forces every *segment* to a square
///     `RoundedRectangleBorder()`, and the resolved `shape` is used only for
///     the group's outer border and clip.
///   * **One `side` is both the border and the divider between segments** —
///     `ButtonStyle.side`'s own doc says so, and it is why there is no
///     separate divider entry.
SegmentedButtonThemeData _segmentedButtonTheme(
  ColorScheme scheme,
  TextTheme text,
) {
  // Derived from the theme's own labelLarge rather than written as a bare
  // TextStyle, which would drop the family and give Newspaper a grotesque.
  TextStyle label(FontWeight weight) =>
      (text.labelLarge ?? const TextStyle()).copyWith(
        fontSize: 13,
        fontWeight: weight,
      );

  return SegmentedButtonThemeData(
    style: ButtonStyle(
      side: WidgetStatePropertyAll<BorderSide>(
        BorderSide(color: scheme.outlineVariant, width: 1),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      textStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (states) => label(states.contains(WidgetState.selected)
            ? FontWeight.w600
            : FontWeight.w500),
      ),
      // Unselected resolves to null on purpose: the segment sits on whatever
      // surface hosts it, which on the filter bubble and Quick Settings is
      // not the same colour.
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) =>
          states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : null),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) =>
          states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant),
    ),
  );
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
    // A badge count is unread state, so it takes the unread colour.
    //
    // Material's default is `error`, which put a fault red on a count of the
    // things a user asked to be told about — and contradicted the rule that
    // orange means unread and red means broken. Both call sites in app.dart
    // pass no colour, so both inherited the default; one theme entry fixes
    // those and every future badge.
    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.secondary,
      textColor: scheme.onSecondary,
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
    segmentedButtonTheme: _segmentedButtonTheme(scheme, text),
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
const Color _npPaper = Color(0xFFF2F1EE); // newsprint background
const Color _npInk = Color(0xFF1D1D1B); // ink text
const Color _npRed = Color(0xFFA0231A); // spot-colour accent
const Color _npSurface2 = Color(0xFFE7E7E3); // nav / secondary surface
const Color _npHairline = Color(0xFFC7C7C1); // rule / outline

/// Newspaper's own ink levels.
///
/// Registered so the widgets that read [FlashColors] work in Newspaper mode at
/// all — before this they threw, because this theme carried no extensions and
/// the call sites used a null check. Newspaper is a setting a user can turn
/// on, so that was a crash on the feed, not a theoretical one.
///
/// The values are newsprint greys mixed from this palette's own ink and paper,
/// not Quiet Ink's: a teal-tinted grey on a warm paper background would read as
/// a rendering fault. Nothing else about this theme changes.
const FlashColors _flashColorsNewspaper = FlashColors(
  // Newsprint ink, at 0.35 and 0.30 from _npInk toward _npPaper.
  //
  // **There is no "changes no pixel" guarantee on these two, and its removal
  // is the point.** The previous pair, 0.62 and 0.55, was chosen to fix an
  // inverted hierarchy and was never checked against paper: it took muted to
  // 2.31:1 and read to 2.76:1, well under the 4.5:1 body text needs. The
  // guarantee that authoring them moved no pixel was true and was also the
  // reason nobody looked — a promise that nothing changed is a promise that
  // nothing was examined.
  //
  // For scale: before Quiet Ink, Newspaper's muted ink was `onSurface` at 0.6
  // alpha, which is lerp 0.40 and 4.27:1. So this is a restoration that lands
  // slightly better than the thing it restores, not a new direction. The 0.62
  // pair never shipped; it existed only on this branch.
  //
  //   onSurfaceMuted  #686765  5.00:1 on paper
  //   onSurfaceRead   #5D5D5A  5.85:1 on paper
  //
  // Read keeps more contrast than muted, so the hierarchy the old pair was
  // introduced to fix still holds.
  onSurfaceMuted: Color(0xFF686765),
  onSurfaceRead: Color(0xFF5D5D5A),
  // 6.8, closed. Parked since pass 7 waiting on Newspaper hues from Design
  // that were never going to arrive, because the right answer was that there
  // should not be any. See FlashColors.monochromeCategories.
  monochromeCategories: true,
  // The same one-step-off-the-page tone Newspaper already uses for its nav
  // and secondary surfaces. Newspaper never authors surfaceContainer, so the
  // role is pinned here rather than read off the scheme.
  bannerSurface: _npSurface2,
  // Not _npInk: at 13.62 it draws a black rule rather than an edge.
  bannerBorder: Color(0xFF686765),
  placeholder: _npSurface2,
  // Ink, not _npRed. In Newspaper `secondary` is `primary` is _npRed, already
  // the nav selection, the FAB, the switch and the masthead tint — so a red
  // saved block is the loudest thing on the row while buying none of the
  // scannability that justified orange in Quiet Ink, where orange appears
  // nowhere else.
  // No pill. Newspaper's nav is a red mark on a paper-grey bar and has been
  // since it shipped; a teal-shaped capsule behind the selected item would be
  // Quiet Ink furniture wearing newsprint colours. Transparent here is how it
  // opts out, without FlashBottomNav needing to know it exists.
  navPill: Colors.transparent,
  // Unchanged at lerp 0.78. Decoration rather than text, so the 4.5:1 bar
  // that moved the two ink levels above does not apply to it.
  //
  // #C3C2C0, not the #C3C2BF printed in DESIGN-HANDOFF.md 1.1 / 1.4 / 6.6.
  //
  // The document gives that hex under the guarantee that authoring these
  // "changes no pixel", and #C3C2BF is one unit of blue away from what the
  // lerp it replaces actually produces — so the two statements disagree, and
  // the value cannot satisfy both.
  //
  // The document settles it against itself. lerp(_npInk, _npPaper, t) on the
  // blue channel gives 157.82 at 0.62, 143.05 at 0.55 and 191.58 at 0.78. The
  // document writes 9E, 8F and BF: the first two are ROUNDED (157.82 -> 9E,
  // not 9D) and only the third is truncated. One value converted the other way
  // from its two neighbours, under a promise of no pixel change, is a
  // transcription slip rather than an override.
  //
  // So the guarantee wins and the code keeps the lerped value. The document is
  // the thing to correct; flagged in the handoff rather than silently
  // reconciled.
  illustration: Color(0xFFC3C2C0),
  inert: Color(0xFFC3C2C0),
  brightness: Brightness.light,
);

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

  final baseText = const TextTheme()
      .copyWith(
        displayLarge:
            const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
        displayMedium:
            const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
        displaySmall:
            const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
        headlineLarge:
            const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
        headlineMedium:
            const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
        headlineSmall:
            const TextStyle(fontFamily: playfair, fontWeight: FontWeight.w700),
        titleLarge:
            const TextStyle(fontFamily: ptSerif, fontWeight: FontWeight.w700),
        titleMedium:
            const TextStyle(fontFamily: ptSerif, fontWeight: FontWeight.w700),
        titleSmall: const TextStyle(fontFamily: ptSerif),
        bodyLarge: const TextStyle(fontFamily: ptSerif),
        bodyMedium: const TextStyle(fontFamily: ptSerif),
        bodySmall: const TextStyle(fontFamily: ptSerif),
        labelLarge: const TextStyle(fontFamily: ptSerif),
        labelMedium: const TextStyle(fontFamily: ptSerif),
        labelSmall: const TextStyle(fontFamily: ptSerif),
      )
      .apply(
        bodyColor: _npInk,
        displayColor: _npInk,
      );

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: kFlashPageTransitions,
    colorScheme: base,
    scaffoldBackgroundColor: _npPaper,
    textTheme: baseText,
    extensions: const <ThemeExtension<dynamic>>[_flashColorsNewspaper],
    appBarTheme: AppBarTheme(
      backgroundColor: _npPaper,
      foregroundColor: _npInk,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: _npRed,
      titleTextStyle: baseText.titleLarge?.copyWith(color: _npInk),
    ),
    // Newspaper has no orange. Its unread accent is _npRed, which is also its
    // primary — so here a red badge is on-palette rather than a fault colour
    // leaking through, and it is the theme's own choice instead of Material's.
    badgeTheme: const BadgeThemeData(
      backgroundColor: _npRed,
      textColor: Colors.white,
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
    segmentedButtonTheme: _segmentedButtonTheme(base, baseText),
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
