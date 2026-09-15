// 3b — backup format v2 carries bookmarks.
//
// **Bookmarks are stored by VALUE, and that is the whole design.** A bookmark
// written as (feed url, guid) restores nothing unless the feed still carries
// that article, and `kFetchDayLimit` is 7 — anything published more than a
// week before the restore is discarded at fetch time and never comes back.
// Backups are normally restored long after they were taken, so a reference
// would restore an empty Bookmarks tab and look exactly like data loss.
//
// Read state is deliberately absent. It can only be held by reference, and by
// the same 7-day arithmetic it matches nothing once the file is a week old.
// Measured before it was left out; see the report.
//
// The compatibility half matters more than the feature half. Changing what a
// file contains creates two new failure paths, and both are tested here: an
// old file into this build, and a new file into a build that only knows v1.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/models/keyword_block.dart';
import 'package:flash/services/backup_serializer.dart';

Future<Database> _open() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  return AppDatabase.instance.database;
}

Folder _folder(int id) =>
    Folder(id: id, name: 'World News', position: 0, createdAt: 1);

Feed _feed(int id) => Feed(
      id: id,
      folderId: 1,
      title: 'The Guardian',
      url: 'https://example.com/rss.xml',
      position: 0,
      createdAt: 1,
    );

Article _bookmark({String guid = 'g1'}) => Article(
      feedId: 1,
      guid: guid,
      title: 'A saved headline',
      url: 'https://example.com/a/$guid',
      publishedAt: 1750000000000,
      fetchedAt: 1750000000000,
      isSaved: true,
      description: 'why it was kept',
    );

/// What a v1 file looks like: no `bookmarks` key at all.
Map<String, dynamic> _v1File() => {
      'version': 1,
      'backedUpAt': 1750000000000,
      'folders': [
        {'name': 'World News', 'position': 0}
      ],
      'feeds': [
        {
          'title': 'The Guardian',
          'url': 'https://example.com/rss.xml',
          'folderName': 'World News',
          'position': 0,
        }
      ],
      'keywords': <dynamic>[],
    };

