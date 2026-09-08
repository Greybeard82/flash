import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/models/content_block.dart';
import 'package:flash/services/clean_article_cache.dart';
import 'package:flash/widgets/article_detail_pane.dart';

/// Never pumpAndSettle in this file. With the WebView replaced by a stand-in,
/// `onLoadStop` never fires, so `_loading` stays true and the pane keeps a
/// SpinningRefreshIcon on screen — whose controller is `..repeat()`. Settling
/// would pump until it timed out. Drive it with explicit pumps instead.
const _toggle = ValueKey('cleanModeToggle');
const _cleanView = ValueKey('cleanArticleView');
const _webStandIn = ValueKey('webStandIn');

Article _article(String url) => Article(
      feedId: 1,
      guid: url,
      title: 'An article',
      url: url,
      fetchedAt: 0,
    );

List<ContentBlock> _blocks(String marker) =>
    [ParagraphBlock('$marker — ${'body text. ' * 40}')];

Future<void> _pump(
  WidgetTester tester, {
  required String url,
  required bool enabled,
  Key paneKey = const ValueKey('pane'),
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: ArticleDetailPane(
        key: paneKey,
        article: _article(url),
        cleanModeEnabledForTesting: enabled,
        webViewOverrideForTesting: (_) =>
            const ColoredBox(key: _webStandIn, color: Color(0xFF000000)),
      ),
    ),
  ));
  await _settle(tester);
}

/// Enough pumps for the async load to resolve, without settling.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(CleanArticleCache.instance.clear);

  testWidgets('no toggle when the setting is off, even with blocks cached',
      (tester) async {
    // The ordering assertion: the setting is checked BEFORE the cache. Read
    // the other way round, a reader who turned clean mode off mid-session
    // would keep seeing the button on every article opened earlier.
    CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));

    await _pump(tester, url: 'https://example.com/a', enabled: false);

    expect(find.byKey(_toggle), findsNothing);
    expect(find.byKey(_cleanView), findsNothing);
  });

  testWidgets('no toggle and no banner for a remembered failure',
      (tester) async {
    CleanArticleCache.instance.put('https://example.com/a', null);

    await _pump(tester, url: 'https://example.com/a', enabled: true);

    expect(find.byKey(_toggle), findsNothing);
    expect(find.text('Clean view not available for this page'), findsNothing,
        reason: 'reopening a known-unextractable article must be quiet');
  });

  testWidgets('the toggle appears once blocks are available', (tester) async {
    CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));

    await _pump(tester, url: 'https://example.com/a', enabled: true);

    expect(find.byKey(_toggle), findsOneWidget);
    expect(find.text('Read clean version'), findsOneWidget);
    // The page is still what is shown until the reader asks otherwise.
    expect(find.byKey(_cleanView), findsNothing);
  });

  testWidgets('tapping switches to the clean view and back', (tester) async {
    CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));
    await _pump(tester, url: 'https://example.com/a', enabled: true);

    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    expect(find.byKey(_cleanView), findsOneWidget);
    expect(find.text('View original page'), findsOneWidget);

    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    expect(find.text('Read clean version'), findsOneWidget);
  });

  testWidgets('the WebView is never rebuilt across a toggle', (tester) async {
    // The keep-alive assertion. Same technique as article_card_thumbnail_test:
    // hold the Element and check identity, which is what actually proves the
    // platform view was not torn down and recreated — and therefore that the
    // page was not reloaded and the scroll position not lost.
    CleanArticleCache.instance.put('https://example.com/a', _blocks('A'));
    await _pump(tester, url: 'https://example.com/a', enabled: true);

    final before = tester.element(find.byKey(_webStandIn, skipOffstage: false));

    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    final during = tester.element(find.byKey(_webStandIn, skipOffstage: false));

    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    final after = tester.element(find.byKey(_webStandIn, skipOffstage: false));

    expect(identical(before, during), isTrue,
        reason: 'switching to clean mode must not tear down the WebView');
    expect(identical(during, after), isTrue,
        reason: 'switching back must not reload the page');
  });

  testWidgets('swapping the article in place resets clean mode',
      (tester) async {
    // The tablet pane swaps `article` rather than rebuilding, so state left
    // over from the previous article would leak onto the next one.
    CleanArticleCache.instance.put('https://example.com/a', _blocks('AAA'));
    CleanArticleCache.instance.put('https://example.com/b', null);

    await _pump(tester, url: 'https://example.com/a', enabled: true);
    await tester.tap(find.byKey(_toggle));
    await tester.pump();
    expect(find.byKey(_cleanView), findsOneWidget);

    // Same pane key: didUpdateWidget, not a fresh State.
    await _pump(tester, url: 'https://example.com/b', enabled: true);

    expect(find.byKey(_toggle), findsNothing,
        reason: "B has no clean version, so A's button must not survive");
    expect(find.byKey(_cleanView), findsNothing);
    expect(find.textContaining('AAA'), findsNothing,
        reason: "A's text must not still be on screen under B");
  });
}
