// An alert match is a permanent snapshot, and no automatic process may ever
// delete one.
//
// This is the single most important invariant of the alerts rework, and the
// old design broke it structurally rather than accidentally. The match lived
// in a column on `articles` (`matched_alert_keyword`), so it had no existence
// apart from the article row: `retireAllRead` deletes read rows,
// `runCleanup` deletes rows that have aged out, a feed deletion cascades every
// row it owns, and the tombstone system exists precisely to keep a deleted
// guid deleted. Every one of those destroyed the alert as a side effect of
// doing its own job correctly — the user's "zelda" alert vanished because
// they had scrolled past the article.
//
// The only thing that kept a match alive was a bolted-on `is_saved = 1`
// auto-bookmark applied at match time. That is not persistence, it is a
// second bug: it filled Bookmarks with entries indistinguishable from
// deliberate ones, and it made an alert silently deletable by un-bookmarking
// it — the article row went back to being ordinary and the next cleanup pass
// took the alert with it.
//
// `alert_matches` is a separate table carrying its own denormalised copy of
// the title, url, feed title and favicon, with deliberately no foreign key on
// `feed_id`. Every test below destroys articles through a real
// ArticleRepository path, or deletes the feed outright, and then asserts the
// snapshot is still there and still renders — several of them with zero
// matching rows left in `articles` at all.
//
// The seeded snapshot deliberately carries a feed title and favicon path that
// differ from the live `feeds` row. A `getEntries` that quietly joined back to
// `feeds` would still look correct against identical values, and would then
// return nothing at all the day the feed is deleted.
//
// If a test in this file fails, routine housekeeping is silently destroying
// alerts and nothing else in the pass matters.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/alert_entry.dart';
import 'package:flash/models/alert_match.dart';
import 'package:flash/models/article.dart';
import 'package:flash/repositories/alert_match_repository.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/utils/constants.dart';

const int _now = 1750000000000;

/// The live feed row's identity.
const String _liveFeedTitle = 'Feed A';
const String _liveFeedFavicon = '/tmp/feed-a.ico';

/// The identity frozen into the snapshot at match time. Different on purpose —
/// see the header note. Feeds get renamed and re-fetch their favicon, and the
/// Alerts tab must keep rendering after the feed is gone entirely.
const String _snapshotFeedTitle = 'Feed A (as matched)';
const String _snapshotFeedFavicon = '/tmp/snapshot-feed-a.ico';

late Database _db;
late ArticleRepository _articles;
late AlertMatchRepository _alerts;
late int _folderId;
late int _feedId;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _articles = ArticleRepository();
  _alerts = AlertMatchRepository();
  _db = await AppDatabase.instance.database;

  _folderId = await _db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _feedId = await _db.insert(TableNames.feeds, {
    'folder_id': _folderId,
    'title': _liveFeedTitle,
    'url': 'https://a.example/feed',
    'favicon_path': _liveFeedFavicon,
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

int _daysAgoMs(int days) =>
    DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

/// An article row, seeded explicitly so read/saved/age are all controllable.
///
/// `matched_alert_keyword` is deliberately never written: after this rework
/// nothing reads or writes that column, and a test that still set it would be
/// asserting against the design it replaced.
Future<int> _insertArticle(
  String guid, {
  bool read = false,
  bool saved = false,
  int? publishedAt,
}) {
  return _db.insert(TableNames.articles, {
    'feed_id': _feedId,
    'guid': guid,
    'title': 'Article $guid',
    'url': 'https://a.example/$guid',
    'description': 'Body $guid',
    'thumbnail_url': 'https://a.example/$guid.png',
    'thumbnail_path': '/tmp/$guid.png',
    'published_at': publishedAt ?? _now,
    'fetched_at': _now,
    'is_read': read ? 1 : 0,
    'is_blocked': 0,
    'is_saved': saved ? 1 : 0,
  });
}

AlertMatch _match(
  String guid,
  String keyword, {
  int? publishedAt,
  int? matchedAt,
}) {
  return AlertMatch(
    feedId: _feedId,
    guid: guid,
    keyword: keyword,
    title: 'Article $guid',
    url: 'https://a.example/$guid',
    description: 'Body $guid',
    thumbnailUrl: 'https://a.example/$guid.png',
    thumbnailPath: '/tmp/$guid.png',
    feedTitle: _snapshotFeedTitle,
    feedFaviconPath: _snapshotFeedFavicon,
    folderId: _folderId,
    publishedAt: publishedAt ?? _now,
    matchedAt: matchedAt ?? _now,
  );
}

/// An article and its alert snapshot, the pairing every test here starts from.
/// The article is **not** saved: the whole point of the rework is that a match
/// survives without the auto-bookmark propping it up.
Future<int> _seedPair(
  String guid,
  String keyword, {
  bool read = false,
  int? publishedAt,
}) async {
  final id = await _insertArticle(guid, read: read, publishedAt: publishedAt);
  await _alerts.insertMatches([_match(guid, keyword, publishedAt: publishedAt)]);
  return id;
}

Future<int> _articleCount() async {
  final r =
      await _db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.articles}');
  return r.first['c'] as int;
}

Future<int> _alertRowCount() async {
  final r =
      await _db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.alertMatches}');
  return r.first['c'] as int;
}

