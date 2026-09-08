import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/article_extractor.dart';
import 'package:flash/services/clean_article_cache.dart';
import 'package:flash/services/clean_reader.dart';

/// An extractor that takes its time, the way a real page fetch does.
class _SlowExtractor extends ArticleExtractor {
  final Duration delay;
  _SlowExtractor(this.delay);

  @override
  Future<List<ContentBlock>?> extract(String url) async {
    await Future<void>.delayed(delay);
    return [ParagraphBlock('Sentence about the thing. ' * 40)];
  }
}

void main() {
  setUp(CleanArticleCache.instance.clear);

  group('extraction has exactly one ceiling', () {
    test('CleanReader adds no timeout of its own', () {
      // The sibling of summary_latency_test's assertion, for the second caller
      // of extract(). Clean mode races the WebView's own load, which is exactly
      // the situation that tempts someone into "it should give up sooner than
      // eight seconds" — the mistake ArticleSummarySheet already made once,
      // where the tighter outer clock fired first almost every time and every
      // extraction was silently thrown away.
      expect(ArticleExtractor.networkTimeout, const Duration(seconds: 8),
          reason: 'There must be exactly one clock on this operation, owned '
              'by the extractor. CleanReader must not add a second.');
    });

    test('a 7s extraction still succeeds', () async {
      // Inside the extractor's own 8s ceiling, but well past any tighter one a
      // caller might add. If this ever fails, someone has wrapped
      // CleanReader.load or _extractor.extract in a timeout.
      final reader =
          CleanReader(extractor: _SlowExtractor(const Duration(seconds: 7)));

      final result = await reader.load('https://example.com/slow');

      expect(result.outcome, CleanReadOutcome.ready);
      expect(result.blocks, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
