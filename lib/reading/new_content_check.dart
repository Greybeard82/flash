/// Whether a reload surfaced any article that wasn't visible before it.
///
/// Pure Dart, no Flutter import — this is a set comparison, not a scroll
/// decision, so it is unit-testable on its own and reusable by every path
/// that reloads the list (fetch, refresh, and reload-without-fetch alike).
///
/// "Visible", not "inserted": callers pass the ids the tab query actually
/// returned, so an article that landed in the database and was then hidden by
/// the age filter, the per-feed cap or a blocklist match does not count as
/// new — moving the list for it would jump the user to the top to see nothing.
abstract final class NewContentCheck {
  static bool hasNew(Set<int?> beforeIds, Iterable<int?> afterIds) {
    return afterIds.any((id) => !beforeIds.contains(id));
  }
}
