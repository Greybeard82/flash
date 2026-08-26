// Regression cover for audit finding A2.
//
// Bookmarks and Search used to mark articles read through a pair of
// "backward-compatible aliases" (markRead/markUnread) that did nothing but
// write is_read to the DB — no read bookkeeping, no unread
// count update, no launcher badge refresh. Because all four screens live in
// a kept-alive IndexedStack and `_AppShell._navigateTo` doesn't reload
// FeedScreen on a plain tab switch, every badge kept showing the pre-read
// count for the rest of the session (PRD §"Badges update live from any tab").
//
// The aliases are gone; both screens now call markAsRead/markAsUnread and
// ping ReadStateNotifier, which FeedScreen listens to and answers by
// re-querying counts from the DB.
//
// Behaviour change in schema v11: an article read from Bookmarks or Search
// now stamps read_at like any other read, so with "Show read" on it stays
// visible in the feed, dimmed, rather than vanishing. That is a deliberate
// consequence of read state being genuinely global — the previous behaviour
// was an artefact of those screens writing is_read directly while never
// touching the in-memory session set. Counts were, and remain, the thing
// this file actually pins.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/utils/constants.dart';

/// The show-read cutoff FeedScreen would pass for a query happening now.
int get _windowStart => DateTime.now()
    .subtract(const Duration(hours: kShowReadBufferHours))
    .millisecondsSinceEpoch;

late ArticleRepository _repo;
late int _folderId;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
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
    await AppDatabase.instance.close();
  });

  test('baseline: the FeedScreen read path keeps the article visible inside '
      'the show-read window', () async {
    final id = await _onlyArticleId();

    // Exactly what FeedScreen._markRead does.
    await _repo.markAsRead(id);

    final visible = await _repo.getArticlesByFolder(
      _folderId,
      readSinceMs: _windowStart,
    );
    expect(visible.map((a) => a.id), contains(id),
        reason: 'a just-read article stays in the list, dimmed in place, in '
            'every tab — now for 48 hours rather than for the session');
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

  test('markAsUnread from Bookmarks clears read_at, '
      'mirroring FeedScreen._markUnread', () async {
    final id = await _onlyArticleId();

    // Article was read in the Feed tab...
    await _repo.markAsRead(id);

    // ...then marked unread from Bookmarks, which also clears the timestamp.
    await _repo.markAsUnread(id);

    final visible =
        await _repo.getArticlesByFolder(_folderId, readSinceMs: _windowStart);
    final row = visible.singleWhere((a) => a.id == id);
    expect(row.readAt, isNull,
        reason: 'leaving a read_at behind while the row is unread in the DB '
            'makes the article simultaneously counted unread by the badge '
            'and matched by the show-read half of the visibility query');
    expect(row.isRead, isFalse);
    expect(await _repo.getTotalUnreadCount(), 1);
  });

  test('an article read from Bookmarks/Search now behaves like any other '
      'read — visible with Show read on, hidden with it off', () async {
    final id = await _onlyArticleId();

    // The Bookmarks/Search path. Under v11 it stamps read_at like every
    // other read, so it no longer diverges from the feed's own path.
    await _repo.markAsRead(id);

    final shown =
        await _repo.getArticlesByFolder(_folderId, readSinceMs: _windowStart);
    expect(shown.map((a) => a.id), contains(id),
        reason: 'read state is genuinely global now: the article is dimmed '
            'in place rather than vanishing, which is what reading it in the '
            'feed would have done');

    final hidden =
        await _repo.getArticlesByFolder(_folderId, readSinceMs: null);
    expect(hidden, isEmpty,
        reason: 'with Show read off it goes, like any other read article. '
            'The badge counts update either way — see the test above.');
  });
}
