import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/content_block.dart';
import 'summary_source.dart';

export '../models/content_block.dart';

class ArticleExtractor {
  static const _userAgent = 'Mozilla/5.0 (compatible; FlashReader/1.0)';

  /// The single ceiling on extraction: long enough for the large majority of
  /// real article pages (ads, tracking scripts, redirects and all) to
  /// resolve, short enough that a caller's "Reading article…" state doesn't
  /// feel broken while it waits. This used to race a second, tighter timeout
  /// in `ArticleSummarySheet` — that outer timeout fired first almost every
  /// time, extraction was abandoned before a real fetch could ever complete,
  /// and every summary silently fell back to the RSS teaser. Don't add
  /// another timeout around a call to [extract] elsewhere; this is the only
  /// one that should exist for this operation.
  static const Duration networkTimeout = Duration(seconds: 8);

  static final _junkTags = {
    'script', 'style', 'noscript', 'nav', 'footer', 'header',
    'aside', 'form', 'iframe', 'template',
  };

  // Every term is anchored with \b, and that is load-bearing. Unanchored,
  // these are substring matches that fire anywhere inside a longer word:
  // bare "ad" matched <html class="techradar"> and deleted entire pages,
  // and "sidebar" matched BBC's ContainerWithSidebarWrapper — a container
  // that *has* a sidebar, not one that is one. It also hit shadow, header,
  // download, thread, loaded and readability, so the damage was much wider
  // than the two sites that happened to expose it.
  //
  // \b sits at a word/non-word transition, so "techradar" — one unbroken
  // run of letters — no longer matches, while ad-container, google-ad and
  // "content ad-slot" still do, because hyphens and spaces are real
  // boundaries. Keep the anchors on anything added here.
  //
  // "widget" is deliberately absent, and anchoring would not have saved it:
  // Future plc's CMS names real content sections "widget" as a standalone
  // word, so that one is a genuine semantic collision rather than a
  // boundary problem, and removal was the right call for it.
  static final _junkClassIdPattern = RegExp(
    r'\bad\b|\badvertisement\b|\bbanner\b|\bsidebar\b|\brelated\b|\bshare\b|'
    r'\bsocial\b|\bcomment\b|\breply\b|\bnewsletter\b|\bsubscribe\b|'
    r'\bcookie\b|\bpopup\b|\bmodal\b|\boverlay\b|\bpromo\b|\bmenu\b|'
    r'\bbreadcrumb\b|'
    // End-of-article recirculation. Each term was checked against the saved
    // fixtures before being added: \bauthor\b and \bbio\b both hit
    // TechRadar's `author author__default-layout` and `slice-author-bio`
    // wrappers — the author photo and bio reported as junk — and \bpopular\b
    // hits its `popular-box` related-links rail.
    //
    // \bprofile\b was in the proposed list and is deliberately NOT here: it
    // occurs in none of the fixtures, so there was nothing to validate it
    // against, and it is the term most likely to collide with an article that
    // is *about* a profile. \bmeta\b is absent for the same reason — it
    // matched only IGN's `meta-items`, and a term that broad needs a page it
    // demonstrably helps before it earns a place beside the ones that deleted
    // whole pages twice already.
    r'\bauthor\b|\bbyline\b|\bbio\b|\brecirculation\b|\btaboola\b|'
    r'\boutbrain\b|\btrending\b|\bpopular\b|\brecommended\b|'
    r'\bmore-from\b|\bread-more\b|\bread-next\b|\byou-may-also\b|'
    r'\bnext-article\b|\bmost-read\b|\btags\b',
    caseSensitive: false,
  );

  static final _contentClassIdBonus = RegExp(
    r'article|content|post|entry|story|body|text|prose',
    caseSensitive: false,
  );

  static final _navClassIdPenalty = RegExp(
    r'nav|menu|sidebar|footer|header|ad|promo|widget',
    caseSensitive: false,
  );

  static final _trackerPattern = RegExp(r'pixel|beacon|track|1x1', caseSensitive: false);

  Future<List<ContentBlock>?> extract(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    ).timeout(networkTimeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    return extractFromHtml(body, url);
  }

