import 'package:flutter/material.dart';
import 'flash_bolt.dart';

/// Small app-bar indicator shown while feeds are fetching in the background.
///
/// Replaces the full-screen pulse that used to cover the feed during cold
/// start. The list is now readable immediately and this sits quietly in the
/// app bar instead, so a slow network never hides content that is already on
/// disk.
class FetchingIndicator extends StatefulWidget {
  final double size;

  const FetchingIndicator({super.key, this.size = 20});

  @override
  State<FetchingIndicator> createState() => _FetchingIndicatorState();
}

class _FetchingIndicatorState extends State<FetchingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _turns;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // One full turn per loop, but not at a constant rate: a quick flick, a
    // slow drift, a snap, then an ease out. A mechanical spinner reads as
    // "loading bar"; this reads as a flicker of energy, which is the point.
    // Segment ends are absolute fractions of a turn so the loop closes on 1.0.
    _turns = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.20)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.20, end: 0.32)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 32,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.32, end: 0.80)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.80, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 30,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The same mark as the app icon and the nav tab, so the spinner and the
    // static bolt are literally one shape.
    //
    // A real bolt is asymmetric and orbits rather than spinning dead-centre if
    // its mass sits off the rotation axis — the hand-drawn symmetric shape
    // that once lived here existed to avoid exactly that, and the Material
    // glyph that replaced it accepted the trade. This asset is safe on that
    // count by construction rather than by luck. Its path is framed in the
    // icon's own 512 square, and the area centroid of that polygon is
    // (259.5, 251.1) against a rotation axis at (256, 256): 6.0 units of
    // offset, 1.17% of the glyph box, which is 0.24dp of orbit at the 20dp
    // this renders at. Measured, not assumed — if the mark is ever redrawn,
    // re-measure before trusting this comment.
    return RotationTransition(
      turns: _turns,
      child: FlashBolt(
        size: widget.size,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
