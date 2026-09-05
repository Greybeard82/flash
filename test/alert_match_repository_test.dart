// AlertMatchRepository — the table that gives an alert match a life of its own.
//
// An alert match used to be a column on `articles` (`matched_alert_keyword`),
// which meant the match had no existence apart from the article row. Every
// path that removes an article removed the alert with it: retireAllRead
// deleted the row on the next refresh, runCleanup deleted it on age, and the
// tombstone written on the way out stopped the re-fetch bringing it back. The
// only thing holding a match on screen was a bolted-on `is_saved = 1`
// auto-bookmark, which dumped entries into Bookmarks the user never chose and
// made an alert silently destroyable by un-bookmarking it. Matching was
// first-match-wins on top of that, so an article hitting two alert keywords was
// filed under exactly one and the other keyword's panel stayed empty for it.
//
// `alert_matches` replaces all of that with a snapshot: one row per
// (feed_id, guid, keyword), carrying its own title, url, thumbnail and feed
// identity, with deliberately no foreign key to `feeds` so it outlives the feed
// being deleted. This file is the proof that the snapshot behaves:
//
//   * a duplicate write is silently ignored and reported as nothing new —
//     that is what makes a retroactive backfill safe to re-run and what stops
//     an article notifying twice;
//   * one article under three keywords is one card carrying three badges, not
//     three cards;
//   * deleting one keyword leaves the article's other keywords standing;
//   * the backfill never touches `is_saved` — the auto-bookmark is gone.
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

// ── Helpers ────────────────────────────────────────────────────────────────

const int _now = 1750000000000;

late Database _db;
late AlertMatchRepository _repo;
late int _gamingFolderId;
late int _techFolderId;
late int _feedA;
late int _feedB;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _db = await AppDatabase.instance.database;
  _repo = AlertMatchRepository();

  _gamingFolderId = await _db.insert(TableNames.folders,
      {'name': 'Gaming', 'position': 0, 'created_at': _now});
  _techFolderId = await _db.insert(TableNames.folders,
      {'name': 'Tech', 'position': 1, 'created_at': _now});

  _feedA = await _db.insert(TableNames.feeds, {
    'folder_id': _gamingFolderId,
    'title': 'Feed A',
    'url': 'https://a.example/feed',
    'favicon_path': '/icons/a.png',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
  _feedB = await _db.insert(TableNames.feeds, {
    'folder_id': _techFolderId,
    'title': 'Feed B',
    'url': 'https://b.example/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': _now,
  });
}

AlertMatch _match(
  String guid,
  String keyword, {
  int? feedId,
  String? title,
  String? url,
  String? description,
  String? thumbnailUrl,
  String? thumbnailPath,
  String? feedTitle,
  String? feedFaviconPath,
  int? folderId,
  int? publishedAt,
  int matchedAt = _now,
  bool isRead = false,
}) =>
    AlertMatch(
      feedId: feedId ?? _feedA,
      guid: guid,
      keyword: keyword,
      title: title ?? 'Article $guid',
      url: url ?? 'https://example.com/$guid',
      description: description,
      thumbnailUrl: thumbnailUrl,
      thumbnailPath: thumbnailPath,
      feedTitle: feedTitle,
      feedFaviconPath: feedFaviconPath,
      folderId: folderId,
      publishedAt: publishedAt,
      matchedAt: matchedAt,
      isRead: isRead,
    );

Future<int> _rowCount() async {
  final r =
      await _db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.alertMatches}');
  return r.first['c'] as int;
}

Future<List<Map<String, Object?>>> _rows({String? guid}) {
  return _db.query(
    TableNames.alertMatches,
    where: guid == null ? null : 'guid = ?',
    whereArgs: guid == null ? null : [guid],
    orderBy: 'keyword ASC',
  );
}

/// Marks one keyword row read behind the repository's back.
///
/// [AlertMatchRepository.setRead] deliberately marks every keyword row for an
/// article at once, so it cannot produce the half-read group that the
/// "an entry is read only when all of its rows are" rule exists to describe.
Future<void> _markRowRead(String guid, String keyword) async {
  await _db.update(
    TableNames.alertMatches,
    {'is_read': 1},
    where: 'guid = ? AND keyword = ?',
    whereArgs: [guid, keyword],
  );
}

