// The domain-matching rule behind the embedded reader's ad/tracker blocking.
//
// Every sub-resource an article page requests is decided by this, so the two
// ways it can be wrong both matter and are both pinned here: letting a
// tracker through (a miss), and blocking a host that merely *looks* like one
// (an over-match, which breaks real pages and is the harder failure to
// notice, because the page just quietly loses a script).
//
// Built from entry lists written here rather than the shipped asset — this
// covers the rule, not the contents of the list, which is expected to grow.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/ad_blocklist.dart';

void main() {
  group('exact host matches', () {
    final list = AdBlocklist.fromEntries(['doubleclick.net', 'criteo.com']);

    test('a host that is the entry itself is blocked', () {
      expect(list.blocks(Uri.parse('https://doubleclick.net/pixel.gif')), isTrue);
    });

    test('a host on the list is blocked whatever the scheme or path', () {
      expect(list.blocks(Uri.parse('http://criteo.com')), isTrue);
      expect(list.blocks(Uri.parse('https://criteo.com/a/b/c?d=e')), isTrue);
    });

    test('matching ignores case', () {
      expect(list.blocks(Uri.parse('https://DoubleClick.NET/x')), isTrue);
    });

    test('an unrelated host is allowed', () {
      expect(list.blocks(Uri.parse('https://bbc.co.uk/news')), isFalse);
    });
  });

  group('subdomain matches', () {
    final list = AdBlocklist.fromEntries(['doubleclick.net']);

    test('a direct subdomain is blocked', () {
      expect(list.blocks(Uri.parse('https://ads.doubleclick.net/x')), isTrue);
    });

    test('a deeply nested subdomain is blocked', () {
      expect(
        list.blocks(Uri.parse('https://a.b.c.doubleclick.net/x')),
        isTrue,
      );
    });
  });

  group('lookalike hosts are not blocked', () {
    final list = AdBlocklist.fromEntries(['doubleclick.net', 'media.net']);

    test('a host that merely ends with the entry text is allowed', () {
      expect(
        list.blocks(Uri.parse('https://notdoubleclick.net/x')),
        isFalse,
        reason: 'the entry must match on a label boundary, not any suffix',
      );
    });

    test('a host with the entry embedded mid-name is allowed', () {
      expect(list.blocks(Uri.parse('https://doubleclick.net.evil.com/x')),
          isFalse);
      expect(list.blocks(Uri.parse('https://mydoubleclick.net/x')), isFalse);
    });

    test('a different site under the same TLD is allowed', () {
      expect(
        list.blocks(Uri.parse('https://mynews.net/article')),
        isFalse,
        reason: 'media.net must not turn every .net host into a tracker',
      );
    });
  });

  group('host+path entries', () {
    // Entries like facebook.com/tr name a tracking endpoint on a host that is
    // otherwise legitimate — blocking the bare host would take the site with
    // it.
    final list = AdBlocklist.fromEntries(['facebook.com/tr', 'mc.yandex.ru']);

    test('the named path is blocked', () {
      expect(list.blocks(Uri.parse('https://facebook.com/tr?id=1')), isTrue);
    });

    test('the rest of the same host is allowed', () {
      expect(list.blocks(Uri.parse('https://facebook.com/somepage')), isFalse);
      expect(list.blocks(Uri.parse('https://facebook.com/')), isFalse);
    });

    test('a plain host entry alongside path entries still works', () {
      expect(list.blocks(Uri.parse('https://mc.yandex.ru/watch/1')), isTrue);
    });
  });

  group('degenerate input', () {
    test('an empty list blocks nothing', () {
      final empty = AdBlocklist.fromEntries(const []);
      expect(empty.blocks(Uri.parse('https://doubleclick.net')), isFalse);
      expect(empty.isEmpty, isTrue);
    });

    test('a url with no host is allowed rather than throwing', () {
      final list = AdBlocklist.fromEntries(['doubleclick.net']);
      expect(list.blocks(Uri.parse('about:blank')), isFalse);
      expect(list.blocks(Uri.parse('data:text/html,hi')), isFalse);
    });

    test('blank and whitespace entries are discarded, not matched', () {
      final list = AdBlocklist.fromEntries(['  ', '', ' criteo.com ']);
      expect(list.blocks(Uri.parse('https://criteo.com')), isTrue,
          reason: 'a padded entry should still be usable');
      expect(list.blocks(Uri.parse('https://example.com')), isFalse);
    });
  });

  group('the shipped list', () {
    test('parses, and splits host entries from host+path entries', () {
      // Guards the shape the loader depends on rather than the exact
      // contents: entries with a slash have to land in hostPaths, or
      // facebook.com/tr would be stored as a host and never match anything.
      final list = AdBlocklist.fromEntries([
        'doubleclick.net',
        'facebook.com/tr',
        'yandex.ru/metrika',
      ]);
      expect(list.hosts, contains('doubleclick.net'));
      expect(list.hostPaths, contains('facebook.com/tr'));
      expect(list.hosts, isNot(contains('facebook.com/tr')));
    });
  });
}
