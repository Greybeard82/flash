// UnreadCounts model tests.
//
// Written independently of the implementation. These pin the contract that
// lets every folder tab's badge update the instant an article is read in ANY
// tab — including the "All" tab.
//
// Covered behaviours:
//  1. Reading an article in folder X decrements BOTH `all` and `byFolder[X]`
//  2. Counts never go negative
//  3. Marking unread increments both again
//  4. Articles in feeds with no folder affect `all` only
//  5. Batch reads (scroll) apply in one pass
//  6. Clearing a folder subtracts exactly that folder's count from `all`
//  7. The model is immutable — every operation returns a new instance

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/unread_counts.dart';

void main() {
  const gaming = 1;
  const tech = 2;

  UnreadCounts seed() =>
      const UnreadCounts(all: 30, byFolder: {gaming: 12, tech: 18});

  group('construction', () {
    test('empty has zero everywhere', () {
      const c = UnreadCounts.empty();
      expect(c.all, 0);
      expect(c.byFolder, isEmpty);
      expect(c.forFolder(gaming), 0);
    });

    test('forFolder returns 0 for an unknown folder', () {
      expect(seed().forFolder(999), 0);
    });
  });

  group('applyRead', () {
    test('decrements all AND the owning folder', () {
      final c = seed().applyRead(gaming);
      expect(c.all, 29);
      expect(c.forFolder(gaming), 11);
      expect(c.forFolder(tech), 18, reason: 'other folders untouched');
    });

    test('a null folder (unfiled feed) decrements all only', () {
      final c = seed().applyRead(null);
      expect(c.all, 29);
      expect(c.forFolder(gaming), 12);
      expect(c.forFolder(tech), 18);
    });

    test('floors at zero — never negative', () {
      const c = UnreadCounts(all: 1, byFolder: {gaming: 1});
      final once = c.applyRead(gaming);
      final twice = once.applyRead(gaming);
      final thrice = twice.applyRead(gaming);
      expect(once.all, 0);
      expect(once.forFolder(gaming), 0);
      expect(thrice.all, 0);
      expect(thrice.forFolder(gaming), 0);
    });

    test('does not mutate the receiver', () {
      final original = seed();
      original.applyRead(gaming);
      expect(original.all, 30);
      expect(original.forFolder(gaming), 12);
    });
  });

  group('applyUnread', () {
    test('increments all and the owning folder', () {
      final c = seed().applyUnread(tech);
      expect(c.all, 31);
      expect(c.forFolder(tech), 19);
    });

    test('increments a folder that had no entry', () {
      final c = seed().applyUnread(77);
      expect(c.all, 31);
      expect(c.forFolder(77), 1);
    });

    test('read then unread round-trips', () {
      final c = seed().applyRead(gaming).applyUnread(gaming);
      expect(c.all, 30);
      expect(c.forFolder(gaming), 12);
    });
  });

  group('applyManyRead — scroll batch', () {
    test('applies every folder id in the batch', () {
      final c = seed().applyManyRead([gaming, gaming, tech, null]);
      expect(c.all, 26);
      expect(c.forFolder(gaming), 10);
      expect(c.forFolder(tech), 17);
    });

    test('an empty batch is a no-op that still returns a value', () {
      final c = seed().applyManyRead(const []);
      expect(c.all, 30);
      expect(c.forFolder(gaming), 12);
    });

    test('over-reading a folder floors both counters', () {
      const c = UnreadCounts(all: 2, byFolder: {gaming: 2});
      final out = c.applyManyRead([gaming, gaming, gaming, gaming]);
      expect(out.all, 0);
      expect(out.forFolder(gaming), 0);
    });
  });

  group('bulk clears', () {
    test('clearedAll zeroes everything', () {
      final c = seed().clearedAll();
      expect(c.all, 0);
      expect(c.byFolder.values.every((v) => v == 0), isTrue);
    });

    test('clearedFolder subtracts that folder from all', () {
      final c = seed().clearedFolder(gaming);
      expect(c.forFolder(gaming), 0);
      expect(c.all, 18, reason: '30 - 12 gaming');
      expect(c.forFolder(tech), 18);
    });

    test('clearing an unknown folder leaves all untouched', () {
      final c = seed().clearedFolder(999);
      expect(c.all, 30);
    });
  });

  group('fromRepository', () {
    test('builds from a total and a per-folder map', () {
      final c = UnreadCounts.fromRepository(
        total: 30,
        byFolder: const {gaming: 12, tech: 18},
      );
      expect(c.all, 30);
      expect(c.forFolder(tech), 18);
    });
  });

  group('equality', () {
    test('two identical instances compare equal', () {
      expect(seed(), equals(seed()));
    });

    test('differing counts are not equal', () {
      expect(seed(), isNot(equals(seed().applyRead(gaming))));
    });
  });
}
