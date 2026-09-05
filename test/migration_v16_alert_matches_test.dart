// The v15 -> v16 move of alert matches out of `articles` and into their own
// table.
//
// Up to v15 an alert match was a *column* on the article:
// `matched_alert_keyword`. That gave a match no existence of its own.
// retireAllRead deleted the article row, runCleanup deleted the article row,
// and the tombstone written into deleted_articles then guaranteed the next
// refresh could not bring it back — so the thing the user asked to be told
// about disappeared on its own, silently, and the Alerts panel emptied itself.
// The interim patch was to force `is_saved = 1` on every match, which parked
// alerts in Bookmarks next to deliberately saved articles with nothing to tell
// them apart, and left the alert exactly one un-bookmark away from deletion.
// Matching was also first-match-wins, so an article hitting two configured
// keywords was filed under one of them and the other attribution was thrown
// away for good.
//
// v16 makes a match a row: `alert_matches` carries its own copy of the title,
// url, images and feed identity, and deliberately has NO foreign key to feeds,
// so the snapshot outlives the article, the cleanup, and the feed itself.
//
// This suite guards the one upgrade path that matters — v15, which is what a
// real device is running today, with matched_alert_keyword populated and
// is_saved forced on. The failures it exists to catch are the quiet ones: a
// table rebuild that drops one column too many or shifts the copy, a backfill
// that loses read state or the feed join, and a re-scan that never recovers
// the second keyword the old logic discarded.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';

const int _now = 1750000000000;

/// Kept distinct from [_fetched] so `matched_at == fetched_at` is an assertion
/// about the right column rather than a coincidence.
const int _published = _now;
const int _fetched = _now + 60000;

late Database _db;
late int _folderId;
late int _feedId;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _db = await AppDatabase.instance.database;

  _folderId = await _db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _feedId = await _db.insert(TableNames.feeds, {
    'folder_id': _folderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'favicon_path': '/icons/a.png',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });

  await _shapeAsV15();
}

/// Turns the freshly-created database back into the shape a v15 device
/// actually has, so the migration is exercised against its real input.
///
/// Derived from the migration steps rather than guessed: v16 adds
/// `alert_matches` and `alert_notification_ids` and removes
/// `matched_alert_keyword`, which v14 appended with ALTER TABLE ADD COLUMN —
/// so it belongs last in the column list, exactly where ADD COLUMN puts it
/// back here.
Future<void> _shapeAsV15() async {
  await _db.execute('DROP TABLE IF EXISTS ${TableNames.alertMatches}');
  await _db.execute('DROP TABLE IF EXISTS ${TableNames.alertNotificationIds}');
  final cols = await _columns(TableNames.articles);
  if (!cols.contains('matched_alert_keyword')) {
    await _db.execute('ALTER TABLE ${TableNames.articles} '
        'ADD COLUMN matched_alert_keyword TEXT');
  }
}

/// Same pragma dance as migration_v13_rebuild_test.dart's `_migrate`: onOpen
/// re-enables foreign key enforcement, which migrateForTesting would otherwise
/// run under — and the v16 articles rebuild, like v13's, drops a table that
/// article_summaries cascades from. Without this the test exercises a
/// configuration production never uses.
Future<void> _migrate({required int from}) async {
  await _db.execute('PRAGMA foreign_keys = OFF');
  await AppDatabase.instance.migrateForTesting(fromVersion: from);
  await _db.execute('PRAGMA foreign_keys = ON');
}

