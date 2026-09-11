// Seeding the starter pack into the database.
//
// The service writes folders and feeds through the ordinary repositories, so
// most of what matters here is what it *doesn't* do on a second run. The pack
// is offered from three places — onboarding, the Flash empty state and the
// Categories empty state — and two of those are reachable long after the user
// has built a library of their own. Adding it twice must not duplicate a
// category, must not move a feed the user has since filed elsewhere, and must
// not touch the onboarding flag.
//
// Real sqflite over FFI, same pattern as feed_repository_test.dart: the rules
// under test are SQL-shaped (UNIQUE on feeds.url, position arithmetic) and a
// fake would only prove the fake agrees with itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/data/starter_pack.dart';
import 'package:flash/db/database.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/repositories/folder_repository.dart';
import 'package:flash/repositories/settings_repository.dart';
import 'package:flash/services/starter_pack_service.dart';

late StarterPackService _service;
late FeedRepository _feedRepo;
late FolderRepository _folderRepo;

/// The folder names the UI would hand in, English-side. In the app these come
/// from the ARB at seeding time; the service never invents them.
const _names = {
  'world_news': 'World News',
  'tech': 'Tech',
  'fitness_health': 'Fitness / Health',
  'travel': 'Travelling',
  'sports': 'Sports',
};

