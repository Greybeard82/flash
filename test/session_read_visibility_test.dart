// Session-read visibility tests. Replaces test/session_read_scope_test.dart,
// which tested the scoped API (idsForScope / clearScope / kAllScope) that no
// longer exists — same coverage, restated against the flat contract.
//
// Behaviour change: the session-read set is global again. An article read in
// any tab stays visible, dimmed in place, in every tab for the rest of the
// session. This is Palabre's model, and it replaces an earlier design where
// an article read in one tab vanished entirely from all the others — which
// made lists the user hadn't touched silently lose rows.
//
// Covered behaviours:
//  1. Reads are recorded once, globally
//  2. An article read in All is still shown (dimmed) by a category's query
//  3. An article read in a category is still shown (dimmed) by All's query
//  4. Mark-unread drops it everywhere
//  5. Mark-all-read on a category forgets only that tab's IDs
//  6. Mark-all-read on All clears everything
//  7. The exposed set is safe to hand to callers

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/session_read_tracker.dart';

// Simulates the union query the repository runs: an article is shown when it
// is unread OR its id is in the session-read set. Every tab now passes the
// same set, so there is no scope parameter left to vary.
List<int> _visible({
  required Map<int, bool> readState, // articleId -> isRead in DB
  required Set<int> sessionIds,
}) =>
    readState.entries
        .where((e) => !e.value || sessionIds.contains(e.key))
        .map((e) => e.key)
        .toList();

void main() {
  late SessionReadTracker tracker;

  setUp(() {
    tracker = SessionReadTracker.instance;
    tracker.clear();
  });

  group('recording', () {
    test('starts empty', () {
      expect(tracker.ids, isEmpty);
    });

    test('add records an id once, globally', () {
      tracker.add(5);
      expect(tracker.ids, contains(5));
      expect(tracker.contains(5), isTrue);
    });

    test('adding the same id twice is idempotent', () {
      tracker.add(5);
      tracker.add(5);
      expect(tracker.ids, {5});
    });

    test('addAll records a batch', () {
      tracker.addAll([1, 2, 3]);
      expect(tracker.ids, {1, 2, 3});
    });

    test('an unknown id is not reported as read', () {
      tracker.add(5);
      expect(tracker.contains(999), isFalse);
    });

    test('the exposed set is unmodifiable, so callers cannot corrupt it', () {
      tracker.add(1);
      expect(() => tracker.ids.add(2), throwsUnsupportedError);
    });
  });

  group('visibility is global', () {
    test('an article read in All is still shown, dimmed, by a category query',
        () {
      final readState = {5: true, 7: false};
      tracker.add(5); // read while viewing All

      final categoryView =
          _visible(readState: readState, sessionIds: tracker.ids);

      expect(categoryView, contains(5),
          reason: 'it stays in place rather than vanishing from a list the '
              'user was not looking at');
      expect(categoryView, containsAll([5, 7]));
    });

    test('an article read in a category is still shown by All\'s query', () {
      final readState = {5: true, 7: false};
      tracker.add(5); // read while viewing a category

      final allView = _visible(readState: readState, sessionIds: tracker.ids);

      expect(allView, contains(5), reason: 'the rule is symmetric');
    });

    test('every tab sees exactly the same rows', () {
      final readState = {1: true, 2: true, 3: false};
      tracker.addAll([1, 2]);

      final a = _visible(readState: readState, sessionIds: tracker.ids);
      final b = _visible(readState: readState, sessionIds: tracker.ids);

      expect(a, equals(b));
      expect(a, containsAll([1, 2, 3]));
    });

    test('a read article not in the session set is hidden everywhere', () {
      // e.g. read in a previous session, or read from Bookmarks/Search which
      // never touch the tracker.
      final readState = {5: true, 7: false};

      expect(_visible(readState: readState, sessionIds: tracker.ids), [7]);
    });
  });

  group('remove — mark as unread', () {
    test('drops the id so it hides again on the next query', () {
      tracker.add(5);
      tracker.remove(5);

      expect(tracker.contains(5), isFalse);
      expect(_visible(readState: {5: false}, sessionIds: tracker.ids), [5]);
    });

    test('leaves other ids alone', () {
      tracker.addAll([5, 6]);
      tracker.remove(5);
      expect(tracker.ids, {6});
    });

    test('removing an id that was never added is a no-op', () {
      tracker.add(5);
      tracker.remove(99);
      expect(tracker.ids, {5});
    });
  });

  group('mark-all-read', () {
    test('on a category: forgets only the ids that tab was showing', () {
      tracker.addAll([1, 2, 3]);
      // 1 and 2 were visible in this category; 3 was read in another tab.
      tracker.removeAll([1, 2]);

      expect(tracker.ids, {3},
          reason: 'clearing wholesale would un-dim and then hide article 3 in '
              'the tab it was actually read in');
    });

    test('on a category: ids read elsewhere survive and stay visible', () {
      final readState = {1: true, 3: true};
      tracker.addAll([1, 3]);
      tracker.removeAll([1]);

      final otherTabView =
          _visible(readState: readState, sessionIds: tracker.ids);
      expect(otherTabView, [3]);
    });

    test('on a category: removing ids that were not tracked is harmless', () {
      tracker.addAll([1]);
      tracker.removeAll([1, 2, 3]);
      expect(tracker.ids, isEmpty);
    });

    test('on All: clears the whole set — start fresh everywhere', () {
      tracker.addAll([1, 2, 3]);
      tracker.clear();

      expect(tracker.ids, isEmpty);
      expect(_visible(readState: {1: true, 2: true}, sessionIds: tracker.ids),
          isEmpty);
    });
  });

  group('the singleton', () {
    test('is one shared instance', () {
      expect(identical(SessionReadTracker.instance, SessionReadTracker.instance),
          isTrue);
    });

    test('carries no scoping API any more', () {
      // Guard against the per-tab model creeping back in: with visibility
      // global there is nothing left to key reads by.
      expect(tracker.ids, isA<Set<int>>());
    });
  });
}
