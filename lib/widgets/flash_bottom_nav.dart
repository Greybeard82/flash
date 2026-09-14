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

  /// Bar padding: 10 above, 6 at the sides, 16 below.
  ///
  /// The bottom 16 is not symmetry — it is the gesture-bar gutter. The bar
  /// sits inside a `SafeArea`, so this is clearance on top of whatever inset
  /// the system reports.
  static const EdgeInsets barPadding = EdgeInsets.fromLTRB(6, 10, 6, 16);

  /// The selected item's pill.
  static const EdgeInsets pillPadding =
      EdgeInsets.symmetric(horizontal: 18, vertical: 6);
  static const double pillRadius = 14;

  /// Between the glyph and its label.
  static const double iconLabelGap = 3;
  static const double iconSize = 21;
  static const double labelSize = 11;

  @override
  Widget build(BuildContext context) {
    final navTheme = Theme.of(context).bottomNavigationBarTheme;
    final ink = Theme.of(context).flashColors;

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
          padding: barPadding,
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

  @override
  Widget build(BuildContext context) {
    final content = isSelected ? selectedColor : unselectedColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlashBottomNav.pillRadius),
      child: Center(
        child: Container(
          // The padding is the same whether or not the pill is painted, so
          // moving the selection does not shift the row. An unselected item
          // is the same shape as a selected one with nothing behind it.
          padding: FlashBottomNav.pillPadding,
          decoration: BoxDecoration(
            color: isSelected ? pillColor : Colors.transparent,
            borderRadius: BorderRadius.circular(FlashBottomNav.pillRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The index-0 glyph is an SVG recoloured by the ambient
              // IconTheme rather than by an Icon.color, so the theme has to be
              // supplied here rather than passed down as a property.
              IconTheme.merge(
                data: IconThemeData(
                  color: content,
                  size: FlashBottomNav.iconSize,
                ),
                child: isSelected ? destination.selectedIcon : destination.icon,
              ),
              // Keyed for the same reason: an Icon wraps itself in a SizedBox
              // of its own size, so an unkeyed search finds 21 before 3.
              const SizedBox(
                key: ValueKey('nav_icon_label_gap'),
                height: FlashBottomNav.iconLabelGap,
              ),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kSansFamily,
                  fontSize: FlashBottomNav.labelSize,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
