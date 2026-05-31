/// In-memory set of article IDs read during the current app session.
/// Empty at process start; never persisted to disk.
class SessionReadTracker {
  SessionReadTracker._();
  static final SessionReadTracker instance = SessionReadTracker._();

  final Set<int> ids = {};

  void add(int id) => ids.add(id);
  void addAll(Iterable<int> newIds) => ids.addAll(newIds);
  void remove(int id) => ids.remove(id);
  void removeWhere(bool Function(int) test) => ids.removeWhere(test);
  void clear() => ids.clear();
}
