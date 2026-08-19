import 'dart:async';

import 'package:flutter/material.dart';

/// Tracks whether the list is actively scrolling, so anything floating over it
/// can get out of the way.
///
/// Mirrors the debounce already used for the mark-read-on-scroll flush in
/// `feed_screen.dart`: every scroll event resets a short timer, and "scrolling
/// stopped" is that timer firing. It deliberately does *not* reuse that timer —
/// `_onScroll` returns early when mark-read-on-scroll is switched off, so the
/// existing debounce never runs in that case, whereas the fade has to work
/// either way.
///
/// One controller drives every floating button, so adding a sixth is a matter
/// of wrapping it in [ScrollFade] rather than repeating any of this.
class ScrollFadeController extends ValueNotifier<bool> {
  /// How long after the last scroll event the buttons come back.
  ///
  /// Matches the 150ms mark-read debounce in `feed_screen.dart` — a fling
  /// keeps emitting scroll events throughout, so this only elapses once the
  /// list has genuinely settled.
  final Duration settleDelay;

  Timer? _timer;
  bool _disposed = false;

  ScrollFadeController({
    this.settleDelay = const Duration(milliseconds: 150),
  }) : super(false);

  /// Call from the scroll listener on every event.
  void onScroll() {
    if (_disposed) return;
    if (!value) value = true;
    _timer?.cancel();
    _timer = Timer(settleDelay, () {
      if (_disposed) return;
      value = false;
    });
  }

  /// Bring the buttons back immediately — used when the list goes away
  /// underneath them, e.g. a tab switch that resets scroll position.
  void settleNow() {
    if (_disposed) return;
    _timer?.cancel();
    value = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Fades [child] down while the list is scrolling and back up once it stops.
///
/// Stays hit-testable at the faded opacity: the buttons are still clearly
/// visible, and swallowing a tap the user could see themselves making would be
/// worse than the momentary overlap the fade exists to reduce.
class ScrollFade extends StatelessWidget {
  /// Faded, not invisible — the cluster should recede, not vanish.
  static const double fadedOpacity = 0.25;

  static const Duration fadeDuration = Duration(milliseconds: 200);

  final ScrollFadeController controller;
  final Widget child;

  const ScrollFade({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller,
      // Passed through rather than rebuilt: the button subtree is unchanged by
      // the fade, so it should not be rebuilt on every transition.
      child: child,
      builder: (context, scrolling, child) => AnimatedOpacity(
        opacity: scrolling ? fadedOpacity : 1.0,
        duration: fadeDuration,
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
