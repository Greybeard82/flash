// FeedsChangedNotifier tests.
//
// Written independently of the implementation. Records a structural change
// to the feed/folder set made while the article list was on another tab, for
// FeedScreen to consume when it next becomes visible.
//
// Covered behaviours:
//  1. Clean by default
//  2. Adding a feed queues a fetch; other edits queue a plain reload
//  3. needsFetch outranks structureOnly in both orders — the escalation rule
//  4. consume() returns the pending change and clears it
//  5. Batching: many changes collapse to one consume
//  6. It is a singleton, so a ping from a repository reaches the feed screen

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/feeds_changed_notifier.dart';

void main() {
  late FeedsChangedNotifier notifier;

  setUp(() {
    notifier = FeedsChangedNotifier.instance;
    notifier.reset();
  });
  tearDown(() => FeedsChangedNotifier.instance.reset());

  test('starts clean', () {
    expect(notifier.isDirty, isFalse);
    expect(notifier.pending, isNull);
  });

  test('adding a feed queues a network fetch', () {
    notifier.feedAdded();
    expect(notifier.pending, FeedsChange.needsFetch,
        reason: 'a new feed has no articles until something fetches it');
  });

  test('a structural edit queues a reload only', () {
    notifier.structureChanged();
    expect(notifier.pending, FeedsChange.structureOnly);
  });

  test('a structural edit after an add does not downgrade the fetch', () {
    notifier.feedAdded();
    notifier.structureChanged();
    expect(notifier.pending, FeedsChange.needsFetch,
        reason: 'add then reorder is a normal sequence; downgrading here '
            'would leave the new feed empty');
  });

  test('an add after a structural edit escalates to a fetch', () {
    notifier.structureChanged();
    notifier.feedAdded();
    expect(notifier.pending, FeedsChange.needsFetch);
  });

  test('consume returns the pending change and clears it', () {
    notifier.feedAdded();

    expect(notifier.consume(), FeedsChange.needsFetch);
    expect(notifier.isDirty, isFalse);
    expect(notifier.consume(), isNull,
        reason: 'a consumed change must not fire a second refresh');
  });

  test('consuming a clean notifier is a no-op', () {
    expect(notifier.consume(), isNull);
    expect(notifier.isDirty, isFalse);
  });

  test('six feeds added in a row collapse to one pending fetch', () {
    for (var i = 0; i < 6; i++) {
      notifier.feedAdded();
    }
    expect(notifier.consume(), FeedsChange.needsFetch);
    expect(notifier.consume(), isNull,
        reason: 'adding six feeds must cost one refresh, not six');
  });

  test('the singleton is shared, so a repository ping reaches the feed', () {
    FeedsChangedNotifier.instance.feedAdded();
    expect(notifier.pending, FeedsChange.needsFetch);
  });
}
