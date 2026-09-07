// Blocking a keyword has to reach the screens, not just the database.
//
// The bug this pins: `retroactivelyBlock` did its job — every matching row
// got `is_blocked = 1`, and every feed query already filters on it — but
// nothing told FeedScreen. It lives in a kept-alive IndexedStack, and the
// blocklist panel is opened from its own Filter bubble, so the article the
// user had just asked to hide sat there, still counted by the chips, until
// the app was restarted.
//
// Two signals go out, and both matter:
//
//   * BlockedStateNotifier, for the feed itself.
//   * AlertsChangedNotifier, because every alerts query carries a
//     `NOT EXISTS (... is_blocked = 1)` clause — flipping this column changes
//     which alert rows exist, so the Alerts tab and its badge are as stale as
//     the feed was.
//
// Pinged from inside the repository writes rather than from the panel, so
// add, edit and delete of a keyword are all covered by one choke point.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/services/alerts_changed_notifier.dart';
import 'package:flash/services/blocked_state_notifier.dart';

late ArticleRepository _repo;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final folder = await db.insert(
      TableNames.folders, {'name': 'Cat1', 'position': 0, 'created_at': ts});
  await db.insert(TableNames.feeds, {
    'folder_id': folder,
    'title': 'Feed1',
    'url': 'https://a.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });
}

Future<void> _tearDown() async => AppDatabase.instance.close();

Future<void> _insert(String guid, String title) async {
  final db = await AppDatabase.instance.database;
  await db.insert(TableNames.articles, {
    'feed_id': 1,
    'guid': guid,
    'title': title,
    'url': 'https://example.com/$guid',
    'published_at': DateTime.now().millisecondsSinceEpoch,
    'fetched_at': 0,
    'is_read': 0,
    'is_blocked': 0,
    'is_saved': 0,
  });
}

Future<int?> _blocked(String guid) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles,
      columns: ['is_blocked'], where: 'guid = ?', whereArgs: [guid], limit: 1);
  return rows.isEmpty ? null : rows.first['is_blocked'] as int;
}

/// Counts notifications from the moment it is created.
class _Counter {
  int count = 0;
  _Counter(ChangeNotifier notifier) {
    notifier.addListener(_bump);
    addTearDown(() => notifier.removeListener(_bump));
  }
  void _bump() => count++;
}

void main() {
  setUp(_setUp);
  tearDown(_tearDown);

  group('adding a keyword', () {
    test('blocks the matching row and announces it', () async {
      await _insert('a', 'Bentley unveils a new EV');
      await _insert('b', 'Something else entirely');

      final blocked = _Counter(BlockedStateNotifier.instance);
      final alerts = _Counter(AlertsChangedNotifier.instance);

      await _repo.retroactivelyBlock('Bentley', false);

      expect(await _blocked('a'), 1);
      expect(await _blocked('b'), 0, reason: 'only the match is hidden');
      expect(blocked.count, 1,
          reason: 'without this the feed keeps showing the blocked article '
              'until the app is restarted — the bug being fixed');
      expect(alerts.count, 1,
          reason: 'alerts queries filter on is_blocked too, so the Alerts '
              'list and its badge are stale in exactly the same way');
    });

    test('announces even when the write is at the end of a long batch',
        () async {
      for (var i = 0; i < 30; i++) {
        await _insert('g$i', i.isEven ? 'Bentley $i' : 'Other $i');
      }
      final blocked = _Counter(BlockedStateNotifier.instance);

      await _repo.retroactivelyBlock('Bentley', false);

      expect(await _blocked('g0'), 1);
      expect(await _blocked('g1'), 0);
      expect(blocked.count, 1,
          reason: 'one signal per write, not one per row');
    });

    test('a keyword that matches nothing still announces', () async {
      await _insert('a', 'Nothing relevant here');
      final blocked = _Counter(BlockedStateNotifier.instance);

      await _repo.retroactivelyBlock('Bentley', false);

      expect(await _blocked('a'), 0);
      expect(blocked.count, 1,
          reason: 'the listener re-queries and finds nothing changed, which '
              'is cheap; suppressing the signal would mean deciding here '
              'what the screens can already see for themselves');
    });
  });

  group('deleting a keyword', () {
    test('unblocks the rows and announces it', () async {
      await _insert('a', 'Bentley unveils a new EV');
      await _repo.retroactivelyBlock('Bentley', false);
      expect(await _blocked('a'), 1);

      final blocked = _Counter(BlockedStateNotifier.instance);
      final alerts = _Counter(AlertsChangedNotifier.instance);

      await _repo.unblockByKeyword('Bentley');

      expect(await _blocked('a'), 0);
      expect(blocked.count, 1,
          reason: 'removing a keyword has to put the articles back on screen, '
              'which is the same staleness in the other direction');
      expect(alerts.count, 1);
    });
  });

  group('whole-word matching is unchanged by the signal', () {
    test('a substring does not match when wholeWord is on', () async {
      await _insert('a', 'Bentleys are cars');
      final blocked = _Counter(BlockedStateNotifier.instance);

      await _repo.retroactivelyBlock('Bentley', true);

      expect(await _blocked('a'), 0,
          reason: 'the notifier must not have changed what gets blocked');
      expect(blocked.count, 1);
    });
  });
}
