// The reader's bar lost its title line, gained three buttons, and kept its
// second line.
//
// The two lines are the source at `titleSmall` and the date at `labelSmall`.
// They were briefly joined into one `publisher · date` line, and the date was
// cut on every article — four buttons leave the text about 160dp, which is
// enough for "Sky Sports · Sep 15, 2026 9:44 …" and no more. Dropping the
// *title* was right for a different reason and stands: 160dp of headline is a
// stub, 160dp of source name is a whole name.
//
// **The height is the assertion that matters most, and it is the least
// obvious.** On the tablet this pane holds a platform view: a bar that changed
// height would resize the WebView mid-read, reflowing the page and throwing
// away the reader's scroll position. The four IconButtons set a 48dp floor and
// the 4dp vertical padding takes it to 56 — which is what the column measured
// with a title and a date, then with a source alone, and now with a source and
// a date. That is a coincidence of Material's defaults rather than a
// guarantee, which is why it is pinned as a number rather than trusted.
//
// The pane needs a WebView it cannot have in a test, so every case here goes
// through `webViewOverrideForTesting` — the seam that already exists for
// `article_detail_pane_clean_mode_test.dart`, not one added for this file.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/services/saved_state_notifier.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_detail_pane.dart';

/// What the bar measures, in every layout. 48dp of IconButton plus 4dp of
/// padding above and below.
const double kReaderBarHeight = 56.0;

Article _article({
  int? id = 1,
  String? feedTitle = 'The Guardian (World)',
  int? publishedAt = 1773000000000,
  bool isSaved = false,
  String url = 'https://www.theguardian.com/world/a-story',
}) =>
    Article(
      id: id,
      feedId: 1,
      guid: 'g1',
      title: 'A headline that is far too long to have ever fitted in the bar',
      url: url,
      publishedAt: publishedAt,
      fetchedAt: 0,
      isSaved: isSaved,
      feedTitle: feedTitle,
    );

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  Article? article,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: theme,
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: ArticleDetailPane(
        article: article ?? _article(),
        onClose: () {},
        cleanModeEnabledForTesting: false,
        webViewOverrideForTesting: (_) => const SizedBox.expand(),
      ),
    ),
  ));
  await tester.pump();
}

/// The bar is the Material that wraps the SafeArea at the top of the pane.
double _barHeight(WidgetTester tester) => tester
    .getSize(find.ancestor(
      of: find.byType(SafeArea),
      matching: find.byType(Material),
    ).first)
    .height;

