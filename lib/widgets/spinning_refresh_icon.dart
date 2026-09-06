import 'package:flutter/material.dart';

/// The app's one loading visual: a circular arrow, turning while work runs.
///
/// It began as the refresh button's own icon. The button used to swap in a
/// rotating app bolt for the duration, which reads as a different control
/// appearing where the one you just pressed used to be, and loses the one
/// affordance a refresh icon has: it is already a picture of going round.
/// Same glyph in both states, only moving.
///
/// That argument turned out to hold everywhere, so this now serves every
/// loading state in the app — the rotating bolt that once did is gone. The
/// static [FlashBolt] is untouched: it is a mark, not an indicator.
///
/// Clockwise, which is `turns` increasing, and the direction the arrowhead
/// already points. Constant speed on purpose: the old bolt's flick-and-drift
/// easing was a flourish, but on a control the user deliberately pressed an
/// uneven spin reads as the app stuttering.
class SpinningRefreshIcon extends StatefulWidget {
  /// Null means "whatever the surrounding IconTheme says", which is what the
  /// resting [Icon] uses — so the spinning and resting states are the same
  /// size without either having to name a number.
  final double? size;

  /// Also null-means-ambient. The refresh button leaves it null so the FAB's
  /// own foreground colour applies; the standalone loading states pass
  /// `colorScheme.primary`, which is the colour they have always been.
  final Color? color;

  const SpinningRefreshIcon({super.key, this.size, this.color});

  @override
  State<SpinningRefreshIcon> createState() => _SpinningRefreshIconState();
}

class _SpinningRefreshIconState extends State<SpinningRefreshIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(Icons.refresh_rounded, size: widget.size, color: widget.color),
    );
  }
}
