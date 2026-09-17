// The reading pane's placeholder has to be true for the section beside it.
//
// "Select an article to read it here" is followable on Flash, Bookmarks and
// Alerts: all three route taps through `openArticle`, which calls `pane.show`.
// Categories does not — it lists folders and feeds and expands them in place,
// so nothing there can ever fill this column. On a tablet that left roughly
// half the screen holding an instruction the user could not obey.
//
// The shell chooses the copy, because it is the only thing that knows which
// section is showing. These pin both halves of that: the default, and the
// override.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_detail_pane.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashQuietInkTheme(brightness: Brightness.light),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('by default the pane asks for an article', (tester) async {
    await _pump(tester, const ArticleDetailPlaceholder());
    expect(find.text('Select an article to read it here'), findsOneWidget);
  });

  testWidgets('a section that cannot fill the pane overrides the copy',
      (tester) async {
    await _pump(
      tester,
      const ArticleDetailPlaceholder(message: 'Articles you open appear here'),
    );

    expect(find.text('Articles you open appear here'), findsOneWidget);
    expect(
      find.text('Select an article to read it here'),
      findsNothing,
      reason: 'Categories must not ask for a selection it cannot accept',
    );
  });

  testWidgets('the override does not change the pane anatomy', (tester) async {
    // Same glyph, same single line of copy — this is a wording change, not a
    // different empty state, so the column must not reflow between sections.
    await _pump(tester, const ArticleDetailPlaceholder());
    final defaultIcons = tester.widgetList(find.byType(Icon)).length;

    await _pump(
      tester,
      const ArticleDetailPlaceholder(message: 'Articles you open appear here'),
    );
    expect(tester.widgetList(find.byType(Icon)).length, defaultIcons);
  });
}
