// Restore must never destroy a library it cannot replace.
//
// Reported by the master audit as SEV-1. `validate` checked only that
// `version == 1` and that `folders` and `feeds` were non-null. `restoreFromMap`
// then deleted every folder — cascading to feeds and articles — and only after
// that cast `data['folders'] as List`. So a file like
// `{"version":1,"folders":{},"feeds":{}}` wiped the user's library and restored
// nothing. Mutation testing proved the guard was untested: deleting the
// `validate()` call broke no tests at all.
//
// Every "throws" case here asserts the library is **unchanged** afterwards.
// Throwing was never the problem — throwing after the delete was.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/models/keyword_block.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/repositories/folder_repository.dart';
import 'package:flash/repositories/keyword_repository.dart';
import 'package:flash/services/backup_serializer.dart';

const int _now = 1750000000000;

late FolderRepository _folderRepo;
late FeedRepository _feedRepo;
late KeywordRepository _keywordRepo;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _folderRepo = FolderRepository();
  _feedRepo = FeedRepository();
  _keywordRepo = KeywordRepository();

  // A library worth losing.
  final gaming = await _folderRepo
      .insert(const Folder(name: 'Gaming', position: 0, createdAt: _now));
  final news = await _folderRepo
      .insert(const Folder(name: 'News', position: 1, createdAt: _now));
  await _feedRepo.insert(Feed(
      folderId: gaming.id!,
      title: 'IGN',
      url: 'https://ign.example/feed',
      position: 0,
      createdAt: _now));
  await _feedRepo.insert(Feed(
      folderId: news.id!,
      title: 'BBC',
      url: 'https://bbc.example/feed',
      position: 0,
      createdAt: _now));
  await _keywordRepo.insert(const
      KeywordBlock(keyword: 'sponsored', wholeWord: false, createdAt: _now));

  final db = await AppDatabase.instance.database;
  final feedId = (await db.query(TableNames.feeds, columns: ['id'])).first['id'];
  await db.insert(TableNames.articles, {
    'feed_id': feedId,
    'guid': 'g1',
    'title': 'An article',
    'url': 'https://example.com/1',
    'published_at': _now,
    'fetched_at': _now,
    'is_read': 0,
    'is_blocked': 0,
    'is_saved': 0,
  });
}

/// A fingerprint of the whole library, for "unchanged" assertions.
Future<Map<String, dynamic>> _snapshot() async {
  final db = await AppDatabase.instance.database;
  final folders = await db.query(TableNames.folders, orderBy: 'name');
  final feeds = await db.query(TableNames.feeds, orderBy: 'url');
  final keywords = await db.query(TableNames.keywordBlocklist, orderBy: 'keyword');
  final articles = await db.query(TableNames.articles, orderBy: 'guid');
  return {
    'folders': folders.map((r) => r['name']).toList(),
    'feeds': feeds.map((r) => r['url']).toList(),
    'keywords': keywords.map((r) => r['keyword']).toList(),
    'articles': articles.map((r) => r['guid']).toList(),
  };
}

