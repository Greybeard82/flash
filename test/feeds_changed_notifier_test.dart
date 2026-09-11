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

  // ── Broadcasting to screens already showing the structure ────────────────
  //
  // The regression: Settings is a pushed route, not a tab. An OPML import with
  // Categories underneath it wrote the folder and told nobody, because the
  // only mechanism was a queued change that FeedsScreen has no visibility
  // transition to consume. The folder existed and was invisible until the app
  // was restarted.

  test('a change notifies listeners', () async {
    var notified = 0;
    void listener() => notified++;
    notifier.addListener(listener);
    addTearDown(() => notifier.removeListener(listener));

    notifier.feedAdded();
    expect(notified, 0, reason: 'the notification is debounced, not immediate');

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(notified, 1);
  });

  test('a burst of writes collapses to one notification', () async {
    // Importing fifty feeds is fifty inserts. A reload each would re-query the
    // whole Categories screen fifty times.
    var notified = 0;
    void listener() => notified++;
    notifier.addListener(listener);
    addTearDown(() => notifier.removeListener(listener));

    for (var i = 0; i < 50; i++) {
      notifier.feedAdded();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(notified, 1);
  });

  test('listening does not consume the pending change', () async {
    // The whole point. FeedsScreen re-queries on the broadcast; the Flash tab
    // still needs the queued change to know it must fetch. If the listener
    // swallowed it, the imported feeds would sit there with no articles.
    var notified = 0;
    void listener() => notified++;
    notifier.addListener(listener);
    addTearDown(() => notifier.removeListener(listener));

    notifier.feedAdded();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(notified, 1);
    expect(notifier.consume(), FeedsChange.needsFetch,
        reason: 'the broadcast must leave the record intact');
  });

  test('reset cancels a pending notification', () async {
    // app.dart calls reset() on the with-pack onboarding path, where the fetch
    // is already handled by FeedScreen mounting fresh. A notification arriving
    // afterwards would be a reload nobody asked for.
    var notified = 0;
    void listener() => notified++;
    notifier.addListener(listener);
    addTearDown(() => notifier.removeListener(listener));

    notifier.feedAdded();
    notifier.reset();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(notified, 0);
    expect(notifier.isDirty, isFalse);
  });
}
