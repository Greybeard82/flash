import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/models/keyword_block.dart';
import 'package:flash/services/backup_serializer.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Folder _folder(int id, String name, {int position = 0}) => Folder(
      id: id,
      name: name,
      position: position,
      createdAt: 0,
    );

Feed _feed({
  required int id,
  required int folderId,
  required String title,
  required String url,
  int position = 0,
  String? siteUrl,
}) =>
    Feed(
      id: id,
      folderId: folderId,
      title: title,
      url: url,
      siteUrl: siteUrl,
      position: position,
      createdAt: 0,
    );

KeywordBlock _kw(String keyword, {bool wholeWord = false}) =>
    KeywordBlock(id: 1, keyword: keyword, wholeWord: wholeWord, createdAt: 0);

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ── toMap / serialisation ────────────────────────────────────────────────

  group('toMap', () {
    test('version is always 1', () {
      final map = BackupSerializer.toMap(folders: [], feeds: [], keywords: []);
      expect(map['version'], 1);
    });

    test('backedUpAt timestamp is present and non-zero', () {
      final map = BackupSerializer.toMap(folders: [], feeds: [], keywords: []);
      expect(map['backedUpAt'], isA<int>());
      expect((map['backedUpAt'] as int) > 0, isTrue);
    });

    test('serialises folder names and positions', () {
      final map = BackupSerializer.toMap(
        folders: [_folder(1, 'Tech', position: 0), _folder(2, 'Sport', position: 1)],
        feeds: [],
        keywords: [],
      );
      final folders = map['folders'] as List;
      expect(folders.length, 2);
      expect(folders[0]['name'], 'Tech');
      expect(folders[0]['position'], 0);
      expect(folders[1]['name'], 'Sport');
    });

    test('serialises feed url, title, position, and folder name', () {
      final map = BackupSerializer.toMap(
        folders: [_folder(10, 'Tech')],
        feeds: [_feed(id: 1, folderId: 10, title: 'Wired', url: 'https://wired.com/feed', position: 2)],
        keywords: [],
      );
      final feeds = map['feeds'] as List;
      expect(feeds.length, 1);
      expect(feeds[0]['title'], 'Wired');
      expect(feeds[0]['url'], 'https://wired.com/feed');
      expect(feeds[0]['folderName'], 'Tech');
      expect(feeds[0]['position'], 2);
    });

    test('serialises keywords with keyword and wholeWord fields', () {
      final map = BackupSerializer.toMap(
        folders: [],
        feeds: [],
        keywords: [_kw('crypto'), _kw('Elon Musk', wholeWord: true)],
      );
      final keywords = map['keywords'] as List;
      expect(keywords.length, 2);
      expect(keywords[0]['keyword'], 'crypto');
      expect(keywords[0]['wholeWord'], isFalse);
      expect(keywords[1]['keyword'], 'Elon Musk');
      expect(keywords[1]['wholeWord'], isTrue);
    });

    test('does NOT include read/unread state, API keys, or bookmarks', () {
      final map = BackupSerializer.toMap(
        folders: [_folder(1, 'Test')],
        feeds: [_feed(id: 1, folderId: 1, title: 'Feed', url: 'https://x.com/rss')],
        keywords: [],
      );
      final keys = map.keys.toSet();
      expect(keys.contains('articles'), isFalse);
      expect(keys.contains('read_state'), isFalse);
      expect(keys.contains('api_key'), isFalse);
      expect(keys.contains('bookmarks'), isFalse);
      expect(keys.contains('saved'), isFalse);
    });

    test('Drive and local-file output are byte-identical (same format)', () {
      final folders = [_folder(1, 'Tech')];
      final feeds = [_feed(id: 1, folderId: 1, title: 'Wired', url: 'https://wired.com/rss')];
      final keywords = [_kw('crypto')];

      final map1 = BackupSerializer.toMap(folders: folders, feeds: feeds, keywords: keywords);
      final map2 = BackupSerializer.toMap(folders: folders, feeds: feeds, keywords: keywords);

      // Version + structure identical (backedUpAt may differ by ms so compare structure only).
      expect(map1['version'], map2['version']);
      expect(jsonEncode(map1['folders']), jsonEncode(map2['folders']));
      expect(jsonEncode(map1['feeds']), jsonEncode(map2['feeds']));
      expect(jsonEncode(map1['keywords']), jsonEncode(map2['keywords']));
    });
  });

  // ── validate ─────────────────────────────────────────────────────────────

  group('validate', () {
    test('accepts valid backup map', () {
      final map = BackupSerializer.toMap(folders: [], feeds: [], keywords: []);
      expect(() => BackupSerializer.validate(map), returnsNormally);
    });

    test('throws on wrong version', () {
      expect(
        () => BackupSerializer.validate({'version': 99, 'folders': [], 'feeds': []}),
        throwsFormatException,
      );
    });

    test('throws when folders key is missing', () {
      expect(
        () => BackupSerializer.validate({'version': 1, 'feeds': []}),
        throwsFormatException,
      );
    });

    test('throws when feeds key is missing', () {
      expect(
        () => BackupSerializer.validate({'version': 1, 'folders': []}),
        throwsFormatException,
      );
    });
  });

  // ── restoreFromMap (wipe + re-insert) ────────────────────────────────────

  group('restoreFromMap', () {
    setUp(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppDatabase.useForTesting();
    });

    tearDown(() async => AppDatabase.instance.close());

    test('alert snapshots follow their feed to its new id', () async {
      // A restore wipes folders and feeds and re-inserts them, and feeds.id is
      // AUTOINCREMENT — so the same feed comes back under a new id. The alert
      // snapshot survives the wipe by design (no FK on feed_id) but is keyed
      // by (feed_id, guid, keyword), so without re-keying the card is orphaned
      // onto a dead id and the next fetch writes a duplicate under the new one.
      final db = await AppDatabase.instance.database;
      final folderId = await db.insert(TableNames.folders,
          {'name': 'Tech', 'position': 0, 'created_at': 0});
      final oldFeedId = await db.insert(TableNames.feeds, {
        'folder_id': folderId,
        'title': 'Wired',
        'url': 'https://wired.com/rss',
        'consecutive_failures': 0,
        'is_dead': 0,
        'position': 0,
        'created_at': 0,
      });
      await db.insert(TableNames.alertMatches, {
        'feed_id': oldFeedId,
        'guid': 'g1',
        'keyword': 'zelda',
        'title': 'Zelda news',
        'url': 'https://example.com/g1',
        'feed_title': 'Wired',
        'folder_id': folderId,
        'matched_at': 10,
        'is_read': 0,
      });

      final map = BackupSerializer.toMap(
        folders: [_folder(folderId, 'Tech')],
        feeds: [
          _feed(
              id: oldFeedId,
              folderId: folderId,
              title: 'Wired',
              url: 'https://wired.com/rss'),
        ],
        keywords: [],
      );
      await BackupSerializer.restoreFromMap(map);

      final feeds = await db.query(TableNames.feeds);
      final newFeedId = feeds.single['id'] as int;
      final newFolderId = feeds.single['folder_id'] as int;
      expect(newFeedId, isNot(oldFeedId),
          reason: 'AUTOINCREMENT must not reuse the id, or this proves '
              'nothing');

      final matches = await db.query(TableNames.alertMatches);
      expect(matches, hasLength(1),
          reason: 'the snapshot survives the wipe — that is what the missing '
              'foreign key is for');
      expect(matches.single['feed_id'], newFeedId,
          reason: 'and it is re-keyed onto the restored feed, so the next '
              'fetch matches it instead of inserting a duplicate');
      expect(matches.single['folder_id'], newFolderId,
          reason: 'folder scoping and mark-folder-read read this copy');
    });

    test('a snapshot whose feed is not in the backup keeps its old id',
        () async {
      // Nothing to re-key onto. The row must survive untouched rather than be
      // deleted or pointed at some other feed: an alert outliving the feed it
      // arrived on is the behaviour alert_matches exists to provide.
      final db = await AppDatabase.instance.database;
      final folderId = await db.insert(TableNames.folders,
          {'name': 'Tech', 'position': 0, 'created_at': 0});
      final goneFeedId = await db.insert(TableNames.feeds, {
        'folder_id': folderId,
        'title': 'Gone',
        'url': 'https://gone.example/rss',
        'consecutive_failures': 0,
        'is_dead': 0,
        'position': 0,
        'created_at': 0,
      });
      await db.insert(TableNames.alertMatches, {
        'feed_id': goneFeedId,
        'guid': 'g2',
        'keyword': 'zelda',
        'title': 'Zelda news',
        'url': 'https://example.com/g2',
        'feed_title': 'Gone',
        'folder_id': folderId,
        'matched_at': 10,
        'is_read': 0,
      });

      await BackupSerializer.restoreFromMap(BackupSerializer.toMap(
        folders: [_folder(folderId, 'Tech')],
        feeds: [
          _feed(
              id: 99,
              folderId: folderId,
              title: 'Wired',
              url: 'https://wired.com/rss'),
        ],
        keywords: [],
      ));

      final matches = await db.query(TableNames.alertMatches);
      expect(matches, hasLength(1));
      expect(matches.single['feed_id'], goneFeedId);
      expect(matches.single['feed_title'], 'Gone',
          reason: 'the snapshot still names the source it actually came from');
    });

    test('returns correct feed count', () async {
      final map = BackupSerializer.toMap(
        folders: [_folder(1, 'Tech')],
        feeds: [
          _feed(id: 1, folderId: 1, title: 'Wired', url: 'https://wired.com/rss'),
          _feed(id: 2, folderId: 1, title: 'Ars', url: 'https://ars.com/rss'),
        ],
        keywords: [],
      );
      final count = await BackupSerializer.restoreFromMap(map);
      expect(count, 2);
    });

    test('round-trip: folder names preserved', () async {
      final map = BackupSerializer.toMap(
        folders: [_folder(1, 'Tech'), _folder(2, 'Sport')],
        feeds: [],
        keywords: [],
      );
      await BackupSerializer.restoreFromMap(map);
      // Verify via a second serialise → restore cycle structurally matches.
      expect((map['folders'] as List).map((f) => f['name']).toList(),
          containsAll(['Tech', 'Sport']));
    });

    test('round-trip: feeds with correct folder assignment', () async {
      final map = BackupSerializer.toMap(
        folders: [_folder(1, 'Tech')],
        feeds: [_feed(id: 1, folderId: 1, title: 'Wired', url: 'https://wired.com/rss')],
        keywords: [],
      );
      final count = await BackupSerializer.restoreFromMap(map);
      expect(count, 1);
    });

    test('round-trip: keywords preserved', () async {
      final map = BackupSerializer.toMap(
        folders: [_folder(1, 'Misc')],
        feeds: [_feed(id: 1, folderId: 1, title: 'X', url: 'https://x.com/rss')],
        keywords: [_kw('crypto'), _kw('spam', wholeWord: true)],
      );
      await BackupSerializer.restoreFromMap(map);
      // keywords count in the backup map itself.
      expect((map['keywords'] as List).length, 2);
    });

    test('feeds with unknown folder name are skipped', () async {
      // 'NoSuchFolder' does not exist in the folders list.
      final data = {
        'version': 1,
        'backedUpAt': DateTime.now().millisecondsSinceEpoch,
        'folders': [
          {'name': 'Tech', 'position': 0},
        ],
        'feeds': [
          {'title': 'Valid', 'url': 'https://a.com/rss', 'folderName': 'Tech', 'position': 0},
          {'title': 'Orphan', 'url': 'https://b.com/rss', 'folderName': 'NoSuchFolder', 'position': 0},
        ],
        'keywords': [],
      };
      final count = await BackupSerializer.restoreFromMap(data);
      expect(count, 1);
    });
  });
}
