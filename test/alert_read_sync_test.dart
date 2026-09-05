// Read-state sync between `articles` and `alert_matches`.
//
// An alert match is a snapshot, not a pointer. It carries its own title, url,
// thumbnail and feed name because the article row it came from is disposable:
// retireAllRead deletes every read, unsaved article, runCleanup deletes
// anything aged past the window, and alert_matches.feed_id deliberately has no
// foreign key so a snapshot outlives its feed too. By the time the user opens
// the Alerts tab the articles row behind an entry may simply not be there.
//
// That is the whole reason `alert_matches.is_read` is a column instead of
// something read through a join on (feed_id, guid): often there is nothing to
// join to. The old design had no such column — the match WAS a column on
// `articles` — and every read-flush destroyed it, which is why it needed a
// bolted-on `is_saved = 1` auto-bookmark to survive at all.
//
// The price of owning the flag is that it has to be mirrored by hand. Every
// place that changes read state moves both sides, keyed on (feed_id, guid) —
// the one identity the two tables still share once the article id is gone.
// This file pins that mirroring in both directions, and pins the single
// deliberate hole in it: mark-read-on-scroll moves `articles` ONLY. The Alerts
// tab is a review surface, and dimming an entry because its article happened
// to scroll past in another tab would destroy the only signal separating
// "seen" from "not yet seen".
//
// Where a row of the sync table describes UI wiring, the test exercises the
// repository calls the widget composes — "tap in the Alerts tab" is
// AlertMatchRepository.setRead plus ArticleRepository.markAsRead when the row
// still exists. The widget wiring itself is covered by the manual QA pass, not
// here.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/alert_entry.dart';
import 'package:flash/models/alert_match.dart';
import 'package:flash/repositories/alert_match_repository.dart';
import 'package:flash/repositories/article_repository.dart';

const int _now = 1750000000000;

/// A feed_id no feeds row has. Legal in alert_matches precisely because that
/// column carries no foreign key — a snapshot has to survive its feed being
/// deleted, and once the feed is gone the snapshot belongs to no folder.
const int _deletedFeedId = 999;

