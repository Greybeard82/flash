import 'dart:async';

import 'package:flutter/foundation.dart';

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
/// 2. **Records *and* broadcasts, which are two different jobs.**
///
///    The *record* is for the article list. `FeedScreen` cannot be on screen
///    when a write happens on another tab, so the change is queued and
///    [consume]d on the next visibility transition: adding six feeds costs one
///    fetch instead of six, and the fetch happens when the user arrives at the
///    Flash tab rather than while they are still working in Categories. That
///    is what [consume] is for, and it must stay single-consumer — a second
///    consumer would swallow the change and the new feeds would arrive empty.
///
///    The *broadcast* is for screens that are already showing the structure
///    and have no visibility transition coming. This used to be nothing, on
///    the reasoning that "every writer lives on another tab" — which stopped
///    being true once Settings could write. Settings is a pushed route, not a
///    tab: with Categories underneath it, an OPML import (or a backup restore,
///    which had the same bug and gets the fix for free) changed the database
///    under a `FeedsScreen` that had loaded once in `initState` and was never
///    told to look again. The folder was there; you had to restart the app to
///    see it.
///
///    [notifyListeners] is debounced rather than fired per write, because the
///    writes come from a loop: importing fifty feeds is fifty inserts, and a
///    reload each would re-query the whole Categories screen fifty times.
class FeedsChangedNotifier extends ChangeNotifier {
  static final FeedsChangedNotifier instance = FeedsChangedNotifier._();

  FeedsChangedNotifier._();

  FeedsChange? _pending;

  /// Coalesces a burst of writes into one notification.
  ///
  /// A [Timer] rather than a microtask: the inserts are awaited one after
  /// another with real database I/O between them, so every microtask queue
  /// drains long before the next insert lands and nothing would ever be
  /// merged. 300ms comfortably spans a bulk import without being noticeable
  /// after a single add.
  Timer? _notifyDebounce;

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
    _notifyDebounce?.cancel();
    _notifyDebounce =
        Timer(const Duration(milliseconds: 300), notifyListeners);
  }

  /// Takes the pending change and clears it. Null if there was none.
  FeedsChange? consume() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  /// Test seam.
  void reset() {
    _pending = null;
    _notifyDebounce?.cancel();
    _notifyDebounce = null;
  }
}
