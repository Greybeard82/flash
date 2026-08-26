/// What kind of structural change happened to the feed or folder set.
enum FeedsChange {
  /// Feeds removed, moved between categories or reordered; categories
  /// created, renamed, deleted or reordered. Every affected article is
  /// already in the database, or already gone by cascade, so the feed screen
  /// only has to re-query. No network.
  structureOnly,

  /// At least one feed was added. A new feed has no articles until something
  /// fetches it, so a re-query alone leaves the user staring at a category
  /// that is inexplicably empty.
  needsFetch,
}

/// Records that the feed or folder structure changed while the article list
/// was not on screen.
///
/// Companion to `ReadStateNotifier`, and it exists for the same underlying
/// reason: the four main screens live in an `IndexedStack` and are all kept
/// alive, so `FeedScreen` is never rebuilt on a plain tab switch.
/// `_AppShell._navigateTo` only reloads it when the Flash tab is re-tapped
/// while already active — walking *back* from Categories takes the other
/// branch and changes nothing. Add six feeds, return to Flash, and the list
/// is exactly as you left it until a manual refresh.
///
/// Two deliberate design choices:
///
/// 1. **Pinged from inside the repository writes, not from the screens.**
///    One choke point, so OPML import, backup restore and onboarding are
///    covered for free instead of being three more call sites to remember.
///
/// 2. **Records rather than broadcasts.** Unlike `ReadStateNotifier` this is
///    not a `ChangeNotifier`, because the article list cannot be on screen
///    when this fires — every writer lives on another tab. Queueing the
///    change and consuming it on the next visibility transition means adding
///    six feeds costs one fetch instead of six, and the fetch happens when
///    the user arrives at the Flash tab rather than while they are still
///    working in Categories.
class FeedsChangedNotifier {
  static final FeedsChangedNotifier instance = FeedsChangedNotifier._();

  FeedsChangedNotifier._();

  FeedsChange? _pending;

  /// The strongest change queued since the last [consume], or null.
  FeedsChange? get pending => _pending;

  bool get isDirty => _pending != null;

  /// A feed was added.
  void feedAdded() => _record(FeedsChange.needsFetch);

  /// Feeds or categories changed without anything new being added.
  void structureChanged() => _record(FeedsChange.structureOnly);

  /// [FeedsChange.needsFetch] always wins. One add anywhere in a batch means
  /// the next consume has to hit the network, however many plain edits follow
  /// it — otherwise adding a feed and then reordering would downgrade the
  /// pending change and the new feed would arrive empty.
  void _record(FeedsChange change) {
    if (_pending != FeedsChange.needsFetch) _pending = change;
  }

  /// Takes the pending change and clears it. Null if there was none.
  FeedsChange? consume() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  /// Test seam.
  void reset() => _pending = null;
}
