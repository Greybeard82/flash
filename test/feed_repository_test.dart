// FeedRepository.moveToFolder tests.
//
// Covers the persistence half of drag-and-drop reorder/move: dragging a
// source within its category (reorder) or into a different category (move)
// must survive a simulated app restart — i.e. the DB write happened, not
// just an in-memory/widget-local reorder.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/repositories/folder_repository.dart';

late FeedRepository _feedRepo;
late FolderRepository _folderRepo;
late int _folderA;
late int _folderB;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _feedRepo = FeedRepository();
  _folderRepo = FolderRepository();

  final now = DateTime.now().millisecondsSinceEpoch;
  final a = await _folderRepo.insert(
      Folder(name: 'World News', position: 0, createdAt: now));
  final b = await _folderRepo.insert(
      Folder(name: 'Gaming', position: 1, createdAt: now));
  _folderA = a.id!;
  _folderB = b.id!;
}

Future<Feed> _addFeed(int folderId, String title, int position) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  return _feedRepo.insert(Feed(
    folderId: folderId,
    title: title,
    url: 'https://example.com/$title',
    position: position,
    createdAt: now,
  ));
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  group('same-category reorder', () {
    test('changes only the target list order, no folder reassignment',
        () async {
      final f1 = await _addFeed(_folderA, 'ign.com', 0);
      final f2 = await _addFeed(_folderA, 'bbc.com', 1);
      final f3 = await _addFeed(_folderA, 'cnn.com', 2);

      // Drag ign.com from index 0 to index 2 (past bbc, past cnn).
      final destOrder = [f2, f3, f1];
      await _feedRepo.moveToFolder(f1, _folderA, destOrder);

      final result = await _feedRepo.getByFolder(_folderA);
      expect(result.map((f) => f.title).toList(), ['bbc.com', 'cnn.com', 'ign.com']);
      expect(result.every((f) => f.folderId == _folderA), isTrue,
          reason: 'reordering must not touch folder assignment');
    });

    test('does not affect a different category\'s feeds', () async {
      await _addFeed(_folderA, 'ign.com', 0);
      final other = await _addFeed(_folderB, 'polygon.com', 0);

      final destOrder = await _feedRepo.getByFolder(_folderA);
      final reordered = destOrder.reversed.toList();
      await _feedRepo.moveToFolder(destOrder.first, _folderA, reordered);

      final folderBFeeds = await _feedRepo.getByFolder(_folderB);
      expect(folderBFeeds, hasLength(1));
      expect(folderBFeeds.single.id, other.id);
      expect(folderBFeeds.single.position, other.position);
    });
  });

  group('cross-category move', () {
    test('reassigns folder_id, removes from source, adds to destination',
        () async {
      final ign = await _addFeed(_folderA, 'ign.com', 0);
      await _addFeed(_folderA, 'bbc.com', 1);
      final gaming = await _feedRepo.getByFolder(_folderB); // empty so far

      await _feedRepo.moveToFolder(ign, _folderB, [ign, ...gaming]);

      final sourceAfter = await _feedRepo.getByFolder(_folderA);
      final destAfter = await _feedRepo.getByFolder(_folderB);

      expect(sourceAfter.map((f) => f.title), ['bbc.com'],
          reason: 'ign.com must be gone from World News');
      expect(destAfter.map((f) => f.title), ['ign.com'],
          reason: 'ign.com must now appear under Gaming');
      expect(destAfter.single.folderId, _folderB);
    });

    test('drops into an arbitrary position among existing destination feeds',
        () async {
      final ign = await _addFeed(_folderA, 'ign.com', 0);
      final polygon = await _addFeed(_folderB, 'polygon.com', 0);
      final kotaku = await _addFeed(_folderB, 'kotaku.com', 1);

      // Drop ign.com between polygon.com and kotaku.com.
      await _feedRepo.moveToFolder(ign, _folderB, [polygon, ign, kotaku]);

      final destAfter = await _feedRepo.getByFolder(_folderB);
      expect(destAfter.map((f) => f.title).toList(),
          ['polygon.com', 'ign.com', 'kotaku.com']);
    });
  });

  group('persistence survives a simulated restart', () {
    test('a cross-category move is visible from a fresh repository query',
        () async {
      final ign = await _addFeed(_folderA, 'ign.com', 0);
      await _feedRepo.moveToFolder(ign, _folderB, [ign]);

      // A brand-new FeedRepository instance re-queries the same on-disk
      // (in-memory-for-tests) DB — nothing here is in-process widget state.
      final freshRepo = FeedRepository();
      final moved = await freshRepo.getById(ign.id!);

      expect(moved, isNotNull);
      expect(moved!.folderId, _folderB);
    });

    test('a same-category reorder is visible from a fresh repository query',
        () async {
      final f1 = await _addFeed(_folderA, 'ign.com', 0);
      final f2 = await _addFeed(_folderA, 'bbc.com', 1);
      await _feedRepo.moveToFolder(f1, _folderA, [f2, f1]);

      final freshRepo = FeedRepository();
      final result = await freshRepo.getByFolder(_folderA);

      expect(result.map((f) => f.title).toList(), ['bbc.com', 'ign.com']);
    });
  });
}