late Database _db;
late ArticleRepository _articles;
late AlertMatchRepository _alerts;
late int _gamingFolderId;
late int _newsFolderId;
late int _feedA;
late int _feedB;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _db = await AppDatabase.instance.database;
  _articles = ArticleRepository();
  _alerts = AlertMatchRepository();

  _gamingFolderId = await _db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _newsFolderId = await _db.insert(TableNames.folders,
      {'name': 'News', 'position': 1, 'created_at': _now});

  _feedA = await _db.insert(TableNames.feeds, {
    'folder_id': _gamingFolderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
  _feedB = await _db.insert(TableNames.feeds, {
    'folder_id': _newsFolderId,
    'title': 'Feed B',
    'url': 'https://b.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

/// Seeds an articles row and returns its id.
///
/// `published_at` defaults to [_now], which is fixed in the past and only gets
/// further away — so a read article seeded this way is always eligible for
/// runCleanup, and no test has to reason about today's date.
///
/// Deliberately writes no alert column: the match lives in its own table now,
/// and nothing reads or writes articles.matched_alert_keyword.
Future<int> _insertArticle(
  int feedId,
  String guid, {
  bool read = false,
  bool saved = false,
  int publishedAt = _now,
}) {
  return _db.insert(TableNames.articles, {
    'feed_id': feedId,
    'guid': guid,
    'title': 'Article $guid',
    'url': 'https://example.com/$guid',
    'description': 'Body of $guid',
    'published_at': publishedAt,
    'fetched_at': _now,
    'is_read': read ? 1 : 0,
    'is_blocked': 0,
    'is_saved': saved ? 1 : 0,
  });
}

AlertMatch _match(
  int feedId,
  String guid,
  String keyword, {
  int? folderId,
  int matchedAt = _now,
}) {
  return AlertMatch(
    feedId: feedId,
    guid: guid,
    keyword: keyword,
    title: 'Article $guid',
    url: 'https://example.com/$guid',
    description: 'Body of $guid',
    feedTitle: 'Feed $feedId',
    folderId: folderId,
    publishedAt: _now,
    matchedAt: matchedAt,
  );
}

/// Written through the repository so these tests seed matches by the same path
/// the fetch pass uses.
Future<void> _seedMatches(List<AlertMatch> matches) async {
  await _alerts.insertMatches(matches);
}

/// Raw `is_read` of every alert_matches row for one (feed_id, guid), keyword
/// order. Read straight from the table rather than through getEntries, because
/// the grouping collapses exactly the disagreement these tests are looking for.
Future<List<int>> _readFlags(int feedId, String guid) async {
  final rows = await _db.query(
    TableNames.alertMatches,
    columns: ['is_read'],
    where: 'feed_id = ? AND guid = ?',
    whereArgs: [feedId, guid],
    orderBy: 'keyword ASC',
  );
  return [for (final r in rows) r['is_read'] as int];
}

/// Raw `is_read` of every alert_matches row in the table, insertion order.
Future<List<int>> _allReadFlags() async {
  final rows = await _db
      .query(TableNames.alertMatches, columns: ['is_read'], orderBy: 'id ASC');
  return [for (final r in rows) r['is_read'] as int];
}

/// The articles id behind a snapshot, or null once the row has been retired or
/// cleaned up. This lookup is what the Alerts tab does before it tries to
/// mirror a read back onto `articles`.
Future<int?> _articleIdFor(int feedId, String guid) async {
  final rows = await _db.query(TableNames.articles,
      columns: ['id'],
      where: 'feed_id = ? AND guid = ?',
      whereArgs: [feedId, guid],
      limit: 1);
  return rows.isEmpty ? null : rows.first['id'] as int;
}

/// `is_read` of an articles row, or null when the row is gone.
Future<int?> _articleReadFlag(int feedId, String guid) async {
  final rows = await _db.query(TableNames.articles,
      columns: ['is_read'],
      where: 'feed_id = ? AND guid = ?',
      whereArgs: [feedId, guid],
      limit: 1);
  return rows.isEmpty ? null : rows.first['is_read'] as int;
}

Future<AlertEntry> _entry(int feedId, String guid) async {
  final entries = await _alerts.getEntries();
  final hits = entries.where((e) => e.feedId == feedId && e.guid == guid);
  expect(hits, isNotEmpty,
      reason: 'getEntries dropped the ($feedId, $guid) entry entirely, so '
          'nothing below is measuring read state');
  return hits.first;
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  // ── Tap in the Alerts tab ────────────────────────────────────────────────

  test(
      'tapping an entry in the Alerts tab marks every keyword row for that '
      '(feed_id, guid)', () async {
    await _insertArticle(_feedA, 'g1');
    await _seedMatches([
      _match(_feedA, 'g1', 'nintendo', folderId: _gamingFolderId),
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);

    // What the tap handler composes: the snapshot always, the articles row
    // only if it is still there.
    await _alerts.setRead(_feedA, 'g1', isRead: true);
    final articleId = await _articleIdFor(_feedA, 'g1');
    await _articles.markAsRead(articleId!);

    expect(await _readFlags(_feedA, 'g1'), [1, 1],
        reason: 'one article is one card however many keywords it hit, so a '
            'keyword row left unread would make the entry pop back to unread '
            'the next time the Alerts tab regrouped it');
    expect((await _entry(_feedA, 'g1')).isRead, isTrue);
    expect(await _articleReadFlag(_feedA, 'g1'), 1,
        reason: 'reading an article in Alerts must also read it everywhere '
            'else, or the same headline stays bold in the All tab');
  });

  test('an entry whose articles row is gone can still be marked read',
      () async {
    await _insertArticle(_feedA, 'g1', read: true);
    await _seedMatches([
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);
    await _articles.retireAllRead();
    expect(await _articleIdFor(_feedA, 'g1'), isNull,
        reason: 'fixture check: the rest of this test is only meaningful once '
            'the articles row is actually gone');

    await expectLater(_alerts.setRead(_feedA, 'g1', isRead: true), completes,
        reason: 'this is the whole reason alert_matches owns an is_read '
            'column: the entry is still on screen after its article was '
            'retired, and tapping it must not throw');

    expect(await _readFlags(_feedA, 'g1'), [1]);
    expect((await _entry(_feedA, 'g1')).isRead, isTrue);
  });

  // ── Tap in the All / category tab ────────────────────────────────────────

  test(
      'marking an article read from the All tab marks its alert match and '
      'leaves an unrelated entry unread', () async {
    await _insertArticle(_feedA, 'g1');
    await _insertArticle(_feedB, 'g2');
    await _seedMatches([
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
      _match(_feedB, 'g2', 'zelda', folderId: _newsFolderId),
    ]);

    final id = (await _articleIdFor(_feedA, 'g1'))!;
    await _articles.markAsRead(id);
    await _alerts.setRead(_feedA, 'g1', isRead: true);

    expect(await _readFlags(_feedA, 'g1'), [1],
        reason: 'an article read in the ordinary feed must not still be '
            'waiting, bold, in the Alerts tab');
    expect(await _readFlags(_feedB, 'g2'), [0],
        reason: 'the sync is keyed on (feed_id, guid), not on the keyword — '
            'reading one hit must not silently clear every other article '
            'carrying the same alert word');
    expect(await _articleReadFlag(_feedB, 'g2'), 0);
  });

  test(
      'marking read or unread when no alert match exists is a harmless no-op, '
      'not a throw', () async {
    await _insertArticle(_feedA, 'plain');
    await _seedMatches([
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);

    final id = (await _articleIdFor(_feedA, 'plain'))!;
    await _articles.markAsRead(id);

    await expectLater(_alerts.setRead(_feedA, 'plain', isRead: true), completes,
        reason: 'every read in the app calls through here and almost none of '
            'them matched an alert; a throw on the empty case would break '
            'marking read in the ordinary feed');
    await expectLater(
        _alerts.setRead(_feedA, 'plain', isRead: false), completes);

    expect(await _readFlags(_feedA, 'plain'), isEmpty,
        reason: 'a no-op must not invent a snapshot row for an article no '
            'keyword ever matched — that row would show up as an entry in the '
            'Alerts tab');
    expect(await _readFlags(_feedA, 'g1'), [0],
        reason: 'the unrelated real match must be untouched by the no-op');
  });

  // ── Swipe mark-unread in Bookmarks ───────────────────────────────────────

  test('un-reading restores unread on every keyword row and on the entry',
      () async {
    await _insertArticle(_feedA, 'g1', read: true, saved: true);
    await _seedMatches([
      _match(_feedA, 'g1', 'nintendo', folderId: _gamingFolderId),
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);
    await _alerts.setRead(_feedA, 'g1', isRead: true);

    // The Bookmarks swipe: articles row back to unread, snapshot with it.
    final id = (await _articleIdFor(_feedA, 'g1'))!;
    await _articles.markAsUnread(id);
    await _alerts.setRead(_feedA, 'g1', isRead: false);

    expect(await _readFlags(_feedA, 'g1'), [0, 0],
        reason: 'the mirror has to run in both directions, and on every '
            'keyword row — one row left at 1 keeps the entry dimmed for ever, '
            'because an entry counts as read only when all of its rows are');
    expect((await _entry(_feedA, 'g1')).isRead, isFalse);
    expect(await _articleReadFlag(_feedA, 'g1'), 0);
  });

  // ── Mark-all-read ────────────────────────────────────────────────────────

  test(
      'mark-all-read on the All tab marks every match, across keywords and '
      'folders', () async {
    await _insertArticle(_feedA, 'g1');
    await _insertArticle(_feedB, 'g2');
    await _seedMatches([
      _match(_feedA, 'g1', 'nintendo', folderId: _gamingFolderId),
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
      _match(_feedB, 'g2', 'election', folderId: _newsFolderId),
      _match(_deletedFeedId, 'gone-1', 'zelda'),
    ]);

    await _articles.markAllAsRead();
    await _alerts.setAllRead();

    expect(await _allReadFlags(), [1, 1, 1, 1],
        reason: 'All means all: a match left unread here reappears as an '
            'entry the user cannot dismiss, right after they cleared '
            'everything');
    expect(await _articleReadFlag(_feedA, 'g1'), 1);
    expect(await _articleReadFlag(_feedB, 'g2'), 1);
  });

  test('mark-all-read on a category tab marks only that folder of matches',
      () async {
    await _insertArticle(_feedA, 'g1');
    await _insertArticle(_feedB, 'g2');
    await _seedMatches([
      _match(_feedA, 'g1', 'nintendo', folderId: _gamingFolderId),
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
      _match(_feedB, 'g2', 'election', folderId: _newsFolderId),
      _match(_deletedFeedId, 'gone-1', 'zelda'),
    ]);

    await _articles.markAllAsReadByFolder(_gamingFolderId);
    await _alerts.setReadByFolder(_gamingFolderId);

    expect(await _readFlags(_feedA, 'g1'), [1, 1]);
    expect(await _readFlags(_feedB, 'g2'), [0],
        reason: 'clearing one category must not clear another, or the badge '
            'on the untouched tab drops to zero without the user reading a '
            'thing');
    expect(await _readFlags(_deletedFeedId, 'gone-1'), [0],
        reason: 'a snapshot with a null folder_id belongs to no category tab, '
            'so no category mark-all-read can claim it; only the Alerts tab '
            'clears that one');
    expect(await _articleReadFlag(_feedB, 'g2'), 0);
  });

  test(
      'mark-all-read on the Alerts tab marks every snapshot but only the '
      'articles that actually matched', () async {
    await _insertArticle(_feedA, 'g1');
    await _insertArticle(_feedA, 'plain');
    await _seedMatches([
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
      _match(_deletedFeedId, 'gone-1', 'zelda'),
    ]);

    // What the Alerts tab composes: clear the whole snapshot table, then
    // mirror onto whichever articles rows still exist.
    await _alerts.setAllRead();
    for (final entry in await _alerts.getEntries()) {
      final id = await _articleIdFor(entry.feedId, entry.guid);
      if (id != null) await _articles.markAsRead(id);
    }

    expect(await _allReadFlags(), [1, 1],
        reason: 'mark-all-read on Alerts clears every entry the tab can show, '
            'including one whose feed has since been deleted');
    expect(await _articleReadFlag(_feedA, 'g1'), 1);
    expect(await _articleReadFlag(_feedA, 'plain'), 0,
        reason: 'the Alerts tab is a filtered slice, so its mark-all-read '
            'must not read the rest of the library the way the All tab does');
  });

  // ── Mark-read-on-scroll: the deliberate exception ────────────────────────

  test('mark-read-on-scroll does not dim the Alerts tab', () async {
    final id = await _insertArticle(_feedA, 'g1');
    await _seedMatches([
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);

    // markManyRead is the bulk path the scroll pass batches into.
    await _articles.markManyRead([id]);

    expect(await _articleReadFlag(_feedA, 'g1'), 1,
        reason: 'fixture check: the scroll pass really did read the article');
    expect(await _readFlags(_feedA, 'g1'), [0],
        reason: 'this exclusion is deliberate, not an oversight. The Alerts '
            'tab is a review surface, and auto-dimming an entry because the '
            'article happened to scroll past in another tab destroys the only '
            'signal separating "seen" from "not yet seen" — the user would '
            'never find out that a keyword had fired');
    expect((await _entry(_feedA, 'g1')).isRead, isFalse);
  });

  // ── Retirement and cleanup leave the snapshot alone ──────────────────────

  test('retireAllRead deletes the article and leaves the snapshot intact',
      () async {
    await _insertArticle(_feedA, 'g1', read: true);
    await _seedMatches([
      _match(_feedA, 'g1', 'nintendo', folderId: _gamingFolderId),
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);
    await _alerts.setRead(_feedA, 'g1', isRead: true);

    final retired = await _articles.retireAllRead();

    expect(retired, 1);
    expect(await _articleIdFor(_feedA, 'g1'), isNull);
    expect(await _readFlags(_feedA, 'g1'), [1, 1],
        reason: 'this is the exact failure the rework exists to fix: the '
            'match used to be a column on the article, so reading it and '
            'flushing destroyed the alert. The snapshot must outlive the row, '
            'read flag included, with no auto-bookmark holding it in place');
    expect(await _alerts.getEntries(), hasLength(1),
        reason: 'the entry stays listed in the Alerts tab after its article '
            'is retired — that is what makes it a record rather than a view');
  });

  test('runCleanup deletes the article and leaves the snapshot intact',
      () async {
    await _insertArticle(_feedA, 'g1', read: true);
    await _seedMatches([
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);

    await _articles.runCleanup();

    expect(await _articleIdFor(_feedA, 'g1'), isNull,
        reason: 'fixture check: published_at is far outside every cleanup '
            'window, so the row should have been swept');
    expect(await _readFlags(_feedA, 'g1'), [0],
        reason: 'cleanup must not reach into alert_matches at all — neither '
            'to delete the snapshot nor to flip its read flag on the way past');
    expect(await _alerts.getEntries(), hasLength(1));
  });

  // ── Grouping consistency guard ───────────────────────────────────────────

  test('an entry whose keyword rows disagree reports isRead false', () async {
    await _insertArticle(_feedA, 'g1');
    await _seedMatches([
      _match(_feedA, 'g1', 'nintendo', folderId: _gamingFolderId),
      _match(_feedA, 'g1', 'zelda', folderId: _gamingFolderId),
    ]);

    // Written straight to the table: every sync path moves all rows for a
    // pair together, so this state is unreachable through the repository.
    await _db.update(TableNames.alertMatches, {'is_read': 1},
        where: 'feed_id = ? AND guid = ? AND keyword = ?',
        whereArgs: [_feedA, 'g1', 'zelda']);

    final entry = await _entry(_feedA, 'g1');
    expect(entry.keywords, ['nintendo', 'zelda']);
    expect(entry.isRead, isFalse,
        reason: 'consistency guard, not a real branch: the sync should never '
            'produce a split group, but if a partial write ever does, the '
            'grouping must survive it and err toward showing the entry rather '
            'than hiding an alert the user has not seen');
  });
}
