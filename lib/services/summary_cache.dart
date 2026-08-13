/// In-memory, session-scoped cache of AI summaries keyed by article URL.
/// Mirrors [SessionReadTracker]'s pattern: empty on launch, never persisted,
/// no DB migration.
class SummaryCache {
  static final SummaryCache instance = SummaryCache._();
  SummaryCache._();

  static const int _maxEntries = 50;

  // Insertion-ordered map: re-inserting a key moves it to the end, which
  // gives us "least-recently-inserted" eviction for free.
  final Map<String, String> _entries = {};

  String? get(String url) => _entries[url];

  bool contains(String url) => _entries.containsKey(url);

  int get length => _entries.length;

  void put(String url, String summary) {
    if (summary.trim().isEmpty) return;

    _entries.remove(url);
    _entries[url] = summary;

    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Test-only reset.
  void clear() => _entries.clear();
}
