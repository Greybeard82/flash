import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One destination in [FlashBottomNav].
class FlashNavDestination {
  /// Shown when this destination is not the current one.
  final Widget icon;

  /// Shown when it is. Pass the same widget for both to keep one glyph.
  final Widget selectedIcon;

  final String label;

  const FlashNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// The phone's bottom navigation bar.
///
/// Replaces Material's [BottomNavigationBar], which cannot draw what the mock
/// asks for: a filled pill wrapping the selected item's icon *and* label.
/// Material's own indicator — on `NavigationBar` — sits behind the icon only,
/// with the label outside and below it.
///
/// **Every colour comes from `bottomNavigationBarTheme`, never from
/// `colorScheme`.** That is what lets one widget serve both themes without
/// knowing which one it is in. Quiet Ink and Newspaper already describe their
/// navigation there — background, selected, unselected — and had done since
/// before this widget existed; reading `colorScheme.surfaceContainer` directly
/// would have quietly changed Newspaper's bar, whose background is `_npSurface2`
/// and whose scheme does not declare `surfaceContainer` at all.
///
/// The pill is the one thing the Material theme has no slot for, so it comes
/// from [FlashColors.navPill]. Newspaper sets that to [Colors.transparent] and
/// therefore renders exactly as it always has — red on paper-grey, no pill, no
/// shape change — while this file stays ignorant of it. That is the whole
/// reason the pill is a role rather than a `primaryContainer` lookup: opting
/// out is a value a theme supplies, not a branch in a widget.
class FlashBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FlashNavDestination> destinations;

  const FlashBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  /// Bar padding at a system inset of zero: 10 above, 6 at the sides, 16
  /// below. See [bottomPaddingFor] for what happens when the inset is not
  /// zero, which on any modern phone it is not.
  static const EdgeInsets barPadding =
      EdgeInsets.fromLTRB(sidePadding, topPadding, sidePadding, bottomGutter);

  static const double sidePadding = 6;
  static const double topPadding = 10;

  /// The gutter the bar wants below its content.
  static const double bottomGutter = 16;

  /// The bottom padding to add on top of a system inset of [inset].
  ///
  /// **The gutter is the inset or 16, never the sum.** The bar sits inside a
  /// `SafeArea`, which already adds the inset; adding a flat 16 on top of that
  /// gave 40dp of dead space under the labels on a gesture-navigation phone,
  /// where the inset alone is 24 and already clears the handle.
  ///
  /// So this subtracts what SafeArea is about to add, and clamps at zero for
  /// insets larger than the gutter:
  ///
  ///     max(16 - inset, 0) + inset == max(16, inset)
  ///
  /// That identity is what `flash_bottom_nav_test.dart` pins, rather than the
  /// arithmetic that produces it — the arithmetic can be rewritten, the
  /// invariant is the promise.
  static double bottomPaddingFor(double inset) =>
      math.max(bottomGutter - inset, 0);

  /// The selected item's pill, at the width the mock was drawn for.
  static const EdgeInsets pillPadding =
      EdgeInsets.symmetric(horizontal: pillPaddingH, vertical: pillPaddingV);
  static const double pillPaddingH = 18;
  static const double pillPaddingV = 6;
  static const double pillRadius = 14;

  /// What the pill tightens to before the label is allowed to shrink.
  ///
  /// Padding gives way first because a slightly narrower pill is invisible
  /// and a smaller label is not.
  static const double minPillPaddingH = 8;

  /// Between the glyph and its label.
  static const double iconLabelGap = 3;
  static const double iconSize = 21;
  static const double labelSize = 11;

  /// The floor the label may never go below, whatever the width or the user's
  /// font-size setting. Under this it stops being a label.
  static const double minLabelSize = 9;

