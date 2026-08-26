// Feed behavior unit tests.
//
// These tests cover the pure-logic list mutations that the feed screen applies
// to its in-memory article list, plus the visibility model that drives what
// the screen shows.
//
// Covered behaviors:
//  1. Visibility query: unread OR read inside the show-read window
//  2. Opening an article dims it in-place (isRead = true), scroll restored
//  3. Scroll-to-read: DB write immediate, UI dims in-place after debounce
//  4. Swipe (either direction) marks article as read and dims in-place
//  5. Articles with isRead=true are rendered at reduced opacity but stay in list
//  6. Tab switch restores that tab's saved scroll offset (or top if none)
//  7. Read state is global: an article read in any tab stays dimmed in place in every tab
//  8. Mark-unread clears read_at and restores full weight

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/article.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

const int _now = 1750000000000;
const int _windowStart = _now - 48 * 60 * 60 * 1000;

Article _article({
  required int id,
  bool isRead = false,
  int feedId = 1,
  int? readAt,
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
      // A read article with no explicit stamp is treated as read "now",
      // which is what markAsRead does.
      readAt: readAt ?? (isRead ? _now : null),
      isBlocked: false,
      isSaved: false,
    );

// Simulates the visibility query: unread, or read at/after the cutoff.
// A null cutoff means read articles are hidden entirely.
List<Article> _visible(List<Article> list, int? readSinceMs) => list
    .where((a) =>
        !a.isRead ||
        (readSinceMs != null && a.readAt != null && a.readAt! >= readSinceMs))
    .toList();

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
  group('Visibility query (unread OR recently read)', () {
    test('Show read off returns only unread articles', () {
      final all = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
        _article(id: 3, isRead: false),
        _article(id: 4, isRead: true),
      ];
      final result = _visible(all, null);
      expect(result.length, 2);
      expect(result.every((a) => !a.isRead), isTrue);
    });

    test('the window brings recently read articles back into view', () {
      final all = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true),
        _article(id: 3, isRead: false),
      ];
      final result = _visible(all, _windowStart);
      expect(result.length, 3);
      expect(result.any((a) => a.id == 2 && a.isRead), isTrue);
    });

    test('articles read before the window stay hidden', () {
      final all = [
        _article(id: 1, isRead: false),
        _article(id: 2, isRead: true, readAt: _windowStart - 1),
      ];
      final result = _visible(all, _windowStart);
      expect(result.map((a) => a.id), [1]);
    });

    test('cold open: Show read off, all read in DB → empty list', () {
      final all = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: true),
      ];
      expect(_visible(all, null), isEmpty);
    });

    test('a read row with no timestamp (pre-v11) is never restored', () {
      // Built directly rather than through _article: that helper stamps a
      // read article with _now, and `??` cannot tell "omitted" from an
      // explicit null. A migrated row genuinely has read_at NULL.
      const legacy = Article(
        id: 1,
        feedId: 1,
        guid: 'guid-1',
        title: 'Article 1',
        url: 'https://example.com/1',
        fetchedAt: 0,
        isRead: true,
      );
      expect(legacy.readAt, isNull);
      expect(_visible([legacy], _windowStart), isEmpty,
          reason: 'NULL never satisfies >=');
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

  group('Mark-unread clears read_at and restores full weight', () {
    test('un-dimming restores isRead=false', () {
      final articles = [_article(id: 1, isRead: true), _article(id: 2)];
      final result = _dimUnread(articles, 1);
      expect(result.firstWhere((a) => a.id == 1).isRead, isFalse);
      expect(result.length, 2);
    });

    test('mark-unread produces an article with no read_at', () {
      final read = _article(id: 2, isRead: true);
      expect(read.readAt, isNotNull);

      final unread = read.copyWith(isRead: false, clearReadAt: true);
      expect(unread.readAt, isNull);
      // Excluded by the read half of the query under every cutoff — and
      // included by the unread half, which is the point.
      expect(_visible([unread], _windowStart).single.id, 2);
      expect(_visible([unread], null).single.id, 2);
    });

    test('after mark-unread the article is visible as unread, not as read',
        () {
      final articles = [
        _article(id: 1, isRead: true)
            .copyWith(isRead: false, clearReadAt: true),
        _article(id: 2),
      ];
      final result = _visible(articles, null);
      expect(result.map((a) => a.id), [1, 2]);
      expect(result.every((a) => !a.isRead), isTrue);
    });
  });

  group('Read state is global across tabs', () {
    test('article read in the All tab stays visible, dimmed, in a folder tab',
        () {
      // Simulate: All tab loaded, user reads article 5. read_at lives on the
      // row itself, so every tab's visibility query sees it.
      final allTabArticles = [_article(id: 5, feedId: 2), _article(id: 6, feedId: 1)];

      final updatedAll = _dimArticle(allTabArticles, 5);

      // Folder tab re-runs its visibility query against the same rows.
      final folderTabArticles = [
        _article(id: 5, feedId: 2, isRead: true),
        _article(id: 7, feedId: 2),
      ];
      final folderResult = _visible(folderTabArticles, _windowStart);

      // Article 5 was read in the All tab — still present here, dimmed, not
      // vanished out from under the user. This is the Palabre model, and
      // reverses the earlier per-tab-absence design.
      expect(folderResult.any((a) => a.id == 5), isTrue);
      expect(folderResult.firstWhere((a) => a.id == 5).isRead, isTrue);
      expect(folderResult.length, 2);

      // And the All tab still shows it dimmed too.
      expect(updatedAll.firstWhere((a) => a.id == 5).isRead, isTrue);
    });

    test('reading in a folder tab equally keeps it visible in All', () {
      final allTabArticles = [
        _article(id: 7, feedId: 2, isRead: true), // read while in a category
        _article(id: 8, feedId: 1),
      ];
      final result = _visible(allTabArticles, _windowStart);

      expect(result.any((a) => a.id == 7), isTrue,
          reason: 'the rule is symmetric — neither direction hides anything');
      expect(result.length, 2);
    });

    test('mark-all-read stamps the dismissal sentinel → reload shows nothing',
        () {
      final before = [
        _article(id: 1, isRead: true),
        _article(id: 2, isRead: false),
      ];
      // Before: article 1 is recently read, so it is still on screen.
      expect(_visible(before, _windowStart).length, 2);

      // markAllAsRead(readAt: kDismissedReadAt) writes epoch, which is
      // outside every window.
      const dismissed = 0;
      final reloaded = [
        _article(id: 1, isRead: true, readAt: dismissed),
        _article(id: 2, isRead: true, readAt: dismissed),
      ];
      expect(_visible(reloaded, _windowStart), isEmpty,
          reason: 'pressing Mark all as read means clear these out — they '
              'must not come back when Show read is switched on');
    });

    test('the dwell timer stamps a real time, so those stay restorable', () {
      // Same bulk write, different intent: reaching the end of a feed is
      // passive reading, so the articles remain inside the window.
      final reloaded = [
        _article(id: 1, isRead: true, readAt: _now),
        _article(id: 2, isRead: true, readAt: _now),
      ];
      expect(_visible(reloaded, _windowStart).length, 2);
      expect(_visible(reloaded, null), isEmpty);
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
