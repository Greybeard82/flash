// The shape of the starter pack itself.
//
// This is the list a brand-new user's entire first impression is built from,
// and the app was pulled from Google Play for showing that user nothing. A bad
// entry here — a typo'd URL, a duplicate, an http:// link Android will block —
// does not fail loudly; it seeds a category that is quietly empty, which is
// precisely the screen the reviewer wrote up.
//
// Deliberately offline. `starter_pack_live_test.dart` is the one that proves
// the feeds still publish; this one proves the data is well-formed, and runs
// on every `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/data/starter_pack.dart';

void main() {
  test('the five categories are present, in display order', () {
    expect(
      kStarterPack.map((c) => c.id).toList(),
      ['world_news', 'tech', 'fitness_health', 'travel', 'sports'],
    );
  });

  test('category ids are unique', () {
    final ids = kStarterPack.map((c) => c.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('every category carries at least two feeds', () {
    // One publisher going quiet must not empty a category. The two exceptions
    // are David's call of 11 Sep 2026, taken when the live gate could find no
    // second feed for either that clears the 7-day fetch window — see
    // kSingleFeedStarterCategories. Anything *not* on that list holding one
    // feed is an accident, and fails here.
    final thin = kStarterPack
        .where((c) => c.feeds.length < 2)
        .map((c) => c.id)
        .toSet();
    expect(thin.difference(kSingleFeedStarterCategories), isEmpty,
        reason: 'a category dropped below two feeds without being declared a '
            'known exception');
    expect(kStarterPack.every((c) => c.feeds.isNotEmpty), isTrue,
        reason: 'an empty category is the bug this whole pass exists to fix');
  });

  test('the single-feed exceptions are still exceptions', () {
    // Stops the allow-list outliving the problem: once a second feed is added,
    // the entry has to go, or the rule above silently stops guarding that
    // category.
    for (final id in kSingleFeedStarterCategories) {
      final category = kStarterPack.firstWhere((c) => c.id == id);
      expect(category.feeds, hasLength(1),
          reason: '$id now has ${category.feeds.length} feeds — remove it from '
              'kSingleFeedStarterCategories');
    }
  });

  test('every feed URL and site URL is absolute https', () {
    for (final category in kStarterPack) {
      for (final feed in category.feeds) {
        for (final raw in [feed.url, feed.siteUrl]) {
          final uri = Uri.parse(raw);
          expect(uri.isAbsolute, isTrue, reason: '$raw is not absolute');
          // http:// is blocked by the app's network security config on a
          // modern Android, so a plain-http entry seeds a feed that can never
          // fetch.
          expect(uri.scheme, 'https', reason: '$raw is not https');
          expect(uri.host, isNotEmpty, reason: '$raw has no host');
        }
      }
    }
  });

  test('no feed URL appears twice in the pack', () {
    // `feeds.url` is UNIQUE, and the service skips a URL that already exists —
    // so a duplicate inside the pack would not crash, it would silently put
    // the feed in whichever category was seeded first and leave the other
    // short.
    final urls = [
      for (final category in kStarterPack)
        for (final feed in category.feeds) feed.url,
    ];
    expect(urls.toSet(), hasLength(urls.length),
        reason: 'duplicate feed URL in the starter pack');
  });

  test('every feed has a title and a description', () {
    // The description is what the Categories screen shows under the feed, and
    // the picker builds its subtitle from the titles.
    for (final category in kStarterPack) {
      for (final feed in category.feeds) {
        expect(feed.title.trim(), isNotEmpty);
        expect(feed.description.trim(), isNotEmpty);
      }
    }
  });

  test('breakingmuscle.com is not in the pack', () {
    // Its feed stopped building on 4 Mar 2025: it parses, returns items, and
    // every one of them is refused by the 7-day fetch window. Exactly the kind
    // of feed that reads as fine in review and ships an empty category.
    final urls = [
      for (final category in kStarterPack)
        for (final feed in category.feeds) '${feed.url} ${feed.siteUrl}',
    ].join(' ');
    expect(urls, isNot(contains('breakingmuscle.com')));
  });
}
