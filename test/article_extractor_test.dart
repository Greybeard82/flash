// Coverage for two real bugs found by testing against live sites and fixed
// in the same pass:
//
// 1. `_junkClassIdPattern` used to include "widget" as a junk signal.
// Future plc's CMS (PC Gamer, TechRadar, GamesRadar) names every content
// section a "widget" — including the actual article body — so this one term
// deleted whole articles before content-scoring ever ran. "widget" was
// removed from the deletion pattern; these tests pin that a widget-classed
// element survives while genuine junk (ad/promo/sidebar-classed elements)
// still gets removed.
//
// 2. `_visitChildren`'s tag whitelist (p/h1-4/blockquote/ul/ol) missed real
// prose on sites that don't wrap paragraphs in any of those tags (confirmed
// on Kotaku). `extractFromHtml` now falls back to the content element's raw
// text when the tag-whitelist walk clearly captured much less than what's
// actually there. These tests construct that shape directly rather than
// asserting whatever the implementation happens to produce.

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/article_extractor.dart';

void main() {
  group('the "widget" junk-pattern false positive', () {
    test('a widget-classed wrapper around real content is not deleted', () {
      const html = '''
        <html><body>
          <article>
            <div class="widget-area widget-hero">
              <p>Real article text that must survive because a CMS calling
              its content wrapper a "widget" does not make it junk.</p>
            </div>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNotNull);
      final paragraphs = blocks!.whereType<ParagraphBlock>().map((b) => b.text);
      expect(paragraphs, contains(contains('Real article text')));
    });

    test('a genuinely junky ad/promo element is still removed', () {
      const html = '''
        <html><body>
          <article>
            <p>Real article text that must survive extraction because it is
            the actual body of the article being read, with enough real
            sentence content here to comfortably clear the two hundred
            character floor this selector requires before being trusted as
            genuine content.</p>
            <div class="ad-promo-banner">
              <p>Buy now! Limited time offer just for you today.</p>
            </div>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNotNull);
      final paragraphs = blocks!.whereType<ParagraphBlock>().map((b) => b.text);
      expect(paragraphs, isNot(contains(contains('Buy now'))),
          reason: 'ad/promo is still a junk signal on its own, independent of widget');
    });
  });

  group('the tag-whitelist fallback', () {
    test('real prose in non-whitelisted tags is recovered from raw text', () {
      const p1 = 'First paragraph text goes here with real sentence content '
          'about a topic to reach the length threshold quickly for this '
          'fallback test.';
      const p2 = 'Second paragraph continues the article with more distinct '
          'sentence content ensuring the raw text substantially exceeds the '
          'four hundred character floor used by this fallback check.';
      const p3 = 'Third paragraph adds even more real prose so that combined '
          'with the first and second paragraphs the total text length '
          'clearly passes the substantiality threshold used by this '
          'fallback logic today.';

      // No <p> tags at all — mirrors the real Kotaku markup this was
      // diagnosed against, where prose lives in bare <div>s.
      const html = '''
        <html><body>
          <article>
            <div>$p1</div>

            <div>$p2</div>

            <div>$p3</div>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNotNull);
      final paragraphs =
          blocks!.whereType<ParagraphBlock>().map((b) => b.text).toList();
      expect(paragraphs, [p1, p2, p3],
          reason: 'raw text split on blank-line boundaries should recover '
              'each paragraph separately, in order');
    });

    test('junk is still stripped before the raw-text fallback runs', () {
      const p1 = 'First paragraph text goes here with real sentence content '
          'about a topic to reach the length threshold quickly for this '
          'fallback test.';
      const p2 = 'Second paragraph continues the article with more distinct '
          'sentence content ensuring the raw text substantially exceeds the '
          'four hundred character floor used by this fallback check.';
      const p3 = 'Third paragraph adds even more real prose so that combined '
          'with the first and second paragraphs the total text length '
          'clearly passes the substantiality threshold used by this '
          'fallback logic today.';

      const html = '''
        <html><body>
          <article>
            <div class="sidebar">Unrelated sidebar text that must not leak
            into the extracted content.</div>
            <div>$p1</div>

            <div>$p2</div>

            <div>$p3</div>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNotNull);
      final combined =
          blocks!.whereType<ParagraphBlock>().map((b) => b.text).join('\n');
      expect(combined, isNot(contains('sidebar text')),
          reason: 'junk removal runs on the whole document before the '
              'fallback ever reads raw text, so it must not resurrect junk');
    });

    test('a normal article using real <p> tags is not touched by the fallback', () {
      const html = '''
        <html><body>
          <article>
            <p>A properly tagged paragraph that the ordinary tag-whitelist
            walk already captures correctly on its own.</p>
            <p>A second properly tagged paragraph, also captured normally
            without needing any fallback at all.</p>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNotNull);
      final paragraphs = blocks!.whereType<ParagraphBlock>().toList();
      expect(paragraphs, hasLength(2),
          reason: 'the walk already captured both paragraphs; the fallback '
              'must not fire and change the block boundaries');
      expect(paragraphs[0].text, startsWith('A properly tagged paragraph'));
      expect(paragraphs[1].text, startsWith('A second properly tagged'));
    });

    test('thin content in non-whitelisted tags is not padded out by the fallback', () {
      const html = '''
        <html><body>
          <article>
            <div>Too short to be worth summarising.</div>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNull,
          reason: 'raw text under the substantiality floor must not trigger '
              'the fallback — thin content should still be reported as thin');
    });

    test('a link-heavy related-articles block is not mistaken for real prose', () {
      // Mirrors a real, live Kotaku article: the identified content element's
      // raw text cleared the substantiality floor, but it was 100% byline,
      // comment count and a "You May Also Like" related-link list — zero
      // real body prose, because the page's actual paragraphs simply are not
      // present in the server-rendered HTML. Falling back to that raw text
      // would have hung a wall of unrelated headlines on the model as if it
      // were "the article."
      const html = '''
        <html><body>
          <article>
            <div>By Some Author | Comments (12)</div>
            <div>
              <a href="/a">Former Capcom Employee Says Western Studios Spend Too Much Time On Jira</a>
              <a href="/b">Kalshi Prematurely Pays Out Millions In Wagers For Losing College Football Team</a>
              <a href="/c">Buddy The Unicorn Kicked Out Of Universal Studios Halloween Horror Nights</a>
              <a href="/d">Marvel's Wolverine Ending Leaks Online In Final Stretch Ahead Of Launch</a>
              <a href="/e">Civilization 7's Biggest Free Update Yet Will Finally Take It To The Atomic Age</a>
            </div>
          </article>
        </body></html>
      ''';

      final blocks = ArticleExtractor().extractFromHtml(html, 'https://example.com/a');

      expect(blocks, isNull,
          reason: 'link-dominated text must not be treated as recovered '
              'article prose, no matter how long it is');
    });
  });
}
