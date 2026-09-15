// Pass 10: B2, and the three smaller tablet items.
//
// **The default is the assertion that matters here.** `isCurrent` exists for
// one surface — the three-column shell's middle column — and the phone and
// Bookmarks must come out byte-for-byte unchanged. That is proved two ways:
// the card's default is false, and `FeedScreen` can only ever pass true when
// `ArticleDetailScope` is above it, which nothing but the three-column shell
// installs. The second is the one that survives somebody adding a call site.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

Article _article() => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      feedTitle: 'The Guardian',
    );

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  bool? isCurrent,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: ListView(children: [
        // `isCurrent` omitted entirely when null, which is what makes the
        // default-off test a test of the default rather than of `false`.
        isCurrent == null
            ? ArticleCard(
                article: _article(),
                onTap: () {},
                onMarkRead: () {},
                onMarkUnread: () {},
                onShare: () {},
                onBookmark: () {},
              )
            : ArticleCard(
                article: _article(),
                isCurrent: isCurrent,
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
}

/// The card's own row container — the outermost Container inside the card,
/// which is the one `isCurrent` paints.
Container _row(WidgetTester tester) => tester.widget<Container>(
      find
          .descendant(of: find.byType(ArticleCard), matching: find.byType(Container))
          .first,
    );

String _code(String source) {
  final withoutBlocks =
      source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
  return const LineSplitter()
      .convert(withoutBlocks)
      .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
      .join(' ');
}

void main() {
  final themes = <String, ThemeData>{
    'light': flashQuietInkTheme(brightness: Brightness.light),
    'dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  themes.forEach((name, theme) {
    group(name, () {
      testWidgets('by default the row paints nothing at all', (tester) async {
        // Not "paints surface" — **null**. A row that painted its own opaque
        // background would cover whatever the list is drawn on and hide the
        // divider under it.
        await _pump(tester, theme);
        expect(_row(tester).color, isNull,
            reason: '$name: the default must be no fill, so the phone and '
                'Bookmarks are byte-for-byte unchanged');
      });

      testWidgets('isCurrent: false is the same as omitting it',
          (tester) async {
        await _pump(tester, theme, isCurrent: false);
        expect(_row(tester).color, isNull);
      });

      testWidgets('isCurrent: true paints surfaceContainer', (tester) async {
        await _pump(tester, theme, isCurrent: true);
        expect(_row(tester).color, theme.colorScheme.surfaceContainer,
            reason: name);
      });

      testWidgets('and NOT primaryContainer', (tester) async {
        // The teal tint is already inside this row, on the action rail. A
        // teal row makes the rail vanish into its own background and the card
        // reads as pressed rather than as current.
        await _pump(tester, theme, isCurrent: true);
        expect(_row(tester).color, isNot(theme.colorScheme.primaryContainer),
            reason: '$name: a current row must not borrow the interactive '
                'colour');
      });

      testWidgets('the action rail is untouched inside a current row',
          (tester) async {
        // One treatment, not two stacked. The rail keeps its own tint whether
        // or not the row it sits in is the current one.
        await _pump(tester, theme, isCurrent: false);
        final normal = tester
            .widget<Material>(find
                .descendant(
                    of: find.byTooltip('Summary'), matching: find.byType(Material))
                .first)
            .color;

        await _pump(tester, theme, isCurrent: true);
        final current = tester
            .widget<Material>(find
                .descendant(
                    of: find.byTooltip('Summary'), matching: find.byType(Material))
                .first)
            .color;

        expect(current, normal, reason: '$name: the rail changed with the row');
        expect(current, theme.colorScheme.primaryContainer);
      });

      testWidgets('a current row renders without throwing', (tester) async {
        await _pump(tester, theme, isCurrent: true);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('where the value comes from', () {
    // Per rule 10.2: the group above proves things about a card this file
    // built. These prove things about the app.

    final feed = File('lib/screens/feed_screen.dart').readAsStringSync();

    test('only FeedScreen passes isCurrent, and only from the shell', () {
      final setters = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path == 'lib/widgets/article_card.dart') continue;
        if (_code(entity.readAsStringSync()).contains('isCurrent:')) {
          setters.add(path);
        }
      }
      expect(setters, ['lib/screens/feed_screen.dart'],
          reason: 'Bookmarks, Alerts and search must keep the default. '
              'Found: $setters');
    });

    test('the flag can only be true under a three-column shell', () {
      // **This is the structural proof that a phone build never sets it.**
      // `_currentUrl` is filled from `ArticleDetailScope.maybeOf(context)`,
      // which the three-column shell installs and nothing else does, so it is
      // null everywhere there is no reading pane.
      final code = _code(feed);
      expect(code, contains('ArticleDetailScope.maybeOf(context)'));
      expect(code, contains('_currentUrl != null && article.url == _currentUrl'),
          reason: 'the null check is what makes the phone case false rather '
              'than accidentally-equal');
    });

    test('the screen subscribes once, not once per row', () {
      // A card reaching for the scope itself would be fifty widgets listening
      // to one controller and rebuilding together.
      final code = _code(feed);
      expect(RegExp(r'addListener\(_onCurrentArticleChanged\)')
          .allMatches(code), hasLength(1));
      // **Two removals, and both are load-bearing.** One in `dispose`, and one
      // in `didChangeDependencies` before attaching to a new controller —
      // without that second one, a shell that handed over a different
      // controller would leave this screen listening to the old one forever.
      // Expected 1 first and it failed on correct code.
      expect(RegExp(r'removeListener\(_onCurrentArticleChanged\)')
          .allMatches(code), hasLength(2),
          reason: 'one detach before re-subscribing, one on dispose; a '
              'missing removal leaks the screen past its route');
    });

    test('ArticleCard never reads the scope itself', () {
      expect(_code(File('lib/widgets/article_card.dart').readAsStringSync()),
          isNot(contains('ArticleDetailScope')),
          reason: 'finding out which article the pane holds is the shell\'s '
              'job, not the card\'s');
    });
  });

  group('the three items that were already correct', () {
    // Verified rather than changed. Recorded as assertions so "already
    // correct in pass 10" survives as something a future edit has to break
    // rather than as a sentence in a report.

    test('2.1 the resize grip takes onSurfaceMuted at 3dp', () {
      final app = _code(File('lib/app.dart').readAsStringSync());
      expect(app, contains('final grip = theme.flashColors.onSurfaceMuted'),
          reason: '6.6 gives this drag affordance an authored answer; nothing '
              'adjacent should be derived instead');
      expect(app, contains('width: 3'));
      expect(app, contains('shape: BoxShape.circle'));
    });

    test('2.2 the Alerts badge is the unread orange, not a leftover', () {
      // 1.6 is canonical: the count carries unread state, which is one of
      // orange's two permitted meanings. Both call sites pass no colour, so
      // the theme is the single answer — which is what stopped it being
      // Material's default `error` red.
      final theme = File('lib/theme/app_theme.dart').readAsStringSync();
      expect(theme, contains('backgroundColor: scheme.secondary'));
      expect(theme, contains('textColor: scheme.onSecondary'));

      final app = _code(File('lib/app.dart').readAsStringSync());
      expect(app, isNot(contains('Badge.count(count: _alertsCount, backgroundColor')),
          reason: 'a colour at the call site would bypass the theme entry and '
              'let the two badges drift apart');
    });

    test('2.3 swapSides is an entry in the column, not a bar button', () {
      // Pass 6 corrected the ARB description that called it a navigation-bar
      // button. This asserts the code matches the corrected description.
      final app = _code(File('lib/app.dart').readAsStringSync());
      expect(app, contains('_SwapSidesButton(onPressed: onSwapSides!)'));
      expect(app, contains('if (onSwapSides != null) _SwapSidesButton'),
          reason: 'pinned below the scrollable destinations rather than among '
              'them — a short window must not be able to scroll the control '
              'that moves the bar out of reach');
    });
  });
}