  @override
  Widget build(BuildContext context) {
    final navTheme = Theme.of(context).bottomNavigationBarTheme;
    final ink = Theme.of(context).flashColors;

    // `paddingOf`, not `viewPaddingOf`, and the difference is not academic.
    //
    // `padding` is the quantity SafeArea consumes, so subtracting the same
    // quantity keeps the two matched. `viewPadding` reports the raw inset
    // regardless of what has already been consumed — so if this bar is ever
    // nested inside another SafeArea, `viewPadding` would still read 24 while
    // `padding` had gone to 0, this would subtract 16 from a gutter that was
    // no longer being added, and the gutter would vanish entirely.
    //
    // Read here rather than inside the SafeArea below, because SafeArea zeroes
    // the padding it consumes in the MediaQuery it hands to its children.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Falling back to the scheme only where a theme has left a slot empty.
    // Both of this app's themes fill all three, so these are for a stock
    // ThemeData — the one a widget test pumps.
    final scheme = Theme.of(context).colorScheme;
    final background = navTheme.backgroundColor ?? scheme.surfaceContainer;
    final selected = navTheme.selectedItemColor ?? scheme.primary;
    final unselected = navTheme.unselectedItemColor ?? scheme.onSurfaceVariant;

    return Material(
      color: background,
      child: SafeArea(
        top: false,
        child: Padding(
          // Keyed so a test can measure this padding rather than whichever
          // Padding happens to come first in the tree — Material and SafeArea
          // both contribute their own.
          key: const ValueKey('nav_bar_padding'),
          // Bottom only. The top 10 and the side 6 are unconditional.
          padding: EdgeInsets.fromLTRB(
            sidePadding,
            topPadding,
            sidePadding,
            bottomPaddingFor(bottomInset),
          ),
          child: Row(
            children: List.generate(destinations.length, (i) {
              return Expanded(
                child: _NavItem(
                  key: ValueKey('nav_item_$i'),
                  destination: destinations[i],
                  isSelected: i == currentIndex,
                  selectedColor: selected,
                  unselectedColor: unselected,
                  pillColor: ink.navPill,
                  onTap: () => onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final FlashNavDestination destination;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final Color pillColor;
  final VoidCallback onTap;

  const _NavItem({
    required super.key,
    required this.destination,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.pillColor,
    required this.onTap,
  });

  /// How wide [text] draws at [size], in this context's font and direction.
  double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
      // The size in [style] is already the final pixel size — the scale was
      // applied when it was chosen — so scaling again here would measure a
      // string nobody is going to draw.
      textScaler: TextScaler.noScaling,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final content = isSelected ? selectedColor : unselectedColor;

    // The item is inside an Expanded, so this is the slot it has to live in.
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxWidth;

        // The user's font-size setting, honoured rather than undone.
        //
        // The previous version wrapped the label in a bare FittedBox, which
        // meant Android's "large text" setting scaled the label up and the
        // FittedBox scaled it straight back down — the accessibility setting
        // did nothing at all, on the surface a user touches most. So the
        // scaled size is the *starting* size here, and it is only given up
        // when it genuinely will not fit, and never below a floor.
        final desired =
            MediaQuery.textScalerOf(context).scale(FlashBottomNav.labelSize);

        TextStyle styleAt(double size) => TextStyle(
              fontFamily: kSansFamily,
              fontSize: size,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: content,
            );

        // Padding gives way before the label does. 18dp is the mock's number
        // at the width it was drawn for; when four destinations no longer fit
        // at that, the pill tightens toward [minPillPaddingH] before anything
        // starts shrinking. A slightly narrower pill is invisible. A smaller
        // label is not.
        var size = desired;
        var pad = FlashBottomNav.pillPaddingH;
        var width = _measure(context, destination.label, styleAt(size));

        if (width + 2 * pad > slot) {
          pad = math.max(
            FlashBottomNav.minPillPaddingH,
            (slot - width) / 2,
          );
        }

        if (width + 2 * pad > slot) {
          // Padding is already at its minimum, so the label has to give. It
          // shrinks proportionally and stops at [minLabelSize]: below that it
          // is not a label any more, and an unreadable word is no better than
          // a truncated one.
          pad = FlashBottomNav.minPillPaddingH;
          final available = slot - 2 * pad;
          final scale = width == 0 ? 1.0 : available / width;
          size = math.max(FlashBottomNav.minLabelSize, desired * scale);
          width = _measure(context, destination.label, styleAt(size));
        }

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FlashBottomNav.pillRadius),
          // Align, not Center, and heightFactor is the whole reason.
          //
          // The tap target should be the full slot the Expanded gives it, but
          // the pill should hug its own content. Center takes the largest size
          // its constraints allow, and in the Scaffold's bottomNavigationBar
          // slot that is the entire viewport — which is exactly how this bar
          // once grew to 800dp and left the body zero pixels.
          child: Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: Container(
              // The padding is the same whether or not the pill is painted, so
              // moving the selection does not shift the row. An unselected
              // item is the same shape as a selected one with nothing behind
              // it.
              padding: EdgeInsets.symmetric(
                horizontal: pad,
                vertical: FlashBottomNav.pillPaddingV,
              ),
              decoration: BoxDecoration(
                color: isSelected ? pillColor : Colors.transparent,
                borderRadius: BorderRadius.circular(FlashBottomNav.pillRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The index-0 glyph is an SVG recoloured by the ambient
                  // IconTheme rather than by an Icon.color, so the theme has
                  // to be supplied here rather than passed down as a property.
                  IconTheme.merge(
                    data: IconThemeData(
                      color: content,
                      size: FlashBottomNav.iconSize,
                    ),
                    child: isSelected
                        ? destination.selectedIcon
                        : destination.icon,
                  ),
                  // Keyed for the same reason: an Icon wraps itself in a
                  // SizedBox of its own size, so an unkeyed search finds 21
                  // before 3.
                  const SizedBox(
                    key: ValueKey('nav_icon_label_gap'),
                    height: FlashBottomNav.iconLabelGap,
                  ),
                  // A backstop, not the mechanism. The size above already
                  // fits by measurement; this only catches the gap between
                  // what TextPainter reports and what the raster actually
                  // needs, and it scales rather than truncating, because
                  // "Categori..." stops being the word.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      softWrap: false,
                      // Already scaled, by hand, above.
                      textScaler: TextScaler.noScaling,
                      style: styleAt(size),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
