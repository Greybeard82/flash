// Regression cover for the self-adjusting article list.
//
// Scrolling slowly, a card would grey out as it passed the midpoint and the
// entire list below it would shift, costing the user their place. The cause
// was in the title style: it dropped from w600 to w400 when read, lighter
// glyphs are narrower, and a title sitting near a wrap boundary reflowed from
// three lines to two. The card lost a line of height and everything below it
// slid up — with no gesture to explain it.
//
// IMPORTANT — read before changing these assertions.
//
// The primary assertion is on the resolved fontWeight, NOT on rendered
// height. flutter_test renders with a test font whose glyphs all share
// identical metrics, so a weight change produces no measurable size
// difference in a widget test. A height-equality test would therefore have
// passed just as happily BEFORE the fix as after it, and caught nothing.
// The style assertion is font-independent and is the one that actually
// pins the contract. Do not "simplify" it into a size check.
//
// The height check below is kept only as a coarse sanity check on the rest
// of the card — padding, maxLines, conditional widgets — where a real
// difference WOULD show up under the test font.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

/// Long enough to wrap, which is where the reflow used to happen.
const String _title =
    'A headline long enough to wrap across three separate lines inside the '
    'card, which is exactly where the reflow used to bite';

Article _article({required bool isRead}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: _title,
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: isRead,
      feedTitle: 'Example Feed',
    );

Future<void> _pump(WidgetTester tester, {required bool isRead}) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashPaletteTheme(palette: 'orange', brightness: Brightness.light),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      // Width pinned so both states wrap against identical constraints; the
      // ListView gives the card genuinely unbounded height so it reports its
      // intrinsic size.
      //
      // This used to be an Align, which passes a *bounded* height — the card's
      // Column is mainAxisSize.max, so it expanded to fill the viewport and
      // every measurement came back as 900.0. The height assertion below was
      // comparing 900 to 900 and had proven nothing since pass 04.
      body: SizedBox(
        width: 400,
        child: ListView(
          children: [
            ArticleCard(
              article: _article(isRead: isRead),
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
  // Settle the dim animation so we measure the resting state, not a frame
  // partway through it.
  await tester.pumpAndSettle();
}

TextStyle _titleStyle(WidgetTester tester) {
  // `.first` is the *innermost* matching ancestor, which is the card's own
  // title style. Material (via Scaffold) wraps its subtree in an
  // AnimatedDefaultTextStyle of its own, so a bare ancestor finder here
  // matches two and throws "Too many elements" — and the outer one is w400,
  // the very value this test exists to prove the title no longer uses.
  final animated = tester.widget<AnimatedDefaultTextStyle>(
    find
        .ancestor(
          of: find.text(_title),
          matching: find.byType(AnimatedDefaultTextStyle),
        )
        .first,
  );
  return animated.style;
}

void main() {
  testWidgets('the title weight does not depend on read state', (tester) async {
    await _pump(tester, isRead: false);
    final unread = _titleStyle(tester);

    expect(unread.fontWeight, FontWeight.w600,
        reason: 'anchors the finder to the card\'s own style rather than the '
            'framework w400 one Material wraps the Scaffold in. Without this '
            'the equality below can pass by matching two wrong values, and '
            'the test reports green while proving nothing.');

    await _pump(tester, isRead: true);
    final read = _titleStyle(tester);

    expect(read.fontWeight, unread.fontWeight,
        reason: 'font weight changes glyph width, which changes wrapping, '
            'which changes card height — the list shifts under the user '
            'mid-scroll. Read state must be carried by colour and opacity '
            'alone.');
  });

  testWidgets('read state is still visible, via colour', (tester) async {
    await _pump(tester, isRead: false);
    final unread = _titleStyle(tester);

    await _pump(tester, isRead: true);
    final read = _titleStyle(tester);

    expect(read.color, isNot(unread.color),
        reason: 'dropping the weight change must not also drop the visual '
            'distinction between read and unread');
  });

  testWidgets('nothing else in the card changes its height when read',
      (tester) async {
    await _pump(tester, isRead: false);
    final unreadHeight = tester.getSize(find.byType(ArticleCard)).height;

    await _pump(tester, isRead: true);
    final readHeight = tester.getSize(find.byType(ArticleCard)).height;

    // Sanity bound first: if the harness ever lets the card expand to the
    // viewport again, both numbers become identical and the equality below
    // passes while measuring nothing. Real cards are 96.8dp and 121.9dp on a
    // Pixel 11 Pro, so this range is generous and still catches that.
    expect(unreadHeight, inInclusiveRange(60, 300),
        reason: 'a card outside this range means the harness is measuring the '
            'viewport, not the card — the failure mode that hid this '
            'assertion for four passes');
    expect(readHeight, inInclusiveRange(60, 300));

    expect(readHeight, unreadHeight,
        reason: 'padding, maxLines or a conditional widget varying on '
            'isRead would shift every card below this one');
  });
}