void main() {
  final themes = <String, ThemeData>{
    'light': flashQuietInkTheme(brightness: Brightness.light),
    'dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  themes.forEach((name, theme) {
    group(name, () {
      testWidgets('the bar is 56dp, with the title line gone', (tester) async {
        await _pump(tester, theme: theme);
        expect(_barHeight(tester), kReaderBarHeight,
            reason: '$name: the bar changed height. On the tablet that '
                'resizes the platform view mid-read and the page reflows.');
      });

      testWidgets('56dp holds when the bookmark is absent', (tester) async {
        // One fewer button, and the floor is still the remaining three.
        await _pump(tester, theme: theme, article: _article(id: null));
        expect(_barHeight(tester), kReaderBarHeight);
      });

      testWidgets('and when there is no attribution to draw at all',
          (tester) async {
        await _pump(tester,
            theme: theme,
            article: _article(feedTitle: null, publishedAt: null));
        expect(_barHeight(tester), kReaderBarHeight);
      });

      testWidgets('the article title is not in the bar', (tester) async {
        // The decision, asserted. A stub of a headline is worse than none,
        // and the page under the bar carries the real one.
        await _pump(tester, theme: theme);
        expect(
            find.text(
                'A headline that is far too long to have ever fitted in the bar'),
            findsNothing,
            reason: '$name: the title line came back');
      });

      testWidgets('the source is line 1, titleSmall in the full ink',
          (tester) async {
        await _pump(tester, theme: theme);
        final text = tester.widget<Text>(
            find.textContaining('The Guardian (World)').first);

        // Pinned to the literal, not to `theme.textTheme.titleSmall.fontSize`,
        // which is **null** on a raw ThemeData — Quiet Ink leaves sizes to
        // Material's ramp and the ramp is applied during localization. That
        // comparison would have been null against 14.0 and failed on correct
        // code; it did, first time. Handoff 11.1 records the trap.
        expect(text.style?.fontSize, 14.0,
            reason: '$name: titleSmall is 14 in the M3 ramp');
        expect(text.style?.color, theme.colorScheme.onSurface,
            reason: '$name: the source is the headline text of the bar');
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
      });

      testWidgets('the date is line 2, labelSmall in muted ink',
          (tester) async {
        // **The line that came back, and the reason it did.** Joined onto the
        // source as `publisher · date`, it was the half that got cut — on
        // every article, because four buttons leave the text about 160dp.
        await _pump(tester, theme: theme);
        final date = tester.widget<Text>(find.textContaining('2026').first);

        expect(date.style?.fontSize, 11.0,
            reason: '$name: labelSmall is 11 in the M3 ramp');
        expect(date.style?.color, theme.flashColors.onSurfaceMuted,
            reason: '$name: the date recedes behind the source above it');
      });

      testWidgets('both lines are present together', (tester) async {
        // The assertion the two above cannot make separately: a bar showing
        // only one of them would satisfy whichever test matched.
        await _pump(tester, theme: theme);
        expect(find.textContaining('The Guardian (World)'), findsOneWidget);
        expect(find.textContaining('2026'), findsOneWidget);
      });

      testWidgets('all four actions are present', (tester) async {
        await _pump(tester, theme: theme);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
        expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
        expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      });

      testWidgets('saved is the filled glyph in secondary', (tester) async {
        // 1.6 is canonical on this, and it is the same treatment the action
        // rail uses, so a bookmark means one thing in the list and in the
        // reader.
        await _pump(tester, theme: theme, article: _article(isSaved: true));
        final icon =
            tester.widget<Icon>(find.byIcon(Icons.bookmark_rounded));
        expect(icon.color, theme.colorScheme.secondary);
        expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      });

      testWidgets('unsaved passes no colour, so it matches its neighbours',
          (tester) async {
        // Deliberately null rather than an explicit onSurfaceVariant: the
        // close and open-in-browser glyphs beside it take M3's IconButton
        // default, and hardcoding the same value here would be a second copy
        // of it that could drift.
        await _pump(tester, theme: theme);
        final icon =
            tester.widget<Icon>(find.byIcon(Icons.bookmark_border_rounded));
        expect(icon.color, isNull);
      });
    });
  });

  group('the attribution', () {
    final theme = flashQuietInkTheme(brightness: Brightness.light);

    testWidgets('falls back to the host, without www.', (tester) async {
      // With the title line gone this is the bar's only text, and both halves
      // of it are nullable on Article. The host is always available — it is
      // what was opened — and it is what Chrome shows in the same position.
      await _pump(tester,
          theme: theme,
          article: _article(
            feedTitle: null,
            publishedAt: null,
            url: 'https://www.theguardian.com/world/a-story',
          ));

      expect(find.text('theguardian.com'), findsOneWidget,
          reason: 'www. is four characters of nothing in a bar this narrow');
    });

    testWidgets('a blank feed title is as empty as a null one', (tester) async {
      // `feedTitle` is trimmed before the join, so whitespace does not sneak
      // past the fallback as a non-empty string.
      await _pump(tester,
          theme: theme,
          article: _article(
              feedTitle: '   ',
              publishedAt: null,
              url: 'https://example.com/x'));
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('the host takes line 1 and the date keeps line 2',
        (tester) async {
      // Changed deliberately in 8c. While the two were joined, an article
      // with a date and no publisher showed the date alone and never reached
      // the fallback. Split, line 1 is the source slot and an article with no
      // publisher has a host to put in it — which is more useful than a
      // date floating on its own.
      await _pump(tester,
          theme: theme,
          article: _article(
              feedTitle: null, url: 'https://www.example.com/x'));
      expect(find.text('example.com'), findsOneWidget);
      expect(find.textContaining('2026'), findsOneWidget);
    });
  });

  group('what truncates, and what survives', () {
    // **The fix this pass exists for.** Joined as `publisher \u00b7 date`, the
    // text had about 160dp on a 360dp phone with four buttons, and the date
    // was the half that got cut \u2014 on every article, not just long ones.
    // Split onto two lines, the truncation falls on the source, which is where
    // it can be afforded, and it falls at the end of the name rather than
    // taking the date with it.
    //
    // Measured with `TextPainter` at the width the bar actually gives the
    // column. `flutter_test` substitutes a font whose every glyph is a full
    // em, so text measures roughly twice as wide here as in Instrument Sans —
    // and **that cuts one way and not the other**, which is worth saying
    // plainly because it is easy to claim more than it supports:
    //
    //   * "this FITS under the stub" ⟹ it fits on a device. Sound. Every
    //     assertion this group actually relies on is of that shape.
    //   * "this OVERFLOWS under the stub" ⟹ nothing about a device. The one
    //     assertion below of that shape exists only to prove the ellipsis
    //     path is being exercised rather than passing because everything
    //     fits. The evidence that a real bar truncates is a screenshot from
    //     the M51, not this.

    final theme = flashQuietInkTheme(brightness: Brightness.light);

    /// The width the bar hands its text column, read off the render tree
    /// rather than assumed.
    double columnWidth(WidgetTester tester) =>
        tester.getSize(find.byType(Column).first).width;

    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    testWidgets('the longest starter-pack source keeps its masthead',
        (tester) async {
      // "The New York Times (World)" is the longest title in the starter pack
      // at 26 characters. What has to survive is the newspaper, not the
      // parenthetical \u2014 so the assertion names the string that must fit,
      // rather than checking that something did.
      await _pump(tester,
          theme: theme,
          article: _article(feedTitle: 'The New York Times (World)'));

      final rendered =
          tester.widget<Text>(find.text('The New York Times (World)'));
      final style = rendered.style!;
      final available = columnWidth(tester);

      expect(widthOf('The New York Times', style), lessThanOrEqualTo(available),
          reason: 'the masthead itself must fit. If this fails the bar is '
              'showing "The New York Ti\u2026" and naming nothing.');

      // And the full string genuinely does not fit, so this test is measuring
      // a real truncation rather than passing because everything fits.
      expect(widthOf('The New York Times (World)', style),
          greaterThan(available),
          reason: 'if the whole name fits, the ellipsis is doing nothing and '
              'the assertion above is not being tested');

      expect(rendered.overflow, TextOverflow.ellipsis);
      expect(rendered.maxLines, 1);
    });

    testWidgets('the date never truncates, in any locale', (tester) async {
      // Scanned across all five rather than assuming which is longest \u2014 and
      // the assumption would have been wrong. German has longer month names
      // but a 24-hour clock, so it comes out at 20 characters where **English**
      // reaches 21 with its " PM".
      await _pump(tester, theme: theme);
      final style = tester.widget<Text>(find.textContaining('2026')).style!;
      final available = columnWidth(tester);

      // The worst case each locale can produce: a long month, a two-digit day
      // and a two-digit hour.
      const candidates = <String>[
        'Sep 25, 2026 10:48 PM', // en, 21
        'Dec 28, 2026 11:59 PM', // en
        '25. Sept. 2026 22:48', // de, 20
        '25 sept. 2026 22:48', // fr, 19
        '25 sept 2026 22:48', // es, 18
        '25 set 2026 22:48', // it, 17
      ];

      for (final date in candidates) {
        expect(widthOf(date, style), lessThanOrEqualTo(available),
            reason: '"$date" does not fit the ${available.toStringAsFixed(1)}dp '
                'the bar gives the date. It is on its own line precisely so '
                'that it does not have to compete with the source.');
      }
    });

    testWidgets('and the date fits even beside the longest source',
        (tester) async {
      // The two lines are independent, so a long source cannot squeeze the
      // date \u2014 but that is exactly the kind of thing that stops being true
      // when someone puts them back in a Row.
      await _pump(tester,
          theme: theme,
          article: _article(feedTitle: 'The New York Times (World)'));

      final date = tester.widget<Text>(find.textContaining('2026'));
      final painter = TextPainter(
        text: TextSpan(text: date.data, style: date.style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: columnWidth(tester));

      expect(painter.didExceedMaxLines, isFalse,
          reason: 'the date was clipped next to a long source, which means '
              'the two lines are sharing a width again');
    });
  });

  group('the bookmark tells the truth', () {
    final theme = flashQuietInkTheme(brightness: Brightness.light);

    testWidgets('it follows a change made somewhere else', (tester) async {
      // The whole reason the pane listens. The same article can be unsaved
      // from the card's rail or the radial menu while the reader sits open
      // over them, and a bookmark button that lies about state is worse than
      // no bookmark button.
      await _pump(tester, theme: theme, article: _article(isSaved: false));
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);

      SavedStateNotifier.instance.articleSavedStateChanged(1, saved: true);
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget,
          reason: 'the reader did not follow an external save');
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
    });

    testWidgets('and ignores a change to a different article', (tester) async {
      // The notifier is a broadcast with no filtering of its own; every
      // listener does its own comparison. Without the id check this pane would
      // repaint its glyph whenever any row anywhere was bookmarked.
      await _pump(tester, theme: theme, article: _article(isSaved: false));

      SavedStateNotifier.instance.articleSavedStateChanged(999, saved: true);
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    });

    testWidgets('no bookmark button at all when the article has no id',
        (tester) async {
      // An article opened from the Alerts tab is built by
      // `AlertEntry.toArticle()` and carries a null id on purpose — identity
      // there is (feedId, guid). Nothing can be written without one, so the
      // button is absent rather than present and inert.
      await _pump(tester, theme: theme, article: _article(id: null));

      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget,
          reason: 'share needs no id and must survive');
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    });
  });

  group('the clean view toggle is untouched', () {
    // Section 3 of the brief: confirm rather than assume. It is a floating
    // extended FAB with a text label, appearing only when a clean version
    // exists, and it is NOT one of the four bar buttons. Losing its label to
    // the bar would cost the most-tapped control in the reader its name.
    testWidgets('no clean-mode glyph is in the bar', (tester) async {
      await _pump(tester, theme: flashQuietInkTheme(brightness: Brightness.light));
      expect(find.byIcon(Icons.auto_stories_rounded), findsNothing);
      expect(find.byIcon(Icons.public_rounded), findsNothing);
      expect(find.byKey(const ValueKey('cleanModeToggle')), findsNothing,
          reason: 'clean mode is off in this harness, so the FAB should be '
              'absent — which is also the conditional behaviour it must keep');
    });
  });
}
