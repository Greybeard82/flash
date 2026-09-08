// The retirement guard, written against the behaviour it must preserve rather
// than against the implementation.
//
// Context: every tab tap ran retireAllRead(), which opens a transaction and
// executes an INSERT and a DELETE even when nothing is read. Measured on the
// Lenovo tablet that per-tap database work costs ~1.7pp of janky frames and
// doubles p95. The fix is to stop calling it when it provably has nothing to
// do — so the assertions here are mostly about what must NOT change.
//
// Plain test(), not testWidgets(): this codebase never combines testWidgets()
// with real sqflite FFI I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';

late ArticleRepository _repo;
late int _feed1;
late int _feed2;

Article _art(int i, {int feedId = 1}) => Article(
      feedId: feedId,
      guid: 'guid-$i',
      title: 'Article $i',
      url: 'https://example.com/$i',
      fetchedAt: 0,
    );

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;

  final folderA = await db.insert(
      TableNames.folders, {'name': 'A', 'position': 0, 'created_at': ts});
  final folderB = await db.insert(
      TableNames.folders, {'name': 'B', 'position': 1, 'created_at': ts});

  _feed1 = await db.insert(TableNames.feeds, {
    'folder_id': folderA,
    'title': 'Feed1',
    'url': 'https://a.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });
  _feed2 = await db.insert(TableNames.feeds, {
    'folder_id': folderB,
    'title': 'Feed2',
    'url': 'https://b.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 1,
    'created_at': ts,
  });
}

Future<int> _countArticles() async {
  final db = await AppDatabase.instance.database;
  final r = await db.rawQuery('SELECT COUNT(*) c FROM ${TableNames.articles}');
  return r.first['c'] as int;
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('hasRetirableRead reports what retireAllRead would act on', () {
    test('false on an empty database', () async {
      expect(await _repo.hasRetirableRead(), isFalse);
    });

    test('false when every article is unread', () async {
      await _repo.insertArticles(_feed1, [_art(1), _art(2)]);
      expect(await _repo.hasRetirableRead(), isFalse);
    });

    test('true once an article is read', () async {
      await _repo.insertArticles(_feed1, [_art(1)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);
      expect(await _repo.hasRetirableRead(), isTrue);
    });

    test('false when the only read article is bookmarked', () async {
      await _repo.insertArticles(_feed1, [_art(1)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);
      await _repo.setSaved(all.first.id!, saved: true);

      // retireAllRead excludes is_saved = 0, so a saved read article is not
      // retirable and the guard must agree — otherwise the guard would send
      // the caller into a transaction that deletes nothing, which is the
      // whole cost being removed.
      expect(await _repo.hasRetirableRead(), isFalse);
    });

    test('false again after a retire has run', () async {
      await _repo.insertArticles(_feed1, [_art(1)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);

      await _repo.retireAllRead();
      expect(await _repo.hasRetirableRead(), isFalse);
    });

    test('folder scope matches retireAllRead\'s scope', () async {
      await _repo.insertArticles(_feed2, [_art(1)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);

      final db = await AppDatabase.instance.database;
      final folders =
          await db.query(TableNames.folders, orderBy: 'position ASC');
      final folderA = folders.first['id'] as int;
      final folderB = folders.last['id'] as int;

      // The read article is in folder B only.
      expect(await _repo.hasRetirableRead(folderId: folderA), isFalse);
      expect(await _repo.hasRetirableRead(folderId: folderB), isTrue);
    });
  });

  group('the guard is equivalent to calling and getting nothing', () {
    test('retireAllRead deletes nothing exactly when the guard says false',
        () async {
      await _repo.insertArticles(_feed1, [_art(1), _art(2)]);

      expect(await _repo.hasRetirableRead(), isFalse);
      expect(await _repo.retireAllRead(), 0,
          reason: 'guard false must mean the call would have been a no-op');

      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);

      expect(await _repo.hasRetirableRead(), isTrue);
      expect(await _repo.retireAllRead(), greaterThan(0),
          reason: 'guard true must mean the call has real work');
    });
  });

  group('retirement behaviour is unchanged', () {
    test('read articles still retire', () async {
      await _repo.insertArticles(_feed1, [_art(1), _art(2)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);

      await _repo.retireAllRead();

      expect(await _countArticles(), 1);
      final left = await _repo.getAllArticles(showRead: true);
      expect(left.single.isRead, isFalse);
    });

    test('unread articles are never deleted', () async {
      await _repo.insertArticles(_feed1, [_art(1), _art(2)]);
      await _repo.insertArticles(_feed2, [_art(3)]);
      await _repo.retireAllRead();
      expect(await _countArticles(), 3);
    });

    test('bookmarked read articles survive retirement', () async {
      await _repo.insertArticles(_feed1, [_art(1), _art(2)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all[0].id!);
      await _repo.markAsRead(all[1].id!);
      await _repo.setSaved(all[0].id!, saved: true);

      await _repo.retireAllRead();

      // Asserted against the table, not getAllArticles: the feed list applies
      // its own visibility rules on top, so a row can survive retirement and
      // still not appear there. What must hold is that the row is not deleted.
      final db = await AppDatabase.instance.database;
      final left = await db.query(TableNames.articles);
      expect(left.length, 1, reason: 'the bookmarked article must survive');
      expect(left.single['is_saved'], 1);
      expect(left.single['guid'], all[0].guid);
      expect(left.single['is_read'], 1,
          reason: 'it stays read — retirement was skipped, not undone');
    });

    test('a retired article is tombstoned so it cannot come back', () async {
      await _repo.insertArticles(_feed1, [_art(1)]);
      final all = await _repo.getAllArticles(showRead: true);
      await _repo.markAsRead(all.first.id!);
      await _repo.retireAllRead();

      final db = await AppDatabase.instance.database;
      final tombs = await db.query(TableNames.deletedArticles);
      expect(tombs.length, 1);
      expect(tombs.first['guid'], 'guid-1');
    });

    test('alert_matches survives retirement of its article', () async {
      await _repo.insertArticles(_feed1, [_art(1)]);
      final all = await _repo.getAllArticles(showRead: true);

      // alert_matches keeps its own copy of feed_id/guid/title/url and has no
      // foreign key to articles, so retiring an article cannot cascade into
      // it. That independence is what lets an alert stay readable after the
      // article behind it has been retired — assert it rather than assume it.
      final db = await AppDatabase.instance.database;
      await db.insert(TableNames.alertMatches, {
        'feed_id': _feed1,
        'guid': 'guid-1',
        'keyword': 'zelda',
        'title': 'Article 1',
        'url': 'https://example.com/1',
        'matched_at': DateTime.now().millisecondsSinceEpoch,
        'is_read': 0,
      });

      await _repo.markAsRead(all.first.id!);
      await _repo.retireAllRead();

      expect(await _countArticles(), 0, reason: 'the article should be gone');
      final matches = await db.query(TableNames.alertMatches);
      expect(matches.length, 1, reason: 'the alert match must survive');
      expect(matches.first['guid'], 'guid-1');
    });
  });
}
