// The refresh *button* clears already-read rows out of the list.
//
// Pressing refresh means "tidy up and show me what's new", so the articles
// the user has already read this session drop out and only unread ones
// remain. Pull-to-refresh deliberately does not do this — see the note on
// FeedScreen._refreshCurrentTab.
//
// The mechanism is entirely in SessionReadTracker: a read article is only
// still visible because its id sits in the session set, so forgetting the
// read ids is the whole change. That makes it testable without pumping
// FeedScreen, which this repo can't do against a real DB anyway (the FFI
// future never resolves inside flutter_test's FakeAsync zone — see
// feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/article.dart';
import 'package:flash/services/session_read_tracker.dart';

Article _article({required int id, required bool isRead}) => Article(
      id: id,
      feedId: 1,
      guid: 'g$id',
      title: 'Article $id',
      url: 'https://example.com/$id',
      fetchedAt: 0,
      isRead: isRead,
    );

/// Mirrors FeedScreen's union query: visible when unread, or read this
/// session.
List<int> _visible(List<Article> articles, Set<int> sessionIds) => articles
    .where((a) => !a.isRead || sessionIds.contains(a.id))
    .map((a) => a.id!)
    .toList();

/// What the refresh button does before reloading.
void _dropReadFromSession(List<Article> onScreen) {
  SessionReadTracker.instance.removeAll(
    [for (final a in onScreen) if (a.isRead && a.id != null) a.id!],
  );
}

void main() {
  late SessionReadTracker tracker;

  setUp(() {
    tracker = SessionReadTracker.instance;
    tracker.clear();
  });
  tearDown(() => SessionReadTracker.instance.clear());

  test('read articles drop out, unread ones stay', () {
    final onScreen = [
      _article(id: 1, isRead: true),
      _article(id: 2, isRead: false),
      _article(id: 3, isRead: true),
      _article(id: 4, isRead: false),
    ];
    tracker.addAll([1, 3]); // read this session, hence still on screen

    expect(_visible(onScreen, tracker.ids), [1, 2, 3, 4]);

    _dropReadFromSession(onScreen);

    expect(_visible(onScreen, tracker.ids), [2, 4],
        reason: 'pressing refresh leaves only what has not been read');
  });

  test('a list with nothing read is unchanged', () {
    final onScreen = [
      _article(id: 1, isRead: false),
      _article(id: 2, isRead: false),
    ];

    _dropReadFromSession(onScreen);

    expect(_visible(onScreen, tracker.ids), [1, 2]);
    expect(tracker.ids, isEmpty);
  });

  test('a fully-read list empties', () {
    final onScreen = [
      _article(id: 1, isRead: true),
      _article(id: 2, isRead: true),
    ];
    tracker.addAll([1, 2]);

    _dropReadFromSession(onScreen);

    expect(_visible(onScreen, tracker.ids), isEmpty);
  });

  test('articles read in another tab are untouched', () {
    // Only what is on screen is forgotten. An article read elsewhere this
    // session keeps its place in the tab it was read in, exactly as the
    // category mark-all-read path behaves.
    final onScreen = [_article(id: 1, isRead: true)];
    tracker.addAll([1, 99]); // 99 read in some other tab, not on screen here

    _dropReadFromSession(onScreen);

    expect(tracker.ids, {99});
  });

  test('pressing refresh twice is stable', () {
    final onScreen = [
      _article(id: 1, isRead: true),
      _article(id: 2, isRead: false),
    ];
    tracker.addAll([1]);

    _dropReadFromSession(onScreen);
    final afterFirst = _visible(onScreen, tracker.ids);
    _dropReadFromSession(onScreen);

    expect(_visible(onScreen, tracker.ids), afterFirst);
    expect(afterFirst, [2]);
  });

  test('pull-to-refresh leaves the session set alone', () {
    // The distinction that keeps the list from collapsing under the finger
    // that just pulled it.
    final onScreen = [
      _article(id: 1, isRead: true),
      _article(id: 2, isRead: false),
    ];
    tracker.addAll([1]);

    // Pull-to-refresh reloads without calling _dropReadFromSession.
    expect(_visible(onScreen, tracker.ids), [1, 2],
        reason: 'the read article stays put, dimmed, on a pull-to-refresh');
  });
}
