/// In-memory, session-scoped cache of AI summaries, keyed by article URL and
/// the length tier that produced them.
///
/// Session-scoped by design: empty on launch, never persisted, no DB
/// migration. A summary is cheap to regenerate and tied to a reading session,
/// so it does not earn a table.
///
/// The tier is part of the key, not incidental to it. Keyed on URL alone, a
/// summary generated at Standard was served back after the reader switched to
/// Detailed — the cache had no way to know the setting it was produced under
/// had changed, so the new tier silently never took effect on any article
/// already read once. Entries for different tiers of the same article are
/// independent and coexist: switching back and forth returns each tier's own
/// text rather than regenerating, which is the behaviour a cache is for.
class SummaryCache {
  static final SummaryCache instance = SummaryCache._();
  SummaryCache._();

  static const int _maxEntries = 50;

  // Insertion-ordered map: re-inserting a key moves it to the end, which
  // gives us "least-recently-inserted" eviction for free.
  final Map<String, String> _entries = {};

  /// The two parts are joined with a separator that cannot occur in a URL
  /// scheme or a tier name, so no pair of (url, tier) can collide with
  /// another.
  static String _key(String url, String tier) => '$url::$tier';

  String? get(String url, String tier) => _entries[_key(url, tier)];

  bool contains(String url, String tier) =>
      _entries.containsKey(_key(url, tier));

  int get length => _entries.length;

  void put(String url, String tier, String summary) {
    if (summary.trim().isEmpty) return;

    final key = _key(url, tier);
    _entries.remove(key);
    _entries[key] = summary;

    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Test-only reset.
  void clear() => _entries.clear();
}
