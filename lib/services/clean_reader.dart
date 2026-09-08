import 'package:flutter/foundation.dart';

import 'article_extractor.dart';
import 'clean_article_cache.dart';
import 'summary_source.dart';

/// Settings key for whether background clean-mode extraction runs at all.
/// Defaults on wherever it is read.
const String kCleanModeEnabledSettingKey = 'clean_mode_enabled';

/// What [CleanReader.load] decided about one article.
///
/// [unavailable] and [alreadyUnavailable] are the same verdict reached at
/// different times, and the caller needs to tell them apart: the "no clean
/// version" banner should appear the first time a URL is judged and never
/// again for that URL, or flicking back to an article would look like a
/// recurring error.
enum CleanReadOutcome { ready, unavailable, alreadyUnavailable }

class CleanReadResult {
  final CleanReadOutcome outcome;
  final List<ContentBlock>? blocks;

  const CleanReadResult(this.outcome, this.blocks);
}

/// Decides whether an article has a clean version worth offering, and caches
/// the answer.
///
/// Split out of [ArticleDetailPane] for the same reason
/// [ArticleExtractor.extractFromHtml] is split out of `extract`: the judgement
/// is the part worth testing, and the shell it lives in needs a platform view
/// to exist at all. The extractor is injectable so this runs with no network.
class CleanReader {
  final ArticleExtractor _extractor;

  CleanReader({ArticleExtractor? extractor})
      : _extractor = extractor ?? ArticleExtractor();

  /// Enough real prose to be worth rendering instead of the page.
  ///
  /// Reuses [SummarySource]'s threshold rather than inventing a second one —
  /// "is there an article here" is the same question both features ask. The
  /// char cap is lifted because this is a measurement, not a prompt payload:
  /// at the default 2500 every long article would measure identically, which
  /// happens not to change a `>= 400` verdict today but would quietly break
  /// the gate if the threshold ever moved.
  @visibleForTesting
  static bool isSubstantial(List<ContentBlock>? blocks) =>
      blocks != null &&
      blocks.isNotEmpty &&
      SummarySource.isSubstantial(
          SummarySource.fromBlocks(blocks, maxChars: 1 << 30));

  /// Fetches, parses and judges [url], consulting and updating the cache.
  ///
  /// Never throws: every failure is a [CleanReadOutcome.unavailable].
  Future<CleanReadResult> load(String url) async {
    final cache = CleanArticleCache.instance;

    if (cache.contains(url)) {
      final cached = cache.get(url);
      return cached != null
          ? CleanReadResult(CleanReadOutcome.ready, cached)
          : const CleanReadResult(CleanReadOutcome.alreadyUnavailable, null);
    }

    List<ContentBlock>? blocks;
    try {
      // No timeout here, deliberately. ArticleExtractor.networkTimeout is the
      // only ceiling this operation gets — see its doc comment, and
      // summary_latency_test, for what a second one cost last time. What is
      // added here is a catch, not a clock: extract() throws on DNS failure,
      // TLS failure, a malformed URL and its own TimeoutException, and an
      // uncaught throw would escape the pane's initState as an unhandled
      // future error.
      blocks = await _extractor.extract(url);
    } catch (_) {
      blocks = null;
    }

    if (!isSubstantial(blocks)) {
      cache.put(url, null);
      return const CleanReadResult(CleanReadOutcome.unavailable, null);
    }

    cache.put(url, blocks);
    return CleanReadResult(CleanReadOutcome.ready, blocks);
  }
}
