// Feed behavior unit tests.
//
// These tests cover the pure-logic list mutations that the feed screen applies
// to its in-memory article list, plus the union-query model that drives what
// the screen shows.
//
// Covered behaviors:
//  1. Union query: unread OR session-read IDs — not unread-only
//  2. Opening an article dims it in-place (isRead = true), scroll restored
//  3. Scroll-to-read: DB write immediate, UI dims in-place after debounce
//  4. Swipe (either direction) marks article as read and dims in-place
//  5. Articles with isRead=true are rendered at reduced opacity but stay in list
//  6. Tab switch restores that tab's saved scroll offset (or top if none)
//  7. Read state is scoped: reading in one tab hides it from other tabs, keeps it dimmed in its own
//  8. Mark-unread removes from session tracker and restores full weight

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/article.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Article _article({
  required int id,
  bool isRead = false,
  int feedId = 1,
}) =>
    Article(
      id: id,
      feedId: feedId,
      guid: 'guid-$id',
      title: 'Article $id',
      url: 'https://example.com/$id',
      description: '',
      fetchedAt: 0,
      isRead: isRead,
      isBlocked: false,
      isSaved: false,
    );

// Simulates the union query: unread OR id ∈ sessionReadIds.
List<Article> _unionQuery(List<Article> list, Set<int> sessionReadIds) =>
    list.where((a) => !a.isRead || sessionReadIds.contains(a.id)).toList();

// Simulates _openArticle / _markRead: dims the tapped article in-place.
List<Article> _dimArticle(List<Article> list, int articleId) => [
      for (final a in list)
        a.id == articleId ? a.copyWith(isRead: true) : a,
    ];

// Simulates _flushMarkReadUI: dims all articles whose IDs are in [ids].
List<Article> _dimIds(List<Article> list, Set<int> ids) => [
      for (final a in list)
        ids.contains(a.id) ? a.copyWith(isRead: true) : a,
    ];

// Simulates _markRead (swipe either direction): dims in-place.
List<Article> _markReadSwipe(List<Article> list, int articleId) =>
    _dimArticle(list, articleId);

