// The v15 alert-match backfill.
//
// v14 added `matched_alert_keyword` via `ALTER TABLE ... ADD COLUMN`, which
// leaves it NULL on every article that already existed — matching only ever
// ran at insert time in RssService.fetchAndStore, so nothing had a chance to
// evaluate a row already sitting in the table before v14 landed. This is the
// concrete explanation for a real report: an alert keyword ("zelda") that
// matched an article already on the device, added before the alert was
// configured, that was never reflected in the Keyword Alerts panel.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';

const int _now = 1750000000000;

late Database _db;
late int _feedId;

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
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

/// Same pragma dance as migration_v13_rebuild_test.dart's `_migrate`: onOpen
/// re-enables foreign key enforcement, which migrateForTesting runs under
/// unless this mirrors it, exercising a configuration production never uses.
Future<void> _migrate({required int from}) async {
  await _db.execute('PRAGMA foreign_keys = OFF');
  await AppDatabase.instance.migrateForTesting(fromVersion: from);
  await _db.execute('PRAGMA foreign_keys = ON');
}

Future<int> _insertArticle(String guid, String title,
    {String? description, String? matchedAlertKeyword, bool saved = false}) async {
  return _db.insert(TableNames.articles, {
    'feed_id': _feedId,
    'guid': guid,
    'title': title,
    'url': 'https://example.com/$guid',
    'description': description,
    'published_at': _now,
    'fetched_at': _now,
    'is_read': 0,
    'is_blocked': 0,
    'is_saved': saved ? 1 : 0,
    'matched_alert_keyword': matchedAlertKeyword,
  });
}

Future<void> _insertAlert(String keyword, {bool wholeWord = false}) async {
  await _db.insert(TableNames.keywordAlerts, {
    'keyword': keyword,
    'whole_word': wholeWord ? 1 : 0,
    'created_at': _now,
  });
}

Future<Map<String, Object?>> _article(int id) async {
  final rows =
      await _db.query(TableNames.articles, where: 'id = ?', whereArgs: [id]);
  return rows.single;
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  test('an article already on the device before the alert existed gets matched',
      () async {
    // The reported scenario: the article predates both v14 and the alert.
    final id = await _insertArticle('a1', 'Nintendo teases new Zelda game');
    await _insertAlert('zelda');

    await _migrate(from: 14);

    final row = await _article(id);
    expect(row['matched_alert_keyword'], 'zelda');
  });

  test('a matched article is auto-bookmarked by the backfill, same as a live match',
      () async {
    final id = await _insertArticle('a2', 'Zelda 40th anniversary announced');
    await _insertAlert('zelda');

    await _migrate(from: 14);

    final row = await _article(id);
    expect(row['is_saved'], 1,
        reason: 'the bookmark is what keeps a match from being deleted by '
            'the normal read-flush / cleanup path');
  });

  test('a non-matching article is left alone', () async {
    final id = await _insertArticle('a3', 'Completely unrelated tech news');
    await _insertAlert('zelda');

    await _migrate(from: 14);

    final row = await _article(id);
    expect(row['matched_alert_keyword'], isNull);
    expect(row['is_saved'], 0);
  });

  test('an article already matched by one alert is not reassigned to another',
      () async {
    final id = await _insertArticle(
      'a4',
      'Zelda and Mario team up',
      matchedAlertKeyword: 'mario',
      saved: true,
    );
    await _insertAlert('zelda');
    await _insertAlert('mario');

    await _migrate(from: 14);

    final row = await _article(id);
    expect(row['matched_alert_keyword'], 'mario',
        reason: 'the pre-existing match must win, mirroring the '
            'matched_alert_keyword IS NULL restriction the live retroactive '
            'path already uses');
  });

  test('no configured alerts is a no-op, not a crash', () async {
    final id = await _insertArticle('a5', 'Zelda news with no alerts configured');

    await _migrate(from: 14);

    final row = await _article(id);
    expect(row['matched_alert_keyword'], isNull);
    expect(row['is_saved'], 0);
  });

  test('whole-word matching is respected during the backfill', () async {
    final id = await _insertArticle('a6', 'A cryptocurrency explainer');
    await _insertAlert('crypto', wholeWord: true);

    await _migrate(from: 14);

    final row = await _article(id);
    expect(row['matched_alert_keyword'], isNull,
        reason: '"crypto" whole-word must not match inside "cryptocurrency"');
  });
}
