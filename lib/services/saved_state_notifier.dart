import 'package:flutter/foundation.dart';

/// Broadcast signal that an article's saved (bookmark) state changed.
///
/// The same kept-alive problem [ReadStateNotifier] documents, one screen
/// over: BookmarksScreen loads its list once in `initState` and then lives
/// in the IndexedStack for the rest of the session. Bookmarking an article
/// from the feed's radial menu wrote the row but left the Bookmarks tab
/// showing "No bookmarks yet" until the user pulled to refresh or restarted.
///
/// The changed article travels with the signal so a listener that already
/// holds it in memory can patch its own copy instead of re-querying — a
/// re-query in FeedScreen would rebuild the list and disturb the scroll
/// position over a single flag. Screens whose list *membership* depends on
/// the flag (BookmarksScreen) still reload.
///
/// Carrying the value also makes the signal self-cancelling: a screen that
/// made the write already agrees with it, so its listener sees no
/// discrepancy and does nothing.
class SavedStateNotifier extends ChangeNotifier {
  static final SavedStateNotifier instance = SavedStateNotifier._();

  SavedStateNotifier._();

  /// The article whose saved state last changed, or null before any change.
  int? get articleId => _articleId;
  int? _articleId;

  /// That article's new saved state.
  bool get saved => _saved;
  bool _saved = false;

  /// Call after any saved/unsaved write.
  void articleSavedStateChanged(int articleId, {required bool saved}) {
    _articleId = articleId;
    _saved = saved;
    notifyListeners();
  }
}
