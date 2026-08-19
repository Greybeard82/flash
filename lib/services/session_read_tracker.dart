/// In-memory set of article IDs read during the current app session. Empty at
/// process start; never persisted to disk.
///
/// An article read anywhere — in any tab — stays visible, dimmed in place, in
/// every tab for the rest of the session. This matches Palabre, the app Flash
/// exists to replace.
///
/// This used to be keyed by scope (`kAllScope` for the All tab, the folder id
/// for a category tab), so an article read in one tab was dimmed there and
/// absent entirely from every other. That made articles silently vanish from
/// lists the user hadn't touched. With visibility global there is no scoping
/// concept left, hence a flat set.
class SessionReadTracker {
  SessionReadTracker._();
  static final SessionReadTracker instance = SessionReadTracker._();

  final Set<int> _ids = {};

  /// Every article read this session, in any tab.
  Set<int> get ids => Set.unmodifiable(_ids);

  bool contains(int id) => _ids.contains(id);

  void add(int id) => _ids.add(id);

  void addAll(Iterable<int> ids) => _ids.addAll(ids);

  /// Marked unread again — drops out of the list on the next query.
  void remove(int id) => _ids.remove(id);

  /// Used by mark-all-read on a category tab, which must forget exactly the
  /// articles that were showing in that tab and leave anything read elsewhere
  /// this session untouched. Clearing the whole set there would wrongly
  /// un-dim — and then hide — articles read in other tabs.
  void removeAll(Iterable<int> ids) => _ids.removeAll(ids);

  /// Used by mark-all-read on the All tab, which already means "start fresh
  /// everywhere".
  void clear() => _ids.clear();
}
