// Tests for SessionReadTracker (pure in-memory unit tests) and the union
// query in ArticleRepository (integration tests via sqflite_ffi).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/services/session_read_tracker.dart';

// ── DB helpers ────────────────────────────────────────────────────────────────

late ArticleRepository _repo;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();
  SessionReadTracker.instance.clear();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final folderId = await db.insert(
    TableNames.folders,
    {'name': 'Tech', 'position': 0, 'created_at': ts},
  );
  await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed',
    'url': 'https://example.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });
}

Future<void> _tearDown() async {
  SessionReadTracker.instance.clear();
  await AppDatabase.instance.close();
}

Article _art(int i, {bool isRead = false}) => Article(
      feedId: 1,
      guid: 'guid-$i',
      title: 'Article $i',
      url: 'https://example.com/$i',
      publishedAt: DateTime.now().millisecondsSinceEpoch - i * 1000,
      fetchedAt: 0,
      isRead: isRead,
    );

Future<void> _insertAndMaybeMarkRead(List<Article> arts) async {
  await _repo.insertArticles(1, arts);
  for (final a in arts.where((a) => a.isRead)) {
    final db = await AppDatabase.instance.database;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'guid = ?',
      whereArgs: [a.guid],
    );
  }
}

Future<int> _idForGuid(String guid) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles, where: 'guid = ?', whereArgs: [guid]);
  return rows.first['id'] as int;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── SessionReadTracker unit tests ─────────────────────────────────────────

  group('SessionReadTracker', () {
    setUp(() => SessionReadTracker.instance.clear());

    test('starts empty', () {
      expect(SessionReadTracker.instance.ids, isEmpty);
    });

    test('add and contains', () {
      SessionReadTracker.instance.add(1);
      SessionReadTracker.instance.add(2);
      expect(SessionReadTracker.instance.ids, containsAll([1, 2]));
    });

    test('remove', () {
      SessionReadTracker.instance.add(5);
      SessionReadTracker.instance.remove(5);
      expect(SessionReadTracker.instance.ids, isEmpty);
    });

    test('clear removes all', () {
      SessionReadTracker.instance.addAll([1, 2, 3]);
      SessionReadTracker.instance.clear();
      expect(SessionReadTracker.instance.ids, isEmpty);
    });

    test('removeWhere removes matching ids', () {
      SessionReadTracker.instance.addAll([1, 2, 3, 4]);
      for (final id in {2, 4}) {
        SessionReadTracker.instance.remove(id);
      }
      expect(SessionReadTracker.instance.ids, containsAll([1, 3]));
      expect(SessionReadTracker.instance.ids, isNot(contains(2)));
      expect(SessionReadTracker.instance.ids, isNot(contains(4)));
    });

    test('is a singleton', () {
      expect(identical(SessionReadTracker.instance, SessionReadTracker.instance), isTrue);
    });
  });

  // ── Union query integration tests ────────────────────────────────────────

  group('getAllArticles union query', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('empty tracker returns only unread articles', () async {
      await _insertAndMaybeMarkRead([_art(1), _art(2, isRead: true), _art(3)]);
      final result = await _repo.getAllArticles(sessionReadIds: {});
      expect(result.length, 2);
      expect(result.every((a) => !a.isRead), isTrue);
    });

    test('tracker adds read articles back into results', () async {
      await _insertAndMaybeMarkRead([_art(1), _art(2, isRead: true), _art(3)]);
      final id2 = await _idForGuid('guid-2');
      final result = await _repo.getAllArticles(sessionReadIds: {id2});
      expect(result.length, 3);
      expect(result.any((a) => a.id == id2 && a.isRead), isTrue);
    });

    test('cold open (empty tracker) never shows previously-read articles', () async {
      await _insertAndMaybeMarkRead([
        _art(1, isRead: true),
        _art(2, isRead: true),
      ]);
      final result = await _repo.getAllArticles(sessionReadIds: {});
      expect(result, isEmpty);
    });

    test('blocked articles are excluded regardless of tracker', () async {
      await _repo.insertArticles(1, [_art(1)]);
      final db = await AppDatabase.instance.database;
      await db.update(TableNames.articles, {'is_blocked': 1}, where: 'guid = ?', whereArgs: ['guid-1']);
      final id1 = await _idForGuid('guid-1');
      final result = await _repo.getAllArticles(sessionReadIds: {id1});
      expect(result, isEmpty);
    });
  });

  group('getArticlesByFolder union query', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('empty tracker returns only unread for that folder', () async {
      await _insertAndMaybeMarkRead([_art(1), _art(2, isRead: true), _art(3)]);
      final db = await AppDatabase.instance.database;
      final folderId = (await db.query(TableNames.folders)).first['id'] as int;
      final result = await _repo.getArticlesByFolder(folderId, sessionReadIds: {});
      expect(result.length, 2);
    });

    test('tracker adds read article back for that folder', () async {
      await _insertAndMaybeMarkRead([_art(1), _art(2, isRead: true)]);
      final db = await AppDatabase.instance.database;
      final folderId = (await db.query(TableNames.folders)).first['id'] as int;
      final id2 = await _idForGuid('guid-2');
      final result = await _repo.getArticlesByFolder(folderId, sessionReadIds: {id2});
      expect(result.length, 2);
      expect(result.any((a) => a.id == id2 && a.isRead), isTrue);
    });
  });

  // ── Cross-tab global read state ───────────────────────────────────────────

  group('global session read state across scopes', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('article marked read in All scope appears dimmed in folder scope', () async {
      await _insertAndMaybeMarkRead([_art(1), _art(2)]);
      final db = await AppDatabase.instance.database;
      final folderId = (await db.query(TableNames.folders)).first['id'] as int;
      final id1 = await _idForGuid('guid-1');

      // Simulate: user reads article 1 in All tab.
      await _repo.markAsRead(id1);
      SessionReadTracker.instance.add(id1);

      // Folder query with tracker — article 1 still visible, dimmed.
      final result = await _repo.getArticlesByFolder(
        folderId,
        sessionReadIds: SessionReadTracker.instance.ids,
      );
      expect(result.length, 2);
      expect(result.firstWhere((a) => a.id == id1).isRead, isTrue);
    });

    test('mark-unread removes from tracker and restores full weight', () async {
      await _insertAndMaybeMarkRead([_art(1)]);
      final id1 = await _idForGuid('guid-1');

      await _repo.markAsRead(id1);
      SessionReadTracker.instance.add(id1);
      expect(SessionReadTracker.instance.ids, contains(id1));

      await _repo.markAsUnread(id1);
      SessionReadTracker.instance.remove(id1);
      expect(SessionReadTracker.instance.ids, isNot(contains(id1)));

      final result = await _repo.getAllArticles(sessionReadIds: SessionReadTracker.instance.ids);
      expect(result.first.isRead, isFalse);
    });

    test('mark-all-read (All tab) + clear tracker → empty list on reload', () async {
      await _insertAndMaybeMarkRead([_art(1), _art(2)]);
      final id1 = await _idForGuid('guid-1');
      SessionReadTracker.instance.add(id1);

      await _repo.markAllAsRead();
      SessionReadTracker.instance.clear();

      final result = await _repo.getAllArticles(sessionReadIds: SessionReadTracker.instance.ids);
      expect(result, isEmpty);
    });

    test('mark-all-read (Category) removes folder IDs from tracker, others remain', () async {
      // Add a second folder/feed to simulate two-folder setup.
      final db = await AppDatabase.instance.database;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final folder2Id = await db.insert(
        TableNames.folders,
        {'name': 'Sports', 'position': 1, 'created_at': ts},
      );
      await db.insert(TableNames.feeds, {
        'folder_id': folder2Id,
        'title': 'Sports Feed',
        'url': 'https://sports.example.com/feed',
        'consecutive_failures': 0,
        'is_dead': 0,
        'position': 0,
        'created_at': ts,
      });

      await _repo.insertArticles(1, [_art(10), _art(11)]);
      await _repo.insertArticles(2, [_art(20)]);

      final id10 = await _idForGuid('guid-10');
      final id20 = await _idForGuid('guid-20');

      // Read articles from both folders this session.
      await _repo.markAsRead(id10);
      await _repo.markAsRead(id20);
      SessionReadTracker.instance.addAll([id10, id20]);

      final folder1Id = (await db.query(TableNames.folders, where: 'name = ?', whereArgs: ['Tech'])).first['id'] as int;

      // "Mark all read" on folder 1: remove its session IDs from tracker.
      final folder1ArticleIds = {id10}; // simulates _articles IDs for that tab
      await _repo.markAllAsReadByFolder(folder1Id);
      for (final id in folder1ArticleIds) {
        SessionReadTracker.instance.remove(id);
      }

      // Folder 1 articles no longer in tracker; folder 2 article still there.
      expect(SessionReadTracker.instance.ids, isNot(contains(id10)));
      expect(SessionReadTracker.instance.ids, contains(id20));
    });
  });
}
