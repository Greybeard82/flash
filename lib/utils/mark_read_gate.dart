/// Gates the mark-as-read-on-scroll pass behind evidence that a *person*
/// moved the list.
///
/// `FeedScreen._onScroll` is a `ScrollController` listener, and a
/// `ScrollController` cannot tell you why the offset changed. Every
/// programmatic `jumpTo` fires it exactly as a finger drag does, and the pass
/// then walks the list marking everything above the new offset as read.
///
/// That is the whole of the reported bug. Pull-to-refresh brought in new
/// articles, the list grew *above* a preserved offset, the RefreshIndicator
/// retracted, and the pass ran against a list the user had never scrolled —
/// reading the new articles within a second of them arriving.
///
/// The gate closes before any programmatic scroll and reopens only on a real
/// user scroll. The signal is `UserScrollNotification` with a direction other
/// than idle: it is dispatched from `updateUserScrollDirection`, which runs
/// for touch drags, mouse wheels and trackpads, but not for `jumpTo` — which
/// calls `goIdle()` first and therefore only ever reports idle.
///
/// Deliberately a plain Dart class with no Flutter import: it is the safety
/// property this pass exists to guarantee, so it is unit-testable on its own
/// rather than buried in a private bool on a 1000-line State.
class MarkReadGate {
  /// Closed on construction. Nothing has been scrolled yet, so nothing is
  /// eligible — and a list sitting at offset 0 has nothing above the viewport
  /// to mark anyway, so starting closed costs nothing and removes a class of
  /// first-frame races.
  bool _open = false;

  /// Whether the mark-as-read pass may run.
  bool get isOpen => _open;

  /// Call immediately before any programmatic scroll (`jumpTo`, `animateTo`).
  void close() => _open = false;

  /// Call on a `UserScrollNotification` whose direction is not idle.
  void open() => _open = true;
}
