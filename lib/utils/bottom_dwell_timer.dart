import 'dart:async';

/// Debounced "reached bottom, wait N seconds, then fire" state machine used
/// to trigger a delayed mark-all-as-read once a feed's article list is
/// scrolled to its end. Kept as plain Dart (no Flutter/DB deps) so it can be
/// tested directly with FakeAsync — this codebase's widget tests can't
/// combine testWidgets() with real sqflite I/O (see feed_repository_test.dart
/// for the established DB-only test pattern).
class BottomDwellTimer {
  final Duration duration;
  final void Function() onComplete;
  final Timer Function(Duration, void Function()) _createTimer;

  Timer? _timer;

  BottomDwellTimer({
    this.duration = const Duration(seconds: 5),
    required this.onComplete,
    Timer Function(Duration, void Function())? createTimer,
  }) : _createTimer = createTimer ?? Timer.new;

  bool get isPending => _timer != null;

  /// Call on every scroll event with whether the list is currently at its
  /// bottom edge. Starts the timer the moment "at bottom" first becomes
  /// true, and cancels it the instant the list leaves the bottom — repeated
  /// bottom/away/bottom cycles restart the wait rather than stacking
  /// multiple timers that could all fire independently.
  void updateAtBottom(bool atBottom) {
    if (atBottom) {
      _timer ??= _createTimer(duration, _fire);
    } else {
      cancel();
    }
  }

  void _fire() {
    _timer = null;
    onComplete();
  }

  /// Cancel on navigation away, tab switch, backgrounding, or dispose.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
