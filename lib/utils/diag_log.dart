import 'package:flutter/foundation.dart';

/// Debug-only, single-line, greppable diagnostics for the scroll/read/lifecycle
/// investigation (Pass 10).
///
/// Every record is one line so it survives `adb logcat | grep`. Nothing here
/// runs in release: each entry point returns immediately unless [kDebugMode],
/// and the string interpolation sits behind that guard so it is not even built.
///
/// This is an instrument, not a feature. It exists to answer three questions
/// that cannot be answered by reading the code: what actually moves the scroll
/// offset, what actually writes `is_read`, and in what order relative to the
/// lifecycle transitions.
class DiagLog {
  static final DateTime _epoch = DateTime.now();

  /// Milliseconds since the isolate started, so lines from one run sort and
  /// subtract cleanly without parsing wall-clock timestamps.
  static int get _t => DateTime.now().difference(_epoch).inMilliseconds;

  /// Last observed lifecycle state, stamped onto [scroll] lines so a scroll
  /// that happens during a transition is visible as such.
  static String lifecycleState = 'resumed';

  /// When the app last reached `resumed`. Read-marking that lands within a few
  /// hundred ms of this is the signature of bugs A and B.
  static DateTime? lastResumeAt;

  /// Milliseconds since the last resume, or -1 if the app has never resumed.
  static int get sinceResumeMs => lastResumeAt == null
      ? -1
      : DateTime.now().difference(lastResumeAt!).inMilliseconds;

  static void scroll({
    required double offset,
    required double delta,
    required double maxExtent,
    required String source,
  }) {
    if (!kDebugMode) return;
    debugPrint('[SCROLL] t=$_t offset=${offset.toStringAsFixed(1)} '
        'delta=${delta.toStringAsFixed(1)} '
        'maxExtent=${maxExtent.toStringAsFixed(1)} '
        'source=$source lifecycle=$lifecycleState');
  }

  static void read({
    required int id,
    required String trigger,
    required double offset,
  }) {
    if (!kDebugMode) return;
    debugPrint('[READ]   t=$_t id=$id trigger=$trigger '
        'offset=${offset.toStringAsFixed(1)} sinceResume=$sinceResumeMs');
  }

  static void retire({
    required int ids,
    required double removedExtent,
    required double offsetBefore,
    required double offsetAfter,
    required bool scrollActive,
  }) {
    if (!kDebugMode) return;
    debugPrint('[RETIRE] t=$_t ids=$ids '
        'removedExtent=${removedExtent.toStringAsFixed(1)} '
        'offsetBefore=${offsetBefore.toStringAsFixed(1)} '
        'offsetAfter=${offsetAfter.toStringAsFixed(1)} '
        'scrollActive=$scrollActive');
  }

  static void lifecycle({
    required String state,
    double? restoredOffset,
    int? anchorId,
  }) {
    if (!kDebugMode) return;
    debugPrint('[LIFECY] t=$_t state=$state '
        'restoredOffset=${restoredOffset?.toStringAsFixed(1) ?? "null"} '
        'anchorId=${anchorId ?? "null"}');
  }
}
