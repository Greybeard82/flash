import 'package:flutter/material.dart';

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
    return RotationTransition(
      turns: _turns,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _SymmetricBoltPainter(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Right half of the bolt outline, top apex to bottom apex, in a coordinate
/// space of -1..1 on both axes. The first and last points sit on the vertical
/// axis (x == 0) and are shared with the mirrored half.
///
/// Only this half is authored anywhere. [buildSymmetricBoltPath] generates the
/// left half by negating x, so the glyph's symmetry is a property of the
/// construction rather than of carefully-typed coordinates.
const List<Offset> kBoltRightHalf = <Offset>[
  Offset(0.00, -1.00), // top apex, on the axis
  Offset(0.46, -0.12), // upper spike
  Offset(0.19, -0.12), // notch back toward the axis
  Offset(0.46, 0.30), // lower spike
  Offset(0.00, 1.00), // bottom apex, on the axis
];

/// Builds the mirror-symmetric bolt, filling [size].
///
/// The app's own logo is a standard asymmetric zigzag; this glyph is symmetric
/// left-to-right so it stays legible while spinning — an asymmetric shape
/// wobbles and reads as off-centre under rotation.
Path buildSymmetricBoltPath(Size size) {
  final halfW = size.width / 2;
  final halfH = size.height / 2;
  Offset toLocal(Offset p) => Offset(halfW + p.dx * halfW, halfH + p.dy * halfH);

  final start = toLocal(kBoltRightHalf.first);
  final path = Path()..moveTo(start.dx, start.dy);

  for (var i = 1; i < kBoltRightHalf.length; i++) {
    final p = toLocal(kBoltRightHalf[i]);
    path.lineTo(p.dx, p.dy);
  }
  // Walk back up the mirrored side, skipping both axis points so they are not
  // emitted twice.
  for (var i = kBoltRightHalf.length - 2; i >= 1; i--) {
    final p = toLocal(Offset(-kBoltRightHalf[i].dx, kBoltRightHalf[i].dy));
    path.lineTo(p.dx, p.dy);
  }

  return path..close();
}

class _SymmetricBoltPainter extends CustomPainter {
  final Color color;

  const _SymmetricBoltPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      buildSymmetricBoltPath(size),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SymmetricBoltPainter oldDelegate) =>
      oldDelegate.color != color;
}
