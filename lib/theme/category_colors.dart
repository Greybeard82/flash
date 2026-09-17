import 'package:flutter/material.dart';

/// One category's colour, in the three places a category is shown: the tick on
/// a feed row, the block on the Categories screen, and the category chip.
///
/// The tick is one colour in both themes. The chip is a tinted block, so it
/// needs a background and a foreground per brightness — the light chip is dark
/// text on a pale tint, the dark chip is pale text on a deep tint, and neither
/// is derivable from the other.
@immutable
class CategoryPalette {
  /// The row tick and the Categories block.
  final Color tick;

  /// Chip fill.
  final Color chipBackground;

  /// Chip label and icon.
  final Color chipForeground;

  const CategoryPalette({
    required this.tick,
    required this.chipBackground,
    required this.chipForeground,
  });
}

/// How many hues exist. A category's stored `color_index` is taken modulo this.
const int kCategoryHueCount = 6;

/// The six hues, in index order.
///
/// **The hue is stored on the folder, not derived from it**, and that is worth
/// stating here because every cheap alternative was considered and each one
/// breaks:
///
/// * **Hashing the name** reshuffles every colour in the app the first time
///   someone renames a category — and the hue appears in three places at once,
///   so the reshuffle is loud rather than subtle.
/// * **Keying off position** moves the same problem to reordering, which
///   people do far more often than renaming.
/// * **Either one, plus localisation, is worse still.** Starter-pack category
///   names are resolved from ARB keys at seeding time and then become ordinary
///   user data, so the same category is "Tech" on an English device and
///   "Technik" on a German one. Any name-derived rule gives two installs of the
///   same pack different colours.
///
/// So the index is a column, assigned once, and this table is a pure lookup.
/// A "change category colour" setting falls out of that for free later; it is
/// deliberately not built yet.
const List<_Hue> _hues = [
  // 0 — World News
  _Hue(
    tick: Color(0xFF93A3BC),
    lightBackground: Color(0xFFEEF1F7),
    lightForeground: Color(0xFF45556E),
    darkBackground: Color(0xFF1B2330),
    darkForeground: Color(0xFFA9BEDA),
  ),
  // 1 — Tech
  _Hue(
    tick: Color(0xFF89B2B4),
    lightBackground: Color(0xFFEAF4F4),
    lightForeground: Color(0xFF2A6266),
    darkBackground: Color(0xFF122624),
    darkForeground: Color(0xFF8FC3C4),
  ),
  // 2 — Gaming. Unused by the starter pack, so it is the first free index a
  // user-created category picks up.
  _Hue(
    tick: Color(0xFFA79AC0),
    lightBackground: Color(0xFFF3EFF7),
    lightForeground: Color(0xFF5B4A78),
    darkBackground: Color(0xFF231E2E),
    darkForeground: Color(0xFFB6A7CE),
  ),
  // 3 — Travelling
  _Hue(
    tick: Color(0xFFBCA97C),
    lightBackground: Color(0xFFF6F2E8),
    lightForeground: Color(0xFF6B5A32),
    darkBackground: Color(0xFF26220F),
    darkForeground: Color(0xFFCDBB8E),
  ),
  // 4 — Sports
  _Hue(
    tick: Color(0xFF9BB79A),
    lightBackground: Color(0xFFEDF4EC),
    lightForeground: Color(0xFF3C5C3B),
    darkBackground: Color(0xFF152317),
    darkForeground: Color(0xFFA6C6A5),
  ),
  // 5 — Fitness / Health
  _Hue(
    tick: Color(0xFFC39BA4),
    lightBackground: Color(0xFFF8EFF1),
    lightForeground: Color(0xFF73404B),
    darkBackground: Color(0xFF2A1A1E),
    darkForeground: Color(0xFFD2A9B2),
  ),
];

@immutable
class _Hue {
  final Color tick;
  final Color lightBackground;
  final Color lightForeground;
  final Color darkBackground;
  final Color darkForeground;

  const _Hue({
    required this.tick,
    required this.lightBackground,
    required this.lightForeground,
    required this.darkBackground,
    required this.darkForeground,
  });
}

/// The palette for a category's stored [colorIndex].
///
/// Takes an index and a brightness, and deliberately **not** a category name —
/// see the note on [_hues]. Out-of-range indices wrap rather than throw: the
/// column is an ordinary integer that a future "change category colour" screen
/// or a hand-edited database could put anywhere, and a category rendering in
/// the wrong colour is a much smaller problem than a feed that will not build.
/// Negative values wrap too, since Dart's `%` already returns a non-negative
/// result for a positive divisor.
CategoryPalette categoryPalette(int colorIndex, Brightness brightness) {
  final hue = _hues[colorIndex % kCategoryHueCount];
  final isLight = brightness == Brightness.light;
  return CategoryPalette(
    tick: hue.tick,
    chipBackground: isLight ? hue.lightBackground : hue.darkBackground,
    chipForeground: isLight ? hue.lightForeground : hue.darkForeground,
  );
}

/// The hue index a new category should take.
///
/// The lowest index nobody is using, so the first six categories are six
/// different colours rather than a run of the same one. Once all six are taken
/// it falls back to spreading by count, which is the only thing left to do.
///
/// [inUse] is the set of `color_index` values the existing categories hold.
int nextCategoryColorIndex(Iterable<int> inUse) {
  final taken = inUse.map((i) => i % kCategoryHueCount).toSet();
  for (var i = 0; i < kCategoryHueCount; i++) {
    if (!taken.contains(i)) return i;
  }
  return taken.length % kCategoryHueCount;
}