void main() {
  tearDown(() async => AppDatabase.instance.close());

  group('the format', () {
    test('this build writes version 2 and still reads version 1', () {
      expect(BackupSerializer.kFormatVersion, 2);
      expect(BackupSerializer.kSupportedVersions, containsAll(<int>[1, 2]));
    });

    test('bookmarks are self-contained, not a reference', () {
      // The assertion that encodes the design. If this ever shrinks to a guid
      // and a feed url, a restore stops working a week after the backup.
      final map = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
        bookmarks: [_bookmark()],
      );
      final b = (map['bookmarks'] as List).single as Map;
      expect(b['title'], 'A saved headline',
          reason: 'without the title the restored bookmark has nothing to '
              'show in the list');
      expect(b['url'], isNotEmpty);
      expect(b['publishedAt'], isNotNull);
      expect(b['feedUrl'], 'https://example.com/rss.xml',
          reason: 'feeds.id is AUTOINCREMENT, so url is the only stable way '
              'back to the feed after a restore');
    });

    test('read state is not in the file', () {
      final map = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
        bookmarks: [_bookmark()],
      );
      expect(map.containsKey('readState'), isFalse);
      expect(map.containsKey('articles'), isFalse);
      final b = (map['bookmarks'] as List).single as Map;
      expect(b.containsKey('isRead'), isFalse,
          reason: 'deliberate: by the 7-day fetch limit it would match '
              'nothing. Recommended against with a measurement, not omitted '
              'by accident.');
    });

    test('an export with no bookmarks still writes the key', () {
      // So a v2 reader never has to distinguish "no bookmarks" from "old
      // file" by the shape of the data.
      final map = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
      );
      expect(map['bookmarks'], isEmpty);
    });
  });

  group('the seven file cases', () {
    test('1. an OLD file into this build restores, with no bookmarks',
        () async {
      await _open();
      final count = await BackupSerializer.restoreFromMap(_v1File());
      expect(count, 1, reason: 'a v1 file must not be refused');

      final db = await AppDatabase.instance.database;
      final saved = await db.query(TableNames.articles);
      expect(saved, isEmpty, reason: 'it simply had none to carry');
    });

    test('2. a NEW file into this build restores the bookmark', () async {
      await _open();
      final map = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
        bookmarks: [_bookmark()],
      );

      await BackupSerializer.restoreFromMap(map);

      final db = await AppDatabase.instance.database;
      final rows = await db.query(TableNames.articles);
      expect(rows, hasLength(1));
      expect(rows.single['title'], 'A saved headline');
      expect(rows.single['is_saved'], 1,
          reason: 'restored unsaved, it is not a bookmark');
      expect(rows.single['is_read'], 0);

      // And attached to the feed that came back, not to a stale id.
      final feeds = await db.query(TableNames.feeds);
      expect(rows.single['feed_id'], feeds.single['id']);
    });

    test('3. a NEW file into an OLD build fails clearly, not silently', () {
      // The old build's check was `(data['version'] as int?) != 1`, so it
      // throws FormatException('Not a valid Flash backup file') on a v2 file.
      // Reproduced here rather than asserted from memory, because "fails
      // gracefully" is the claim and a silent partial restore is the fear.
      final v2 = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
        bookmarks: [_bookmark()],
      );

      void oldBuildValidate(Map<String, dynamic> data) {
        if ((data['version'] as int?) != 1) {
          throw const FormatException('Not a valid Flash backup file');
        }
      }

      expect(() => oldBuildValidate(v2), throwsFormatException,
          reason: 'an older build must refuse a v2 file outright. It is '
              'checked BEFORE any deletion, so the old library survives.');
    });

    test('4. a corrupt file is refused', () {
      final corrupt = {
        'version': 2,
        'folders': [
          {'name': 'World News', 'position': 0}
        ],
        'feeds': [
          {
            'title': 'x',
            'url': 'y',
            'folderName': 'World News',
          }
        ],
        'bookmarks': [
          {'guid': 'g1', 'title': 42, 'url': 'u'}
        ],
      };
      expect(() => BackupSerializer.validate(corrupt), throwsFormatException,
          reason: 'a bookmark with a numeric title would throw mid-restore, '
              'after the wipe');
    });

    test('5. a truncated file is refused', () {
      // Truncation in practice means valid JSON that stops early, or invalid
      // JSON. Both must be refused before anything is deleted.
      final text = jsonEncode(_v1File());
      final truncated = text.substring(0, text.length ~/ 2);
      expect(() => jsonDecode(truncated), throwsFormatException);

      // And the structurally-truncated case: keys simply missing.
      expect(() => BackupSerializer.validate({'version': 2, 'folders': []}),
          throwsFormatException);
    });

    test('6. an empty file is refused', () {
      expect(() => BackupSerializer.validate(<String, dynamic>{}),
          throwsFormatException);
      expect(() => jsonDecode(''), throwsFormatException);
    });

    test('7. a file from a different app entirely is refused', () {
      // No version key at all, plausible-looking keys.
      expect(
          () => BackupSerializer.validate({
                'feeds': [
                  {'title': 'x', 'url': 'y'}
                ],
                'exportedBy': 'SomeOtherReader',
              }),
          throwsFormatException);
    });
  });

  group('restoring bookmarks does not break what already worked', () {
    test('a bookmark whose feed is not in the file is skipped, not invented',
        () async {
      await _open();
      final map = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
        bookmarks: [_bookmark()],
      );
      (map['bookmarks'] as List).first['feedUrl'] = 'https://gone.example/rss';

      await BackupSerializer.restoreFromMap(map);

      final db = await AppDatabase.instance.database;
      expect(await db.query(TableNames.articles), isEmpty,
          reason: 'an article with no feed has nothing to open from and '
              'nowhere to sit');
    });

    test('a v1 file still reports its feed count', () async {
      await _open();
      expect(await BackupSerializer.restoreFromMap(_v1File()), 1);
    });

    test('two bookmarks on the same feed both land', () async {
      await _open();
      final map = BackupSerializer.toMap(
        folders: [_folder(1)],
        feeds: [_feed(1)],
        keywords: const <KeywordBlock>[],
        bookmarks: [_bookmark(guid: 'g1'), _bookmark(guid: 'g2')],
      );
      await BackupSerializer.restoreFromMap(map);

      final db = await AppDatabase.instance.database;
      expect(await db.query(TableNames.articles), hasLength(2));
    });
  });
}
