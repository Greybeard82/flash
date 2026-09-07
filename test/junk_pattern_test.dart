// The class/id junk filter, and specifically the boundary bug that made it
// delete whole articles.
//
// Every term in that pattern used to be a bare substring, so `hasMatch`
// fired anywhere the letters appeared inside a longer word. Two real sites
// proved it, and both are pinned here as literal class strings taken from
// their live markup:
//
//   * TechRadar's root element is <html class="techradar">, and "techradar"
//     contains "ad". The filter deleted the document, so the site returned
//     nothing at all.
//   * BBC's article body sits inside ssrcss-...-ContainerWithSidebarWrapper,
//     which contains "Sidebar" — a container that *has* a sidebar slot, not
//     one that is a sidebar.
//
// The fix is word boundaries, not dropping the terms: "ad" and "sidebar"
// are two of the most accurate junk signals there are when they appear as
// actual words. So this file has to check both directions — that the real
// junk still matches, and that these lookalikes no longer do. A test that
// only checked the second half would pass on an empty pattern.
//
// The extractor is exercised through its public surface rather than the
// private RegExp: what matters is whether real content survives, which is
// the thing that was broken.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/article_extractor.dart';

/// Enough prose to clear the substantiality floor, so a test failing means
/// the filter ate the content rather than the content simply being thin.
const _body = '''
<p>Nvidia has confirmed that DLSS 5 will ship alongside the next driver
branch, with the company citing a rebuilt transformer model as the reason
for the jump in image stability at lower render resolutions.</p>
<p>The company says the new model runs at roughly the same cost as the
previous one, which is the detail that matters for anyone on older
hardware, since it means the feature is not restricted to the newest
cards in the range.</p>
<p>Independent testing is not available yet, and Nvidia has not published
per-game numbers, so the practical gain in any specific title remains
unmeasured for now.</p>
''';

List<String>? _extractParagraphs(String html) {
  final blocks =
      ArticleExtractor().extractFromHtml(html, 'https://example.com/a');
  return blocks?.whereType<ParagraphBlock>().map((b) => b.text).toList();
}

void main() {
  group('lookalike class names must not be treated as junk', () {
    test('TechRadar: "techradar" on the root element does not delete the page',
        () {
      // The exact shape that returned nothing: the site's own name, which
      // happens to contain "ad", on <html>. Deleting that element takes the
      // whole document with it.
      const html = '''
        <html class="techradar"><body class="news-page default_page_layout_news">
          <article>$_body</article>
        </body></html>
      ''';

      final paragraphs = _extractParagraphs(html);
      expect(paragraphs, isNotNull,
          reason: 'a class containing "ad" mid-word must not delete anything');
      expect(paragraphs!.join(' '), contains('DLSS 5'));
    });

    test('BBC: "ContainerWithSidebarWrapper" does not delete the article body',
        () {
      const html = '''
        <html><body>
          <div class="ssrcss-js09yk-ContainerWithSidebarWrapper e1jl38b40">
            <article>$_body</article>
          </div>
        </body></html>
      ''';

      final paragraphs = _extractParagraphs(html);
      expect(paragraphs, isNotNull,
          reason: '"Sidebar" mid-word in camelCase is not a sidebar');
      expect(paragraphs!.join(' '), contains('transformer model'));
    });

    test('other words that merely contain a junk term survive', () {
      // All of these matched the old unanchored pattern: shadow, header,
      // download, thread, loaded and readability all contain "ad".
      for (final cls in [
        'card-shadow',
        'page-header',
        'download-panel',
        'thread-list',
        'is-loaded',
        'readability-normal',
        'adaptive-grid',
      ]) {
        final html = '''
          <html><body><div class="$cls"><article>$_body</article></div></body></html>
        ''';
        expect(_extractParagraphs(html), isNotNull,
            reason: '"$cls" contains a junk term only mid-word');
      }
    });
  });

  group('real junk is still removed', () {
    // The other half of the fix. Anchoring must not have quietly disarmed
    // the filter — these are the cases it exists for.
    for (final cls in [
      'ad',
      'ad-container',
      'google-ad',
      'sidebar',
      'sidebar-widget',
      'cookie-banner',
      'social-share',
      'newsletter-signup',
      'related-posts',
      'main-menu',
      'promo-strip',
    ]) {
      test('"$cls" is stripped', () {
        final html = '''
          <html><body>
            <article>
              $_body
              <div class="$cls"><p>Subscribe now for unmissable offers and
              deals delivered straight to your inbox every single week.</p></div>
            </article>
          </body></html>
        ''';

        final paragraphs = _extractParagraphs(html);
        expect(paragraphs, isNotNull);
        expect(paragraphs!.join(' '), isNot(contains('Subscribe now')),
            reason: '"$cls" names real junk and must still be removed');
        expect(paragraphs.join(' '), contains('DLSS 5'),
            reason: 'the real article must survive alongside it');
      });
    }
  });
}
