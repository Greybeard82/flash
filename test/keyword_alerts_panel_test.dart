// The Keyword alerts management panel.
//
// Two of these pin bugs that were only reachable through the UI:
//
//   * The destructive confirmation used to be a `showDialog`. This panel is
//     presented by `showBubblePanel` as a raw `Overlay.insert`, which sits
//     above every Navigator route — so the dialog painted *underneath* the
//     bubble's own scrim and every tap aimed at Delete was swallowed by the
//     scrim's dismiss handler. The keyword could not be deleted at all. It is
//     now rendered inline, and these tests assert that: no Navigator route is
//     pushed, and the buttons work.
//
//   * Renaming a keyword onto one that already exists hit the UNIQUE
//     constraint on keyword_alerts.keyword. The old order deleted the matches
//     first, so the snapshots were destroyed and the rename then threw into
//     nothing — silently, because the panel's callbacks are VoidCallbacks and
//     the app installs no global async error handler.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/widgets/keyword_alerts_panel.dart';

late Database _db;
late int _feedId;

const int _now = 1750000000000;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _db = await AppDatabase.instance.database;

  final folderId = await _db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _feedId = await _db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'favicon_path': '/icons/a.png',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

/// Every database call from inside a `testWidgets` body has to go through
/// [WidgetTester.runAsync].
///
/// The body runs in fake async, and sqflite's FFI implementation completes its
/// futures on the real event loop — so a bare `await _db.insert(...)` here
/// simply never returns and the test hangs until the suite times out. `setUp`
/// is outside the fake zone, which is why the initial open works without this.
Future<T> _real<T>(WidgetTester tester, Future<T> Function() body) async {
  late T result;
  await tester.runAsync(() async => result = await body());
  return result;
}

Future<void> _alert(WidgetTester tester, String keyword,
        {bool wholeWord = false}) =>
    _real(tester, () async {
      await _db.insert(TableNames.keywordAlerts, {
        'keyword': keyword,
        'whole_word': wholeWord ? 1 : 0,
        'created_at': _now,
      });
    });

/// A match with no `articles` row behind it — the case where the snapshot is
/// the last copy and losing it is unrecoverable.
Future<void> _match(WidgetTester tester, String guid, String keyword) =>
    _real(tester, () async {
      await _db.insert(TableNames.alertMatches, {
        'feed_id': _feedId,
        'guid': guid,
        'keyword': keyword,
        'title': 'Article $guid',
        'url': 'https://example.com/$guid',
        'feed_title': 'Feed A',
        'folder_id': 1,
        'matched_at': _now,
        'is_read': 0,
      });
    });

Future<void> _pumpPanel(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('en')],
    home: Scaffold(
      body: SingleChildScrollView(child: KeywordAlertsPanel()),
    ),
  ));
  await _settle(tester);
}

/// Pump until the panel is quiet, without `pumpAndSettle`.
///
/// Two things make pumpAndSettle unusable here. The panel reads the database
/// in initState and sqflite's FFI future only completes on the *real* event
/// loop, which the test binding's fake async does not drive; and while it is
/// loading the panel shows a [SpinningRefreshIcon], whose controller is
/// `..repeat()` — an animation that never ends, so pumpAndSettle would pump
/// until it timed out even once the data had arrived.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<List<String>> _keywords(WidgetTester tester) => _real(tester, () async {
      final rows =
          await _db.query(TableNames.keywordAlerts, orderBy: 'keyword');
      return [for (final r in rows) r['keyword'] as String];
    });

