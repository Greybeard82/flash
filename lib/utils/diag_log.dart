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
/// Prints via [debugPrintSynchronously] rather than [debugPrint]: the latter
/// throttles to roughly 1KB/s, and a scroll flood pushes later lines minutes
/// behind the events they describe — which made [retire] lines look absent
/// when the flush had in fact run.
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
    debugPrintSynchronously('[SCROLL] t=$_t offset=${offset.toStringAsFixed(1)} '
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
    debugPrintSynchronously('[READ]   t=$_t id=$id trigger=$trigger '
        'offset=${offset.toStringAsFixed(1)} sinceResume=$sinceResumeMs');
  }

  /// Logged at each flush. [ids] is the drained queue length, which is the
  /// only way to observe how large the queue grows in real use — it is
  /// deliberately uncapped, so this number is worth watching.
  static void retire({required int ids, required String trigger}) {
    if (!kDebugMode) return;
    debugPrintSynchronously('[RETIRE] t=$_t ids=$ids trigger=$trigger');
  }

  static void lifecycle({
    required String state,
    double? restoredOffset,
    int? anchorId,
  }) {
    if (!kDebugMode) return;
    debugPrintSynchronously('[LIFECY] t=$_t state=$state '
        'restoredOffset=${restoredOffset?.toStringAsFixed(1) ?? "null"} '
        'anchorId=${anchorId ?? "null"}');
  }

  /// Pass 20 investigation: "never received a keyword-alert notification".
  /// Called from _doRefresh on every refresh path (cold start, background
  /// WorkManager task, pull-to-refresh, manual refresh) so a run against
  /// each path shows exactly where the chain stops -- no alerts configured,
  /// no hits found, or a hit found but the plugin call itself failing.
  /// [source] distinguishes the background WorkManager isolate from the
  /// foreground app isolate, since flutter_local_notifications has to be
  /// initialized independently in each.
  ///
  /// Pass 21: [newCount] replaced what used to be a count of every unblocked
  /// article the fetch re-parsed (the same number on every refresh, since RSS
  /// feeds re-serve their last N items) with the count actually new this
  /// pass -- the same set [hitCount] is now computed from, so a repeat
  /// notification for an already-seen article shows up here as `hits=0`
  /// rather than being silently indistinguishable from a real one.
  static void alert({
    required String source,
    required int alertCount,
    required int newCount,
    required int hitCount,
    String? shown,
    String? error,
  }) {
    if (!kDebugMode) return;
    debugPrintSynchronously('[ALERT]  t=$_t source=$source '
        'alerts=$alertCount new=$newCount hits=$hitCount '
        'shown=${shown ?? "n/a"} error=${error ?? "none"}');
  }
}
