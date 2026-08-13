// SummarySource tests.
//
// Written independently of the implementation. Builds the plain-text body that
// gets handed to the on-device model. The bug this fixes: the summary sheet
// previously sent `article.description ?? title` — an RSS teaser — so the model
// summarised the teaser, not the article.
//
// Covered behaviours:
//  1. Full extracted body is flattened to plain text, in document order
//  2. Images are dropped; their captions are not treated as prose
//  3. Headings, quotes and list items survive as readable text
//  4. Output is capped, and truncation happens on a sentence/word boundary
//  5. Empty or image-only extraction falls back to the RSS description
//  6. Whitespace is normalised so the model isn't fed blank-line noise

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/content_block.dart';
import 'package:flash/services/summary_source.dart';

void main() {
  group('flattening', () {
    test('keeps paragraphs in document order', () {
      final text = SummarySource.fromBlocks([
        ParagraphBlock('First paragraph.'),
        ParagraphBlock('Second paragraph.'),
        ParagraphBlock('Third paragraph.'),
      ]);
      expect(text.indexOf('First'), lessThan(text.indexOf('Second')));
      expect(text.indexOf('Second'), lessThan(text.indexOf('Third')));
    });

    test('includes headings as text', () {
      final text = SummarySource.fromBlocks([
        HeadingBlock(2, 'Background'),
        ParagraphBlock('Body text.'),
      ]);
      expect(text, contains('Background'));
      expect(text, contains('Body text.'));
    });

    test('includes quotes', () {
      final text = SummarySource.fromBlocks([
        QuoteBlock('We had no choice, she said.'),
      ]);
      expect(text, contains('We had no choice'));
    });

    test('flattens list items', () {
      final text = SummarySource.fromBlocks([
        ListBlock(ordered: false, items: ['Alpha', 'Beta', 'Gamma']),
      ]);
      expect(text, contains('Alpha'));
      expect(text, contains('Beta'));
      expect(text, contains('Gamma'));
    });

    test('drops images entirely', () {
      final text = SummarySource.fromBlocks([
        ParagraphBlock('Real prose.'),
        ImageBlock('https://example.com/photo.jpg',
            caption: 'A photo of the scene'),
      ]);
      expect(text, contains('Real prose.'));
      expect(text, isNot(contains('example.com')));
      expect(text, isNot(contains('A photo of the scene')));
    });
  });

  group('whitespace', () {
    test('collapses runs of blank lines and trims', () {
      final text = SummarySource.fromBlocks([
        ParagraphBlock('   Leading and trailing.   '),
        ParagraphBlock('\n\n\n'),
        ParagraphBlock('Next.'),
      ]);
      expect(text.trim(), text);
      expect(text, isNot(contains('\n\n\n')));
      expect(text, contains('Leading and trailing.'));
    });
  });

  group('capping', () {
    test('short bodies pass through untouched', () {
      final text = SummarySource.fromBlocks(
        [ParagraphBlock('Short body.')],
        maxChars: 6000,
      );
      expect(text, 'Short body.');
    });

    test('long bodies are capped at maxChars', () {
      final long = List.generate(
        400,
        (i) => ParagraphBlock('Sentence number $i is here and it is padding.'),
      );
      final text = SummarySource.fromBlocks(long, maxChars: 1000);
      expect(text.length, lessThanOrEqualTo(1000));
      expect(text.length, greaterThan(500),
          reason: 'should use most of the budget, not truncate early');
    });

    test('truncation does not split a word', () {
      final long = [ParagraphBlock('word ' * 500)];
      final text = SummarySource.fromBlocks(long, maxChars: 100);
      expect(text.endsWith('wor'), isFalse);
      expect(text.trim().split(' ').last, anyOf('word', '…', 'word…'));
    });

    test('default cap matches the native trim', () {
      expect(SummarySource.defaultMaxChars, 2500,
          reason: 'Matches the native trim; larger inputs dominate Nano TTFT.');
    });
  });

  group('fallbacks', () {
    test('empty block list falls back to the description', () {
      final text = SummarySource.fromBlocks(
        const [],
        fallback: 'RSS teaser text.',
      );
      expect(text, 'RSS teaser text.');
    });

    test('null block list falls back to the description', () {
      final text = SummarySource.fromBlocks(
        null,
        fallback: 'RSS teaser text.',
      );
      expect(text, 'RSS teaser text.');
    });

    test('image-only extraction falls back to the description', () {
      final text = SummarySource.fromBlocks(
        [ImageBlock('https://example.com/a.jpg')],
        fallback: 'RSS teaser text.',
      );
      expect(text, 'RSS teaser text.');
    });

    test('whitespace-only extraction falls back to the description', () {
      final text = SummarySource.fromBlocks(
        [ParagraphBlock('   '), ParagraphBlock('\n')],
        fallback: 'RSS teaser text.',
      );
      expect(text, 'RSS teaser text.');
    });

    test('no blocks and no fallback yields an empty string', () {
      expect(SummarySource.fromBlocks(const [], fallback: null), '');
    });

    test('a usable body is preferred over the fallback', () {
      final text = SummarySource.fromBlocks(
        [ParagraphBlock('The full article body goes here.')],
        fallback: 'RSS teaser text.',
      );
      expect(text, contains('full article body'));
      expect(text, isNot(contains('teaser')));
    });
  });

  group('adequacy check', () {
    test('reports whether the body is substantial enough to summarise', () {
      expect(SummarySource.isSubstantial('word ' * 200), isTrue);
      expect(SummarySource.isSubstantial('Too short.'), isFalse);
      expect(SummarySource.isSubstantial(''), isFalse);
    });
  });
}
