import 'package:flutter/material.dart';

/// The refresh button's own circular arrow, turning while a refresh runs.
///
/// The button used to swap in [FetchingIndicator] — the app's bolt — for the
/// duration. That reads as a different control appearing where the one you
/// just pressed used to be, and it loses the one affordance a refresh icon
/// has: it is already a picture of going round. Same glyph in both states,
/// only moving.
///
/// Clockwise, which is `turns` increasing, and the direction the arrowhead
/// already points. Constant speed on purpose: the bolt's flick-and-drift
/// easing is a flourish for an ambient indicator, but on a control the user
/// deliberately pressed, an uneven spin reads as the app stuttering.
class SpinningRefreshIcon extends StatefulWidget {
  /// Null means "whatever the surrounding IconTheme says", which is what the
  /// resting [Icon] uses — so the spinning and resting states are the same
  /// size without either having to name a number.
  final double? size;

  const SpinningRefreshIcon({super.key, this.size});

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
      child: Icon(Icons.refresh_rounded, size: widget.size),
    );
  }
}
