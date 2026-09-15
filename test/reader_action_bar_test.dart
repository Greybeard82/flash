// The reader's bar lost its title line and gained three buttons.
//
// **The height is the assertion that matters most, and it is the least
// obvious.** On the tablet this pane holds a platform view: a bar that changed
// height would resize the WebView mid-read, reflowing the page and throwing
// away the reader's scroll position. The four IconButtons set a 48dp floor and
// the 4dp vertical padding takes it to 56 — which is exactly what the
// two-line title column measured before, so nothing moves. That is a
// coincidence of Material's defaults rather than a guarantee, which is why it
// is pinned as a number rather than trusted.
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

      testWidgets('the source is the only line, at titleSmall', (tester) async {
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
        expect(text.style?.fontSize, isNot(11.0),
            reason: '$name: 11 is labelSmall, which is where this line used '
                'to be. Promoting it is the change — it is no longer a '
                'caption under a title, it is what the bar says.');
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
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

    testWidgets('the date survives when there is no publisher',
        (tester) async {
      // Play policy wants source and date. Only the join being wholly empty
      // reaches the fallback.
      await _pump(tester,
          theme: theme, article: _article(feedTitle: null));
      expect(find.text('example.com'), findsNothing);
      expect(find.textContaining('2026'), findsOneWidget);
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