Future<int> _matchCount(WidgetTester tester, String keyword) =>
    _real(tester, () async {
      final rows = await _db.rawQuery(
          'SELECT COUNT(*) c FROM ${TableNames.alertMatches} WHERE keyword = ?',
          [keyword]);
      return rows.first['c'] as int;
    });

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('the destructive confirmation', () {
    testWidgets('is rendered inline, not as a pushed route', (tester) async {
      await _alert(tester, 'zelda');
      await _match(tester, 'g1', 'zelda');
      await _pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await _settle(tester);

      expect(find.textContaining('zelda'), findsWidgets);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'an AlertDialog here is pushed onto the Navigator, which '
              'puts it underneath the bubble overlay this panel lives in — '
              'invisible and untappable');
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('names the number of cards that would actually be lost',
        (tester) async {
      await _alert(tester, 'zelda');
      await _alert(tester, 'mario');
      // g1 is zelda-only and would be lost; g2 also matched mario and only
      // loses a badge, so it must not be counted.
      await _match(tester, 'g1', 'zelda');
      await _match(tester, 'g2', 'zelda');
      await _match(tester, 'g2', 'mario');
      await _pumpPanel(tester);

      // `.last`, not `.first`: rows are sorted, so the bins are mario then
      // zelda. mario's only match is shared with zelda, so deleting it orphans
      // nothing and skips the prompt entirely — which is itself the rule.
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await _settle(tester);

      expect(find.textContaining('1 article will disappear'), findsOneWidget,
          reason: 'only the card whose *only* keyword is this one disappears; '
              'g2 keeps its mario badge and must not be counted');
    });

    testWidgets('Cancel leaves the keyword and its matches alone',
        (tester) async {
      await _alert(tester, 'zelda');
      await _match(tester, 'g1', 'zelda');
      await _pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(await _keywords(tester), ['zelda']);
      expect(await _matchCount(tester, 'zelda'), 1);
    });

    testWidgets('Delete removes the keyword and its matches', (tester) async {
      await _alert(tester, 'zelda');
      await _match(tester, 'g1', 'zelda');
      await _pumpPanel(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);

      expect(await _keywords(tester), isEmpty);
      expect(await _matchCount(tester, 'zelda'), 0);
    });
  });

  testWidgets('the prompt is reachable when the panel has to scroll',
      (tester) async {
    // The panel is a Column inside the bubble's height-capped
    // SingleChildScrollView. With enough keywords it scrolls, and a prompt
    // rendered at the top of that Column lands above the current scroll
    // offset — off screen — exactly reproducing the showDialog bug it
    // replaced. Rendered in place of its own row it is always where the user
    // just tapped.
    for (var i = 0; i < 16; i++) {
      await _alert(tester, 'keyword-${i.toString().padLeft(2, '0')}');
    }
    await _match(tester, 'g1', 'keyword-15');

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        // Mirrors bubble_panel.dart: a capped box with the panel scrolling
        // inside it.
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: const SingleChildScrollView(
              child: KeywordAlertsPanel(),
            ),
          ),
        ),
      ),
    ));
    await _settle(tester);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0.0),
        reason: 'the fixture must actually scroll, or it proves nothing');

    // Bring the last keyword's row into view, the way a user reaching for it
    // would, and delete it from there.
    await tester.dragUntilVisible(
      find.text('keyword-15'),
      find.byType(SingleChildScrollView),
      const Offset(0, -80),
    );
    await _settle(tester);

    final bin = find.descendant(
      of: find.ancestor(
          of: find.text('keyword-15'), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.delete_outline),
    );
    await tester.tap(bin);
    await _settle(tester);

    final confirm = find.text('Delete');
    expect(confirm, findsOneWidget);
    // Measured against the scroll viewport, not the window: the bubble clips
    // to its capped height, so anything outside that is invisible and not
    // hit-testable even though it is inside the 800x600 test surface.
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final rect = tester.getRect(confirm);
    expect(rect.top, greaterThanOrEqualTo(viewport.top),
        reason: 'the prompt must not be scrolled off the top — the original '
            'bug — nor off the bottom');
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));

    await tester.tap(confirm);
    // Two settles: this fixture has 16 keywords, so the delete plus the
    // reload behind it needs more real-event-loop time than the small ones.
    await _settle(tester);
    await _settle(tester);
    expect(await _keywords(tester), isNot(contains('keyword-15')),
        reason: 'and tapping it must actually delete the keyword');
  });

  group('duplicate keywords', () {
    testWidgets('adding one that already exists is refused, not backfilled',
        (tester) async {
      // whole_word is ON in the table. Re-adding with the box unticked used to
      // be ignored by the insert but still drive the backfill, writing rows the
      // configured alert would never have produced.
      await _alert(tester, 'zelda', wholeWord: true);
      await _pumpPanel(tester);

      await tester.tap(find.text('Add keyword'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'zelda');
      await tester.tap(find.text('Add'));
      await _settle(tester);

      expect(find.textContaining('already an alert keyword'), findsOneWidget);
      expect(await _keywords(tester), ['zelda']);
      final rows = await _real(tester, () => _db.query(TableNames.keywordAlerts));
      expect(rows.single['whole_word'], 1,
          reason: 'the stored setting must not be quietly replaced');
    });

    testWidgets('renaming onto an existing keyword destroys nothing',
        (tester) async {
      await _alert(tester, 'zelda');
      await _alert(tester, 'mario');
      await _match(tester, 'g1', 'zelda');
      await _pumpPanel(tester);

      await tester.longPress(find.text('zelda'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'mario');
      await tester.tap(find.text('Save'));
      await _settle(tester);

      expect(find.textContaining('already an alert keyword'), findsOneWidget);
      expect(await _keywords(tester), ['mario', 'zelda'],
          reason: 'neither keyword changed');
      expect(await _matchCount(tester, 'zelda'), 1,
          reason: 'the snapshot is the last copy of an article that may be '
              'long retired — the old code deleted it and then threw');
    });
  });

  testWidgets('cancelling the edit form abandons its pending confirmation',
      (tester) async {
    await _alert(tester, 'zelda');
    await _match(tester, 'g1', 'zelda');
    await _pumpPanel(tester);

    await tester.longPress(find.text('zelda'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'link');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text('Delete'), findsOneWidget, reason: 'the confirm is up');

    // Back out of the edit itself while the confirmation is still waiting.
    await tester.tap(find.text('Cancel').last);
    await _settle(tester);

    expect(await _keywords(tester), ['zelda'],
        reason: 'cancelling the form cancels the whole operation; the rename '
            'must not still be parked on a live confirmation waiting to '
            'commit itself');
    expect(await _matchCount(tester, 'zelda'), 1);
    expect(find.text('Delete'), findsNothing,
        reason: 'and the orphaned prompt must not be left on screen');
  });
}