Future<void> _expectUnchanged(Map<String, dynamic> before) async {
  expect(await _snapshot(), before,
      reason: 'a backup file that fails validation must leave the user '
          'exactly as they were — rejecting it after the wipe is the bug');
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('malformed payloads are rejected before anything is deleted', () {
    test('the reported case: folders and feeds are maps, not lists', () async {
      final before = await _snapshot();

      expect(
        () => BackupSerializer.restoreFromMap(
            {'version': 1, 'folders': {}, 'feeds': {}}),
        throwsA(isA<FormatException>()),
      );
      await _expectUnchanged(before);
    });

    test('wrong version', () async {
      final before = await _snapshot();

      expect(
        () => BackupSerializer.restoreFromMap(
            {'version': 2, 'folders': [], 'feeds': []}),
        throwsA(isA<FormatException>()),
      );
      await _expectUnchanged(before);
    });

    test('folders contains a string instead of a map', () async {
      final before = await _snapshot();

      expect(
        () => BackupSerializer.restoreFromMap({
          'version': 1,
          'folders': ['Gaming'],
          'feeds': [],
        }),
        throwsA(isA<FormatException>()),
      );
      await _expectUnchanged(before);
    });

    test('a feed entry missing url', () async {
      final before = await _snapshot();

      expect(
        () => BackupSerializer.restoreFromMap({
          'version': 1,
          'folders': [
            {'name': 'Gaming', 'position': 0}
          ],
          'feeds': [
            {'title': 'IGN', 'folderName': 'Gaming'}
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      await _expectUnchanged(before);
    });

    test('a keyword entry that is not a map', () async {
      final before = await _snapshot();

      expect(
        () => BackupSerializer.restoreFromMap({
          'version': 1,
          'folders': [],
          'feeds': [],
          'keywords': ['sponsored'],
        }),
        throwsA(isA<FormatException>()),
      );
      await _expectUnchanged(before);
    });

    test('a position of the wrong type', () async {
      final before = await _snapshot();

      // `as int?` tolerates null but throws on a String — a null-only check
      // would have let this through and blown up mid-restore.
      expect(
        () => BackupSerializer.restoreFromMap({
          'version': 1,
          'folders': [
            {'name': 'Gaming', 'position': '0'}
          ],
          'feeds': [],
        }),
        throwsA(isA<FormatException>()),
      );
      await _expectUnchanged(before);
    });
  });

  group('valid payloads restore', () {
    test('keywords absent entirely still succeeds', () async {
      final count = await BackupSerializer.restoreFromMap({
        'version': 1,
        'folders': [
          {'name': 'Tech', 'position': 0}
        ],
        'feeds': [
          {'title': 'Verge', 'url': 'https://verge.example/f', 'folderName': 'Tech'}
        ],
      });

      expect(count, 1, reason: 'older backups omit the keywords key entirely');
      final snap = await _snapshot();
      expect(snap['keywords'], isEmpty);
      expect(snap['folders'], ['Tech']);
    });

    test('a valid backup restores counts and folder assignments', () async {
      final count = await BackupSerializer.restoreFromMap({
        'version': 1,
        'folders': [
          {'name': 'Tech', 'position': 0},
          {'name': 'Sport', 'position': 1},
        ],
        'feeds': [
          {'title': 'Verge', 'url': 'https://verge.example/f', 'folderName': 'Tech'},
          {'title': 'Sky', 'url': 'https://sky.example/f', 'folderName': 'Sport'},
          {'title': 'Orphan', 'url': 'https://orphan.example/f', 'folderName': 'Gone'},
        ],
        'keywords': [
          {'keyword': 'crypto', 'wholeWord': true}
        ],
      });

      expect(count, 2, reason: 'the feed naming a missing folder is skipped');

      final db = await AppDatabase.instance.database;
      final rows = await db.rawQuery('''
        SELECT f.url AS url, fo.name AS folder
        FROM ${TableNames.feeds} f
        JOIN ${TableNames.folders} fo ON f.folder_id = fo.id
        ORDER BY f.url
      ''');
      expect(rows.map((r) => '${r['folder']}/${r['url']}').toList(), [
        'Sport/https://sky.example/f',
        'Tech/https://verge.example/f',
      ]);

      final snap = await _snapshot();
      expect(snap['keywords'], ['crypto']);
      expect(snap['articles'], isEmpty,
          reason: 'the old library cascaded away with its folders');
    });

    test('round trip: serialise, restore, and the library matches', () async {
      final folders = await _folderRepo.getAll();
      final feeds = await _feedRepo.getAll();
      final keywords = await _keywordRepo.getAll();
      final map = BackupSerializer.toMap(
          folders: folders, feeds: feeds, keywords: keywords);

      final before = await _snapshot();

      await BackupSerializer.restoreFromMap(map);

      final after = await _snapshot();
      expect(after['folders'], before['folders']);
      expect(after['feeds'], before['feeds']);
      expect(after['keywords'], before['keywords']);
      expect(after['articles'], isEmpty,
          reason: 'articles are deliberately not in the backup format — they '
              're-fetch. Everything else must survive a round trip intact');
    });
  });

  group('the wipe and the re-insert are one transaction', () {
    test('a failure part-way through the insert rolls the wipe back',
        () async {
      final before = await _snapshot();

      // Two feeds with the same url: feeds.url is NOT NULL UNIQUE, so the
      // second insert fails part-way through the restore — after the wipe has
      // already run inside the transaction, which is exactly the window that
      // used to leave the user with nothing. (folders.name is deliberately
      // not unique, so duplicate categories are legal and cannot be used to
      // force this.)
      await expectLater(
        BackupSerializer.restoreFromMap({
          'version': 1,
          'folders': [
            {'name': 'Tech', 'position': 0}
          ],
          'feeds': [
            {'title': 'One', 'url': 'https://same.example/f', 'folderName': 'Tech'},
            {'title': 'Two', 'url': 'https://same.example/f', 'folderName': 'Tech'},
          ],
        }),
        throwsA(anything),
      );

      await _expectUnchanged(before);
    });
  });
}
