// Reading an OPML file.
//
// OPML is a format every reader claims to support and none implements the same
// way. Feedly, Inoreader and NetNewsWire all nest differently, disagree about
// whether a folder's name lives in `text` or `title`, and happily emit
// outlines that are not feeds at all. So this parser is deliberately
// permissive about structure and strict about one thing: an entry is a feed if
// and only if it has an `xmlUrl` that Flash can actually fetch.
//
// Pure. No database, no file system, no network — the DB half is
// opml_import_test.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/opml_service.dart';

/// What the Settings screen passes in from the ARB. Hardcoded here so these
/// tests do not need a Flutter binding to load localisations.
const _fallback = 'Imported';

List<OpmlFeedEntry> _parse(String source) =>
    OpmlService.parse(source, fallbackFolderName: _fallback);

void main() {
  group('nesting', () {
    test('feeds take the name of their folder outline', () {
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline text="Tech">
      <outline type="rss" text="Ars Technica"
               xmlUrl="https://feeds.arstechnica.com/arstechnica/index"
               htmlUrl="https://arstechnica.com"/>
      <outline type="rss" text="The Verge"
               xmlUrl="https://www.theverge.com/rss/index.xml"/>
    </outline>
  </body>
</opml>''');

      expect(entries, hasLength(2));
      expect(entries.every((e) => e.folderName == 'Tech'), isTrue);
      expect(entries.first.title, 'Ars Technica');
      expect(entries.first.xmlUrl,
          'https://feeds.arstechnica.com/arstechnica/index');
      expect(entries.first.siteUrl, 'https://arstechnica.com');
      // htmlUrl is optional and its absence must not invent one.
      expect(entries.last.siteUrl, isNull);
    });

    test('a top-level feed with no folder gets the fallback name', () {
      // Flat exports are common — Inoreader produces one for an account with
      // no folders. These feeds have to land somewhere nameable.
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline type="rss" text="BBC" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml"/>
  </body>
</opml>''');

      expect(entries, hasLength(1));
      expect(entries.single.folderName, _fallback);
    });

    test('three levels of nesting flatten to the top-level folder', () {
      // Flash has exactly one level of categories. Preserving deeper structure
      // is impossible without a schema change, and dropping the feeds would be
      // worse than flattening them, so the *top* ancestor wins — that is the
      // one the user recognises as the category.
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline text="News">
      <outline text="Europe">
        <outline text="UK">
          <outline type="rss" text="Guardian"
                   xmlUrl="https://www.theguardian.com/world/rss"/>
        </outline>
      </outline>
    </outline>
  </body>
</opml>''');

      expect(entries, hasLength(1));
      expect(entries.single.folderName, 'News',
          reason: 'the deepest ancestor "UK" must not become the category');
    });

    test('a folder outline uses title when text is absent', () {
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline title="Sport">
      <outline type="rss" text="BBC Sport"
               xmlUrl="https://feeds.bbci.co.uk/sport/rss.xml"/>
    </outline>
  </body>
</opml>''');

      expect(entries.single.folderName, 'Sport');
    });
  });

  group('feed naming', () {
    test('title wins over text', () {
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline type="rss" title="Proper Name" text="fallback"
             xmlUrl="https://example.com/feed.xml"/>
  </body>
</opml>''');

      expect(entries.single.title, 'Proper Name');
    });

    test('text is used when title is missing', () {
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline type="rss" text="Only Text" xmlUrl="https://example.com/feed.xml"/>
  </body>
</opml>''');

      expect(entries.single.title, 'Only Text');
    });

    test('the URL host is used when both are missing', () {
      // A nameless feed is still a feed. Showing the host beats showing an
      // empty row, and the user can rename it.
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline type="rss" xmlUrl="https://news.example.com/feed.xml"/>
  </body>
</opml>''');

      expect(entries.single.title, 'news.example.com');
    });

    test('a blank title falls through to text, then to the host', () {
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline type="rss" title="   " text="  "
             xmlUrl="https://blank.example.com/feed.xml"/>
  </body>
</opml>''');

      expect(entries.single.title, 'blank.example.com');
    });
  });

  group('what is skipped', () {
    test('outlines with no xmlUrl are not feeds', () {
      // Link outlines, text notes and empty folders all look like this.
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline text="Just a note"/>
    <outline type="link" text="A bookmark" url="https://example.com"/>
  </body>
</opml>''');

      expect(entries, isEmpty);
    });

    test('non-http schemes are skipped', () {
      // feed:// and ftp:// cannot be fetched by RssService, so importing them
      // would create feeds that are permanently broken.
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline type="rss" text="Feed scheme" xmlUrl="feed://example.com/rss"/>
    <outline type="rss" text="FTP" xmlUrl="ftp://example.com/rss.xml"/>
    <outline type="rss" text="Relative" xmlUrl="/rss.xml"/>
    <outline type="rss" text="Empty" xmlUrl=""/>
    <outline type="rss" text="Good" xmlUrl="http://example.com/rss.xml"/>
    <outline type="rss" text="Also good" xmlUrl="https://example.com/rss.xml"/>
  </body>
</opml>''');

      expect(entries.map((e) => e.title).toList(), ['Good', 'Also good'],
          reason: 'both http and https are accepted, nothing else is');
    });

    test('a URL repeated inside the file yields one entry', () {
      // Exports from readers that allow a feed in two folders produce this.
      // The first occurrence wins, so the feed keeps the first folder it
      // appeared under rather than jumping to the last.
      final entries = _parse('''
<opml version="2.0">
  <body>
    <outline text="First">
      <outline type="rss" text="Dup" xmlUrl="https://example.com/feed.xml"/>
    </outline>
    <outline text="Second">
      <outline type="rss" text="Dup again" xmlUrl="https://example.com/feed.xml"/>
    </outline>
  </body>
</opml>''');

      expect(entries, hasLength(1));
      expect(entries.single.folderName, 'First');
    });
  });

  group('bad input', () {
    test('malformed XML raises OpmlParseException', () {
      // The import path catches exactly this type to show the error banner, so
      // it must be a typed error and not a bare FormatException from the XML
      // package leaking through.
      expect(
        () => _parse('<opml><body><outline text="unclosed"></body>'),
        throwsA(isA<OpmlParseException>()),
      );
    });

    test('an empty string raises OpmlParseException', () {
      expect(() => _parse(''), throwsA(isA<OpmlParseException>()));
    });

    test('XML that is not OPML at all raises OpmlParseException', () {
      // Picking the wrong file is the likeliest mistake, and FileType.any
      // means nothing stops the user doing it.
      expect(
        () => _parse('<rss version="2.0"><channel></channel></rss>'),
        throwsA(isA<OpmlParseException>()),
      );
    });

    test('valid OPML containing no feeds parses to an empty list', () {
      // Not an error — the file is well-formed, it simply has nothing to
      // import. The caller decides what to say about that.
      final entries = _parse('<opml version="2.0"><body></body></opml>');
      expect(entries, isEmpty);
    });
  });
}
