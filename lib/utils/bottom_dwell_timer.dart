import 'dart:async';

/// "Reached the bottom, waited N seconds, fire once" state machine, used to
/// mark a feed read once its article list is scrolled to the end.
///
/// Kept as plain Dart (no Flutter/DB deps) so it can be tested directly with
/// FakeAsync — this codebase's widget tests can't combine testWidgets() with
/// real sqflite I/O (see feed_repository_test.dart for the established
/// DB-only test pattern).
class BottomDwellTimer {
  final void Function() onComplete;
  final Timer Function(Duration, void Function()) _createTimer;

  Duration _duration;
  bool _enabled;
  Timer? _timer;

  /// Set once the timer fires and cleared only when the list leaves the
  /// bottom. Without it, any further scroll event while still parked at the
  /// end would re-arm and fire again — every few seconds on a delay, and on
  /// essentially every scroll event when the delay is zero.
  bool _firedAtThisBottom = false;

  BottomDwellTimer({
    Duration duration = const Duration(seconds: 5),
    bool enabled = true,
    required this.onComplete,
    Timer Function(Duration, void Function())? createTimer,
  })  : _duration = duration,
        _enabled = enabled,
        _createTimer = createTimer ?? Timer.new;

  bool get isPending => _timer != null;
  Duration get duration => _duration;
  bool get enabled => _enabled;

  /// Applies a settings change. Any pending wait is abandoned — the next
  /// scroll event at the bottom re-arms under the new configuration, so a
  /// user who shortens the delay doesn't have the old one fire at them first.
  void configure({required bool enabled, required Duration duration}) {
    if (_enabled == enabled && _duration == duration) return;
    _enabled = enabled;
    _duration = duration;
    cancel();
  }

  /// Call on every scroll event with whether the list is at its bottom edge.
  ///
  /// A zero [duration] still goes through a timer rather than calling back
  /// inline: firing synchronously inside a scroll callback would re-enter
  /// setState mid-notification. `Timer(Duration.zero)` lands on the next
  /// event-loop turn, which is imperceptible but safe.
  void updateAtBottom(bool atBottom) {
    if (!atBottom) {
      cancel();
      return;
    }
    if (!_enabled || _firedAtThisBottom) return;
    _timer ??= _createTimer(_duration, _fire);
  }

  void _fire() {
    _timer = null;
    _firedAtThisBottom = true;
    onComplete();
  }

  /// Cancel on navigation away, tab switch, backgrounding, or dispose. Also
  /// clears the fired latch, so returning to the bottom later can fire again.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _firedAtThisBottom = false;
  }
}
