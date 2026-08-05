/// Scope key for the All tab. Negative so it can never collide with a
/// folder_id, which is a positive autoincrement value.
const int kAllScope = -1;

/// In-memory, scope-keyed sets of article IDs read during the current app
/// session. Empty at process start; never persisted to disk.
///
/// An article read in one scope (tab) is visible only in that scope for the
/// rest of the session — not in any other.
class SessionReadTracker {
  SessionReadTracker._();
  static final SessionReadTracker instance = SessionReadTracker._();

  final Map<int, Set<int>> _byScope = {};

  Set<int> idsForScope(int scope) =>
      Set.unmodifiable(_byScope[scope] ?? const <int>{});

  bool isReadInScope(int id, int scope) =>
      _byScope[scope]?.contains(id) ?? false;

  Set<int> get allIds => _byScope.values.expand((s) => s).toSet();

  void add(int id, {required int scope}) {
    _byScope.putIfAbsent(scope, () => {}).add(id);
  }

  void addAll(Iterable<int> ids, {required int scope}) {
    if (ids.isEmpty) return;
    _byScope.putIfAbsent(scope, () => {}).addAll(ids);
  }

  void removeEverywhere(int id) {
    for (final scopeSet in _byScope.values) {
      scopeSet.remove(id);
    }
  }

  void clearScope(int scope) {
    _byScope[scope]?.clear();
  }

  void clear() {
    _byScope.clear();
  }
}