  /// The HTML-parsing half of [extract], split out so it can be tested
  /// against constructed markup without a real network fetch.
  List<ContentBlock>? extractFromHtml(String html, String baseUrl) {
    final doc = html_parser.parse(html);

    _removeJunk(doc);

    final contentEl = _findMainContent(doc);
    if (contentEl == null) return null;

    var blocks = _walkElement(contentEl, baseUrl);

    // The tag-whitelist walk above only reads text out of p/h1-4/blockquote/
    // ul/ol — it recurses into div/section/article/main purely to find more
    // of those tags nested inside. Some sites' real prose isn't wrapped in
    // any of those tags at all, so the walk can come back thin even when the
    // already-correctly-identified content element's raw text holds much
    // more. When that gap is large, fall back to the element's raw text.
    //
    // That raw text is NOT automatically trustworthy, though: on a live
    // Kotaku article the "article" element's raw text was 100% byline,
    // comment count, a newsletter CTA and a "You May Also Like" related-link
    // list — zero real body prose, because Kotaku's actual paragraph content
    // isn't present in the server-rendered HTML at all for that page. Naively
    // falling back there would hand Nano a wall of unrelated headlines
    // dressed up as "the article." The one signal that reliably tells real
    // prose apart from a related-links block is link density — a related-
    // link list is almost entirely anchor text, while an article body has
    // only occasional inline links — so this reuses the same linkRatio
    // concept _findMainContent already scores candidates on, as a hard
    // reject here rather than a soft penalty.
    final rawText = contentEl.text.trim();
    final rawLinkText =
        contentEl.querySelectorAll('a').map((a) => a.text).join();
    final rawLinkRatio =
        rawText.isNotEmpty ? rawLinkText.length / rawText.length : 0.0;
    if (_blocksTextLength(blocks) < rawText.length / 2 &&
        SummarySource.isSubstantial(rawText) &&
        rawLinkRatio < 0.3) {
      final paragraphs = rawText
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      blocks = paragraphs.length > 1
          ? paragraphs.map((p) => ParagraphBlock(p)).toList()
          : [ParagraphBlock(rawText)];
    }

    blocks = _trimTrailingJunk(blocks);

    // Filter tracker images, and dedupe images by resolved src.
    //
    // A hero image routinely appears twice in server-rendered HTML — once as
    // a <figure> lead, once inside the body wrapper the walk later recurses
    // into. Confirmed on The Verge, where both saved fixtures emit the same
    // src twice in a row; TechRadar, BBC, IGN, Eurogamer and RPS emit none.
    // There is no legitimate case for rendering the identical asset twice in
    // one article. The first occurrence is kept, because that is the one
    // carrying the real caption, and later repeats are dropped however far
    // apart they are rather than only when adjacent.
    final seenImageSrcs = <String>{};
    final filtered = blocks.where((b) {
      if (b is ImageBlock) {
        if (b.src.length < 50 && _trackerPattern.hasMatch(b.src)) return false;
        if (!seenImageSrcs.add(b.src)) return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) return null;
    return filtered;
  }

  /// Headings that announce end-of-article recirculation rather than more
  /// article. Every entry beyond the obvious ones came from a real saved
  /// fixture: "Most Popular" and "More in:" from The Verge, "Related topics",
  /// "Related internet links" and "Get in touch" from the BBC.
  static final _recircHeading = RegExp(
    r'^(read (more|next)|more (from|on|stories|in)\b|related\b|you may also|'
    r'recommended|trending|most (read|popular)|sign up|subscribe|follow us|'
    r'about the author|get in touch|share this|more like this)',
    caseSensitive: false,
  );

  /// Drops trailing blocks that are end-of-article recirculation rather than
  /// article body: a heading that announces it and everything after it, then
  /// any trailing link rolls the walk flattened into lists, and trailing
  /// images such as an author portrait.
  ///
  /// Only ever trims from the end, and only looks inside the last 40%.
  /// Cutting mid-article on a heuristic risks truncating a real piece at its
  /// first subheading, which is a far worse failure than leaving some junk at
  /// the bottom — a how-to with a legitimate "Related settings" section early
  /// on must not lose everything after it. Across the saved fixtures the junk
  /// consistently begins 70-85% of the way through, so the window is wide
  /// enough to catch it and narrow enough to be safe.
  ///
  /// Within that window it takes the EARLIEST match, not the latest. The BBC
  /// ends with "Get in touch", "Related topics", a tag list and then "Related
  /// internet links"; cutting at the last match would strip one heading and
  /// leave the other three behind.
  List<ContentBlock> _trimTrailingJunk(List<ContentBlock> blocks) {
    if (blocks.isEmpty) return blocks;

    final windowStart = (blocks.length * 0.6).floor();
    var end = blocks.length;

    for (var i = windowStart; i < blocks.length; i++) {
      final b = blocks[i];
      if (b is HeadingBlock && _recircHeading.hasMatch(b.text.trim())) {
        end = i;
        break;
      }
    }

    while (end > 0 &&
        (blocks[end - 1] is ListBlock || blocks[end - 1] is ImageBlock)) {
      end--;
    }

    // Never trim away the article itself. If the heuristics would leave
    // nothing substantial they have misfired — keep everything, because
    // showing some junk beats silently truncating a real article to nothing.
    final trimmed = blocks.sublist(0, end);
    return SummarySource.isSubstantial(
      trimmed.whereType<ParagraphBlock>().map((p) => p.text).join(),
    )
        ? trimmed
        : blocks;
  }

  int _blocksTextLength(List<ContentBlock> blocks) {
    var total = 0;
    for (final block in blocks) {
      switch (block) {
        case HeadingBlock():
          total += block.text.length;
        case ParagraphBlock():
          total += block.text.length;
        case QuoteBlock():
          total += block.text.length;
        case ListBlock():
          total += block.items.join().length;
        case ImageBlock():
          break;
      }
    }
    return total;
  }

  void _removeJunk(Document doc) {
    // Remove by tag
    for (final tag in _junkTags) {
      for (final el in doc.querySelectorAll(tag).toList()) {
        el.remove();
      }
    }
    // Remove by class/id pattern
    for (final el in doc.querySelectorAll('[id],[class]').toList()) {
      final id = el.attributes['id'] ?? '';
      final cls = el.attributes['class'] ?? '';
      if (_junkClassIdPattern.hasMatch(id) || _junkClassIdPattern.hasMatch(cls)) {
        el.remove();
      }
    }
  }

  Element? _findMainContent(Document doc) {
    // Try specific content selectors first (most reliable)
    for (final selector in [
      '[itemprop="articleBody"]',
      '[role="article"]',
      'article',
      '.article-body',
      '.post-content',
      '.entry-content',
      '.article-content',
      '.story-body',
      '[role="main"]',
      'main',
    ]) {
      final el = doc.querySelector(selector);
      if (el != null && el.text.trim().length > 200) return el;
    }

    // Score divs and sections
    final candidates = doc.querySelectorAll('div, section');
    Element? best;
    double bestScore = double.negativeInfinity;

    for (final el in candidates) {
      final text = el.text.trim();
      final textLen = text.length;
      if (textLen < 100) continue;

      final pCount = el.querySelectorAll('p').length;
      final linkText = el.querySelectorAll('a').map((a) => a.text).join('');
      final linkTextLen = linkText.length;
      final linkRatio = textLen > 0 ? linkTextLen / textLen : 0.0;

      final classId = '${el.attributes['class'] ?? ''} ${el.attributes['id'] ?? ''}';
      final bonus = _contentClassIdBonus.hasMatch(classId) ? 20.0 : 0.0;
      final penalty = _navClassIdPenalty.hasMatch(classId) ? 20.0 : 0.0;

      final score = (pCount * 3) + (textLen / 80) - (linkRatio * 30) + bonus - penalty;

      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    return best;
  }

  List<ContentBlock> _walkElement(Element el, String baseUrl) {
    final blocks = <ContentBlock>[];
    _visitChildren(el, baseUrl, blocks);
    return blocks;
  }

  void _visitChildren(Element el, String baseUrl, List<ContentBlock> blocks) {
    for (final node in el.nodes) {
      if (node is! Element) continue;
      final tag = node.localName?.toLowerCase() ?? '';

      if (tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4') {
        final level = int.parse(tag.substring(1));
        final text = node.text.trim();
        if (text.isNotEmpty) blocks.add(HeadingBlock(level, text));
      } else if (tag == 'p') {
        final text = node.text.trim();
        if (text.length >= 20) blocks.add(ParagraphBlock(text));
      } else if (tag == 'blockquote') {
        final text = node.text.trim();
        if (text.isNotEmpty) blocks.add(QuoteBlock(text));
      } else if (tag == 'ul' || tag == 'ol') {
        final items = node.querySelectorAll('li')
            .map((li) => li.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (items.isNotEmpty) {
          blocks.add(ListBlock(ordered: tag == 'ol', items: items));
        }
      } else if (tag == 'img') {
        final src = node.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          final resolvedSrc = Uri.parse(baseUrl).resolve(src).toString();
          final alt = node.attributes['alt'];
          blocks.add(ImageBlock(resolvedSrc, caption: alt?.isNotEmpty == true ? alt : null));
        }
      } else if (tag == 'figure') {
        final img = node.querySelector('img');
        if (img != null) {
          final src = img.attributes['src'] ?? '';
          if (src.isNotEmpty) {
            final resolvedSrc = Uri.parse(baseUrl).resolve(src).toString();
            final caption = node.querySelector('figcaption')?.text.trim();
            blocks.add(ImageBlock(resolvedSrc, caption: caption?.isNotEmpty == true ? caption : null));
          }
        }
      } else if (tag == 'div' ||
          tag == 'section' ||
          tag == 'article' ||
          tag == 'main' ||
          tag == 'picture') {
        // 'picture' is here so a <picture><source...><img></picture> is
        // reached through one predictable path. Without it the wrapper was
        // skipped whole while a sibling <img> was still picked up, which is
        // one of the two ways the same asset arrived twice. TechRadar uses 45
        // of them on a single article page, the BBC 20.
        _visitChildren(node, baseUrl, blocks);
      }
    }
  }
}