AlertEntry _entry(List<AlertEntry> entries, String guid) =>
    entries.firstWhere((e) => e.guid == guid);

Future<void> _insertAlert(String keyword, {bool wholeWord = false}) async {
  await _db.insert(TableNames.keywordAlerts, {
    'keyword': keyword,
    'whole_word': wholeWord ? 1 : 0,
    'created_at': _now,
  });
}

Future<int> _insertArticle(
  String guid,
  String title, {
  int? feedId,
  String? description,
  bool isRead = false,
  bool isSaved = false,
}) {
  return _db.insert(TableNames.articles, {
    'feed_id': feedId ?? _feedA,
    'guid': guid,
    'title': title,
    'url': 'https://example.com/$guid',
    'description': description,
    'published_at': _now,
    'fetched_at': _now,
    'is_read': isRead ? 1 : 0,
    'is_blocked': 0,
    'is_saved': isSaved ? 1 : 0,
  });
}

Future<Map<String, Object?>> _articleRow(String guid) async {
  final rows = await _db
      .query(TableNames.articles, where: 'guid = ?', whereArgs: [guid]);
  return rows.single;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  group('insertMatches', () {
    test('writes the rows and returns exactly the ones it wrote', () async {
      final written = await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a2', 'mario'),
      ]);

      expect(await _rowCount(), 2);
      expect(
        written.map((m) => '${m.guid}/${m.keyword}').toSet(),
        {'a1/zelda', 'a2/mario'},
      );
    });

    test('a duplicate (feed_id, guid, keyword) writes nothing and is reported '
        'as nothing new', () async {
      await _repo.insertMatches([_match('a1', 'zelda')]);
      final second = await _repo.insertMatches([_match('a1', 'zelda')]);

      expect(await _rowCount(), 1,
          reason: 'the unique index is what makes the whole feature '
              're-runnable: a second pass over the same article must not '
              'create a second card');
      expect(second, isEmpty,
          reason: 'the returned set is what the notification planner fires '
              'on — a match already on record must never notify again');
    });

    test('the same article under two keywords writes two rows', () async {
      final written = await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      expect(await _rowCount(), 2,
          reason: 'first-match-wins is gone — an article hitting two alert '
              'keywords must be recorded under both, or one keyword panel '
              'stays wrongly empty');
      expect(written.length, 2);
    });

    test('an empty batch is a no-op returning nothing', () async {
      final written = await _repo.insertMatches([]);

      expect(written, isEmpty);
      expect(await _rowCount(), 0);
    });

    test('a match survives its feed being deleted', () async {
      await _repo.insertMatches([_match('a1', 'zelda', feedId: _feedB)]);
      await _db.delete(TableNames.feeds, where: 'id = ?', whereArgs: [_feedB]);

      expect(await _rowCount(), 1,
          reason: 'alert_matches deliberately has no foreign key on feed_id — '
              'the row is a snapshot, and unsubscribing from a feed must not '
              'silently empty the Alerts tab');
    });
  });

  group('getEntries', () {
    test('two keywords on one article collapse into one entry listing both, '
        'sorted', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      final entries = await _repo.getEntries();

      expect(entries.length, 1,
          reason: 'one article is one card no matter how many keywords it '
              'hit — two cards for the same headline is the duplicate the '
              'grouping exists to prevent');
      expect(entries.single.keywords, ['nintendo', 'zelda'],
          reason: 'badge order has to be stable across rebuilds, so the '
              'keyword list is sorted rather than left in insert order');
    });

    test('entries come back newest matched_at first', () async {
      await _repo.insertMatches([
        _match('older', 'zelda', matchedAt: _now),
        _match('newer', 'zelda', matchedAt: _now + 5000),
        _match('middle', 'zelda', matchedAt: _now + 1000),
      ]);

      final entries = await _repo.getEntries();

      expect(entries.map((e) => e.guid).toList(),
          ['newer', 'middle', 'older']);
    });

    test('an entry with one of its two keyword rows read is still unread',
        () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);
      await _markRowRead('a1', 'zelda');

      final entries = await _repo.getEntries();

      expect(entries.single.isRead, isFalse,
          reason: 'the card is one thing to the user — dimming it while a '
              'keyword row on it is still unread would hide an alert they '
              'have never seen');
    });

    test('an entry is read once every one of its keyword rows is read',
        () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);
      await _markRowRead('a1', 'zelda');
      await _markRowRead('a1', 'nintendo');

      final entries = await _repo.getEntries();

      expect(entries.single.isRead, isTrue);
    });

    test('matchedAt is the newest match across the group', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda', matchedAt: _now),
        _match('a1', 'nintendo', matchedAt: _now + 9000),
      ]);

      final entries = await _repo.getEntries();

      expect(entries.single.matchedAt, _now + 9000,
          reason: 'a new keyword hitting an article the user has already '
              'scrolled past has to lift it back to the top, so the group '
              'takes the max and not the first row');
    });

    test('the snapshot fields round-trip onto the entry', () async {
      await _repo.insertMatches([
        _match(
          'a1',
          'zelda',
          title: 'Nintendo teases new Zelda game',
          url: 'https://a.example/zelda',
          description: 'A short teaser trailer aired overnight.',
          thumbnailUrl: 'https://a.example/thumb.jpg',
          thumbnailPath: '/cache/thumb.jpg',
          feedTitle: 'Feed A',
          feedFaviconPath: '/icons/a.png',
          publishedAt: _now - 60000,
        ),
      ]);

      final entry = (await _repo.getEntries()).single;

      expect(entry.title, 'Nintendo teases new Zelda game');
      expect(entry.url, 'https://a.example/zelda');
      expect(entry.description, 'A short teaser trailer aired overnight.');
      expect(entry.thumbnailUrl, 'https://a.example/thumb.jpg');
      expect(entry.thumbnailPath, '/cache/thumb.jpg');
      expect(entry.feedTitle, 'Feed A');
      expect(entry.feedFaviconPath, '/icons/a.png');
      expect(entry.publishedAt, _now - 60000,
          reason: 'the row carries everything the card draws, so the Alerts '
              'tab never has to join back to an articles row that cleanup may '
              'already have deleted');
    });

    test('filtering by keyword drops entries that do not carry it', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a2', 'mario'),
      ]);

      final entries = await _repo.getEntries(keyword: 'zelda');

      expect(entries.map((e) => e.guid).toList(), ['a1']);
    });

    test('a filtered entry still reports its full keyword set', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      final entries = await _repo.getEntries(keyword: 'zelda');

      expect(entries.single.keywords, ['nintendo', 'zelda'],
          reason: 'filtering the list must not amputate the badges — the card '
              'shown under "zelda" is still the same article that also '
              'matched "nintendo"');
    });
  });

  group('countsByKeyword', () {
    test('reports a live count per keyword', () async {
      await _insertAlert('zelda');
      await _insertAlert('mario');
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a2', 'zelda'),
        _match('a3', 'mario'),
      ]);

      final counts = await _repo.countsByKeyword();

      expect(counts['zelda'], 2);
      expect(counts['mario'], 1);
    });

    test('a configured alert with no matches yet reports 0 rather than '
        'vanishing', () async {
      await _insertAlert('zelda');
      await _insertAlert('metroid');
      await _repo.insertMatches([_match('a1', 'zelda')]);

      final counts = await _repo.countsByKeyword();

      expect(counts.containsKey('metroid'), isTrue,
          reason: 'a keyword the user just added has to appear in the panel '
              'immediately — a map built only from match rows makes a real, '
              'configured alert look like it was never saved');
      expect(counts['metroid'], 0);
    });

    test('an article matching two keywords counts once under each', () async {
      await _insertAlert('zelda');
      await _insertAlert('nintendo');
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      final counts = await _repo.countsByKeyword();

      expect(counts['zelda'], 1);
      expect(counts['nintendo'], 1);
    });
  });

  group('totalEntryCount', () {
    test('is zero with nothing recorded', () async {
      expect(await _repo.totalEntryCount(), 0);
    });

    test('counts distinct articles, so a three-keyword article counts once',
        () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
        _match('a1', 'switch'),
        _match('a2', 'zelda'),
      ]);

      final total = await _repo.totalEntryCount();
      final perKeywordSum = (await _repo.countForKeyword('zelda')) +
          (await _repo.countForKeyword('nintendo')) +
          (await _repo.countForKeyword('switch'));

      expect(total, 2);
      expect(total, lessThan(perKeywordSum),
          reason: 'the Alerts badge counts cards, not keyword hits — summing '
              'the per-keyword counts is exactly the wrong arithmetic and '
              'would show 4 above a list of 2');
    });
  });

  group('countForKeyword / countForKeywordSet', () {
    Future<void> seed() async {
      await _repo.insertMatches([
        _match('a1', 'a'),
        _match('a1', 'b'),
        _match('a1', 'c'),
        _match('a2', 'a'),
        _match('a2', 'b'),
        _match('a3', 'a'),
      ]);
    }

    test('countForKeyword counts the entries carrying it', () async {
      await seed();
      expect(await _repo.countForKeyword('a'), 3);
      expect(await _repo.countForKeyword('b'), 2);
      expect(await _repo.countForKeyword('c'), 1);
    });

    test('countForKeywordSet counts only entries carrying every keyword',
        () async {
      await seed();

      expect(await _repo.countForKeywordSet(['a', 'b']), 2,
          reason: 'a combined notification says how many articles hit the '
              'whole set — counting the union would overstate it on every '
              'article that hit only one');
    });

    test('an extra keyword does not disqualify an entry from the intersection',
        () async {
      await _repo.insertMatches([
        _match('a1', 'a'),
        _match('a1', 'b'),
        _match('a1', 'c'),
      ]);

      expect(await _repo.countForKeywordSet(['a', 'b']), 1,
          reason: 'this is an intersection, not an exact-set match — an '
              'article that also hit a third keyword still hit both of these');
    });

    test('a one-keyword set agrees with countForKeyword', () async {
      await seed();

      expect(await _repo.countForKeywordSet(['a']),
          await _repo.countForKeyword('a'),
          reason: 'the notification body for a single keyword and the panel '
              'badge for it must never disagree');
    });

    test('an empty set counts nothing rather than throwing', () async {
      await seed();

      expect(await _repo.countForKeywordSet([]), 0,
          reason: 'an empty IN (...) is a SQL syntax error, and this is '
              'reachable the moment a pass writes no new rows');
    });
  });

  group('orphanCountForKeyword', () {
    test('counts entries whose only keyword is this one', () async {
      await _repo.insertMatches([
        _match('solo', 'zelda'),
        _match('shared', 'zelda'),
        _match('shared', 'nintendo'),
      ]);

      expect(await _repo.orphanCountForKeyword('zelda'), 1,
          reason: 'the delete-keyword confirmation promises how many cards '
              'disappear — counting every entry carrying the keyword would '
              'threaten the user with losing cards that actually survive');
    });

    test('an entry carrying another keyword too is not counted', () async {
      await _repo.insertMatches([
        _match('shared', 'zelda'),
        _match('shared', 'nintendo'),
      ]);

      expect(await _repo.orphanCountForKeyword('nintendo'), 0,
          reason: 'removing "nintendo" leaves this card standing, one badge '
              'lighter');
    });
  });

  group('deleteEntry', () {
    test('removes every keyword row for the pair and returns how many',
        () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      final deleted = await _repo.deleteEntry(_feedA, 'a1');

      expect(deleted, 2);
      expect(await _rowCount(), 0,
          reason: 'dismissing a card has to take all of its keyword rows — a '
              'leftover row rebuilds the same card on the next read');
    });

    test('leaves other entries, and the same guid on another feed, untouched',
        () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a2', 'zelda'),
        _match('a1', 'zelda', feedId: _feedB),
      ]);

      await _repo.deleteEntry(_feedA, 'a1');

      final remaining = await _repo.getEntries();
      expect(remaining.length, 2);
      expect(
        remaining.map((e) => '${e.feedId}/${e.guid}').toSet(),
        {'$_feedA/a2', '$_feedB/a1'},
        reason: 'guids are only unique within a feed, so deleting by guid '
            'alone would take an unrelated article from another feed with it',
      );
    });
  });

  group('deleteByKeyword', () {
    test('removes only that keyword\'s rows and returns how many', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a2', 'zelda'),
        _match('a3', 'mario'),
      ]);

      final deleted = await _repo.deleteByKeyword('zelda');

      expect(deleted, 2);
      expect((await _repo.getEntries()).map((e) => e.guid).toList(), ['a3']);
    });

    test('an entry that also carried another keyword survives with the rest',
        () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      await _repo.deleteByKeyword('zelda');

      final entries = await _repo.getEntries();
      expect(entries.single.keywords, ['nintendo'],
          reason: 'deleting one alert must not take an article that two '
              'alerts matched — under first-match-wins that article was '
              'attributed to one keyword and vanished with it');
    });
  });

  group('setRead / setAllRead / setReadByFolder', () {
    test('setRead marks every keyword row for the pair', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);

      await _repo.setRead(_feedA, 'a1', isRead: true);

      expect((await _rows(guid: 'a1')).map((r) => r['is_read']).toList(),
          [1, 1],
          reason: 'an entry only counts as read when all of its rows are, so '
              'marking a card read has to reach all of them or the card never '
              'dims');
      expect((await _repo.getEntries()).single.isRead, isTrue);
    });

    test('setRead(isRead: false) marks them unread again', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
      ]);
      await _repo.setRead(_feedA, 'a1', isRead: true);

      await _repo.setRead(_feedA, 'a1', isRead: false);

      expect((await _rows(guid: 'a1')).map((r) => r['is_read']).toList(),
          [0, 0]);
      expect((await _repo.getEntries()).single.isRead, isFalse);
    });

    test('setRead leaves other entries alone', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a2', 'zelda'),
      ]);

      await _repo.setRead(_feedA, 'a1', isRead: true);

      expect(_entry(await _repo.getEntries(), 'a2').isRead, isFalse);
    });

    test('setAllRead marks everything', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda'),
        _match('a1', 'nintendo'),
        _match('a2', 'mario', feedId: _feedB),
      ]);

      await _repo.setAllRead();

      final rows = await _rows();
      expect(rows.every((r) => r['is_read'] == 1), isTrue);
      expect((await _repo.getEntries()).every((e) => e.isRead), isTrue);
    });

    test('setReadByFolder only touches rows in that folder', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda', folderId: _gamingFolderId),
        _match('a2', 'mario', feedId: _feedB, folderId: _techFolderId),
      ]);

      await _repo.setReadByFolder(_gamingFolderId);

      final entries = await _repo.getEntries();
      expect(_entry(entries, 'a1').isRead, isTrue);
      expect(_entry(entries, 'a2').isRead, isFalse,
          reason: 'clearing one folder tab must not silently clear the '
              'alerts belonging to every other folder');
    });

    test('setReadByFolder tolerates rows with no folder', () async {
      await _repo.insertMatches([
        _match('a1', 'zelda', folderId: _gamingFolderId),
        _match('orphan', 'zelda', folderId: null),
      ]);

      await _repo.setReadByFolder(_gamingFolderId);

      final entries = await _repo.getEntries();
      expect(_entry(entries, 'a1').isRead, isTrue);
      expect(_entry(entries, 'orphan').isRead, isFalse,
          reason: 'a snapshot whose feed has since been moved or deleted can '
              'carry a null folder_id, and NULL = ? is never true — it must '
              'be skipped, not crash the mark-read');
    });
  });

  group('backfillKeyword', () {
    test('records a match for every article whose title contains the keyword',
        () async {
      await _insertArticle('x1', 'Nintendo teases new Zelda game');
      await _insertArticle('x2', 'Zelda 40th anniversary announced');
      await _insertArticle('x3', 'Completely unrelated tech news');

      final inserted = await _repo.backfillKeyword('zelda', false);

      expect(inserted, 2,
          reason: 'an alert added today has to find the articles already on '
              'the device — matching only at fetch time was the reported bug');
      expect((await _repo.getEntries()).map((e) => e.guid).toSet(),
          {'x1', 'x2'});
    });

    test('matches on the description as well as the title', () async {
      await _insertArticle('x1', 'Weekly roundup',
          description: 'A big Zelda announcement landed overnight.');

      expect(await _repo.backfillKeyword('zelda', false), 1,
          reason: 'the live path builds its haystack from title + '
              'description, and a backfill that searched only titles would '
              'quietly disagree with it');
    });

    test('carries the feed title, favicon and folder from the join', () async {
      await _insertArticle('x1', 'Nintendo teases new Zelda game');

      await _repo.backfillKeyword('zelda', false);

      final entry = (await _repo.getEntries()).single;
      expect(entry.feedTitle, 'Feed A');
      expect(entry.feedFaviconPath, '/icons/a.png');
      expect((await _rows(guid: 'x1')).single['folder_id'], _gamingFolderId,
          reason: 'the row has to snapshot its folder at match time — '
              'setReadByFolder reads it, and the feed it came from may be '
              'gone by then');
    });

    test('whole-word matching is respected', () async {
      await _insertArticle('x1', 'A cryptocurrency explainer');

      expect(await _repo.backfillKeyword('crypto', true), 0,
          reason: '"crypto" whole-word must not match inside '
              '"cryptocurrency" — same KeywordMatcher semantics the live '
              'match and the blocklist use');
      expect(await _repo.backfillKeyword('crypto', false), 1,
          reason: 'with whole-word off the same article is a substring hit, '
              'which is what makes the flag worth having');
    });

    test('is idempotent — a second run reports zero new and changes nothing',
        () async {
      await _insertArticle('x1', 'Nintendo teases new Zelda game');
      await _insertArticle('x2', 'Zelda 40th anniversary announced');

      final first = await _repo.backfillKeyword('zelda', false);
      final countAfterFirst = await _rowCount();
      final second = await _repo.backfillKeyword('zelda', false);

      expect(first, 2);
      expect(second, 0,
          reason: 'the backfill runs whenever a keyword is edited or '
              're-enabled, so re-running it must be free — a nonzero result '
              'here would re-notify articles the user has already seen');
      expect(await _rowCount(), countAfterFirst);
    });

    test('read articles are matched too', () async {
      await _insertArticle('x1', 'Nintendo teases new Zelda game',
          isRead: true);

      expect(await _repo.backfillKeyword('zelda', false), 1,
          reason: 'the Alerts tab is a record of what matched, not of what is '
              'still unread — skipping read articles would leave a keyword '
              'looking like it had never hit anything');
    });

    test('does not bookmark the article it matched', () async {
      await _insertArticle('x1', 'Nintendo teases new Zelda game');

      await _repo.backfillKeyword('zelda', false);

      expect((await _articleRow('x1'))['is_saved'], 0,
          reason: 'the auto-bookmark is gone — alert_matches is what keeps a '
              'match alive now, and is_saved = 1 polluted Bookmarks with '
              'entries the user never chose and could not tell apart from '
              'deliberate ones');
    });

    test('a keyword nothing matches writes nothing at all', () async {
      await _insertArticle('x1', 'Nintendo teases new Zelda game');

      expect(await _repo.backfillKeyword('mario', false), 0);
      expect(await _rowCount(), 0,
          reason: 'the backfill is silent by design — a keyword that hits '
              'nothing must leave the Alerts tab exactly as it found it');
    });
  });

  group('notificationIdFor', () {
    test('is stable across calls for the same keyword list', () async {
      final first = await _repo.notificationIdFor(['zelda']);
      final second = await _repo.notificationIdFor(['zelda']);

      expect(second, first,
          reason: 'a stable id per keyword set is what lets a second hit on '
              'the same keyword replace its own notification instead of '
              'stacking, and lets a different keyword post alongside it');
    });

    test('the same keywords in a different order collapse to one id',
        () async {
      final ab = await _repo.notificationIdFor(['a', 'b']);
      final ba = await _repo.notificationIdFor(['b', 'a']);

      expect(ba, ab,
          reason: 'the key is canonicalised by sorting before joining, so '
              'row order out of SQLite cannot split one notification into two');
    });

    test('different keyword sets get different ids', () async {
      final a = await _repo.notificationIdFor(['a']);
      final ab = await _repo.notificationIdFor(['a', 'b']);

      expect(ab, isNot(a),
          reason: 'every alert used to post under one hardcoded id, so each '
              'new alert silently replaced the previous one in the shade');
    });

    test('ids sit at or above the reserved 2000 floor', () async {
      final id = await _repo.notificationIdFor(['zelda']);

      expect(id, greaterThanOrEqualTo(2000),
          reason: 'the offset keeps alert notifications clear of the ids the '
              'rest of the app already posts under');
    });
  });
}
