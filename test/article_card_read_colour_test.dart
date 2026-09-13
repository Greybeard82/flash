// A read article title is a different colour, and exactly the same shape.
//
// Two assertions that have to hold together, and the second is the one with
// history behind it.
//
// **Colour.** Read state used to be `onSurface` at 45% alpha. Quiet Ink gives
// it a named role, `FlashColors.onSurfaceRead`, because alpha cannot express
// the palette: 45% ink over a white page and 45% ink over a near-black one are
// two different greys, and neither is the one that was specified.
//
// **Weight.** It does not change, and this file is where that is enforced.
// The title is w600 read or unread. It used to drop to w400 when read, and
// lighter glyphs are narrower, so a title sitting near a wrap boundary
// reflowed from three lines to two the instant mark-read-on-scroll fired: the
// card lost a line of height and every card below it slid up under the
// reader's eyes, mid-scroll, with no gesture to explain it. That is the app's
// central invariant — the list never moves under the reader — and it has a
// whole MANUAL_QA section of its own.
//
// The Quiet Ink spec asks for w300 on read titles. That is a *larger* step
// than the w400 that caused the bug, so it was not adopted; the lighter
// reading comes from the colour instead. This test pins that decision so it
// cannot be quietly reversed, and so the next person to read the spec finds
// out why the code disagrees with it.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

/// Long enough to wrap, which is where a weight change would bite.
const String _title =
    'A headline long enough to wrap across three separate lines inside the '
    'card, which is exactly where a weight change would reflow it';

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

Future<void> _pump(
  WidgetTester tester, {
  required bool isRead,
  required Brightness brightness,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashQuietInkTheme(brightness: brightness),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
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
  await tester.pumpAndSettle();
}

/// The title's resolved style. `AnimatedDefaultTextStyle` is what carries it,
/// so reading the Text widget's own style would come back null.
TextStyle _titleStyle(WidgetTester tester) {
  final finder = find.ancestor(
    of: find.text(_title),
    matching: find.byType(DefaultTextStyle),
  );
  return tester.widget<DefaultTextStyle>(finder.first).style;
}

void main() {
  for (final brightness in Brightness.values) {
    final theme = flashQuietInkTheme(brightness: brightness);
    final flash = theme.extension<FlashColors>()!;
    final name = brightness.name;

    group(name, () {
      testWidgets('an unread title is full-strength ink', (tester) async {
        await _pump(tester, isRead: false, brightness: brightness);
        expect(_titleStyle(tester).color, theme.colorScheme.onSurface);
      });

      testWidgets('a read title takes the named read role', (tester) async {
        await _pump(tester, isRead: true, brightness: brightness);
        final colour = _titleStyle(tester).color;
        expect(colour, flash.onSurfaceRead);
        // Belt and braces: the role must not have been wired to the same
        // value as unread ink, which would make the test above pass while
        // read state became invisible.
        expect(colour, isNot(theme.colorScheme.onSurface));
      });

      testWidgets('read state is carried by colour, never by weight',
          (tester) async {
        await _pump(tester, isRead: false, brightness: brightness);
        final unread = _titleStyle(tester);

        await _pump(tester, isRead: true, brightness: brightness);
        final read = _titleStyle(tester);

        expect(read.fontWeight, unread.fontWeight,
            reason: 'a lighter weight is a narrower glyph, which reflows a '
                'wrapped title and slides every card below it up under the '
                'reader mid-scroll. The spec asks for w300 here; it is not '
                'adopted, deliberately');
        expect(read.fontWeight, FontWeight.w600);
        expect(read.height, unread.height,
            reason: 'line height cannot move either');
        expect(read.fontSize, unread.fontSize);
      });
    });
  }

  testWidgets('the two brightnesses use different read greys', (tester) async {
    // #79817F light, #87908F dark. If these ever collapsed to one value it
    // would mean the role had been wired to a single hex rather than the
    // palette, and one of the two themes would be wrong.
    final light =
        flashQuietInkTheme(brightness: Brightness.light).extension<FlashColors>()!;
    final dark =
        flashQuietInkTheme(brightness: Brightness.dark).extension<FlashColors>()!;
    expect(light.onSurfaceRead, isNot(dark.onSurfaceRead));
  });
}
