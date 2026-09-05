import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/alert_entry.dart';
import '../models/alert_match.dart';
import '../utils/keyword_matcher.dart';

/// Everything that reads or writes `alert_matches`, the permanent snapshot of
/// what an alert keyword has matched.
///
/// Deliberately separate from [ArticleRepository], and never reached from it:
/// the whole point of the table is that an alert survives every path that
/// removes an article — retirement, cleanup, tombstoning, the display-age
/// filter, the per-feed cap. Read state is the one thing the two tables share,
/// and it is composed at the UI call sites rather than wired in here, so
/// neither side can quietly start deleting on the other's behalf.
class AlertMatchRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  // ── Insert ─────────────────────────────────────────────────────────────────

  /// Records [matches], ignoring any that are already on record.
  ///
  /// Returns exactly the subset actually written. That return value is what the
  /// notification planner fires on, so it has to mean "new to the user" and
  /// nothing looser: RSS feeds re-serve the same items on every fetch and a
  /// backfill re-runs whenever a keyword is edited, so without the pre-check
  /// every refresh would re-notify the whole panel. `INSERT OR IGNORE` alone
  /// cannot answer this — `last_insert_rowid()` is ambiguous when a row is
  /// ignored and does not say *which* rows were — so the unique
  /// (feed_id, guid, keyword) triples already present are queried up front,
  /// exactly as [ArticleRepository.insertArticles] does for guids.
  Future<List<AlertMatch>> insertMatches(List<AlertMatch> matches) async {
    if (matches.isEmpty) return [];
    final db = await _db;

    final existing = <String>{};
    final rows = await db.query(
      TableNames.alertMatches,
      columns: ['feed_id', 'guid', 'keyword'],
    );
    for (final row in rows) {
      existing.add(_tripleKey(
        row['feed_id'] as int,
        row['guid'] as String,
        row['keyword'] as String,
      ));
    }

    final written = <AlertMatch>[];
    final batch = db.batch();
    for (final match in matches) {
      final key = _tripleKey(match.feedId, match.guid, match.keyword);
      // Guards against a duplicate *within* this batch as well as against one
      // already in the table — a single fetch can easily hand the same article
      // to the same keyword twice.
      if (!existing.add(key)) continue;
      batch.insert(TableNames.alertMatches, match.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      written.add(match);
    }
    await batch.commit(noResult: true);

    return written;
  }

  /// Joined on NUL, a byte no guid or keyword can contain, so two distinct
  /// triples cannot flatten onto the same string.
  static String _tripleKey(int feedId, String guid, String keyword) =>
      '$feedId\u0000$guid\u0000$keyword';

  // ── Read queries ───────────────────────────────────────────────────────────

  /// Every alert match as cards, newest first, optionally filtered to the
  /// entries carrying [keyword].
  ///
  /// A filtered entry still lists its *full* keyword set: the card shown under
  /// "zelda" is the same article that also matched "nintendo", and amputating
  /// the badges to fit the filter would misreport it.
  ///
  /// The grouping is done in Dart rather than with GROUP_CONCAT or a second
  /// query per entry. This is a personal reader's alert list — hundreds of rows
  /// at the very outside — and folding an already-sorted result is both
  /// cheaper to read and easier to keep honest about the "read only when every
  /// row is read" rule than the SQL would be.

  /// Hides a snapshot whose article is currently blocked.
  ///
  /// "The blocklist wins" is enforced when a match is *created* — the fetch
  /// path, the backfill and the v16 migration all skip blocked articles — but
  /// blocking is retroactive: `ArticleRepository.retroactivelyBlock` sets
  /// is_blocked on articles already stored, and it has no business reaching
  /// into alert_matches. Without this the article would vanish from the feed,
  /// bookmarks, search and every count while its card sat on the Alerts tab.
  ///
  /// A filter rather than a delete, deliberately. Rule 3.4 allows exactly
  /// three things to remove a match — the user bins it, its keyword is
  /// deleted, or its keyword is edited — and a blocklist entry is none of
  /// them. Unblocking the keyword brings the card back, which is the
  /// behaviour a reversible setting should have.
  ///
  /// NOT EXISTS, not a join: a snapshot whose article has been retired has
  /// nothing to join to and must stay visible. No row means not blocked.
  static const String _notBlocked = '''
    NOT EXISTS (
      SELECT 1 FROM ${TableNames.articles} a
      WHERE a.feed_id = ${TableNames.alertMatches}.feed_id
        AND a.guid = ${TableNames.alertMatches}.guid
        AND a.is_blocked = 1
    )
  ''';

  Future<List<AlertEntry>> getEntries({String? keyword}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT * FROM ${TableNames.alertMatches}
      WHERE $_notBlocked
      ORDER BY matched_at DESC
    ''');

    final byPair = <String, List<AlertMatch>>{};
    final order = <String>[];
    for (final row in rows) {
      final match = AlertMatch.fromMap(row);
      final pair = '${match.feedId}\u0000${match.guid}';
      final group = byPair.putIfAbsent(pair, () {
        order.add(pair);
        return <AlertMatch>[];
      });
      group.add(match);
    }

    final entries = <AlertEntry>[];
    for (final pair in order) {
      final group = byPair[pair]!;
      final keywords = group.map((m) => m.keyword).toList()..sort();
      if (keyword != null && !keywords.contains(keyword)) continue;
      // The first row of the group is the newest, because the query is ordered
      // — so it is also the snapshot most likely to reflect the article as it
      // stands, and the one whose matched_at is the group's max.
      final newest = group.first;
      entries.add(AlertEntry(
        feedId: newest.feedId,
        guid: newest.guid,
        keywords: keywords,
        title: newest.title,
        url: newest.url,
        description: newest.description,
        thumbnailUrl: newest.thumbnailUrl,
        thumbnailPath: newest.thumbnailPath,
        feedTitle: newest.feedTitle,
        feedFaviconPath: newest.feedFaviconPath,
        publishedAt: newest.publishedAt,
        matchedAt: newest.matchedAt,
        isRead: group.every((m) => m.isRead),
      ));
    }
    return entries;
  }

  // ── Counts ─────────────────────────────────────────────────────────────────

  /// Entry count per keyword, for the per-keyword badges in the alerts panel.
  ///
  /// The LEFT JOIN runs from `keyword_alerts`, not from the match rows, so a
  /// keyword the user has just added reports 0 instead of vanishing: a map
  /// built only from matches makes a real, configured alert look like it was
  /// never saved. Keywords with rows but no configured alert — a keyword
  /// deleted while its snapshots stand — are unioned back in, since their
  /// cards are still on screen and still need a badge.
  Future<Map<String, int>> countsByKeyword() async {
    final db = await _db;
    // Collapsing to one row per (keyword, article) first is what makes this a
    // count of cards rather than of keyword hits, and it keeps the DISTINCT off
    // a feed_id-plus-guid string the two columns would have to be concatenated
    // into.
    const perKeyword = '''
      SELECT keyword, COUNT(*) AS cnt FROM (
        SELECT keyword, feed_id, guid FROM ${TableNames.alertMatches}
        WHERE $_notBlocked
        GROUP BY keyword, feed_id, guid
      )
      GROUP BY keyword
    ''';
    final rows = await db.rawQuery('''
      SELECT k.keyword AS keyword, COALESCE(c.cnt, 0) AS cnt
      FROM ${TableNames.keywordAlerts} k
      LEFT JOIN ($perKeyword) c ON c.keyword = k.keyword
      UNION
      SELECT c.keyword AS keyword, c.cnt AS cnt
      FROM ($perKeyword) c
      WHERE c.keyword NOT IN (SELECT keyword FROM ${TableNames.keywordAlerts})
    ''');
    return {
      for (final row in rows) row['keyword'] as String: row['cnt'] as int,
    };
  }

  /// How many cards the Alerts tab holds in total.
  ///
  /// DISTINCT (feed_id, guid), so a three-keyword article counts once. The
  /// badge counts cards, not keyword hits — summing the per-keyword counts
  /// would show 4 above a list of 2.
  Future<int> totalEntryCount() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM (
        SELECT feed_id, guid FROM ${TableNames.alertMatches}
        WHERE $_notBlocked
        GROUP BY feed_id, guid
      )
    ''');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  Future<int> countForKeyword(String keyword) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM (
        SELECT feed_id, guid FROM ${TableNames.alertMatches}
        WHERE keyword = ? AND $_notBlocked
        GROUP BY feed_id, guid
      )
    ''', [keyword]);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Entries carrying **every** keyword in [keywords] — the intersection, not
  /// an exact-set match, so an article that also hit a fourth keyword still
  /// counted as hitting these three.
  ///
  /// This is the number a combined notification quotes. Counting the union
  /// instead would overstate it on every article that hit only one of them.
  /// An empty list returns 0 rather than building `IN ()`, which is a SQL
  /// syntax error and is reachable the moment a fetch pass writes no new rows.
  Future<int> countForKeywordSet(List<String> keywords) async {
    if (keywords.isEmpty) return 0;
    final db = await _db;
    final placeholders = List.filled(keywords.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM (
        SELECT feed_id, guid FROM ${TableNames.alertMatches}
        WHERE keyword IN ($placeholders)
        GROUP BY feed_id, guid
        HAVING COUNT(DISTINCT keyword) = ?
      )
    ''', [...keywords, keywords.length]);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// Entries whose *only* keyword is [keyword] — i.e. the cards that would
  /// actually disappear if the user deleted this alert.
  ///
  /// The delete confirmation quotes this number, so it must exclude entries
  /// that carry another keyword too: those survive one badge lighter, and
  /// counting them would threaten the user with losing cards that stay.
  Future<int> orphanCountForKeyword(String keyword) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM (
        SELECT feed_id, guid FROM ${TableNames.alertMatches}
        GROUP BY feed_id, guid
        HAVING COUNT(DISTINCT keyword) = 1
           AND MAX(keyword) = ?
      )
    ''', [keyword]);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Dismisses one card, taking every keyword row behind it. A leftover row
  /// would rebuild the same card on the next read.
  ///
  /// Keyed on the pair and not the guid alone: guids are only unique within a
  /// feed, so deleting by guid would take an unrelated article from another
  /// feed with it.
  Future<int> deleteEntry(int feedId, String guid) async {
    final db = await _db;
    return db.delete(
      TableNames.alertMatches,
      where: 'feed_id = ? AND guid = ?',
      whereArgs: [feedId, guid],
    );
  }

  /// Drops the rows belonging to one keyword, leaving every other keyword on
  /// the same articles standing. Under first-match-wins an article matched by
  /// two alerts was attributed to one of them and vanished with it; one row
  /// per keyword is what fixes that.
  Future<int> deleteByKeyword(String keyword) async {
    final db = await _db;
    return db.delete(
      TableNames.alertMatches,
      where: 'keyword = ?',
      whereArgs: [keyword],
    );
  }

  // ── Read state ─────────────────────────────────────────────────────────────

  /// Marks every keyword row for one card, because an entry only counts as
  /// read when all of its rows are — leaving one behind would make the card
  /// pop back to unread the next time the tab regrouped it.
  Future<void> setRead(int feedId, String guid, {required bool isRead}) async {
    final db = await _db;
    await db.update(
      TableNames.alertMatches,
      {'is_read': isRead ? 1 : 0},
      where: 'feed_id = ? AND guid = ?',
      whereArgs: [feedId, guid],
    );
  }

  /// The batch counterpart of [setRead], for mark-read-on-scroll.
  ///
  /// Scroll marking works in article ids and writes them in one statement, so
  /// mirroring it one card at a time would mean a query per article on every
  /// scroll flush. The ids are resolved to `(feed_id, guid)` inside SQLite
  /// instead — a snapshot whose article has since been retired simply matches
  /// nothing, which is the same no-op [setRead] already is.
  ///
  /// Note this is only ever called for the article list. Scrolling the Alerts
  /// tab itself must not mark anything read, and does not: that list has its
  /// own ScrollController which the mark-read listener is not attached to.
  Future<void> setReadForArticleIds(List<int> articleIds,
      {required bool isRead}) async {
    if (articleIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(articleIds.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${TableNames.alertMatches} SET is_read = ? '
      'WHERE EXISTS (SELECT 1 FROM ${TableNames.articles} a '
      '              WHERE a.id IN ($placeholders) '
      '                AND a.feed_id = ${TableNames.alertMatches}.feed_id '
      '                AND a.guid = ${TableNames.alertMatches}.guid)',
      [isRead ? 1 : 0, ...articleIds],
    );
  }

  Future<void> setAllRead() async {
    final db = await _db;
    await db.update(TableNames.alertMatches, {'is_read': 1});
  }

  /// Marks the alerts snapshotted from one folder read.
  ///
  /// Rows carry a point-in-time `folder_id` and a snapshot whose feed has since
  /// been moved or deleted can hold null there. `folder_id = ?` is never true
  /// of NULL, so those rows are simply skipped rather than crashing or being
  /// swept up by a folder they no longer belong to.
  Future<void> setReadByFolder(int folderId) async {
    final db = await _db;
    await db.update(
      TableNames.alertMatches,
      {'is_read': 1},
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
  }

  // ── Backfill ───────────────────────────────────────────────────────────────

  /// Matches [keyword] against every article already on the device and records
  /// what it finds. Returns how many rows were written.
  ///
  /// An alert added today has to find the articles that arrived yesterday —
  /// matching only at fetch time was the reported bug. Read articles are
  /// included: the Alerts tab is a record of what matched, not of what is still
  /// unread, and skipping them would leave a live keyword looking like it had
  /// never hit anything.
  ///
  /// Blocked articles are skipped. The blocklist already won at fetch time but
  /// not here or in the panel query, so a blocked article could appear in
  /// Alerts while being hidden everywhere else; this rework settles it the same
  /// way in every path — the blocklist wins.
  ///
  /// Matching goes through [KeywordMatcher] so alerts and the blocklist agree
  /// on what "matches" means at the character level, even though they now
  /// differ on first-vs-all. `INSERT OR IGNORE` via [insertMatches] makes the
  /// pass free to re-run, which matters because it runs on every keyword edit
  /// and a nonzero result would re-notify articles the user has already seen.
  /// It never writes to `articles` — the auto-bookmark that used to hold a
  /// match alive is gone.
  Future<int> backfillKeyword(String keyword, bool wholeWord) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT a.feed_id, a.guid, a.title, a.url, a.description,
             a.thumbnail_url, a.thumbnail_path, a.published_at,
             f.title AS feed_title, f.favicon_path AS feed_favicon_path,
             f.folder_id AS folder_id
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 0
    ''');

    final matches = <AlertMatch>[];
    for (final row in rows) {
      final haystack = KeywordMatcher.buildHaystack(
        row['title'] as String,
        row['description'] as String?,
      );
      if (!KeywordMatcher.matches(keyword, haystack, wholeWord: wholeWord)) {
        continue;
      }
      matches.add(AlertMatch(
        feedId: row['feed_id'] as int,
        guid: row['guid'] as String,
        keyword: keyword,
        title: row['title'] as String,
        url: row['url'] as String,
        description: row['description'] as String?,
        thumbnailUrl: row['thumbnail_url'] as String?,
        thumbnailPath: row['thumbnail_path'] as String?,
        feedTitle: row['feed_title'] as String?,
        feedFaviconPath: row['feed_favicon_path'] as String?,
        folderId: row['folder_id'] as int?,
        publishedAt: row['published_at'] as int?,
        matchedAt: now,
      ));
    }

    final written = await insertMatches(matches);
    return written.length;
  }

  // ── Notification ids ───────────────────────────────────────────────────────

  /// A stable notification id for one keyword set.
  ///
  /// Every alert used to post under the hardcoded id 2, so each new alert
  /// silently replaced the previous one in the shade. An id per keyword set
  /// gives a second hit on the same keyword the right behaviour — it replaces
  /// its own notification — while a different keyword posts alongside it.
  ///
  /// The key is the sorted keywords joined by NUL, a byte no keyword can
  /// contain, so no pair of distinct sets can collide on it. The input is
  /// sorted again here despite the parameter name: a caller handing them over
  /// in row order would otherwise split one notification into two, and sorting
  /// a handful of strings is cheaper than the bug.
  ///
  /// Ids are offset by 2000 to keep alerts clear of the ids the rest of the app
  /// already posts under.
  Future<int> notificationIdFor(List<String> sortedKeywords) async {
    final db = await _db;
    final key = (List<String>.of(sortedKeywords)..sort()).join('\u0000');
    await db.rawInsert(
      'INSERT OR IGNORE INTO ${TableNames.alertNotificationIds} (key) VALUES (?)',
      [key],
    );
    final rows = await db.query(
      TableNames.alertNotificationIds,
      columns: ['id'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return 2000 + (rows.first['id'] as int);
  }
}
