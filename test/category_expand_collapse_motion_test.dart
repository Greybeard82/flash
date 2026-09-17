// Expanding and collapsing a category has to *move*, in both directions,
// downward only.
//
// Two faults were reported on the Categories screen on 17 September 2026, and
// both came out of one `AnimatedSize` block in `_FolderSectionState.build`:
//
//   1. `AnimatedSize` defaults to `alignment: Alignment.center`, and the
//      collapsed child was `SizedBox.shrink()` — zero WIDE as well as zero
//      tall. So the box grew from 0x0 about its centre and the rows appeared
//      to arrive from the left as much as from above.
//
//   2. On collapse `_expanded` went false and the rows left the tree in the
//      same frame. `AnimatedSize` was then shrinking a box that was already
//      empty: the rows vanished instantly and only whitespace closed behind
//      them.
//
// **The two faults need two different assertions, and only one of them is
// about height.** Fault 2 did not stop the *geometry* animating — the empty
// box still shrank over its duration, so everything below the section still
// slid up smoothly. A height-only test passes against the broken code. What
// fault 2 actually destroyed is the presence of the rows while that happens,
// which is why `collapse keeps the rows on screen while it runs` is the test
// that pins it, and the height assertions ride along as a guard against the
// opposite regression (an instant jump).
//
// Fault 1 is measured as width, not as position: a centre-aligned grow is
// narrower than the list partway through, and top-left-anchored growth is
// full width from the first frame.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/screens/feeds_screen.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/keyword_group_panel.dart';

const int _now = 1758000000000;

/// Two categories, so the second one's header can be used as a ruler: its
/// vertical position IS the height of everything above it, which is exactly
/// the first section's height plus a constant. Measuring that instead of the
/// animating widget itself keeps the test blind to which widget does the
/// animating, so it reads the same before and after the fix.
Future<void> _seed() async {
  final db = await AppDatabase.instance.database;
  await db.insert('folders', {
    'id': 1,
    'name': 'Alpha',
    'position': 0,
    'created_at': _now,
    'color_index': 0,
  });
  await db.insert('folders', {
    'id': 2,
    'name': 'Beta',
    'position': 1,
    'created_at': _now,
    'color_index': 1,
  });
  for (var i = 0; i < 3; i++) {
    await db.insert('feeds', {
      'id': i + 1,
      'folder_id': 1,
      'title': 'Feed $i',
      'url': 'https://example.com/$i.xml',
      'position': i,
      'created_at': _now,
    });
  }
}

Widget _app() => const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('en')],
      home: Scaffold(body: FeedsScreen()),
    );

