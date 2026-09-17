// The Alerts tab used to destroy bookmarks, and this is the file that stops it.
//
// **The bug, in full, because the shape of it is the lesson.**
// `AlertEntry.toArticle()` never set `isSaved`, so it defaulted to `false` and
// every card in Alerts drew an *unsaved* bookmark. `_toggleSaved` did not read
// the snapshot: it resolved the real `articles` row by (feedId, guid) and
// flipped **that**. So a user who had saved an article, met it again in Alerts
// and tapped what looked like "save this" ran a toggle that found the row
// saved and unsaved it. The bookmark was gone, the user had asked for the
// opposite, and nothing told them.
//
// **The invariant: the glyph and the write read the same source, and that
// source is the real row.** A snapshot cannot know its own saved state —
// `is_saved` is a column on `articles`, which is exactly what a snapshot does
// not have — so the screen resolves it once per load and passes it in.
//
// The query-count group is the other half. Resolving per row would have fixed
// the glyph and put a database read inside a scrolling list's `itemBuilder`,
// and that is counted here rather than reasoned about: the factory is wrapped
// in `SqfliteDatabaseFactoryLogger` and every statement is tallied.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/alert_match.dart';
import 'package:flash/repositories/alert_match_repository.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/screens/alerts_screen.dart';
import 'package:flash/theme/app_theme.dart';

/// Counts every SQL statement the app issues, so "does not scale with row
/// count" is measured rather than asserted from reading the code.
class _QueryCounter {
  int count = 0;
  final List<String> statements = [];

  void reset() {
    count = 0;
    statements.clear();
  }

  void record(SqfliteLoggerEvent event) {
    if (event is SqfliteLoggerSqlEvent) {
      count++;
      statements.add(event.sql);
    }
  }
}

final _counter = _QueryCounter();

Future<int> _insertArticle({
  required int feedId,
  required String guid,
  required bool isSaved,
}) async {
  final db = await AppDatabase.instance.database;
  // `feeds.folder_id` is NOT NULL and references `folders(id)`, so a feed
  // cannot be inserted without a folder first. Learned the hard way: a bare
  // `feeds` insert with `ConflictAlgorithm.ignore` swallowed its own failure
  // and the foreign key blew up one statement later, on `articles`.
  final existing = await db.query('feeds',
      columns: ['id'], where: 'id = ?', whereArgs: [feedId]);
  if (existing.isEmpty) {
    final folderId = await db.insert('folders',
        {'name': 'A Folder', 'position': 0, 'created_at': 0});
    await db.insert('feeds', {
      'id': feedId,
      'folder_id': folderId,
      'title': 'A Feed',
      'url': 'https://example.com/feed$feedId',
      'created_at': 0,
    });
  }
  return db.insert('articles', {
    'feed_id': feedId,
    'guid': guid,
    'title': 'A headline',
    'url': 'https://example.com/$guid',
    'fetched_at': 0,
    'is_read': 0,
    'is_saved': isSaved ? 1 : 0,
    'is_blocked': 0,
  });
}

Future<void> _insertMatch({
  required int feedId,
  required String guid,
  required String keyword,
}) =>
    AlertMatchRepository().insertMatches([
      AlertMatch(
        feedId: feedId,
        guid: guid,
        keyword: keyword,
        title: 'A headline',
        url: 'https://example.com/$guid',
        matchedAt: 1,
        isRead: false,
        feedTitle: 'A Feed',
      ),
    ]);

/// Seeds the database, mounts the screen, and lets its real `_load()` finish.
///
/// **`runAsync` is not optional here and the reason is documented in three
/// other files in this repo.** `testWidgets` runs inside `flutter_test`'s
/// FakeAsync zone, where a sqflite FFI Future never resolves — awaiting one
/// directly hangs the test rather than failing it, which is what the first
/// version of this file did. Real I/O has to happen inside `runAsync`, and the
/// widget's own load needs a real pause before the tree is pumped again.
Future<void> _seedAndPump(WidgetTester tester, Future<void> Function() seed) async {
  await tester.runAsync(seed);
  _counter.reset();
  await tester.pumpWidget(_app());
  // Two rounds, not one. `_load()` awaits two real reads in sequence — the
  // entries, then the saved keys — and each needs its own pass outside the
  // FakeAsync zone before the tree is rebuilt. Measured: one round renders
  // nothing, two renders the list.
  await _settleRealAsync(tester);
}

/// Lets pending real I/O finish, then rebuilds.
Future<void> _settleRealAsync(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump();
  }
}