Future<int> _tombstoneCountFor(String guid) async {
  final r = await _db.rawQuery(
    'SELECT COUNT(*) AS c FROM ${TableNames.deletedArticles} '
    'WHERE feed_id = ? AND guid = ?',
    [_feedId, guid],
  );
  return r.first['c'] as int;
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  test('retiring the read article leaves the alert snapshot behind, and the '
      'Alerts tab renders it with no article row to render from', () async {
    final id = await _seedPair('a1', 'zelda');
    await _articles.markAsRead(id);

    final retired = await _articles.retireAllRead();

    expect(retired, 1, reason: 'the article was read and unsaved, so '
        'retirement must still take it — the fix is not to exempt it');
    expect(await _articleCount(), 0,
        reason: 'the Alerts tab has to render from zero matching rows in '
            '`articles`; if the article survives, this file proves nothing '
            'about whether the snapshot is independent of it');

    expect(await _alertRowCount(), 1,
        reason: 'retirement destroyed the old matched_alert_keyword column '
            'along with the row it lived on — the whole reason alerts got '
            'their own table');

    final List<AlertEntry> entries = await _alerts.getEntries();
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.guid, 'a1');
    expect(entry.keywords, ['zelda']);
    expect(entry.title, 'Article a1',
        reason: 'the card has no article row left to read a title from');
    expect(entry.url, 'https://a.example/a1',
        reason: 'without the url the entry cannot be opened, which makes the '
            'alert useless even though it is still listed');
    expect(entry.feedTitle, _snapshotFeedTitle,
        reason: 'the feed identity must come from the snapshot columns, not a '
            'join — a join would silently pass here and fail once the feed is '
            'deleted');
    expect(entry.feedFaviconPath, _snapshotFeedFavicon);
  });

  test('cleanup deleting an unread, unsaved, ancient article leaves the alert '
      'snapshot behind', () async {
    await _seedPair('a2', 'zelda', publishedAt: _daysAgoMs(30));

    final deleted = await _articles.runCleanup();

    expect(deleted, 1,
        reason: 'an unread unsaved article this old is past every window the '
            'user can select, so cleanup is right to take it');
    expect(await _articleCount(), 0);

    final entries = await _alerts.getEntries();
    expect(entries, hasLength(1),
        reason: 'in the old design this article was only spared because the '
            'match had set is_saved = 1; nothing props the snapshot up now '
            'and nothing needs to');
    expect(entries.single.title, 'Article a2');
  });

  test('deleting the feed cascades the article away and the snapshot still '
      'reports the feed it was matched in', () async {
    await _seedPair('a3', 'zelda');

    // Production runs with enforcement on (onConfigure turns it off only for
    // the duration of a migration, onOpen turns it back on). Stated explicitly
    // so this test is about alert_matches surviving the cascade, not about
    // whether the cascade happened at all.
    await _db.execute('PRAGMA foreign_keys = ON');
    await _db.delete(TableNames.feeds, where: 'id = ?', whereArgs: [_feedId]);

    expect(await _articleCount(), 0,
        reason: 'articles.feed_id cascades on feed deletion — the precondition '
            'this test exists to survive');

    expect(await _alertRowCount(), 1,
        reason: 'alert_matches.feed_id deliberately carries no foreign key: a '
            'snapshot has to outlive its feed');

    final entries = await _alerts.getEntries();
    expect(entries, hasLength(1));
    expect(entries.single.feedTitle, _snapshotFeedTitle,
        reason: 'there is no feeds row left to join to, so the denormalised '
            'copy is the only thing that can label this card');
    expect(entries.single.feedFaviconPath, _snapshotFeedFavicon);
  });

  test('retireAllRead reports its normal deleted count and does not remove a '
      'single alert row, however many there are', () async {
    // Eight distinct articles, ten alert rows: two of them matched two
    // keywords each, which is exactly what first-match-wins used to lose.
    const guids = ['b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'b8'];
    for (final guid in guids) {
      await _insertArticle(guid, read: true);
    }
    await _alerts.insertMatches([
      for (final guid in guids) _match(guid, 'zelda'),
      _match('b1', 'nintendo'),
      _match('b2', 'nintendo'),
    ]);
    expect(await _alertRowCount(), 10, reason: 'fixture sanity check');

    final retired = await _articles.retireAllRead();

    expect(retired, guids.length,
        reason: 'retirement must keep returning the number of articles it '
            'deleted — the count drives the snackbar and the refresh, and '
            'alert rows are not articles');
    expect(await _articleCount(), 0);
    expect(await _alertRowCount(), 10,
        reason: 'every keyword row survives, including the second keyword on '
            'an article that matched twice');
    expect(await _alerts.totalEntryCount(), guids.length,
        reason: 'ten rows still collapse to eight cards — a partial deletion '
            'would show up here as a card that lost one of its keywords');
  });

  test('cleanup\'s unread-retention branch fires on kUnreadRetentionDays and '
      'still leaves both snapshots alone', () async {
    // Pinned to the constant rather than a literal: the branch exists so an
    // unread article the widest slider setting can no longer reach stops
    // inflating the badge, and the alert must survive the day that boundary
    // moves.
    await _seedPair('c1', 'zelda',
        publishedAt: _daysAgoMs(kUnreadRetentionDays + 2));
    await _seedPair('c2', 'zelda',
        publishedAt: _daysAgoMs(kUnreadRetentionDays - 2));

    final deleted = await _articles.runCleanup();

    expect(deleted, 1,
        reason: 'only the article past kUnreadRetentionDays is unreachable by '
            'any slider setting');
    expect(await _articleCount(), 1);
    expect(await _alertRowCount(), 2,
        reason: 'the retention window governs what the feed list can still '
            'reach, and says nothing about what the user asked to be alerted '
            'about');

    final entries = await _alerts.getEntries();
    expect(entries.map((e) => e.guid).toSet(), {'c1', 'c2'});
  });

  test('a tombstone records the article\'s deletion and has no hold over the '
      'alert row for the same guid', () async {
    final id = await _seedPair('d1', 'zelda');
    await _articles.markAsRead(id);

    await _articles.retireAllRead();

    expect(await _tombstoneCountFor('d1'), 1,
        reason: 'retirement must still tombstone the guid, or the next fetch '
            'resurrects the article as unread');
    expect(await _alertRowCount(), 1,
        reason: 'a tombstone says "do not re-insert this article"; it is not '
            'a statement about the alert, and the two must not share a '
            'lifetime');

    final entries = await _alerts.getEntries();
    expect(entries, hasLength(1));
    expect(entries.single.keywords, ['zelda']);
  });

  test('clearAllTombstones leaves alert_matches untouched', () async {
    final id = await _seedPair('e1', 'zelda');
    await _articles.markAsRead(id);
    await _articles.retireAllRead();

    final cleared = await _articles.clearAllTombstones();

    expect(cleared, 1);
    expect(await _articles.tombstoneCount(), 0);
    expect(await _alertRowCount(), 1,
        reason: 'the one route back from retirement touches the tombstone '
            'table only — it must not take alerts with it, in either '
            'direction');
    expect((await _alerts.getEntries()).single.guid, 'e1');
  });

  test('pruneTombstones leaves alert_matches untouched', () async {
    await _seedPair('f1', 'zelda');
    await _db.insert(TableNames.deletedArticles, {
      'feed_id': _feedId,
      'guid': 'f1',
      'deleted_at': _daysAgoMs(kTombstoneDayLimit + 1),
    });

    final pruned = await _articles.pruneTombstones();

    expect(pruned, 1, reason: 'fixture sanity check: the tombstone really was '
        'old enough to prune');
    expect(await _alertRowCount(), 1,
        reason: 'pruning runs on every cold start and background refresh, so '
            'anything it can reach is effectively deleted on a timer');
    expect((await _alerts.getEntries()).single.guid, 'f1');
  });

  test('a 2-day display-age filter does not hide a 10-day-old alert entry',
      () async {
    final published = _daysAgoMs(10);
    await _seedPair('g1', 'zelda', publishedAt: published);

    // The Alerts tab deliberately does not run feed_screen._applyDisplayFilters
    // — the Filter bubble's Article age slider is about how far back the feed
    // list reaches, not about how long an alert the user asked for stays
    // listed. This pins that the data layer imposes no cutoff of its own, so
    // the tab's choice is the only thing that decides.
    expect(published, lessThan(displayCutoffMs(2)),
        reason: 'fixture sanity check: this entry is old enough that a 2-day '
            'display filter would drop it');

    final entries = await _alerts.getEntries();

    expect(entries.map((e) => e.guid), ['g1'],
        reason: 'an age cutoff inside getEntries would make alerts expire '
            'silently, with nothing in the UI to explain where they went');
    expect(entries.single.publishedAt, published);
  });

  test('the per-feed article cap does not apply to alert entries', () async {
    const extra = 5;
    final guids = [for (var i = 0; i < kFetchArticleLimit + extra; i++) 'h$i'];
    // All on one feed: the cap the feed list applies is per feed, so a single
    // feed is the only shape that can trip it.
    await _alerts.insertMatches([for (final guid in guids) _match(guid, 'zelda')]);

    final entries = await _alerts.getEntries();

    expect(entries, hasLength(kFetchArticleLimit + extra),
        reason: 'the cap governs how many articles a feed may store and show; '
            'silently dropping the oldest alerts past 100 would lose exactly '
            'the ones the user has not caught up on');
    expect(entries.map((e) => e.guid).toSet(), guids.toSet());
    expect(await _alerts.totalEntryCount(), kFetchArticleLimit + extra);
  });

  test('inserting articles never writes an alert_matches row on its own',
      () async {
    await _db.insert(TableNames.keywordAlerts,
        {'keyword': 'zelda', 'whole_word': 0, 'created_at': _now});

    await _articles.insertArticles(_feedId, [
      Article(
        feedId: _feedId,
        guid: 'i1',
        title: 'Nintendo teases new Zelda game',
        url: 'https://a.example/i1',
        publishedAt: _now,
        fetchedAt: _now,
      ),
    ]);

    expect(await _articleCount(), 1, reason: 'fixture sanity check');
    expect(await _alertRowCount(), 0,
        reason: 'ArticleRepository must not know that alert_matches exists — '
            'matching is the fetch path\'s job, and a repository that wrote '
            'matches as a side effect of insertion would re-create exactly '
            'the coupling this rework removes');
    expect(await _alerts.getEntries(), isEmpty);
  });
}
