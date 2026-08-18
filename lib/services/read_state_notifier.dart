import 'package:flutter/foundation.dart';

/// Broadcast signal that an article's read state changed somewhere outside
/// the feed screen — Bookmarks or Search.
///
/// The four main screens live in an IndexedStack and are all kept alive, so
/// FeedScreen is never rebuilt or reloaded on a plain tab switch
/// (`_AppShell._navigateTo` only reloads when the Feed tab is re-tapped while
/// already active). Without this signal, marking an article read in Bookmarks
/// left FeedScreen's in-memory UnreadCounts — and therefore every folder
/// badge, the All badge, and the launcher badge — showing the pre-read count
/// for the rest of the session.
///
/// FeedScreen owns the counts, so it listens here and re-queries them from
/// the DB. Screens that mutate read state without owning counts just ping.
class ReadStateNotifier extends ChangeNotifier {
  static final ReadStateNotifier instance = ReadStateNotifier._();

  ReadStateNotifier._();

  /// Call after any read/unread write made outside FeedScreen.
  void articleReadStateChanged() => notifyListeners();
}
