import 'package:flutter/foundation.dart';

/// Broadcast signal that the set of blocked articles changed.
///
/// The same kept-alive problem [ReadStateNotifier] and [SavedStateNotifier]
/// document, from a third direction. Adding a blocklist keyword writes
/// `is_blocked = 1` across every matching row and every feed query already
/// filters on it — but `FeedScreen` lives in the app's `IndexedStack` and is
/// not rebuilt by the panel closing, so the article the user just asked to
/// hide stayed on screen, with the chip counts still counting it, until the
/// app was restarted.
///
/// A broadcast rather than the record-and-consume shape of
/// [FeedsChangedNotifier], because the blocklist panel is opened from
/// FeedScreen's own Filter bubble: the list *is* on screen when this fires,
/// which is exactly the case that notifier documents itself as not covering.
///
/// Carries no payload. Blocking changes list *membership* — which rows come
/// back at all — so a listener cannot patch its copy in place the way
/// [SavedStateNotifier]'s listeners can; the only correct response is to
/// re-query.
class BlockedStateNotifier extends ChangeNotifier {
  static final BlockedStateNotifier instance = BlockedStateNotifier._();

  BlockedStateNotifier._();

  /// Call after any write that changes `is_blocked` on existing rows.
  void blockedArticlesChanged() => notifyListeners();
}