Future<int> _insertArticle(
  String guid,
  String title, {
  String? description,
  String? matchedAlertKeyword,
  bool read = false,
  bool saved = false,
  bool blocked = false,
  String? blockedKeyword,
}) async {
  return _db.insert(TableNames.articles, {
    'feed_id': _feedId,
    'guid': guid,
    'title': title,
    'url': 'https://example.com/$guid',
    'description': description,
    'thumbnail_url': 'https://example.com/$guid.png',
    'thumbnail_path': '/thumbs/$guid.png',
    'published_at': _published,
    'fetched_at': _fetched,
    'is_read': read ? 1 : 0,
    'is_blocked': blocked ? 1 : 0,
    'is_saved': saved ? 1 : 0,
    'blocked_keyword': blockedKeyword,
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

Future<List<String>> _columns(String table) async {
  final rows = await _db.rawQuery('PRAGMA table_info($table)');
  return [for (final r in rows) r['name'] as String];
}

/// Index name -> its SQL definition, for [table].
Future<Map<String, String?>> _indexes(
    [String table = TableNames.articles]) async {
  final rows = await _db.rawQuery(
    "SELECT name, sql FROM sqlite_master "
    "WHERE type = 'index' AND tbl_name = '$table'",
  );
  return {
    for (final r in rows)
      r['name'] as String:
          (r['sql'] as String?)?.replaceAll(RegExp(r'\s+'), ' ').trim(),
  };
}

Future<bool> _tableExists(String name) async {
  final rows = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='$name'");
  return rows.isNotEmpty;
}

/// alert_matches rows in keyword order, so assertions can read positionally.
Future<List<Map<String, Object?>>> _matches({String? guid}) async {
  return _db.query(
    TableNames.alertMatches,
    where: guid == null ? null : 'guid = ?',
    whereArgs: guid == null ? null : [guid],
    orderBy: 'keyword ASC',
  );
}

Future<Map<String, Object?>> _article(int id) async {
  final rows =
      await _db.query(TableNames.articles, where: 'id = ?', whereArgs: [id]);
  return rows.single;
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  group('the backfill turns the column into a row', () {
    test('an alert-matched article becomes one fully populated snapshot',
        () async {
      // The alert row matters: the backfill only resurrects a match whose
      // keyword still exists, so a v15 device is modelled with both halves.
      await _insertAlert('zelda');
      await _insertArticle(
        'a1',
        'Nintendo teases new Zelda game',
        description: 'A short blurb',
        matchedAlertKeyword: 'zelda',
      );

      await _migrate(from: 15);

      final rows = await _matches(guid: 'a1');
      expect(rows, hasLength(1),
          reason: 'one recorded match must produce one row — a match with no '
              'row is an alert the user configured and will never be shown');
      final m = rows.single;
      expect(m['feed_id'], _feedId);
      expect(m['guid'], 'a1');
      expect(m['keyword'], 'zelda');
      expect(m['title'], 'Nintendo teases new Zelda game');
      expect(m['url'], 'https://example.com/a1');
      expect(m['description'], 'A short blurb');
      expect(m['thumbnail_url'], 'https://example.com/a1.png');
      expect(m['thumbnail_path'], '/thumbs/a1.png');
      expect(m['feed_title'], 'Feed A',
          reason: 'the card has to render after the feed is gone, so feed '
              'identity is copied in rather than looked up later');
      expect(m['feed_favicon_path'], '/icons/a.png');
      expect(m['folder_id'], _folderId,
          reason: 'folder scoping and mark-folder-read work off this copy');
      expect(m['published_at'], _published);
      expect(m['matched_at'], _fetched,
          reason: 'fetched_at is the only honest answer to "when did this '
              'match" for a row that predates the table; published_at would '
              'sort a back-dated article to the bottom of the Alerts tab');
      expect(m['is_read'], 0);
    });

    test('read state carries across, so a read alert does not come back unread',
        () async {
      await _insertAlert('zelda');
      await _insertArticle('a2', 'Zelda 40th anniversary announced',
          matchedAlertKeyword: 'zelda', read: true);

      await _migrate(from: 15);

      expect((await _matches(guid: 'a2')).single['is_read'], 1,
          reason: 'losing this re-raises every already-read alert as new and '
              'inflates the Alerts badge on first launch after the upgrade');
    });

    test('a blocked article is left behind by both halves of the upgrade',
        () async {
      // Two separate filters have to hold for this: the SQL backfill's
      // `is_blocked = 0`, and the re-scan's. v15 wrote matched_alert_keyword
      // without consulting the blocklist at all, so a v15 device really can
      // arrive here with a blocked article already carrying a match — which is
      // why the backfill cannot simply trust the column.
      await _insertAlert('zelda');
      await _insertArticle('b1', 'Nintendo teases new Zelda game',
          matchedAlertKeyword: 'zelda',
          blocked: true,
          blockedKeyword: 'nintendo');

      await _migrate(from: 15);

      expect(await _matches(guid: 'b1'), isEmpty,
          reason: 'the blocklist wins over an alert. A blocked article that '
              'became an alert_matches row would be permanent and would show '
              'on the Alerts tab, which is the one list no cleanup can reach');
    });

    test('a match whose keyword was deleted before the upgrade is not revived',
        () async {
      // The column was never cleared when an alert was deleted, so a v15
      // device still carries 'zelda' stamps long after the user removed the
      // keyword. Reviving them would create alert_matches rows that nothing
      // can ever delete: §3.4 allows exactly three deletions — the user bins
      // it, its keyword is deleted, or its keyword is edited — and the last
      // two cannot fire for a keyword that no longer exists. The Alerts tab
      // would carry a chip absent from Manage keywords forever.
      await _insertAlert('mario');
      await _insertArticle('a9', 'Zelda 40th anniversary',
          matchedAlertKeyword: 'zelda');

      await _migrate(from: 15);

      final rows = await _matches(guid: 'a9');
      expect(rows.where((r) => r['keyword'] == 'zelda'), isEmpty,
          reason: 'a keyword the user deleted must not come back as an '
              'undeletable row');
      expect(rows, isEmpty,
          reason: 'and the re-scan must not invent one either — "mario" does '
              'not appear in this title');
    });

    test('a live keyword still backfills when a dead one sits beside it',
        () async {
      // The guard has to be per-row, not "skip the backfill if any keyword is
      // missing" — the far more common upgrade has one deleted keyword and
      // several live ones, and losing the live ones would be the worse bug.
      await _insertAlert('zelda');
      await _insertArticle('a10', 'Zelda 40th anniversary',
          matchedAlertKeyword: 'zelda');
      await _insertArticle('a11', 'Crypto crash', matchedAlertKeyword: 'crypto');

      await _migrate(from: 15);

      expect((await _matches(guid: 'a10')).single['keyword'], 'zelda');
      expect(await _matches(guid: 'a11'), isEmpty);
    });

    test('an article that matched two alerts yields two rows, one per keyword',
        () async {
      // v15 could only ever record one: KeywordAlertRepository.findMatch
      // returned the first hit and stopped. The second attribution was thrown
      // away at insert time, and the only place it can be recovered from is a
      // re-scan of the stored articles against the stored alerts.
      await _insertArticle(
        'a3',
        'Zelda and Mario team up in a crossover',
        matchedAlertKeyword: 'zelda',
      );
      await _insertAlert('zelda');
      await _insertAlert('mario');

      await _migrate(from: 15);

      final rows = await _matches(guid: 'a3');
      expect([for (final r in rows) r['keyword']], ['mario', 'zelda'],
          reason: 'the re-scan recovers the attribution first-match-wins '
              'discarded — without it the "mario" alert stays permanently '
              'empty for an article that plainly matches it');
      for (final r in rows) {
        expect(r['title'], 'Zelda and Mario team up in a crossover');
        expect(r['url'], 'https://example.com/a3');
        expect(r['feed_title'], 'Feed A',
            reason: 'a recovered row is a full snapshot, not a stub');
        expect(r['feed_favicon_path'], '/icons/a.png');
        expect(r['folder_id'], _folderId);
        expect(r['matched_at'], isNotNull);
      }
    });

    test('the re-scan reaches an article that never matched anything in v15',
        () async {
      // matched_alert_keyword was only ever written at insert time, so an
      // article stored before the alert was configured carries NULL forever.
      await _insertArticle('a4', 'Hands on with the new Zelda demo');
      await _insertAlert('zelda');

      await _migrate(from: 15);

      final rows = await _matches(guid: 'a4');
      expect(rows, hasLength(1),
          reason: 'an article already on the device when the alert was added '
              'must appear in the Alerts tab after the upgrade');
      expect(rows.single['keyword'], 'zelda');
      expect(rows.single['is_read'], 0);
    });

    test('whole-word alerts are respected by the re-scan', () async {
      await _insertArticle('a5', 'A cryptocurrency explainer');
      await _insertAlert('crypto', wholeWord: true);

      await _migrate(from: 15);

      expect(await _matches(guid: 'a5'), isEmpty,
          reason: '"crypto" whole-word must not match inside '
              '"cryptocurrency" — the migration has to use the same matcher '
              'the live path does, or the two disagree about what matched');
    });

    test('an article matching nothing produces no rows', () async {
      await _insertArticle('a6', 'Completely unrelated tech news');
      await _insertAlert('zelda');

      await _migrate(from: 15);

      expect(await _matches(guid: 'a6'), isEmpty);
    });
  });

  group('the interim auto-bookmark is cleared', () {
    test('a v15 auto-bookmark on a matched article is still cleared',
        () async {
      // The other side of the `oldVersion >= 15` guard. This database really
      // did run v15, so is_saved = 1 on a matched article is the auto-bookmark
      // and clearing it is the whole point of the step.
      await _insertAlert('zelda');
      final id = await _insertArticle('s1', 'Zelda 40th anniversary',
          matchedAlertKeyword: 'zelda', saved: true);

      await _migrate(from: 15);

      expect((await _article(id))['is_saved'], 0);
      expect(await _matches(guid: 's1'), hasLength(1),
          reason: 'and the alert survives as a row of its own, which is what '
              'made the bookmark unnecessary');
    });


    test('is_saved is 0 on every previously alert-matched article', () async {
      final auto = await _insertArticle('b1', 'Zelda news',
          matchedAlertKeyword: 'zelda', saved: true);
      // The user ALSO deliberately bookmarked this one, and it loses the
      // bookmark too. That is the accepted, deliberate trade-off: is_saved is
      // one flag with no provenance, so there is no way to tell an
      // auto-bookmark the alert system forced on from one the user tapped.
      // Clearing both is the honest option — the alternative leaves every
      // migrated alert sitting in Bookmarks forever, which is the pollution
      // this rework exists to end.
      final deliberate = await _insertArticle('b2', 'Mario news',
          matchedAlertKeyword: 'mario', saved: true);

      await _migrate(from: 15);

      expect((await _article(auto))['is_saved'], 0,
          reason: 'Bookmarks must stop listing alert matches the user never '
              'saved');
      expect((await _article(deliberate))['is_saved'], 0,
          reason: 'accepted trade-off: is_saved cannot distinguish an '
              'auto-bookmark from a deliberate one');
    });

    test('a bookmark on an article no alert ever matched is untouched',
        () async {
      final id =
          await _insertArticle('b3', 'Something the user saved', saved: true);

      await _migrate(from: 15);

      expect((await _article(id))['is_saved'], 1,
          reason: 'the clear is scoped to matched_alert_keyword IS NOT NULL; '
              'widening it empties the whole Bookmarks tab on upgrade');
    });
  });

  group('the articles rebuild preserves the table', () {
    test('matched_alert_keyword is gone afterwards, and nothing else is',
        () async {
      await _insertArticle('c1', 'Zelda news', matchedAlertKeyword: 'zelda');
      final before = await _columns(TableNames.articles);
      expect(before, contains('matched_alert_keyword'),
          reason: 'the fixture is doing its job');

      await _migrate(from: 15);

      final after = await _columns(TableNames.articles);
      expect(after, isNot(contains('matched_alert_keyword')),
          reason: 'a column nothing reads is a standing invitation to write '
              'code that trusts it — the match now lives in alert_matches');
      expect(after, before.where((c) => c != 'matched_alert_keyword').toList(),
          reason: 'every other column survives, in the same order');
    });

    test('row count is identical before and after', () async {
      for (var i = 0; i < 25; i++) {
        await _insertArticle('c$i', 'Article $i',
            read: i.isEven,
            saved: i % 5 == 0,
            matchedAlertKeyword: i % 7 == 0 ? 'zelda' : null);
      }
      final before = (await _db.query(TableNames.articles)).length;

      await _migrate(from: 15);

      expect((await _db.query(TableNames.articles)).length, before);
      expect(before, 25, reason: 'the fixture is doing its job');
    });

    test('every value survives: ids, read state, saved state, blocked_keyword',
        () async {
      final keepId = await _insertArticle(
        'keep',
        'Title keep',
        description: 'Body keep',
        read: true,
        saved: true,
        blockedKeyword: 'spoiler',
      );
      final plainId = await _insertArticle('plain', 'Title plain');
      // A matched_alert_keyword present on the way in, to prove the copy does
      // not shift columns when the source table has one more than the target.
      final matchedId = await _insertArticle('matched', 'Zelda title',
          matchedAlertKeyword: 'zelda');

      await _migrate(from: 15);

      final kept = await _article(keepId);
      expect(kept['guid'], 'keep');
      expect(kept['title'], 'Title keep');
      expect(kept['url'], 'https://example.com/keep');
      expect(kept['description'], 'Body keep');
      expect(kept['thumbnail_url'], 'https://example.com/keep.png');
      expect(kept['thumbnail_path'], '/thumbs/keep.png');
      expect(kept['published_at'], _published);
      expect(kept['fetched_at'], _fetched);
      expect(kept['is_read'], 1, reason: 'read state is not recoverable');
      expect(kept['is_saved'], 1, reason: 'a lost bookmark is a lost bookmark');
      expect(kept['is_blocked'], 0);
      expect(kept['blocked_keyword'], 'spoiler');
      expect(kept['feed_id'], _feedId);

      final plain = await _article(plainId);
      expect(plain['is_read'], 0);
      expect(plain['is_saved'], 0);
      expect(plain['id'], plainId, reason: 'ids are carried, not reassigned');

      final matched = await _article(matchedId);
      expect(matched['id'], matchedId,
          reason: 'ids are carried, not reassigned');
      expect(matched['title'], 'Zelda title',
          reason: 'the row that lost a column keeps every other value');
    });

    test('rows referencing articles are not cascade-deleted', () async {
      // article_summaries.article_id REFERENCES articles(id) ON DELETE
      // CASCADE. DROP TABLE with enforcement on would take every summary with
      // it — silently, and with no way back.
      final id =
          await _insertArticle('c-sum', 'Zelda news', matchedAlertKeyword: 'zelda');
      await _db.insert(TableNames.articleSummaries, {
        'article_id': id,
        'summary': 'a summary',
        'model': 'gemini-nano',
        'generated_at': _now,
      });

      await _migrate(from: 15);

      final summaries = await _db.query(TableNames.articleSummaries);
      expect(summaries.length, 1,
          reason: 'the summary must survive its article being rebuilt');
      expect(summaries.single['article_id'], id);
    });

    test('every index present before is present after, same definition',
        () async {
      await _insertArticle('c-idx', 'Title');
      final before = await _indexes();

      await _migrate(from: 15);

      final after = await _indexes();
      expect(after.keys.toSet(), before.keys.toSet(),
          reason: 'DROP TABLE takes every index with it silently — a missing '
              'one shows up as a slow query, or as duplicate articles when '
              'UNIQUE(feed_id, guid) is the one that vanished');
      for (final name in before.keys) {
        expect(after[name], before[name], reason: 'definition of $name');
      }
      expect(
        after.keys.where((k) => k.startsWith('idx_')).toSet(),
        {
          'idx_articles_guid_feed',
          'idx_articles_feed_id',
          'idx_articles_is_read',
          'idx_articles_is_blocked',
          'idx_articles_published_at',
          'idx_articles_read_published',
          'idx_articles_feed_read_published',
        },
      );
    });

    test('the unique guid index still rejects a duplicate', () async {
      await _insertArticle('dupe', 'Title dupe');

      await _migrate(from: 15);

      expect(
          () => _db.insert(TableNames.articles, {
                'feed_id': _feedId,
                'guid': 'dupe',
                'title': 'Title dupe',
                'url': 'https://example.com/dupe',
                'fetched_at': _fetched,
                'is_read': 0,
                'is_blocked': 0,
                'is_saved': 0,
              }),
          throwsA(isA<DatabaseException>()),
          reason: 'dedup depends on this index; losing it in the rebuild '
              'would resurrect duplicate articles in production');
    });

    test('foreign_key_check returns nothing after the rebuild', () async {
      final id =
          await _insertArticle('c-fk', 'Zelda news', matchedAlertKeyword: 'zelda');
      await _db.insert(TableNames.articleSummaries, {
        'article_id': id,
        'summary': 's',
        'model': 'm',
        'generated_at': _now,
      });

      await _migrate(from: 15);

      expect(await _db.rawQuery('PRAGMA foreign_key_check'), isEmpty,
          reason: 'a database with dangling references is worse than one '
              'still on the old schema');
    });

    test('no leftover articles_new scratch table', () async {
      await _migrate(from: 15);

      expect(await _tableExists('articles_new'), isFalse);
    });

    test('a migrated database has the same articles columns as a fresh one',
        () async {
      // Pins the v16 rebuild statement to SchemaStatements.createArticles.
      // They are written out separately for readability, so drift between them
      // has to fail here rather than in somebody's library.
      await _insertArticle('c-fresh', 'Title');
      await _migrate(from: 15);
      final migrated = await _columns(TableNames.articles);

      await AppDatabase.instance.close();
      AppDatabase.useForTesting();
      _db = await AppDatabase.instance.database;
      final fresh = await _columns(TableNames.articles);

      expect(migrated, fresh);
    });
  });

  group('the new tables', () {
    test('a match outlives its feed — there is no foreign key on feed_id',
        () async {
      await _insertAlert('zelda');
      await _insertArticle('d1', 'Zelda news', matchedAlertKeyword: 'zelda');

      await _migrate(from: 15);
      expect(await _matches(guid: 'd1'), hasLength(1),
          reason: 'the fixture is doing its job');

      await _db.delete(TableNames.feeds, where: 'id = ?', whereArgs: [_feedId]);

      expect(
          await _db.query(TableNames.articles,
              where: 'feed_id = ?', whereArgs: [_feedId]),
          isEmpty,
          reason: 'articles.feed_id cascades, which proves enforcement really '
              'is on for this delete — otherwise the assertion below passes '
              'for the wrong reason');
      expect(await _matches(guid: 'd1'), hasLength(1),
          reason: 'the snapshot is the whole point: an alert the user asked '
              'for must not be destroyed by unsubscribing from the feed it '
              'arrived on');
    });

    test('the unique (feed_id, guid, keyword) index rejects a duplicate',
        () async {
      await _migrate(from: 15);

      Future<int> insert() => _db.insert(TableNames.alertMatches, {
            'feed_id': _feedId,
            'guid': 'd2',
            'keyword': 'zelda',
            'title': 'Zelda news',
            'url': 'https://example.com/d2',
            'matched_at': _now,
            'is_read': 0,
          });

      await insert();
      expect(insert, throwsA(isA<DatabaseException>()),
          reason: 'INSERT OR IGNORE dedup for a re-seen article depends on '
              'this index; without it every refresh adds another copy of the '
              'same alert and notifies for it again');
      expect(
          (await _indexes(TableNames.alertMatches)).keys,
          containsAll(<String>[
            'idx_alert_matches_unique',
            'idx_alert_matches_keyword',
            'idx_alert_matches_matched_at',
          ]));
    });

    test('a migrated database has the same alert_matches shape as a fresh one',
        () async {
      await _migrate(from: 15);
      final migratedCols = await _columns(TableNames.alertMatches);
      final migratedIdx = await _indexes(TableNames.alertMatches);

      await AppDatabase.instance.close();
      AppDatabase.useForTesting();
      _db = await AppDatabase.instance.database;

      expect(migratedCols, await _columns(TableNames.alertMatches),
          reason: 'an upgraded device and a fresh install must be able to run '
              'the same queries against the same table');
      final freshIdx = await _indexes(TableNames.alertMatches);
      expect(migratedIdx.keys.toSet(), freshIdx.keys.toSet());
      for (final name in freshIdx.keys) {
        expect(migratedIdx[name], freshIdx[name],
            reason: 'definition of $name');
      }
    });

    test('alert_notification_ids exists and its key column is unique',
        () async {
      await _migrate(from: 15);

      expect(await _tableExists(TableNames.alertNotificationIds), isTrue);
      expect(await _columns(TableNames.alertNotificationIds), ['id', 'key']);

      // The canonical key the planner builds: the sorted keywords joined by
      // NUL, which no keyword can contain, so one set cannot forge another's
      // id.
      final key = ['mario', 'zelda'].join(String.fromCharCode(0));
      final id =
          await _db.insert(TableNames.alertNotificationIds, {'key': key});
      expect(id, greaterThan(0),
          reason: 'the rowid is what makes a stable per-keyword-set '
              'notification id possible at all');
      expect(
          () => _db.insert(TableNames.alertNotificationIds, {'key': key}),
          throwsA(isA<DatabaseException>()),
          reason: 'one keyword set must map to one id for good — a second row '
              'for the same key is a second notification that replaces the '
              'first in the shade, which is the bug this table exists to fix');
    });
  });

  group('idempotence and the empty case', () {
    test('running the migration twice is a no-op the second time', () async {
      await _insertArticle('e1', 'Zelda and Mario team up',
          matchedAlertKeyword: 'zelda', read: true, saved: true);
      await _insertAlert('zelda');
      await _insertAlert('mario');

      await _migrate(from: 15);
      final articlesAfterFirst = await _db.query(TableNames.articles);
      final matchesAfterFirst = await _matches();
      final indexesAfterFirst = await _indexes();
      expect(matchesAfterFirst, hasLength(2),
          reason: 'the fixture is doing its job');

      await _migrate(from: 15);

      expect(await _db.query(TableNames.articles), articlesAfterFirst,
          reason: 'a half-applied upgrade is retried on the next open, so the '
              'second pass must not trip over the column it already dropped');
      expect(await _matches(), matchesAfterFirst,
          reason: 'INSERT OR IGNORE plus the unique index keeps the backfill '
              'safe to re-run — a duplicated match is a duplicated card');
      expect((await _indexes()).keys.toSet(), indexesAfterFirst.keys.toSet());
    });

    test('a v15 database with no alerts and no matches migrates cleanly',
        () async {
      await _insertArticle('e2', 'Just an article');
      await _insertArticle('e3', 'Another one', read: true);

      await _migrate(from: 15);

      expect(await _matches(), isEmpty,
          reason: 'nothing configured, nothing matched, nothing invented');
      expect(await _tableExists(TableNames.alertMatches), isTrue);
      expect(await _tableExists(TableNames.alertNotificationIds), isTrue);
      expect((await _db.query(TableNames.articles)).length, 2);
      expect(await _columns(TableNames.articles),
          isNot(contains('matched_alert_keyword')));
      expect(await _db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  // Every group above enters at v15, which is what a real device is running.
  // A device that skipped a release enters at v14 instead and walks v15 and
  // v16 in one _onUpgrade pass, and the two steps disagree about almost
  // everything: v15 matches first-match-wins and forces is_saved = 1, v16
  // matches every keyword and clears is_saved again. This group is the only
  // cover for that ordering — it used to live in
  // migration_v15_alert_backfill_test.dart, which was deleted with the
  // decisions it pinned.
  group('entering the chain at v14', () {
    test('an article v15 would have matched lands as a snapshot row',
        () async {
      // v14 only ever wrote matched_alert_keyword at insert time, so the
      // column is NULL here and it is the v15 step that fills it in — which
      // v16 then has to find and copy.
      await _insertArticle('f1', 'Nintendo teases new Zelda game');
      await _insertAlert('zelda');

      await _migrate(from: 14);

      final rows = await _matches(guid: 'f1');
      expect(rows, hasLength(1));
      expect(rows.single['keyword'], 'zelda');
      expect(rows.single['feed_title'], 'Feed A',
          reason: 'a row the chain produced is as complete as one v15 '
              'produced — the entry version must not decide how much of the '
              'snapshot survives');
      expect(rows.single['matched_at'], _fetched);
    });

    test('no auto-bookmark is left behind on the way past v15', () async {
      final id = await _insertArticle('f2', 'Zelda 40th anniversary');
      await _insertAlert('zelda');

      await _migrate(from: 14);

      expect((await _article(id))['is_saved'], 0,
          reason: 'v15 sets is_saved = 1 on everything it matches. Running '
              'both steps back to back must not leave that bookmark behind — '
              'the user never made it, and it exists in this database for '
              'milliseconds');
    });

    test('a v14 bookmark on an already-matched article survives', () async {
      // The case the `oldVersion >= 15` guard exists for. v14's fetch path
      // wrote matched_alert_keyword and nothing else — the auto-bookmark
      // arrived only in v15 — so on a v14 device an is_saved = 1 sitting on a
      // matched article is a bookmark the user made by hand, and there is
      // nothing for the clear to undo.
      final id = await _insertArticle('f6', 'Zelda 40th anniversary',
          matchedAlertKeyword: 'zelda', saved: true);
      await _insertAlert('zelda');

      await _migrate(from: 14);

      expect((await _article(id))['is_saved'], 1,
          reason: 'v14 never auto-bookmarked, so clearing this destroys a '
              'bookmark the user made and nothing else');
      expect(await _matches(guid: 'f6'), hasLength(1));
    });

    test('a bookmark the user made by hand survives the whole chain',
        () async {
      // The counterpart to the test above, and the reason the v15 step is
      // skipped when the same pass continues to v16. This article was
      // bookmarked deliberately, months before any alert existed, and it
      // happens to contain a word the user later made an alert for. v15 would
      // stamp matched_alert_keyword on it, and v16's
      // `is_saved = 0 WHERE matched_alert_keyword IS NOT NULL` would then
      // clear a bookmark no alert ever created. Nothing in this rework is
      // allowed to delete a bookmark the user made.
      final id = await _insertArticle('f5', 'Zelda 40th anniversary',
          saved: true);
      await _insertAlert('zelda');

      await _migrate(from: 14);

      expect((await _article(id))['is_saved'], 1,
          reason: 'the alert system never touched is_saved on this device, so '
              'it has no business clearing it');
      expect(await _matches(guid: 'f5'), hasLength(1),
          reason: 'and the alert is still recorded — preserving the bookmark '
              'must not cost the match');
    });

    test('both keywords come back for an article v15 filed under one',
        () async {
      await _insertArticle('f3', 'Zelda and Mario team up in a crossover');
      await _insertAlert('zelda');
      await _insertAlert('mario');

      await _migrate(from: 14);

      expect([for (final r in await _matches(guid: 'f3')) r['keyword']],
          ['mario', 'zelda'],
          reason: 'v15 stops at the first hit and v16 re-scans without one, '
              'so the second attribution has to survive being discarded and '
              'recovered inside a single upgrade');
    });

    test('a v14 database ends up in the same shape as a v15 one', () async {
      await _insertArticle('f4', 'Just an article');

      await _migrate(from: 14);

      expect(await _columns(TableNames.articles),
          isNot(contains('matched_alert_keyword')));
      expect(await _tableExists(TableNames.alertMatches), isTrue);
      expect(await _tableExists(TableNames.alertNotificationIds), isTrue);
      expect(await _db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  });
}
