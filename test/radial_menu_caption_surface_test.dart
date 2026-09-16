// The radial menu's captions have to sit on a surface, not on the article list.
//
// The icon circles always had one — `Material(color: surfaceContainerHighest,
// elevation: 4)` — but the "Share" and "Bookmark" captions under them were bare
// `Text` painted straight onto the menu's scrim, which means onto whatever
// headline happened to be behind them. The labels are the only thing naming the
// two glyphs, so an unreadable label is an unreadable menu.
//
// Pinned across all three themes because the fix is only correct if the colour
// is *resolved* rather than picked: Quiet Ink light, Quiet Ink dark and
// Newspaper each answer `surfaceContainerHighest` differently, and Newspaper
// registers no `FlashColors` extension at all.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/radial_menu.dart';

Article _article() => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      feedTitle: 'Example Feed',
    );

Future<void> _openMenu(WidgetTester tester, ThemeData theme) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox.expand());
    }),
  ));

  showRadialMenu(
    context: ctx,
    onShare: () {},
    onBookmark: () {},
    article: _article(),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The caption's own backing Material — the innermost one wrapping the label.
Material _captionSurface(WidgetTester tester, String label) {
  final finder = find
      .ancestor(of: find.text(label), matching: find.byType(Material))
      .first;
  return tester.widget<Material>(finder);
}

Color? _captionInk(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  final cases = <String, ThemeData>{
    'Quiet Ink light': flashQuietInkTheme(brightness: Brightness.light),
    'Quiet Ink dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  cases.forEach((name, theme) {
    testWidgets('$name: radial captions sit on surfaceContainerHighest',
        (tester) async {
      await _openMenu(tester, theme);

      for (final label in const ['Share', 'Bookmark']) {
        expect(find.text(label), findsOneWidget,
            reason: '$name: expected a "$label" caption');

        expect(
          _captionSurface(tester, label).color,
          theme.colorScheme.surfaceContainerHighest,
          reason: '$name: "$label" must sit on the same surface as the circle '
              'above it, not on the article list behind the scrim',
        );
      }
    });

    testWidgets('$name: radial caption ink resolves to onSurfaceVariant',
        (tester) async {
      await _openMenu(tester, theme);

      for (final label in const ['Share', 'Bookmark']) {
        expect(
          _captionInk(tester, label),
          theme.colorScheme.onSurfaceVariant,
          reason: '$name: caption ink is resolved from the theme, not picked',
        );
      }
    });
  });

  testWidgets('the three themes really do resolve different caption surfaces',
      (tester) async {
    // Guards the tests above from passing because every theme happens to
    // answer the same colour, which would make them assert nothing.
    final resolved = {
      for (final e in cases.entries) e.key: e.value.colorScheme.surfaceContainerHighest,
    };
    expect(resolved.values.toSet().length, cases.length,
        reason: 'each theme must answer surfaceContainerHighest differently: '
            '$resolved');
  });
}
