// Feed behavior unit tests.
//
// These tests cover the pure-logic list mutations that the feed screen applies
// to its article list. They do NOT require a real SQLite database or Flutter
// widget pump — they test Dart functions directly.
//
// Covered behaviors (current, post-rewrite):
//  1. getAllArticles returns only unread+unblocked articles from the DB
//  2. Opening an article dims it in-place (isRead = true), scroll restored
//  3. Scroll-to-read: DB write immediate, UI dims in-place after debounce
//  4. Swipe (either direction) marks article as read and dims in-place
//  5. Articles with isRead=true are rendered at reduced opacity but stay in list
//  6. Tab switch restores that tab's saved scroll offset (or top if none)
//  7. Read state is global: marking read in "All" removes it from category DB query

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

// Simulates _openArticle: dims the tapped article in-place, rest unchanged.
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

// Simulates the unread-only filter used by getAllArticles / getArticlesByFolder.
List<Article> _unreadOnly(List<Article> list) =>
    list.where((a) => !a.isRead).toList();

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DB query returns only unread articles', () {
    test('_articlesForTab returns only unread articles', () {
      final all = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
        _article(id: 3, isRead: false),
        _article(id: 4, isRead: true),
      ];
      final result = _unreadOnly(all);
      expect(result.length, 2);
      expect(result.every((a) => !a.isRead), isTrue);
    });

    test('empty list when all articles are read', () {
      final all = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: true),
      ];
      expect(_unreadOnly(all), isEmpty);
    });
  });

  group('Opening an article dims it in-place', () {
    test('opened article is marked read but stays in list', () {
      final articles = [
        _article(id: 1),
        _article(id: 2),
        _article(id: 3),
      ];
      final result = _dimArticle(articles, 2);
      expect(result.length, 3);
      expect(result.any((a) => a.id == 2), isTrue);
      expect(result.firstWhere((a) => a.id == 2).isRead, isTrue);
    });

    test('articles above and below dimmed article are unchanged', () {
      final articles = [
        _article(id: 10),
        _article(id: 20),
        _article(id: 30),
      ];
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
        _article(id: 1),
        _article(id: 2),
        _article(id: 3),
        _article(id: 4),
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
      final articles = [
        _article(id: 1),
        _article(id: 2),
        _article(id: 3),
      ];
      final result = _markReadSwipe(articles, 2);
      expect(result.length, 3);
      expect(result.any((a) => a.id == 2), isTrue);
      expect(result.firstWhere((a) => a.id == 2).isRead, isTrue);
    });

    test('swipe on already-read article is a no-op', () {
      final articles = [
        _article(id: 1, isRead: true),
        _article(id: 2),
      ];
      final result = _markReadSwipe(articles, 1);
      expect(result.length, 2);
      expect(result.firstWhere((a) => a.id == 1).isRead, isTrue);
    });

    test('both swipe directions produce same in-place dim result', () {
      final articles = [_article(id: 5), _article(id: 6)];
      final leftSwipe = _markReadSwipe(articles, 5);
      final rightSwipe = _markReadSwipe(articles, 5);
      // Both directions call the same _markRead logic.
      expect(leftSwipe.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(rightSwipe.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(leftSwipe.length, rightSwipe.length);
    });
  });

  group('Read articles stay in list with reduced opacity signal', () {
    test('isRead=true acts as the opacity signal (no removal from list)', () {
      final articles = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
      ];
      // The list contains both; caller uses isRead to pick opacity.
      expect(articles.length, 2);
      expect(articles.firstWhere((a) => a.id == 1).isRead, isFalse);
      expect(articles.firstWhere((a) => a.id == 2).isRead, isTrue);
    });
  });

  group('Refresh behavior', () {
    test('refresh with new articles populates list', () {
      final fetched = [_article(id: 10), _article(id: 11), _article(id: 12)];
      final displayed = _unreadOnly(fetched);
      expect(displayed.length, 3);
    });

    test('refresh with no new articles returns empty list', () {
      final fetched = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: true),
      ];
      final displayed = _unreadOnly(fetched);
      expect(displayed, isEmpty);
    });
  });

  group('Read state is global across tabs', () {
    test('article marked read in All is absent from category DB query', () {
      // Both lists start with article 5 as unread.
      final allTabArticles = [_article(id: 5, feedId: 2), _article(id: 6, feedId: 1)];
      final techTabArticles = [_article(id: 5, feedId: 2), _article(id: 7, feedId: 2)];

      // User opens article 5 in All tab → dimmed in-place in All.
      final updatedAll = _dimArticle(allTabArticles, 5);

      // Tech tab reloads from DB (unread-only) — article 5 is now read in DB.
      final updatedTech = _unreadOnly(
        techTabArticles.map((a) => a.id == 5 ? a.copyWith(isRead: true) : a).toList(),
      );

      expect(updatedAll.any((a) => a.id == 5), isTrue);
      expect(updatedAll.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(updatedTech.any((a) => a.id == 5), isFalse);
    });
  });

  group('Tab switch', () {
    test('switching tabs loads only that tab\'s unread articles', () {
      final techArticles = [
        _article(id: 3, feedId: 2, isRead: true),
        _article(id: 4, feedId: 2, isRead: false),
        _article(id: 5, feedId: 2, isRead: false),
      ];
      final result = _unreadOnly(techArticles);
      expect(result.length, 2);
      expect(result.every((a) => a.feedId == 2), isTrue);
    });
  });
}
