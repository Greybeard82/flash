// Writing an imported OPML file into the database.
//
// The rule this exists to enforce is **merge, never replace**. Backup restore
// wipes and re-inserts, which is right for a backup — it is a snapshot of the
// whole library. An OPML file is not a snapshot; it is someone else's reader,
// or a subset, or a file the user has hand-edited. Treating it like a restore
// would silently delete everything they already had.
//
// Real sqflite over FFI, same pattern as feed_repository_test.dart and
// starter_pack_service_test.dart: the rules under test are SQL-shaped (UNIQUE
// on feeds.url, position arithmetic, folder reuse) and a fake would only prove
// the fake agrees with itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/repositories/folder_repository.dart';
import 'package:flash/services/opml_service.dart';

late OpmlService _service;
late FeedRepository _feedRepo;
late FolderRepository _folderRepo;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _service = OpmlService();
  _feedRepo = FeedRepository();
  _folderRepo = FolderRepository();
}

OpmlFeedEntry _entry(String folder, String title, String url,
        {String? siteUrl}) =>
    OpmlFeedEntry(
      folderName: folder,
      title: title,
      xmlUrl: url,
      siteUrl: siteUrl,
    );

Future<Folder> _folder(String name, int position) => _folderRepo.insert(
      Folder(
        name: name,
        position: position,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

Future<Feed> _feed(int folderId, String title, String url, int position) =>
    _feedRepo.insert(Feed(
      folderId: folderId,
      title: title,
      url: url,
      position: position,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  group('a fresh library', () {
    test('creates the folders and feeds the file describes', () async {
      final result = await _service.importEntries([
        _entry('Tech', 'Ars Technica', 'https://arstechnica.com/feed',
            siteUrl: 'https://arstechnica.com'),
        _entry('Tech', 'The Verge', 'https://theverge.com/feed'),
        _entry('News', 'Guardian', 'https://theguardian.com/feed'),
      ]);

      expect(result.feedsImported, 3);
      expect(result.foldersCreated, 2);
      expect(result.skipped, 0);

      final folders = await _folderRepo.getAll();
      expect(folders.map((f) => f.name).toList(), ['Tech', 'News'],
          reason: 'folders are created in the order the file presents them');

      final stored = await _feedRepo.getByUrl('https://arstechnica.com/feed');
      expect(stored!.title, 'Ars Technica');
      expect(stored.siteUrl, 'https://arstechnica.com');
    });

    test('feeds are positioned 0..n inside their folder', () async {
      await _service.importEntries([
        _entry('Tech', 'One', 'https://one.example.com/feed'),
        _entry('Tech', 'Two', 'https://two.example.com/feed'),
        _entry('Tech', 'Three', 'https://three.example.com/feed'),
      ]);

      final folder = (await _folderRepo.getAll()).single;
      final feeds = await _feedRepo.getByFolder(folder.id!);
      expect(feeds.map((f) => f.title).toList(), ['One', 'Two', 'Three']);
      expect(feeds.map((f) => f.position).toList(), [0, 1, 2]);
    });
  });

  group('merging into a library that already has things', () {
    test('an existing folder is matched case-insensitively, not duplicated',
        () async {
      // The same rule the starter pack uses — see folder_matching.dart.
      await _folder('  tech  ', 0);

      final result = await _service.importEntries([
        _entry('Tech', 'Ars Technica', 'https://arstechnica.com/feed'),
      ]);

      expect(result.foldersCreated, 0);
      final folders = await _folderRepo.getAll();
      expect(folders, hasLength(1));
      expect(folders.single.name, '  tech  ',
          reason: 'the name the user chose is kept, not overwritten by the '
              'spelling in the file');
      expect(await _feedRepo.getByFolder(folders.single.id!), hasLength(1));
    });

    test('a URL already subscribed is skipped and never moved', () async {
      final mine = await _folder('My stuff', 0);
      await _feed(mine.id!, 'My own name for it',
          'https://arstechnica.com/feed', 0);

      final result = await _service.importEntries([
        _entry('Tech', 'Ars Technica', 'https://arstechnica.com/feed'),
        _entry('Tech', 'The Verge', 'https://theverge.com/feed'),
      ]);

      expect(result.skipped, 1);
      expect(result.feedsImported, 1);

      final stored = await _feedRepo.getByUrl('https://arstechnica.com/feed');
      expect(stored!.folderId, mine.id,
          reason: 'import must not re-file a feed the user has placed');
      expect(stored.title, 'My own name for it', reason: 'nor rename it');
    });

    test('new feeds are appended after a reused folder\'s existing feeds',
        () async {
      final tech = await _folder('Tech', 0);
      await _feed(tech.id!, 'Already here', 'https://mine.example.com/feed', 0);

      await _service.importEntries([
        _entry('Tech', 'Imported one', 'https://a.example.com/feed'),
        _entry('Tech', 'Imported two', 'https://b.example.com/feed'),
      ]);

      final feeds = await _feedRepo.getByFolder(tech.id!);
      expect(feeds.map((f) => f.title).toList(),
          ['Already here', 'Imported one', 'Imported two']);
      expect(feeds.map((f) => f.position).toList(), [0, 1, 2]);
    });

    test('new folders are positioned after the folders already there',
        () async {
      await _folder('Mine A', 0);
      await _folder('Mine B', 1);

      await _service.importEntries([
        _entry('Fresh', 'A feed', 'https://fresh.example.com/feed'),
      ]);

      final folders = await _folderRepo.getAll();
      expect(folders.map((f) => f.name).toList(),
          ['Mine A', 'Mine B', 'Fresh']);
      expect(folders.last.position, 2);
    });

    test('re-importing the same file changes nothing', () async {
      final entries = [
        _entry('Tech', 'Ars Technica', 'https://arstechnica.com/feed'),
        _entry('News', 'Guardian', 'https://theguardian.com/feed'),
      ];

      final first = await _service.importEntries(entries);
      final second = await _service.importEntries(entries);

      expect(second.feedsImported, 0);
      expect(second.foldersCreated, 0);
      expect(second.skipped, first.feedsImported);
      expect(await _folderRepo.getAll(), hasLength(2));
      expect(await _feedRepo.getAll(), hasLength(2));
    });
  });

  test('an empty entry list writes nothing', () async {
    final result = await _service.importEntries([]);
    expect(result.feedsImported, 0);
    expect(result.foldersCreated, 0);
    expect(result.skipped, 0);
    expect(await _folderRepo.getAll(), isEmpty);
  });
}
