import '../models/content_block.dart';

/// In-memory, session-scoped cache of clean-mode extraction results, keyed by
/// article URL.
///
/// Session-scoped by design, same reasoning as [SummaryCache]: extraction is
/// cheap enough to redo and tied to a reading session, so it does not earn a
/// table. Without it, leaving an article and coming back — or toggling clean
/// mode off and on — would silently re-fetch and re-parse the same page.
///
/// Two deliberate divergences from [SummaryCache]:
///
/// The key is the URL alone. There is no tier here, so there is no second
/// dimension for entries to collide across.
///
/// **Failures are cached**, as a null value. [SummaryCache] never caches its
/// failures and is right not to — a model or service failure is transient and
/// worth retrying. Extraction is not: it is a deterministic parse of the page's
/// own HTML, so retrying costs a second full page fetch to reach the same
/// verdict, and it would re-show the "not available" banner every single time
/// the reader reopened that article. Do not "fix" this to match SummaryCache.
///
/// So `contains(url) == true` with `get(url) == null` is the meaningful state
/// "this URL has been tried and has no clean version".
class CleanArticleCache {
  static final CleanArticleCache instance = CleanArticleCache._();
  CleanArticleCache._();

  static const int _maxEntries = 50;

  // Insertion-ordered map: re-inserting a key moves it to the end, which gives
  // least-recently-inserted eviction for free.
  final Map<String, List<ContentBlock>?> _entries = {};

  /// The blocks for [url], or null both when the URL is unknown and when it is
  /// known to have no clean version. Use [contains] to tell those apart.
  List<ContentBlock>? get(String url) => _entries[url];

  /// Whether [url] has been decided this session, successfully or not.
  bool contains(String url) => _entries.containsKey(url);

  int get length => _entries.length;

  /// Records a verdict. A null or empty [blocks] records "no clean version"
  /// rather than being dropped — that is the whole point of caching failures.
  void put(String url, List<ContentBlock>? blocks) {
    final value = (blocks == null || blocks.isEmpty) ? null : blocks;

    _entries.remove(url);
    _entries[url] = value;

    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Test-only reset.
  void clear() => _entries.clear();
}