Widget _app() => MaterialApp(
      locale: const Locale('en'),
      theme: flashQuietInkTheme(brightness: Brightness.light),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: const AlertsScreen(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // ignore: experimental_member_use
    databaseFactory = SqfliteDatabaseFactoryLogger(
      databaseFactoryFfi,
      options: SqfliteLoggerOptions(log: _counter.record),
    );
  });

  setUp(() async {
    AppDatabase.useForTesting();
    _counter.reset();
  });

  group('the glyph and the write read the same source', () {
    testWidgets('an already-saved article shows a SAVED bookmark',
        (tester) async {
      // The assertion the old code failed. Before the fix this rendered
      // `bookmark_border_rounded` — an unsaved glyph on a saved article —
      // which is the lie the whole bug rests on.
      await _seedAndPump(tester, () async {
        await _insertArticle(feedId: 1, guid: 'g-saved', isSaved: true);
        await _insertMatch(feedId: 1, guid: 'g-saved', keyword: 'flutter');
      });

      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget,
          reason: 'a saved article must draw a saved bookmark. If this is the '
              'outline glyph, tapping it will UNSAVE the article while '
              'looking like "save this".');
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
    });

    testWidgets('an unsaved article shows an unsaved bookmark',
        (tester) async {
      // The other direction, so the fix is not just "always saved".
      await _seedAndPump(tester, () async {
        await _insertArticle(feedId: 1, guid: 'g-unsaved', isSaved: false);
        await _insertMatch(feedId: 1, guid: 'g-unsaved', keyword: 'flutter');
      });

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
    });

    testWidgets('two taps return the real row to where it started',
        (tester) async {
      // **Asserted against the row, not the glyph.** A glyph-only round trip
      // would pass even if both taps wrote the same value, which is close to
      // the original bug.
      final repo = ArticleRepository();
      await _seedAndPump(tester, () async {
        await _insertArticle(feedId: 1, guid: 'g-trip', isSaved: true);
        await _insertMatch(feedId: 1, guid: 'g-trip', keyword: 'flutter');
      });

      Future<bool> savedInDb() async {
        late bool saved;
        await tester.runAsync(() async {
          saved = (await repo.findByGuid(1, 'g-trip'))!.isSaved;
        });
        return saved;
      }

      Future<void> tapAndSettle(IconData icon) async {
        await tester.tap(find.byIcon(icon));
        await tester.pump();
        await _settleRealAsync(tester);
      }

      expect(await savedInDb(), isTrue, reason: 'precondition');

      await tapAndSettle(Icons.bookmark_rounded);
      expect(await savedInDb(), isFalse,
          reason: 'the first tap on a SAVED article unsaves it');

      await tapAndSettle(Icons.bookmark_border_rounded);
      expect(await savedInDb(), isTrue,
          reason: 'and the second puts it back. Before the fix the glyph '
              'started wrong, so the first tap already went the wrong way and '
              'this round trip ended inverted.');
    });
  });

  group('the list build issues no queries, however long the list', () {
    // Resolving saved state per row would be N queries for N rows, inside an
    // `itemBuilder` that runs again on every scroll. The fix resolves once per
    // load instead, and this is what proves it.

    Future<int> queriesForEntries(WidgetTester tester, int n) async {
      // Tear the tree down first. Pumping `_app()` a second time reuses the
      // same element, so `initState` does not run again and the screen issues
      // no queries at all — which reads as "0 queries for 12 entries" and
      // looks like a spectacular optimisation rather than a dead harness.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      AppDatabase.useForTesting();

      await _seedAndPump(tester, () async {
        for (var i = 0; i < n; i++) {
          await _insertArticle(feedId: 1, guid: 'g$i', isSaved: i.isEven);
          await _insertMatch(feedId: 1, guid: 'g$i', keyword: 'flutter');
        }
      });
      return _counter.count;
    }

    testWidgets('one entry and twelve entries cost the same', (tester) async {
      final few = await queriesForEntries(tester, 1);
      final many = await queriesForEntries(tester, 12);

      expect(many, few,
          reason: 'the screen issued $few queries for 1 entry and $many for '
              '12. A difference means saved state is being resolved per row, '
              'which is a database read inside a scrolling list.');
      // Two: the entries, and the saved keys. Named rather than bounded, so
      // a third read has to be a deliberate edit here.
      expect(many, 2,
          reason: 'the screen should issue exactly two reads — one for the '
              'entries and one for the saved keys — and issued $many');
    });

    testWidgets('and the saved lookup happens exactly once per load',
        (tester) async {
      await queriesForEntries(tester, 6);

      final savedLookups = _counter.statements
          .where((sql) => sql.contains('is_saved = 1'))
          .toList();

      expect(savedLookups, hasLength(1),
          reason: 'expected one saved-state read for the whole screen, got '
              '${savedLookups.length}:\n  ${savedLookups.join('\n  ')}');
    });
  });
}
