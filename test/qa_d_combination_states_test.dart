// QA section D — combination states.
//
// `ways-of-working` records that eight interacting read-state rules, each
// specified correctly on its own and never modelled together, caused several
// regression cycles. This is that category: every rule below is already
// tested in isolation somewhere in this suite. None of them was tested
// **combined**, which is where they went wrong last time.
//
// The invariant the whole redesign rests on is the one to break here: **the
// list never moves under the reader.** No combination of states may change a
// card's height, a title's weight, or the number of lines it takes. Colour
// and layout-neutral fills only.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

const _longTitle =
    'Leader of Reform UK in Wales stands down after arrest on suspicion of '
    'assault, party confirms in a statement issued late on Monday evening';

Article _article({
  bool isRead = false,
  bool isSaved = false,
  bool thumbnail = true,
  bool longTitle = false,
}) =>
    Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: longTitle ? _longTitle : 'A headline',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch - 3600000,
      fetchedAt: 0,
      feedTitle: 'The Guardian',
      isRead: isRead,
      isSaved: isSaved,
      thumbnailUrl: thumbnail ? 'https://example.com/t.jpg' : null,
    );

final _themes = <String, ThemeData>{
  'Quiet Ink light': flashQuietInkTheme(brightness: Brightness.light),
  'Quiet Ink dark': flashQuietInkTheme(brightness: Brightness.dark),
  'Newspaper': flashNewspaperTheme(),
};

Future<Size> _pumpCard(
  WidgetTester tester,
  ThemeData theme,
  Article article, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: locale,
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('en'), Locale('de'), Locale('es'), Locale('fr'), Locale('it'),
    ],
    home: Scaffold(
      body: ListView(children: [
        ArticleCard(
          article: article,
          onTap: () {},
          onMarkRead: () {},
          onMarkUnread: () {},
          onShare: () {},
          onBookmark: () {},
        ),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(ArticleCard));
}

/// Every state a card can actually be holding at once.
final _combinations = <String, Article>{
  'plain': _article(),
  'read': _article(isRead: true),
  'saved': _article(isSaved: true),
  'read + saved': _article(isRead: true, isSaved: true),
  'no thumbnail': _article(thumbnail: false),
  'read + no thumbnail': _article(isRead: true, thumbnail: false),
  'read + saved + no thumbnail':
      _article(isRead: true, isSaved: true, thumbnail: false),
};

void main() {
  _themes.forEach((themeName, theme) {
    group(themeName, () {
      testWidgets('read state never changes the card height', (tester) async {
        // The invariant. If a read card is a different height from an unread
        // one, every card below it moves the instant mark-read-on-scroll
        // fires — which is the bug the whole "list never moves" rule exists
        // to prevent.
        final unread = await _pumpCard(tester, theme, _article());
        final read = await _pumpCard(tester, theme, _article(isRead: true));
        expect(read.height, unread.height, reason: themeName);
      });

      testWidgets('nor does saved state, alone or with read', (tester) async {
        final plain = await _pumpCard(tester, theme, _article());
        for (final entry in {
          'saved': _article(isSaved: true),
          'read + saved': _article(isRead: true, isSaved: true),
        }.entries) {
          final size = await _pumpCard(tester, theme, entry.value);
          expect(size.height, plain.height,
              reason: '$themeName: "${entry.key}" changed the row height');
        }
      });

      testWidgets('every combination renders without throwing',
          (tester) async {
        for (final entry in _combinations.entries) {
          await _pumpCard(tester, theme, entry.value);
          expect(tester.takeException(), isNull,
              reason: '$themeName / ${entry.key}');
        }
      });

      testWidgets('a long title wraps without changing weight',
          (tester) async {
        // Weight is the other way a list moves: a lighter glyph is narrower,
        // so a title near a wrap boundary reflows and everything below slides.
        final short = await _pumpCard(tester, theme, _article());
        final long = await _pumpCard(tester, theme, _article(longTitle: true));
        expect(long.height, greaterThan(short.height),
            reason: '$themeName: a long title must actually wrap, or this '
                'test is measuring nothing');

        final readLong =
            await _pumpCard(tester, theme, _article(longTitle: true, isRead: true));
        expect(readLong.height, long.height,
            reason: '$themeName: a long title that reflows on read is the '
                'worst case of the moving-list bug, because the movement is '
                'a whole line rather than a pixel');
      });

      testWidgets('the missing-thumbnail case keeps the row height',
          (tester) async {
        // The placeholder is a fill, not an absence: a card with no image
        // must occupy the same space as one with an image, or a feed of
        // mixed articles becomes a ragged column that reflows as thumbnails
        // load in.
        final withImage = await _pumpCard(tester, theme, _article());
        final without = await _pumpCard(tester, theme, _article(thumbnail: false));
        expect(without.height, withImage.height, reason: themeName);
      });
    });
  });

  group('switching locale does not reflow the card', () {
    // The reader-open version of this needs a device; what can be checked
    // here is the part that would actually move the list — whether a
    // different locale's relative timestamp changes the row height.
    testWidgets('all five locales give the same card height', (tester) async {
      final theme = flashQuietInkTheme(brightness: Brightness.light);
      final heights = <String, double>{};
      for (final code in ['en', 'de', 'es', 'fr', 'it']) {
        final size =
            await _pumpCard(tester, theme, _article(), locale: Locale(code));
        heights[code] = size.height;
      }
      expect(heights.values.toSet(), hasLength(1),
          reason: 'a locale whose timestamp wraps to a second line would '
              'change the row height for every card at once: $heights');
    });
  });

  group('switching theme does not reflow the card', () {
    testWidgets('Quiet Ink light and dark are identical in layout',
        (tester) async {
      // Newspaper is deliberately excluded: it changes the font family, so a
      // different height there is correct rather than a bug.
      final light = await _pumpCard(
          tester, flashQuietInkTheme(brightness: Brightness.light), _article());
      final dark = await _pumpCard(
          tester, flashQuietInkTheme(brightness: Brightness.dark), _article());
      expect(dark.height, light.height,
          reason: 'switching theme with the list on screen must not move it');
    });
  });
}
