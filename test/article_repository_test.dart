import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/utils/constants.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

late ArticleRepository _repo;

final _now = DateTime.now();
final _recent = _now.subtract(const Duration(days: 1));
final _old = _now.subtract(const Duration(days: 8));

Article _art(int i, {DateTime? published}) => Article(
      feedId: 1,
      guid: 'guid-$i',
      title: 'Article $i',
      url: 'https://example.com/$i',
      publishedAt: published?.millisecondsSinceEpoch,
      fetchedAt: 0,
    );

Future<void> _setUp({bool twoFolders = false}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;

  final f1 = await db.insert(
      TableNames.folders, {'name': 'Cat1', 'position': 0, 'created_at': ts});
  await db.insert(TableNames.feeds, {
    'folder_id': f1,
    'title': 'Feed1',
    'url': 'https://a.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });

  if (twoFolders) {
    final f2 = await db.insert(
        TableNames.folders, {'name': 'Cat2', 'position': 1, 'created_at': ts});
    await db.insert(TableNames.feeds, {
      'folder_id': f2,
      'title': 'Feed2',
      'url': 'https://b.com/feed',
      'consecutive_failures': 0,
      'is_dead': 0,
      'position': 0,
      'created_at': ts,
    });
  }
}

Future<void> _tearDown() async => AppDatabase.instance.close();

Future<int> _count() async {
  final db = await AppDatabase.instance.database;
  final r =
      await db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.articles}');
  return r.first['c'] as int;
}

Future<Map<String, dynamic>?> _row(String guid) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles,
      where: 'guid = ?', whereArgs: [guid], limit: 1);
  return rows.isEmpty ? null : rows.first;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('insertArticles', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('writes new articles to the DB', () async {
      await _repo.insertArticles(1, [_art(1, published: _recent)]);
      expect(await _count(), 1);
    });

    test('skips articles whose feed_id + guid already exist', () async {
      final a = _art(1, published: _recent);
      await _repo.insertArticles(1, [a]);
      await _repo.insertArticles(1, [a]);
      expect(await _count(), 1);
    });

    // The return value is what refresh_service.dart now bases the
    // keyword-alert notification on: a repeat notification for an
    // already-seen article was the entire reported bug, and it traced back to
    // treating every re-parsed article as new rather than checking this.
    group('the returned "genuinely new" set', () {
      test('a first-time article comes back as new', () async {
        final a = _art(1, published: _recent);
        final result = await _repo.insertArticles(1, [a]);
        expect(result.map((r) => r.guid), [a.guid]);
      });

      test('re-inserting the same article returns nothing the second time',
          () async {
        final a = _art(2, published: _recent);
        await _repo.insertArticles(1, [a]);
        final second = await _repo.insertArticles(1, [a]);
        expect(second, isEmpty,
            reason: 'a re-fetched article the feed is still serving must not '
                'be reported as new — this is what used to fire a keyword '
                'alert notification on every single refresh');
      });

      test('a mixed batch reports only the ones actually new this call',
          () async {
        final old = _art(3, published: _recent);
        await _repo.insertArticles(1, [old]);

        final fresh = _art(4, published: _recent);
        final result = await _repo.insertArticles(1, [old, fresh]);

        expect(result.map((r) => r.guid).toSet(), {fresh.guid});
      });

      test('a tombstoned guid is not reported as new even though it never '
          'made it into the table', () async {
        final db = await AppDatabase.instance.database;
        await db.insert(TableNames.deletedArticles, {
          'feed_id': 1,
          'guid': 'guid-5',
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
        });
        final a = _art(5, published: _recent);

        final result = await _repo.insertArticles(1, [a]);

        expect(result, isEmpty);
        expect(await _row('guid-5'), isNull,
            reason: 'the tombstone must still block the insert itself, same '
                'as before this change');
      });
    });

    // A test round-tripping matched_alert_keyword through the article row
    // stood here. The column is gone: as a column a match had no existence
    // apart from the article, so retirement, cleanup and the tombstone system
    // all destroyed it. A match is now a row in alert_matches carrying its own
    // snapshot, and insertArticles has nothing to say about it. What this
    // proved is covered by test/alert_match_repository_test.dart (the write
    // and read-back) and test/alert_persistence_test.dart (surviving the
    // deletion paths that used to take it).
  });

  group('markAsRead / markAsUnread', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('markAsRead sets is_read=1 for the correct article only', () async {
      await _repo.insertArticles(
          1, [_art(1, published: _recent), _art(2, published: _recent)]);
      final db = await AppDatabase.instance.database;
      final id1 = (await db.query(TableNames.articles,
              where: 'guid = ?', whereArgs: ['guid-1'], limit: 1))
          .first['id'] as int;
      await _repo.markAsRead(id1);
      expect((await _row('guid-1'))!['is_read'], 1);
      expect((await _row('guid-2'))!['is_read'], 0);
    });

    test('markAsUnread sets is_read=0 for the correct article only', () async {
      await _repo.insertArticles(
          1, [_art(1, published: _recent), _art(2, published: _recent)]);
      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles);
      final id1 = rows.first['id'] as int;
      final id2 = rows.last['id'] as int;
      await _repo.markAsRead(id1);
      await _repo.markAsRead(id2);
      await _repo.markAsUnread(id1);
      expect((await _row('guid-1'))!['is_read'], 0);
      expect((await _row('guid-2'))!['is_read'], 1);
    });
  });

  group('markAllAsRead', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('sets is_read=1 for every article in the DB', () async {
      await _repo.insertArticles(1, [
        _art(1, published: _recent),
        _art(2, published: _recent),
        _art(3, published: _recent),
      ]);
      await _repo.markAllAsRead();
      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles);
      expect(rows.every((r) => r['is_read'] == 1), isTrue);
    });
  });

  group('markAllAsReadByFolder', () {
    setUp(() => _setUp(twoFolders: true));
    tearDown(_tearDown);

    test('sets is_read=1 only for articles in the given folder', () async {
      // Feed 1 is folder 1; feed 2 is folder 2. Insert one article each.
      await _repo.insertArticles(1, [_art(1, published: _recent)]);
      await _repo.insertArticles(2, [_art(2, published: _recent)]);

      final db = await AppDatabase.instance.database;
      final f1 = (await db.query(TableNames.folders,
              where: 'name = ?', whereArgs: ['Cat1'], limit: 1))
          .first['id'] as int;
      await _repo.markAllAsReadByFolder(f1);

      expect((await _row('guid-1'))!['is_read'], 1);
      expect((await _row('guid-2'))!['is_read'], 0);
    });

    test('does not affect articles in other folders', () async {
      await _repo.insertArticles(1, [_art(1, published: _recent)]);
      await _repo.insertArticles(2, [_art(2, published: _recent)]);

      final db = await AppDatabase.instance.database;
      final f2 = (await db.query(TableNames.folders,
              where: 'name = ?', whereArgs: ['Cat2'], limit: 1))
          .first['id'] as int;
      await _repo.markAllAsReadByFolder(f2);

      expect((await _row('guid-1'))!['is_read'], 0);
      expect((await _row('guid-2'))!['is_read'], 1);
    });
  });

  group('runCleanup', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('deletes read articles where published_at is older than 7 days',
        () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.markAllAsRead();
      await _repo.runCleanup();
      expect(await _count(), 0);
    });

    test('does not delete read articles where published_at is within 7 days',
        () async {
      await _repo.insertArticles(1, [_art(1, published: _recent)]);
      await _repo.markAllAsRead();
      await _repo.runCleanup();
      expect(await _count(), 1);
    });

    // Extended rather than renamed. This was one test called "does not delete
    // unread articles regardless of age", and its fixture could not prove that
    // claim: `_old` is 8 days, while runCleanup's unread branch only deletes
    // past the fixed kUnreadRetentionDays floor of 15, so the branch it named
    // never ran. Both halves are worth pinning, so it is now two tests — the
    // original assertion under an honest name, plus the case that actually
    // crosses the floor and shows "regardless of age" was never true.
    test('an unread article is exempt from the read cutoff', () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      // Do NOT mark as read.
      await _repo.runCleanup();
      expect(await _count(), 1);
    });

    test('an unread article past the fixed retention floor is deleted',
        () async {
      final beyondFloor =
          _now.subtract(const Duration(days: kUnreadRetentionDays + 1));
      await _repo.insertArticles(1, [_art(1, published: beyondFloor)]);

      await _repo.runCleanup();

      expect(await _count(), 0,
          reason: 'past kUnreadRetentionDays no Article age setting can bring '
              'it back into the list, so leaving it in the table only keeps '
              'inflating the unread badge with articles nobody can reach');
    });

    test('returns the number of rows deleted', () async {
      await _repo.insertArticles(1, [
        _art(1, published: _old),
        _art(2, published: _old),
        _art(3, published: _recent),
      ]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup();
      expect(deleted, 2);
    });

    test('does not delete saved articles even if old and read', () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      // Saved through setSaved rather than on the way in: insertArticles binds
      // a.isSaved, so the fixture could set it itself — it is is_read that the
      // insert hardcodes to 0. Going through the real method is still the
      // right call here, because setSaved is what the bookmark button uses and
      // this test is about what cleanup does to a bookmark.
      final db = await AppDatabase.instance.database;
      final id =
          (await db.query(TableNames.articles, limit: 1)).first['id'] as int;
      await _repo.setSaved(id, saved: true);
      await _repo.markAllAsRead();
      await _repo.runCleanup();
      expect(await _count(), 1);
    });
  });

  group('runCleanup with folderId', () {
    setUp(() => _setUp(twoFolders: true));
    tearDown(_tearDown);

    test('deletes only that folder\'s eligible articles', () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.insertArticles(2, [_art(2, published: _old)]);
      await _repo.markAllAsRead();

      final db = await AppDatabase.instance.database;
      final f1 = (await db.query(TableNames.folders,
              where: 'name = ?', whereArgs: ['Cat1'], limit: 1))
          .first['id'] as int;
      final deleted = await _repo.runCleanup(folderId: f1);

      expect(deleted, 1);
      expect(await _row('guid-1'), isNull);
      expect(await _row('guid-2'), isNotNull);
    });

    test('does not delete eligible articles in other folders', () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.insertArticles(2, [_art(2, published: _old)]);
      await _repo.markAllAsRead();

      final db = await AppDatabase.instance.database;
      final f1 = (await db.query(TableNames.folders,
              where: 'name = ?', whereArgs: ['Cat1'], limit: 1))
          .first['id'] as int;
      await _repo.runCleanup(folderId: f1);

      expect((await _row('guid-2'))!['is_read'], 1);
    });
  });

  group('unread counts', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('getTotalUnreadCount returns correct count', () async {
      await _repo.insertArticles(1, [
        _art(1, published: _recent),
        _art(2, published: _recent),
      ]);
      expect(await _repo.getTotalUnreadCount(), 2);
    });

    test('getUnreadCount returns count for a specific folder', () async {
      await _repo.insertArticles(1, [
        _art(1, published: _recent),
        _art(2, published: _recent),
      ]);
      final db = await AppDatabase.instance.database;
      final f1 =
          (await db.query(TableNames.folders, limit: 1)).first['id'] as int;
      expect(await _repo.getUnreadCount(f1), 2);
    });
  });

  group('markAllAsRead + runCleanup combined', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('articles within 7 days remain in DB as read after combined operation',
        () async {
      await _repo.insertArticles(1, [_art(1, published: _recent)]);
      await _repo.markAllAsRead();
      await _repo.runCleanup();
      final row = await _row('guid-1');
      expect(row, isNotNull);
      expect(row!['is_read'], 1);
    });

    test('articles older than 7 days are gone from DB after combined operation',
        () async {
      await _repo.insertArticles(1, [_art(1, published: _old)]);
      await _repo.markAllAsRead();
      await _repo.runCleanup();
      expect(await _row('guid-1'), isNull);
    });
  });

  group('kFetchDayLimit used in cleanup', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('cleanup cutoff is based on kFetchDayLimit days ago', () async {
      // Article 5 seconds inside the safe zone (just under kFetchDayLimit days
      // old) must NOT be deleted. Using a buffer avoids a sub-millisecond race
      // between the test's DateTime.now() and runCleanup()'s DateTime.now().
      final justWithin = DateTime.now()
          .subtract(const Duration(days: kFetchDayLimit))
          .add(const Duration(seconds: 5));
      await _repo.insertArticles(1, [_art(1, published: justWithin)]);
      await _repo.markAllAsRead();
      // runCleanup deletes where published_at < cutoff (strictly less than).
      // justWithin is >= cutoff, so it is NOT deleted.
      final deleted = await _repo.runCleanup();
      expect(deleted, 0);
    });
  });

  // A 'keyword alerts' group covering retroactivelyMatchAlert and
  // clearAlertMatchesByKeyword stood here. Both methods are gone with the
  // column they wrote, and two of the decisions those tests pinned are ones
  // this rework deliberately reverses: the `is_saved = 1` auto-bookmark that
  // kept a match alive by parking it in Bookmarks, and first-match-wins, which
  // threw away the second keyword an article matched. Keeping them adapted
  // would have preserved exactly the behaviour the new table exists to undo.
  //
  // The behaviour that is still wanted moved with the code:
  // backfillKeyword and deleteByKeyword are covered by
  // test/alert_match_repository_test.dart, whole-word matching by
  // test/keyword_matcher_test.dart, and the guarantee that a match survives
  // cleanup and retirement — which the auto-bookmark was standing in for — by
  // test/alert_persistence_test.dart.
}
