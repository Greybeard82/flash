import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/article_extractor.dart';
import 'package:flash/services/clean_article_cache.dart';
import 'package:flash/services/clean_reader.dart';

/// Comfortably over SummarySource.isSubstantial's 400-character floor.
final _longProse = 'Sentence about the thing. ' * 40;

/// Subclassing rather than a mock package: this repo has no mockito or
/// mocktail, and ArticleExtractor is a plain class with one method worth
/// faking.
class _FakeExtractor extends ArticleExtractor {
  final List<ContentBlock>? Function(String url) _result;
  int calls = 0;

  _FakeExtractor(this._result);

  /// Always throws whatever [error] is.
  factory _FakeExtractor.throwing(Object error) =>
      _FakeExtractor((_) => throw error);

  @override
  Future<List<ContentBlock>?> extract(String url) async {
    calls++;
    return _result(url);
  }
}

void main() {
  setUp(CleanArticleCache.instance.clear);

  group('verdicts', () {
    test('substantial content is ready and lands in the cache', () async {
      final extractor = _FakeExtractor((_) => [ParagraphBlock(_longProse)]);

      final result = await CleanReader(extractor: extractor)
          .load('https://example.com/a');

      expect(result.outcome, CleanReadOutcome.ready);
      expect(result.blocks, isNotNull);
      expect(CleanArticleCache.instance.get('https://example.com/a'), isNotNull);
    });

    test('too little text is unavailable, and the failure is cached', () async {
      final extractor = _FakeExtractor((_) => [ParagraphBlock('Too short.')]);

      final result = await CleanReader(extractor: extractor)
          .load('https://example.com/a');

      expect(result.outcome, CleanReadOutcome.unavailable);
      expect(result.blocks, isNull);
      expect(
          CleanArticleCache.instance.contains('https://example.com/a'), isTrue);
      expect(CleanArticleCache.instance.get('https://example.com/a'), isNull);
    });

    test('null from the extractor is unavailable', () async {
      final result = await CleanReader(extractor: _FakeExtractor((_) => null))
          .load('https://example.com/a');

      expect(result.outcome, CleanReadOutcome.unavailable);
    });

    test('an empty block list is unavailable', () async {
      final result = await CleanReader(extractor: _FakeExtractor((_) => []))
          .load('https://example.com/a');

      expect(result.outcome, CleanReadOutcome.unavailable);
    });
  });

  // extract() throws rather than returning null on network trouble, and this
  // runs from the pane's initState — an uncaught throw would surface as an
  // unhandled future error while the reader is opening.
  group('extraction never throws out of load()', () {
    test('a socket failure becomes unavailable', () async {
      final result = await CleanReader(
              extractor: _FakeExtractor.throwing(
                  const SocketException('no route to host')))
          .load('https://example.com/a');

      expect(result.outcome, CleanReadOutcome.unavailable);
    });

    test('a timeout becomes unavailable', () async {
      final result = await CleanReader(
              extractor: _FakeExtractor.throwing(TimeoutException('too slow')))
          .load('https://example.com/a');

      expect(result.outcome, CleanReadOutcome.unavailable);
    });
  });

  group('the cache prevents a second fetch', () {
    test('a repeated success is served from cache', () async {
      final extractor = _FakeExtractor((_) => [ParagraphBlock(_longProse)]);
      final reader = CleanReader(extractor: extractor);

      await reader.load('https://example.com/a');
      final second = await reader.load('https://example.com/a');

      expect(second.outcome, CleanReadOutcome.ready);
      expect(second.blocks, isNotNull);
      expect(extractor.calls, 1, reason: 'the page must not be fetched twice');
    });

    test('a repeated failure is alreadyUnavailable and refetches nothing',
        () async {
      final extractor = _FakeExtractor((_) => [ParagraphBlock('Short.')]);
      final reader = CleanReader(extractor: extractor);

      final first = await reader.load('https://example.com/a');
      final second = await reader.load('https://example.com/a');

      expect(first.outcome, CleanReadOutcome.unavailable);
      expect(second.outcome, CleanReadOutcome.alreadyUnavailable,
          reason: 'the banner must not fire again for the same URL');
      expect(extractor.calls, 1,
          reason: 'a deterministic parse must not be retried over the network');
    });
  });

  group('the substantiality gate', () {
    test('measures untruncated text', () {
      // fromBlocks truncates at 2500 chars by default. The gate must measure
      // the whole article, so that a threshold change later cannot be silently
      // capped by the summariser's prompt budget.
      final huge = [ParagraphBlock('word ' * 20000)];
      expect(CleanReader.isSubstantial(huge), isTrue);
    });

    test('399 characters is not substantial, 500 is', () {
      expect(CleanReader.isSubstantial([ParagraphBlock('x' * 399)]), isFalse);
      expect(CleanReader.isSubstantial([ParagraphBlock('x' * 500)]), isTrue);
    });

    test('null and empty are not substantial', () {
      expect(CleanReader.isSubstantial(null), isFalse);
      expect(CleanReader.isSubstantial([]), isFalse);
    });

    test('images alone are not substantial', () {
      expect(
          CleanReader.isSubstantial([ImageBlock('https://example.com/x.jpg')]),
          isFalse);
    });
  });
}