List<String> get _allIds => kStarterPack.map((c) => c.id).toList();

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _service = StarterPackService();
  _feedRepo = FeedRepository();
  _folderRepo = FolderRepository();
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  group('fresh database', () {
    test('creates every selected category and feed', () async {
      final result = await _service.addCategories(_allIds, _names);

      final expectedFeeds =
          kStarterPack.fold<int>(0, (sum, c) => sum + c.feeds.length);
      expect(result.foldersCreated, kStarterPack.length);
      expect(result.feedsAdded, expectedFeeds);
      expect(result.feedsSkipped, 0);
      expect(result.addedFeeds, hasLength(expectedFeeds));

      final folders = await _folderRepo.getAll();
      expect(folders.map((f) => f.name).toList(),
          kStarterPack.map((c) => _names[c.id]).toList());

      final feeds = await _feedRepo.getAll();
      expect(feeds, hasLength(expectedFeeds));
    });

    test('folders are positioned 0..n in pack order', () async {
      await _service.addCategories(_allIds, _names);
      final folders = await _folderRepo.getAll();
      expect(folders.map((f) => f.position).toList(),
          List.generate(kStarterPack.length, (i) => i));
    });

    test('feeds are positioned 0..n within their own folder', () async {
      await _service.addCategories(_allIds, _names);
      final folders = await _folderRepo.getAll();

      for (var i = 0; i < kStarterPack.length; i++) {
        final inFolder = await _feedRepo.getByFolder(folders[i].id!);
        expect(inFolder.map((f) => f.position).toList(),
            List.generate(kStarterPack[i].feeds.length, (n) => n),
            reason: 'positions in ${folders[i].name}');
        expect(inFolder.map((f) => f.title).toList(),
            kStarterPack[i].feeds.map((f) => f.title).toList(),
            reason: 'feed order in ${folders[i].name}');
      }
    });

    test('a feed carries the pack title, url, siteUrl and description',
        () async {
      await _service.addCategories(['tech'], _names);
      final source = kStarterPack[1].feeds.first;
      final stored = await _feedRepo.getByUrl(source.url);

      expect(stored, isNotNull);
      expect(stored!.title, source.title);
      expect(stored.siteUrl, source.siteUrl);
      expect(stored.description, source.description);
      expect(stored.createdAt, greaterThan(0));
    });

    test('only the selected categories are seeded', () async {
      final result = await _service.addCategories(['tech', 'sports'], _names);

      expect(result.foldersCreated, 2);
      final folders = await _folderRepo.getAll();
      expect(folders.map((f) => f.name).toList(), ['Tech', 'Sports']);
    });
  });

  group('running it twice', () {
    test('the second run adds nothing at all', () async {
      final first = await _service.addCategories(_allIds, _names);
      final second = await _service.addCategories(_allIds, _names);

      expect(second.foldersCreated, 0);
      expect(second.feedsAdded, 0);
      expect(second.feedsSkipped, first.feedsAdded);
      expect(second.addedFeeds, isEmpty);

      expect(await _folderRepo.getAll(), hasLength(kStarterPack.length));
      expect(await _feedRepo.getAll(), hasLength(first.feedsAdded));
    });
  });

  group('reusing what the user already has', () {
    test('an existing folder matches on trimmed, case-insensitive name',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _folderRepo
          .insert(Folder(name: '  world news  ', position: 0, createdAt: now));

      final result = await _service.addCategories(['world_news'], _names);

      expect(result.foldersCreated, 0,
          reason: 'a second "World News" beside the existing one is the '
              'duplicate this rule exists to prevent');
      final folders = await _folderRepo.getAll();
      expect(folders, hasLength(1));
      // The user's spelling wins — the pack is a guest in their category.
      expect(folders.single.name, '  world news  ');
      expect(await _feedRepo.getByFolder(folders.single.id!),
          hasLength(kStarterPack.first.feeds.length));
    });

    test('a feed already filed elsewhere is skipped and left where it is',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final mine = await _folderRepo
          .insert(Folder(name: 'My stuff', position: 0, createdAt: now));
      final packUrl = kStarterPack.first.feeds.first.url;
      await _feedRepo.insert(Feed(
        folderId: mine.id!,
        title: 'My own name for it',
        url: packUrl,
        position: 0,
        createdAt: now,
      ));

      final result = await _service.addCategories(['world_news'], _names);

      expect(result.feedsSkipped, 1);
      expect(result.feedsAdded, kStarterPack.first.feeds.length - 1);

      final stored = await _feedRepo.getByUrl(packUrl);
      expect(stored!.folderId, mine.id,
          reason: 'seeding must never move a feed the user has filed');
      expect(stored.title, 'My own name for it', reason: 'nor rename one');
    });

    test('new folders are positioned after the folders already there',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _folderRepo
          .insert(Folder(name: 'Mine A', position: 0, createdAt: now));
      await _folderRepo
          .insert(Folder(name: 'Mine B', position: 1, createdAt: now));

      await _service.addCategories(['tech'], _names);

      final folders = await _folderRepo.getAll();
      expect(folders.map((f) => f.name).toList(), ['Mine A', 'Mine B', 'Tech']);
      expect(folders.last.position, 2);
    });

    test('new feeds are positioned after the existing feeds of a reused folder',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final tech = await _folderRepo
          .insert(Folder(name: 'Tech', position: 0, createdAt: now));
      await _feedRepo.insert(Feed(
        folderId: tech.id!,
        title: 'Something of mine',
        url: 'https://example.com/mine.xml',
        position: 0,
        createdAt: now,
      ));

      await _service.addCategories(['tech'], _names);

      final inFolder = await _feedRepo.getByFolder(tech.id!);
      expect(inFolder.first.title, 'Something of mine');
      expect(inFolder.map((f) => f.position).toList(),
          List.generate(inFolder.length, (i) => i));
      expect(inFolder.map((f) => f.title).skip(1).toList(),
          kStarterPack[1].feeds.map((f) => f.title).toList());
    });
  });

  test('onboarding_complete is not touched', () async {
    // The flag belongs to the screen that owns the decision. Seeding happens
    // from two empty states long after onboarding is done, and writing it here
    // would mean the Categories empty state could silently "complete"
    // onboarding for someone who had skipped it.
    // Read before and after rather than asserting a literal: the schema seeds
    // the row as 'false', so "untouched" is what this pins, not "absent".
    final settings = SettingsRepository();
    final before = await settings.get('onboarding_complete');
    expect(before, 'false');
    await _service.addCategories(_allIds, _names);
    expect(await settings.get('onboarding_complete'), before);
  });
}
