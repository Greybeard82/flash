import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Flash mark — the same bolt the launcher icon draws, without its disc.
///
/// One asset, `assets/images/flash_bolt.svg`, carrying the bolt path copied
/// verbatim from the icon's own source. In-app bolts used to be Material's
/// `Icons.bolt_*`, which merely looked like the app icon; this is the icon.
///
/// **One state, not two.** The mark was authored as a single path, so there is
/// no outline/filled pair to swap between the way the Material glyphs did in
/// the nav bar. Rather than invent a second variant, selected state is carried
/// by colour alone — which is what [size] and [color] defaulting to the
/// ambient [IconTheme] is for: `BottomNavigationBar` and `NavigationRail` both
/// wrap their icons in an IconTheme holding the selected or unselected colour,
/// so this picks the right one up without either of them being told about it.
///
/// Single-tone by design — one path, one fill — so a `srcIn` filter recolours
/// the whole mark and every existing call site's `colorScheme` tint keeps
/// working. A multi-tone mark would have had to render as authored instead.
class FlashBolt extends StatelessWidget {
  /// Falls back to the ambient [IconTheme], like an [Icon] would.
  final double? size;
  final Color? color;

  const FlashBolt({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolved = color ?? iconTheme.color ?? Theme.of(context).colorScheme.primary;
    final side = size ?? iconTheme.size ?? 24.0;

    return SvgPicture.asset(
      'assets/images/flash_bolt.svg',
      width: side,
      height: side,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
    );
  }
}
