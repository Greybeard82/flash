// Export then import must give back what you started with.
//
// This is the test that catches the mistakes the other two cannot: an
// attribute the writer emits and the reader ignores, a folder order that
// survives serialisation but not parsing, feed order that depends on map
// iteration. Each half can be individually correct and still disagree.
//
// One guarantee is deliberately *not* claimed: an **empty** folder does not
// survive the round trip. Import is feed-driven — a folder exists because a
// feed lands in it — so a category with no feeds is exported as an empty
// outline and then has nothing to recreate it. That is a real limitation, not
// an oversight, and the fixture below reflects the case that matters by giving
// every folder at least one feed.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/repositories/folder_repository.dart';
import 'package:flash/services/opml_service.dart';

late FeedRepository _feedRepo;
late FolderRepository _folderRepo;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _feedRepo = FeedRepository();
  _folderRepo = FolderRepository();
}

/// Folder name -> ordered feed titles/urls, as they go in and must come out.
const _fixture = {
  'World News': [
    ['BBC News', 'https://feeds.bbci.co.uk/news/world/rss.xml'],
    ['The Guardian', 'https://www.theguardian.com/world/rss'],
  ],
  'Tech': [
    ['Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index'],
    ['The Verge', 'https://www.theverge.com/rss/index.xml'],
    ['WIRED', 'https://www.wired.com/feed/rss'],
  ],
  'Sports': [
    ['BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml'],
  ],
};

Future<void> _seed() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  var folderPosition = 0;
  for (final entry in _fixture.entries) {
    final folder = await _folderRepo.insert(
        Folder(name: entry.key, position: folderPosition++, createdAt: now));
    var feedPosition = 0;
    for (final feed in entry.value) {
      await _feedRepo.insert(Feed(
        folderId: folder.id!,
        title: feed[0],
        url: feed[1],
        siteUrl: 'https://example.com/${feed[0]}',
        position: feedPosition++,
        createdAt: now,
      ));
    }
  }
}

/// The library as `{folder name: [feed titles in order]}`.
Future<Map<String, List<String>>> _snapshot() async {
  final out = <String, List<String>>{};
  for (final folder in await _folderRepo.getAll()) {
    final feeds = await _feedRepo.getByFolder(folder.id!);
    out[folder.name] = feeds.map((f) => f.title).toList();
  }
  return out;
}

Future<String> _export() async {
  final folders = await _folderRepo.getAll();
  final feedsByFolder = <int, List<Feed>>{
    for (final folder in folders)
      folder.id!: await _feedRepo.getByFolder(folder.id!),
  };
  return OpmlService.buildOpml(folders: folders, feedsByFolder: feedsByFolder);
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  test('export then import into a fresh database reproduces the library',
      () async {
    await _seed();
    final before = await _snapshot();
    final opml = await _export();

    // A genuinely empty database, as if on a new phone.
    await AppDatabase.instance.close();
    AppDatabase.useForTesting();
    _feedRepo = FeedRepository();
    _folderRepo = FolderRepository();
    expect(await _folderRepo.getAll(), isEmpty);

    final entries = OpmlService.parse(opml, fallbackFolderName: 'Imported');
    final result = await OpmlService().importEntries(entries);

    expect(result.skipped, 0);
    expect(result.foldersCreated, _fixture.length);
    expect(result.feedsImported,
        _fixture.values.fold<int>(0, (sum, f) => sum + f.length));

    final after = await _snapshot();
    expect(after, before,
        reason: 'folder order, feed order and every name must survive');
  });

  test('the exported document carries the attributes a reader needs',
      () async {
    await _seed();
    final opml = await _export();

    expect(opml, contains('version="2.0"'));
    expect(opml, contains('<opml'));
    expect(opml, contains('<body>'));
    // One parent outline per folder.
    expect(opml, contains('World News'));
    expect(opml, contains('type="rss"'));
    expect(opml, contains('xmlUrl="https://www.wired.com/feed/rss"'));
    expect(opml, contains('htmlUrl='));
    // Both naming attributes, because readers disagree about which they read.
    expect(opml, contains('text="WIRED"'));
    expect(opml, contains('title="WIRED"'));
  });

  test('re-importing an export into the SAME database adds nothing', () async {
    // The realistic mistake: export, then import the file you just made.
    await _seed();
    final opml = await _export();
    final before = await _snapshot();

    final entries = OpmlService.parse(opml, fallbackFolderName: 'Imported');
    final result = await OpmlService().importEntries(entries);

    expect(result.feedsImported, 0);
    expect(result.foldersCreated, 0);
    expect(result.skipped,
        _fixture.values.fold<int>(0, (sum, f) => sum + f.length));
    expect(await _snapshot(), before);
  });
}
