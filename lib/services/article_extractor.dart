import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/content_block.dart';

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

  static final _junkClassIdPattern = RegExp(
    r'ad|advertisement|banner|sidebar|related|share|social|comment|reply|'
    r'newsletter|subscribe|cookie|popup|modal|overlay|promo|widget|menu|breadcrumb',
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
    final doc = html_parser.parse(body);
    final baseUrl = url;

    _removeJunk(doc);

    final contentEl = _findMainContent(doc);
    if (contentEl == null) return null;

    final blocks = _walkElement(contentEl, baseUrl);

    // Filter tracker images
    final filtered = blocks.where((b) {
      if (b is ImageBlock) {
        if (b.src.length < 50 && _trackerPattern.hasMatch(b.src)) return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) return null;
    return filtered;
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
      } else if (tag == 'div' || tag == 'section' || tag == 'article' || tag == 'main') {
        _visitChildren(node, baseUrl, blocks);
      }
    }
  }
}
