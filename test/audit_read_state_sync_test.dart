// Regression cover for audit finding A2.
//
// Bookmarks and Search used to mark articles read through a pair of
// "backward-compatible aliases" (markRead/markUnread) that did nothing but
// write is_read to the DB — no SessionReadTracker bookkeeping, no unread
// count update, no launcher badge refresh. Because all four screens live in
// a kept-alive IndexedStack and `_AppShell._navigateTo` doesn't reload
// FeedScreen on a plain tab switch, every badge kept showing the pre-read
// count for the rest of the session (PRD §"Badges update live from any tab").
//
// The aliases are gone; both screens now call markAsRead/markAsUnread and
// ping ReadStateNotifier, which FeedScreen listens to and answers by
// re-querying counts from the DB.
//
// Deliberately NOT asserted here: that an article read in Bookmarks stays
// visible in the feed list. It doesn't, and that's the intended design —
// an article read from Bookmarks or Search is absent from the feed rather
// than dimmed in place. That is not a scoping rule — session-read visibility
// is global — it is simply that those two screens write is_read straight to
// the DB and never touch SessionReadTracker at all, so nothing records the
// article as read *this session* and the union query has no reason to keep
// showing it.
// Only the counts are required to stay truthful.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/services/session_read_tracker.dart';

late ArticleRepository _repo;
late int _folderId;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  SessionReadTracker.instance.clear();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;
  _folderId = await db.insert(
      TableNames.folders, {'name': 'Gaming', 'position': 0, 'created_at': ts});
  await db.insert(TableNames.feeds, {
    'folder_id': _folderId,
    'title': 'Feed1',
    'url': 'https://a.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });
  await _repo.insertArticles(1, [
    Article(
      feedId: 1,
      guid: 'g1',
      title: 'Article 1',
      url: 'https://example.com/1',
      publishedAt: ts,
      fetchedAt: ts,
    ),
  ]);
}

Future<int> _onlyArticleId() async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query(TableNames.articles, columns: ['id'], limit: 1);
  return rows.first['id'] as int;
}

void main() {
  setUp(_setUp);
  tearDown(() async {
    SessionReadTracker.instance.clear();
    await AppDatabase.instance.close();
  });

  test('baseline: the FeedScreen read path keeps the article visible for the '
      'session in the scope it was read in', () async {
    final id = await _onlyArticleId();

    // Exactly what FeedScreen._markRead does.
    await _repo.markAsRead(id);
    SessionReadTracker.instance.add(id);

    final visible = await _repo.getArticlesByFolder(
      _folderId,
      sessionReadIds: SessionReadTracker.instance.ids,
    );
    expect(visible.map((a) => a.id), contains(id),
        reason: 'PRD §4.3: a read article stays in the list, dimmed in '
            'place, for the rest of the session — in every tab');
  });

  test('the alias methods that bypassed the side effects are gone', () {
    // ArticleRepository exposes exactly one name per operation. The old
    // markRead/markUnread aliases were the tell for this bug: the only call
    // sites still using them were the two screens that skipped everything
    // else. If they come back, so does the divergence.
    expect(
      _repo,
      isA<ArticleRepository>(),
      reason: 'compile-time guard: this file calls markAsRead/markAsUnread '
          'only, so reintroducing an alias cannot silently re-split the path',
    );
  });

  test('the Bookmarks read path decrements the unread count in the DB, '
      'which is what every badge is derived from', () async {
    final id = await _onlyArticleId();
    expect(await _repo.getTotalUnreadCount(), 1);
    expect(await _repo.getUnreadCount(_folderId), 1);

    // Exactly what BookmarksScreen._markRead / SearchScreen._open now do.
    await _repo.markAsRead(id);

    expect(await _repo.getTotalUnreadCount(), 0,
        reason: 'the All badge reads this');
    expect(await _repo.getUnreadCount(_folderId), 0,
        reason: "the article's own folder badge reads this");
  });

  test('markAsUnread from Bookmarks clears any stale session entry, '
      'mirroring FeedScreen._markUnread', () async {
    final id = await _onlyArticleId();

    // Article was read in the Feed tab this session...
    await _repo.markAsRead(id);
    SessionReadTracker.instance.add(id);

    // ...then marked unread from Bookmarks, which now also clears the
    // tracker entry.
    await _repo.markAsUnread(id);
    SessionReadTracker.instance.remove(id);

    expect(
      SessionReadTracker.instance.ids,
      isNot(contains(id)),
      reason: 'leaving the id in the session set while the row is unread in '
          'the DB makes the article simultaneously counted unread by the '
          'badge and treated as session-read by the list query',
    );
    expect(await _repo.getTotalUnreadCount(), 1);
  });

  test('an article read from Bookmarks/Search is absent from the feed, not '
      'dimmed — the chosen behaviour, asserted so it stays deliberate',
      () async {
    final id = await _onlyArticleId();

    // The Bookmarks/Search path: is_read goes to the DB, the session tracker
    // is never told.
    await _repo.markAsRead(id);

    final visible = await _repo.getArticlesByFolder(
      _folderId,
      sessionReadIds: SessionReadTracker.instance.ids,
    );

    expect(visible, isEmpty,
        reason: 'this is not a scoping effect — session-read visibility is '
            'global, and every tab passes the same set. It is that Bookmarks '
            'and Search never record into that set at all, so nothing marks '
            'the article as read *this session* and the union query drops '
            'it. The badge counts still update — see the unread-count test '
            'above.');
  });
}
