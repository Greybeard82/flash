// Scoped SessionReadTracker tests.
//
// Written independently of the implementation.
//
// Behaviour change from UX Pass 01: the session-read set is no longer global.
// An article read in one tab stays visible (dimmed) in THAT tab only — so the
// list you are actively scrolling never collapses under you — but it is gone
// entirely from every other tab. Scrolling an article past the top is a signal
// of disinterest; it should not follow you around the app as grey clutter.
//
// Scope key: kAllScope (-1) for the All tab, folder_id for a category tab.
// Folder ids are positive autoincrement values, so there is no collision.
//
// Covered behaviours:
//  1. Reads are recorded against a scope, not globally
//  2. An article read in All is absent from a category tab's union query
//  3. An article read in a category is absent from All's union query
//  4. Returning to the scope where it was read still shows it, dimmed
//  5. Mark-unread removes it from every scope
//  6. Mark-all-read clears one scope or all scopes
//  7. Scope views are safe to hand to callers

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/session_read_tracker.dart';

// Simulates the union query the repository runs: an article is shown when it
// is unread OR its id is in the session-read set for the scope being viewed.
List<int> _visible({
  required Map<int, bool> readState, // articleId -> isRead in DB
  required Set<int> scopeIds,
}) =>
    readState.entries
        .where((e) => !e.value || scopeIds.contains(e.key))
        .map((e) => e.key)
        .toList();

void main() {
  const allScope = kAllScope;
  const gaming = 1;
  const tech = 2;

  late SessionReadTracker tracker;

  setUp(() {
    tracker = SessionReadTracker.instance;
    tracker.clear();
  });

  group('scope isolation', () {
    test('starts empty in every scope', () {
      expect(tracker.idsForScope(allScope), isEmpty);
      expect(tracker.idsForScope(gaming), isEmpty);
    });

    test('an id added to All is not present in a folder scope', () {
      tracker.add(5, scope: allScope);
      expect(tracker.idsForScope(allScope), contains(5));
      expect(tracker.idsForScope(gaming), isEmpty);
    });

    test('an id added to a folder is not present in All', () {
      tracker.add(5, scope: gaming);
      expect(tracker.idsForScope(gaming), contains(5));
      expect(tracker.idsForScope(allScope), isEmpty);
    });

    test('the same id can be recorded in two scopes independently', () {
      tracker.add(5, scope: allScope);
      tracker.add(5, scope: gaming);
      expect(tracker.isReadInScope(5, allScope), isTrue);
      expect(tracker.isReadInScope(5, gaming), isTrue);
      expect(tracker.isReadInScope(5, tech), isFalse);
    });

    test('unknown scopes return an empty set rather than throwing', () {
      expect(tracker.idsForScope(999), isEmpty);
    });

    test('the returned scope view cannot corrupt the tracker', () {
      tracker.add(5, scope: allScope);
      final view = tracker.idsForScope(allScope);
      expect(() => view.add(99), throwsUnsupportedError);
    });
  });

  group('addAll — scroll batches', () {
    test('records a whole batch against one scope', () {
      tracker.addAll([1, 2, 3], scope: allScope);
      expect(tracker.idsForScope(allScope), {1, 2, 3});
      expect(tracker.idsForScope(gaming), isEmpty);
    });

    test('an empty batch is a no-op', () {
      tracker.addAll(const [], scope: allScope);
      expect(tracker.idsForScope(allScope), isEmpty);
    });
  });

  group('the headline behaviour — read in All, gone from Gaming', () {
    test('a Gaming article read while scrolling All disappears from Gaming',
        () {
      // Articles 5 and 6 belong to Gaming. The user scrolls past 5 in All.
      tracker.add(5, scope: allScope);
      final readState = {5: true, 6: false};

      final inGaming = _visible(
        readState: readState,
        scopeIds: tracker.idsForScope(gaming),
      );

      expect(inGaming, isNot(contains(5)),
          reason: 'read elsewhere — must not appear at all, not even dimmed');
      expect(inGaming, contains(6));
    });

    test('but it is still there, dimmed, when the user returns to All', () {
      tracker.add(5, scope: allScope);
      final readState = {5: true, 6: false};

      final inAll = _visible(
        readState: readState,
        scopeIds: tracker.idsForScope(allScope),
      );

      expect(inAll, contains(5),
          reason: 'the list being scrolled must never collapse underneath');
      expect(inAll, contains(6));
    });

    test('the rule is symmetric — read in Gaming, gone from All', () {
      tracker.add(5, scope: gaming);
      final readState = {5: true, 6: false};

      expect(
        _visible(readState: readState, scopeIds: tracker.idsForScope(allScope)),
        isNot(contains(5)),
      );
      expect(
        _visible(readState: readState, scopeIds: tracker.idsForScope(gaming)),
        contains(5),
      );
    });

    test('articles read in a previous session appear nowhere', () {
      // Nothing in the tracker — the app was relaunched.
      final readState = {5: true, 6: false};
      for (final scope in [allScope, gaming, tech]) {
        expect(
          _visible(readState: readState, scopeIds: tracker.idsForScope(scope)),
          [6],
        );
      }
    });
  });

  group('removeEverywhere — mark as unread', () {
    test('clears the id from every scope', () {
      tracker.add(5, scope: allScope);
      tracker.add(5, scope: gaming);
      tracker.removeEverywhere(5);
      expect(tracker.isReadInScope(5, allScope), isFalse);
      expect(tracker.isReadInScope(5, gaming), isFalse);
    });

    test('leaves other ids alone', () {
      tracker.addAll([5, 6], scope: allScope);
      tracker.removeEverywhere(5);
      expect(tracker.idsForScope(allScope), {6});
    });

    test('removing an untracked id is a no-op', () {
      tracker.add(5, scope: allScope);
      tracker.removeEverywhere(99);
      expect(tracker.idsForScope(allScope), {5});
    });
  });

  group('clearing', () {
    test('clearScope empties one scope and leaves the others', () {
      tracker.addAll([1, 2], scope: allScope);
      tracker.addAll([3, 4], scope: gaming);
      tracker.clearScope(gaming);
      expect(tracker.idsForScope(gaming), isEmpty);
      expect(tracker.idsForScope(allScope), {1, 2});
    });

    test('clear empties everything', () {
      tracker.addAll([1, 2], scope: allScope);
      tracker.addAll([3, 4], scope: gaming);
      tracker.clear();
      expect(tracker.idsForScope(allScope), isEmpty);
      expect(tracker.idsForScope(gaming), isEmpty);
      expect(tracker.allIds, isEmpty);
    });

    test('clearing an untouched scope is a no-op', () {
      tracker.addAll([1, 2], scope: allScope);
      tracker.clearScope(tech);
      expect(tracker.idsForScope(allScope), {1, 2});
    });
  });

  group('allIds', () {
    test('is the union across scopes, deduplicated', () {
      tracker.addAll([1, 2], scope: allScope);
      tracker.addAll([2, 3], scope: gaming);
      expect(tracker.allIds, {1, 2, 3});
    });
  });

  group('scope keys', () {
    test('kAllScope is negative so it cannot collide with a folder id', () {
      expect(kAllScope, lessThan(0));
    });
  });
}
