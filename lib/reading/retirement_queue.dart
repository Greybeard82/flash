import 'dart:collection';

/// Article ids that have scrolled past the retirement frontier and are waiting
/// to be deleted.
///
/// Retirement used to delete rows the moment the frontier identified them.
/// Deleting a row above the viewport always shifts everything below it up by
/// that row's height, so the offset had to be corrected by the same amount to
/// cancel the shift — and that cancellation lands a frame late. The user felt
/// it as a small adjustment every time he lifted his finger. No amount of
/// tuning removes it: cancelling a shift is always a race with the frame the
/// shift happens in.
///
/// So the work is split. Identifying rows is cheap and moves nothing, and
/// happens whenever the frontier says so. *Deleting* them happens only at the
/// four moments where the scroll position is being rebuilt anyway — mark all
/// as read, the refresh FAB, pull-to-refresh, and a category tab switch — so
/// there is no shift to cancel and no arithmetic left to get wrong.
///
/// In memory only, and empty on cold launch, like `SessionReadTracker`. Ids
/// queued in a session that ends without a flush are simply never retired:
/// they survive to the next session and are re-queued when the user scrolls
/// past them again. That is intended, not a leak.
class RetirementQueue {
  /// Insertion-ordered and de-duplicating, which is exactly the contract:
  /// scrolling past the same row twice must not queue it twice, and [drain]
  /// hands ids back oldest-first.
  final LinkedHashSet<int> _pending = LinkedHashSet<int>();

  bool get isEmpty => _pending.isEmpty;

  /// How many ids are waiting. Logged at each flush so the real-world size of
  /// the queue is observable — deliberately uncapped, because a cap would be a
  /// fifth flush trigger in disguise and would fire at an arbitrary moment.
  int get length => _pending.length;

  /// Whether [id] is waiting to be retired.
  ///
  /// A pending row is still rendered and fully interactive; pending means
  /// "will be deleted at the next flush", not "gone".
  bool isPending(int id) => _pending.contains(id);

  void enqueue(Iterable<int> ids) => _pending.addAll(ids);

  /// Takes [id] back out without retiring it.
  ///
  /// Two cases require this: bookmarking (PRD 4.9 — saved articles are never
  /// deleted, whatever their read state or age) and marking unread. Scrolling
  /// back up to a queued row does *not* release it: the row is still on screen
  /// and interactive either way, so the user cannot tell, and un-queueing on
  /// scroll-back would put frontier logic back into the scrolling path.
  void release(int id) => _pending.remove(id);

  /// Empties the queue and returns its contents in enqueue order.
  List<int> drain() {
    final ids = _pending.toList(growable: false);
    _pending.clear();
    return ids;
  }
}
