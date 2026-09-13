// FlashColors has to resolve from any theme, including Newspaper's.
//
// The bug this pins reached the branch in pass 1 and was invisible until pass 2
// widened the blast radius. `FlashColors` is a ThemeExtension registered by
// `flashQuietInkTheme`, and the call sites read it as
// `theme.extension<FlashColors>()!` — a null check. Two themes in this app do
// not carry it:
//
//   * `flashNewspaperTheme()`, which registers no extensions at all. Newspaper
//     mode is a first-class setting, so every widget reading the extension
//     crashed the moment the user turned it on. The article card's read-title
//     colour, added in pass 1, was already in that position.
//   * any stock `ThemeData` — a widget test that pumps `MaterialApp()` with no
//     `theme:`, which is most of them.
//
// A crash is the worst possible failure for a colour lookup, so `flashColors`
// falls back instead of throwing, and Newspaper registers its own ink so it
// gets newsprint greys rather than a generic fallback.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';
import 'package:flash/widgets/article_detail_pane.dart';

Article _article({bool isRead = false}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: isRead,
      feedTitle: 'Example Feed',
    );

Future<void> _pump(WidgetTester tester, ThemeData? theme, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: ListView(children: [child])),
  ));
  await tester.pump();
}

void main() {
  group('every theme resolves the ink roles', () {
    test('Quiet Ink carries the extension outright', () {
      for (final b in Brightness.values) {
        expect(flashQuietInkTheme(brightness: b).extension<FlashColors>(),
            isNotNull);
      }
    });

    test('Newspaper carries one of its own', () {
      // Not the Quiet Ink values — newsprint is a different palette, and an
      // ink role borrowed from the teal theme would read as a bug on paper.
      final paper = flashNewspaperTheme();
      final ink = paper.extension<FlashColors>();
      expect(ink, isNotNull,
          reason: 'Newspaper mode is a setting a user can turn on; a widget '
              'that reads the extension must not crash there');
      expect(ink!.onSurfaceMuted,
          isNot(flashQuietInkTheme(brightness: Brightness.light).extension<FlashColors>()!.onSurfaceMuted));
    });

    test('a stock ThemeData falls back rather than throwing', () {
      // Most widget tests pump MaterialApp() with no theme:. Before this,
      // every one of them that touched a converted widget died on a null
      // check — which is how pass 2 found the Newspaper bug.
      expect(() => ThemeData().flashColors, returnsNormally);
      expect(() => ThemeData.dark().flashColors, returnsNormally);
    });

    test('the fallback still gives three distinct, usable levels', () {
      for (final base in [ThemeData(), ThemeData.dark()]) {
        final ink = base.flashColors;
        expect({ink.onSurfaceMuted, ink.onSurfaceRead, ink.placeholder},
            hasLength(3));
        expect(ink.brightness, base.brightness);
      }
    });

    test('flashColors prefers a registered extension over the fallback', () {
      final theme = flashQuietInkTheme(brightness: Brightness.light);
      expect(theme.flashColors, same(theme.extension<FlashColors>()));
    });
  });

  group('widgets that read the roles survive every theme', () {
    // The regression, end to end. Each of these paints via FlashColors.
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
      ('stock ThemeData', ThemeData()),
    ]) {
      testWidgets('$name: an article card renders', (tester) async {
        await _pump(
          tester,
          theme,
          ArticleCard(
            article: _article(isRead: true),
            onTap: () {},
            onMarkRead: () {},
            onMarkUnread: () {},
            onShare: () {},
            onBookmark: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('A headline'), findsOneWidget);
      });

      testWidgets('$name: the empty reading pane renders', (tester) async {
        await _pump(tester, theme, const ArticleDetailPlaceholder());
        expect(tester.takeException(), isNull);
      });
    }
  });
}
