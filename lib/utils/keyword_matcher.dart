/// Shared keyword matching logic used by both the blocklist and alert systems.
class KeywordMatcher {
  /// Returns true if [keyword] is found in [haystack].
  ///
  /// Matching is always case-insensitive. When [wholeWord] is true, matches
  /// only on word boundaries (e.g. "crypto" will not match "cryptocurrency").
  static bool matches(String keyword, String haystack, {bool wholeWord = false}) {
    if (wholeWord) {
      final pattern = RegExp(
        r'\b' + RegExp.escape(keyword) + r'\b',
        caseSensitive: false,
      );
      return pattern.hasMatch(haystack);
    }
    return haystack.toLowerCase().contains(keyword.toLowerCase());
  }

  /// Builds the haystack string from an article's title and optional description.
  static String buildHaystack(String title, String? description) =>
      '$title ${description ?? ''}';
}
