// The keyword badges under an Alerts-tab card.
//
// Four rules, all of them things that went wrong at least once:
//
//   1. At most three chips, then a "+N" summarising the rest. A card matching
//      six keywords must not become a wall of chips.
//   2. Chips are sorted, so the same card shows the same three every time —
//      which three survive the cut must be a property of the keyword set, not
//      of the order the query happened to return rows in.
//   3. A long keyword is truncated rather than allowed to eat the row.
//   4. The row's height does not change with read state. Read state is carried
//      by colour and opacity alone; anything that changes layout when a card
//      is marked read slides the whole list under the user's finger.
//
// And one that is really a layout bug this pins: a chip hugs its label. The
// Container drawing it originally set `alignment: Alignment.center`, which
// installs an Align that grows to its incoming constraints — and those are
// loose, coming from Flexible — so a single badge stretched the full width of
// the card and read as a banner rather than a badge.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

const double _cardWidth = 400;

Article _article() => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'Nintendo teases new Zelda game',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: false,
      feedTitle: 'Example Feed',
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<String> keywords,
  bool isRead = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashPaletteTheme(palette: 'orange', brightness: Brightness.dark),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SizedBox(
        width: _cardWidth,
        // A ListView so the card reports its intrinsic height rather than
        // expanding to fill the viewport — see article_card_layout_test.dart.
        child: ListView(
          children: [
            ArticleCard(
              article: _article().copyWith(isRead: isRead),
              alertKeywords: keywords,
              onTap: () {},
              onMarkRead: () {},
              onMarkUnread: () {},
              onShare: () {},
              onBookmark: () {},
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The text of every chip, in the order they are laid out.
List<String> _chipLabels(WidgetTester tester) {
  final labels = <String>[];
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final data = widget.data;
    if (data == null) continue;
    // The card also renders the title, the feed name and the timestamp; chips
    // are matched by being the ones inside the badge row, which is the only
    // place labelSmall + w600 is used.
    if (widget.style?.fontWeight == FontWeight.w600 &&
        widget.maxLines == 1 &&
        widget.overflow == TextOverflow.ellipsis) {
      labels.add(data);
    }
  }
  return labels;
}

void main() {
  testWidgets('one keyword renders one chip', (tester) async {
    await _pump(tester, keywords: ['zelda']);
    expect(_chipLabels(tester), ['zelda']);
  });

  testWidgets('a chip hugs its label instead of filling the card',
      (tester) async {
    await _pump(tester, keywords: ['zelda']);

    final chip = find.ancestor(
      of: find.text('zelda'),
      matching: find.byType(Container),
    );
    final width = tester.getSize(chip.first).width;

    expect(width, lessThan(_cardWidth / 2),
        reason: 'a single badge stretching the width of the card reads as a '
            'banner, not a badge — this is what `alignment: Alignment.center` '
            'on the chip Container did');
    expect(width, greaterThan(0));
  });

  testWidgets('four keywords render three chips plus +1', (tester) async {
    await _pump(tester, keywords: ['zelda', 'mario', 'nintendo', 'switch']);

    final labels = _chipLabels(tester);
    expect(labels, hasLength(4), reason: 'three keywords plus the overflow');
    expect(labels.last, '+1');
  });

  testWidgets('six keywords still render three chips, summarised as +3',
      (tester) async {
    await _pump(tester,
        keywords: ['a-one', 'b-two', 'c-three', 'd-four', 'e-five', 'f-six']);

    final labels = _chipLabels(tester);
    expect(labels, ['a-one', 'b-two', 'c-three', '+3']);
  });

  testWidgets('which three survive the cut is stable, not query order',
      (tester) async {
    await _pump(tester, keywords: ['zelda', 'mario', 'nintendo', 'switch']);
    final first = _chipLabels(tester);

    // Same set, different order in.
    await _pump(tester, keywords: ['switch', 'nintendo', 'mario', 'zelda']);
    expect(_chipLabels(tester), first,
        reason: 'the same card must not show "zelda, mario" one refresh and '
            '"mario, zelda" the next');
  });

  testWidgets('a keyword longer than 14 characters is truncated',
      (tester) async {
    await _pump(tester, keywords: ['nintendo switch 2 pro']);

    final labels = _chipLabels(tester);
    expect(labels, hasLength(1));
    expect(labels.single, 'nintendo switc…',
        reason: '14 characters then an ellipsis — cut before layout, so the '
            'chip that gets shortened is the long one rather than whichever '
            'happens to sit last');
  });

  testWidgets('badge row height is identical read and unread', (tester) async {
    await _pump(tester, keywords: ['zelda', 'mario']);
    final unread = tester.getSize(find.byType(ArticleCard)).height;

    await _pump(tester, keywords: ['zelda', 'mario'], isRead: true);
    final read = tester.getSize(find.byType(ArticleCard)).height;

    expect(read, unread,
        reason: 'read state is colour and opacity only. A height change here '
            'slides every card below it while the user is mid-scroll');
  });

  testWidgets('no keywords renders no chips and no empty gap', (tester) async {
    await _pump(tester, keywords: const []);
    expect(_chipLabels(tester), isEmpty);

    final withBadges = await (() async {
      await _pump(tester, keywords: ['zelda']);
      return tester.getSize(find.byType(ArticleCard)).height;
    })();
    await _pump(tester, keywords: const []);
    final without = tester.getSize(find.byType(ArticleCard)).height;

    expect(without, lessThan(withBadges),
        reason: 'a card with no alert keywords must not reserve the row');
  });
}