/// Pump until the screen is quiet, without `pumpAndSettle`.
///
/// `FeedsScreen` reads the database in `initState` and sqflite's FFI future
/// only completes on the *real* event loop, which the test binding's fake
/// async does not drive; and while it loads the screen shows a
/// `SpinningRefreshIcon`, whose controller is `..repeat()`. `pumpAndSettle`
/// would therefore pump until it timed out even once the data had arrived.
/// Same reasoning, and the same shape, as `keyword_alerts_panel_test.dart`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The ruler: where the second category's header sits. Rises as the first
/// section collapses, falls as it expands.
double _betaTop(WidgetTester tester) =>
    tester.getTopLeft(find.text('Beta')).dy;

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    AppDatabase.useForTesting();
    await _seed();
  });

  group('a category section unrolls and rolls back up', () {
    testWidgets('collapse keeps the rows on screen while it runs',
        (tester) async {
      await tester.pumpWidget(_app());
      await _settle(tester);

      // Sections start collapsed. Open it and let the expand finish.
      final collapsedTop = _betaTop(tester);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final expandedTop = _betaTop(tester);

      expect(expandedTop, greaterThan(collapsedTop),
          reason: 'the three feed rows should have pushed Beta down');
      expect(find.text('Feed 0'), findsOneWidget);

      // Collapse, and look halfway through.
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // THE ASSERTION THAT FAILS AGAINST THE OLD CODE. With the rows dropped
      // from the tree on the toggling frame there is nothing left to see
      // collapsing, however smoothly the empty box behind them shrinks.
      expect(find.text('Feed 0'), findsOneWidget,
          reason: 'the rows must still be painting while the section closes; '
              'dropping them on the toggle frame is what made collapse look '
              'like an instant disappearance');

      final midTop = _betaTop(tester);
      expect(midTop, greaterThan(collapsedTop),
          reason: 'halfway through, the section must not already be shut');
      expect(midTop, lessThan(expandedTop),
          reason: 'halfway through, the section must not still be fully open');

      // And it finishes: closed, with nothing of the section left mounted.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_betaTop(tester), closeTo(collapsedTop, 0.5));
      expect(find.text('Feed 0'), findsNothing,
          reason: 'a collapsed section must not keep its rows mounted');
    });

    testWidgets('expand is anchored to the header, not to the centre',
        (tester) async {
      await tester.pumpWidget(_app());
      await _settle(tester);

      await tester.tap(find.text('Alpha'));
      await tester.pump();

      // THE ASSERTION THAT FAILS AGAINST THE OLD CODE, and it is deliberately
      // blind to which widget does the animating.
      //
      // A vertical reveal anchored at the top holds its content still and
      // lets the clip edge travel down over it: the first row is laid out at
      // its final position on frame one and never moves. Centre alignment
      // instead places the child at `boxTop - (childHeight - boxHeight) / 2`
      // — above the section — and slides it down into place as the box grows,
      // which is the sideways-and-downward drift that was reported.
      //
      // `getTopLeft` reports layout position, not what survives the clip, so
      // this sees the drift whether or not the pixels are visible.
      await tester.pump(const Duration(milliseconds: 40));
      final early = tester.getTopLeft(find.text('Feed 0')).dy;
      await tester.pump(const Duration(milliseconds: 80));
      final later = tester.getTopLeft(find.text('Feed 0')).dy;
      await tester.pump(const Duration(milliseconds: 400));
      final settled = tester.getTopLeft(find.text('Feed 0')).dy;

      expect(early, closeTo(settled, 0.5),
          reason: 'the first row must be at its final position from the very '
              'first frame; starting it above the section and sliding it down '
              'is what made the rows read as arriving from off to one side');
      expect(later, closeTo(settled, 0.5),
          reason: 'and it must not drift at any point during the reveal');
    });

    testWidgets('expand moves in steps rather than jumping', (tester) async {
      await tester.pumpWidget(_app());
      await _settle(tester);

      final collapsedTop = _betaTop(tester);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midTop = _betaTop(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final expandedTop = _betaTop(tester);

      expect(midTop, greaterThan(collapsedTop));
      expect(midTop, lessThan(expandedTop));
    });
  });

  // ── The sibling ────────────────────────────────────────────────────────────
  //
  // `keyword_group_panel.dart` had the identical `AnimatedSize` block and so
  // the identical pair of faults. It backs the keyword BLOCKLIST bubble (via
  // `KeywordBlocklistPanel`, opened from the article list), not the Alerts
  // screen — `KeywordAlertsPanel` is a separate widget that deliberately does
  // not reuse it and never had an `AnimatedSize` at all.
  //
  // No database here: the panel takes its data through an injected
  // [KeywordGroupController], so a fake one is enough and this group adds no
  // sqflite traffic to the suite.
  group('a keyword group unrolls and rolls back up', () {
    testWidgets('collapse keeps the matched articles on screen while it runs',
        (tester) async {
      await tester.pumpWidget(_blocklistApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('Match one'), findsNothing,
          reason: 'sanity: groups start collapsed');

      await tester.tap(find.text('spoilers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Match one'), findsOneWidget);
      final openTop = tester.getTopLeft(find.text('Match one')).dy;

      await tester.tap(find.text('spoilers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The fault that made collapse invisible.
      expect(find.text('Match one'), findsOneWidget,
          reason: 'the rows must still be painting while the group closes');

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Match one'), findsNothing,
          reason: 'a closed group must not keep its rows mounted');

      // And the other fault: top-anchored, so the first row does not drift.
      await tester.tap(find.text('spoilers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.text('Match one')).dy,
          closeTo(openTop, 0.5),
          reason: 'the first row must open at its final position, not slide '
              'down into it from above');
    });
  });
}

// ── Fake blocklist controller ──────────────────────────────────────────────

class _FakeGroupController implements KeywordGroupController {
  @override
  Future<List<KeywordGroupEntry>> loadKeywords() async => const [
        KeywordGroupEntry(id: 1, keyword: 'spoilers', wholeWord: false),
      ];

  @override
  Future<List<Article>> loadArticles() async => const [
        Article(
            feedId: 1,
            guid: 'a',
            title: 'Match one',
            url: 'https://example.com/a',
            fetchedAt: _now),
        Article(
            feedId: 1,
            guid: 'b',
            title: 'Match two',
            url: 'https://example.com/b',
            fetchedAt: _now),
      ];

  @override
  String? keywordOf(Article article) => 'spoilers';

  @override
  Future<void> addKeyword(String keyword, bool wholeWord) async {}

  @override
  Future<void> deleteKeyword(KeywordGroupEntry entry) async {}

  @override
  Future<void> editKeyword(
          KeywordGroupEntry entry, String newKeyword, bool newWholeWord) async {
  }
}

Widget _blocklistApp() => MaterialApp(
      locale: const Locale('en'),
      theme: flashQuietInkTheme(brightness: Brightness.light),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: SingleChildScrollView(
          child: KeywordGroupPanel(
            controller: _FakeGroupController(),
            icon: Icons.block,
            title: 'Blocklist',
            subtitle: 'Hidden keywords',
            matchIcon: Icons.article_outlined,
            addFieldHint: 'word or phrase',
            emptyIcon: Icons.block,
            emptyTitle: 'Nothing blocked',
            emptyBody: 'Add a keyword to hide matching articles.',
          ),
        ),
      ),
    );