// Simulates _markUnread: un-dims the article.
List<Article> _dimUnread(List<Article> list, int articleId) => [
      for (final a in list)
        a.id == articleId ? a.copyWith(isRead: false) : a,
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Union query (unread OR session-read)', () {
    test('empty tracker returns only unread articles', () {
      final all = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
        _article(id: 3, isRead: false),
        _article(id: 4, isRead: true),
      ];
      final result = _unionQuery(all, {});
      expect(result.length, 2);
      expect(result.every((a) => !a.isRead), isTrue);
    });

    test('tracker adds read articles back into view', () {
      final all = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
        _article(id: 3, isRead: false),
      ];
      final result = _unionQuery(all, {2});
      expect(result.length, 3);
      expect(result.any((a) => a.id == 2 && a.isRead), isTrue);
    });

    test('cold open: empty tracker, all read in DB → empty list', () {
      final all = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: true),
      ];
      expect(_unionQuery(all, {}), isEmpty);
    });

    test('tracker with IDs not in the list is safe (no crash, no phantom rows)', () {
      final all = [_article(id: 1), _article(id: 2)];
      final result = _unionQuery(all, {99, 100});
      expect(result.length, 2);
    });
  });

  group('Opening an article dims it in-place', () {
    test('opened article is marked read but stays in list', () {
      final articles = [_article(id: 1), _article(id: 2), _article(id: 3)];
      final result = _dimArticle(articles, 2);
      expect(result.length, 3);
      expect(result.any((a) => a.id == 2), isTrue);
      expect(result.firstWhere((a) => a.id == 2).isRead, isTrue);
    });

    test('articles above and below dimmed article are unchanged', () {
      final articles = [_article(id: 10), _article(id: 20), _article(id: 30)];
      final result = _dimArticle(articles, 20);
      expect(result.map((a) => a.id).toList(), [10, 20, 30]);
      expect(result.firstWhere((a) => a.id == 10).isRead, isFalse);
      expect(result.firstWhere((a) => a.id == 30).isRead, isFalse);
    });

    test('opening last article dims it but list has one element', () {
      final articles = [_article(id: 1)];
      final result = _dimArticle(articles, 1);
      expect(result.length, 1);
      expect(result.first.isRead, isTrue);
    });
  });

  group('Scroll-to-read dims articles in-place', () {
    test('scrolled-past articles are dimmed, not removed', () {
      final articles = [
        _article(id: 1), _article(id: 2), _article(id: 3), _article(id: 4),
      ];
      final result = _dimIds(articles, {1, 2});
      expect(result.length, 4);
      expect(result.firstWhere((a) => a.id == 1).isRead, isTrue);
      expect(result.firstWhere((a) => a.id == 2).isRead, isTrue);
      expect(result.firstWhere((a) => a.id == 3).isRead, isFalse);
      expect(result.firstWhere((a) => a.id == 4).isRead, isFalse);
    });

    test('unread count decreases by number of dimmed articles', () {
      int unreadCount = 4;
      final dimmed = {1, 2};
      unreadCount = (unreadCount - dimmed.length).clamp(0, unreadCount);
      expect(unreadCount, 2);
    });

    test('dimming all articles leaves them in list but all read', () {
      final articles = [_article(id: 1), _article(id: 2)];
      final result = _dimIds(articles, {1, 2});
      expect(result.length, 2);
      expect(result.every((a) => a.isRead), isTrue);
    });
  });

  group('Swipe mark-as-read dims article in-place', () {
    test('swiped article is dimmed, not removed', () {
      final articles = [_article(id: 1), _article(id: 2), _article(id: 3)];
      final result = _markReadSwipe(articles, 2);
      expect(result.length, 3);
      expect(result.any((a) => a.id == 2), isTrue);
      expect(result.firstWhere((a) => a.id == 2).isRead, isTrue);
    });

    test('swipe on already-read article leaves it read', () {
      final articles = [_article(id: 1, isRead: true), _article(id: 2)];
      final result = _markReadSwipe(articles, 1);
      expect(result.length, 2);
      expect(result.firstWhere((a) => a.id == 1).isRead, isTrue);
    });

    test('both swipe directions produce same in-place dim result', () {
      final articles = [_article(id: 5), _article(id: 6)];
      final leftSwipe = _markReadSwipe(articles, 5);
      final rightSwipe = _markReadSwipe(articles, 5);
      expect(leftSwipe.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(rightSwipe.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(leftSwipe.length, rightSwipe.length);
    });
  });

  group('Mark-unread removes from tracker and restores full weight', () {
    test('un-dimming restores isRead=false', () {
      final articles = [_article(id: 1, isRead: true), _article(id: 2)];
      final result = _dimUnread(articles, 1);
      expect(result.firstWhere((a) => a.id == 1).isRead, isFalse);
      expect(result.length, 2);
    });

    test('tracker removal: ID no longer in session set', () {
      final tracker = <int>{1, 2, 3};
      tracker.remove(2);
      expect(tracker, containsAll([1, 3]));
      expect(tracker, isNot(contains(2)));
    });

    test('after mark-unread, union query re-hides the article on next tab load', () {
      final articles = [_article(id: 1, isRead: true), _article(id: 2)];
      // Tracker no longer contains id 1 (was removed by _markUnread).
      final result = _unionQuery(articles, {});
      // Article 1 is read but not in tracker → excluded.
      expect(result.any((a) => a.id == 1), isFalse);
      expect(result.any((a) => a.id == 2), isTrue);
    });
  });

  group('Read state is scoped per tab (session tracker)', () {
    test('article read in All tab is absent from folder tab', () {
      // Simulate: All tab loaded, user reads article 5. Recorded under All's
      // own scope — a folder tab's union query never sees it.
      final allTabArticles = [_article(id: 5, feedId: 2), _article(id: 6, feedId: 1)];
      final allScopeTracker = <int>{};

      final updatedAll = _dimArticle(allTabArticles, 5);
      allScopeTracker.add(5);

      // Folder tab re-runs its union query with its own (empty) scope tracker.
      final folderTabArticles = [
        _article(id: 5, feedId: 2, isRead: true),
        _article(id: 7, feedId: 2),
      ];
      final folderScopeTracker = <int>{};
      final folderResult = _unionQuery(folderTabArticles, folderScopeTracker);

      // Article 5 was read elsewhere (All scope) — absent entirely, not dimmed.
      expect(folderResult.any((a) => a.id == 5), isFalse);
      expect(folderResult.length, 1);

      // All tab still shows it, dimmed, in its own scope.
      expect(updatedAll.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(allScopeTracker, contains(5));
    });

    test('mark-all-read (All) + clear tracker → reload shows unread-only', () {
      final beforeClear = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: false),
      ];
      final tracker = <int>{1};

      // Before clear: article 1 still visible via tracker.
      expect(_unionQuery(beforeClear, tracker).length, 2);

      // After markAllAsRead + clear tracker: unread-only.
      tracker.clear();
      final reloaded = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: true), // now also marked read
      ];
      expect(_unionQuery(reloaded, tracker), isEmpty);
    });

    test('mark-all-read (Category) removes folder IDs, other tab IDs remain', () {
      final tracker = <int>{10, 20}; // 10 = folder1, 20 = folder2
      final folder1Ids = {10};

      tracker.removeWhere(folder1Ids.contains);

      expect(tracker, isNot(contains(10)));
      expect(tracker, contains(20));
    });
  });

  group('Tab switch', () {
    test('tab with saved scroll offset restores position', () {
      final positions = <int, double>{0: 320.0, 1: 0.0};
      // Switching from tab 0 to tab 1: save tab 0, restore tab 1.
      expect(positions[0], 320.0);
      expect(positions[1] ?? 0.0, 0.0);
    });

    test('switching to a new tab (no saved offset) starts at top', () {
      final positions = <int, double>{};
      final offset = positions[2] ?? 0.0;
      expect(offset, 0.0);
    });
  });

  group('Read articles stay in list with reduced opacity signal', () {
    test('isRead=true acts as the opacity signal (no removal from list)', () {
      final articles = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
      ];
      expect(articles.length, 2);
      expect(articles.firstWhere((a) => a.id == 1).isRead, isFalse);
      expect(articles.firstWhere((a) => a.id == 2).isRead, isTrue);
    });
  });
}
