import 'package:sqflite/sqflite.dart';
import '../utils/diag_log.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/article.dart';
import '../utils/keyword_matcher.dart';
import '../utils/constants.dart';

class ArticleRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  // ── Insert ─────────────────────────────────────────────────────────────────

  /// Insert articles for a feed, deduplicating two ways.
  ///
  /// `INSERT OR IGNORE` against the unique (feed_id, guid) index stops
  /// duplicates *within* the table. That alone used to be enough, because a
  /// read article kept its row and so kept its guid to collide with.
  /// Retirement deletes the row, taking the guid with it — and the article is
  /// still in the feed's XML and still inside the fetch window, so the
  /// NOT EXISTS check against [TableNames.deletedArticles] is what stops the
  /// next refresh resurrecting everything the user just cleared. Both are
  /// needed: the index guards within a fetch, the tombstone guards across one.
  Future<void> insertArticles(int feedId, List<Article> articles) async {
    if (articles.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    final fetchedAt = DateTime.now().millisecondsSinceEpoch;
    for (final a in articles) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO ${TableNames.articles}
        (feed_id, guid, title, url, description, thumbnail_url, thumbnail_path,
         published_at, fetched_at, is_read, is_blocked, is_saved, blocked_keyword)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 0, ?
        WHERE NOT EXISTS (
          SELECT 1 FROM ${TableNames.deletedArticles}
          WHERE feed_id = ? AND guid = ?
        )
      ''', [
        feedId,
        a.guid,
        a.title,
        a.url,
        a.description,
        a.thumbnailUrl,
        a.thumbnailPath,
        a.publishedAt,
        fetchedAt,
        a.isBlocked ? 1 : 0,
        a.blockedKeyword,
        feedId,
        a.guid,
      ]);
    }
    await batch.commit(noResult: true);
  }

  // ── Read queries ───────────────────────────────────────────────────────────

  /// Unblocked articles across all folders visible under the current
  /// read-visibility rule. Newest first.
  Future<List<Article>> getAllArticles({required bool showRead}) async {
    final db = await _db;
    final (where, args) = _visibilityClause(null, showRead);
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE $where
      ORDER BY a.published_at DESC
    ''', args);
    return rows.map(Article.fromMap).toList();
  }

  /// As [getAllArticles], scoped to one folder.
  Future<List<Article>> getArticlesByFolder(
    int folderId, {
    required bool showRead,
  }) async {
    final db = await _db;
    final (where, args) = _visibilityClause(folderId, showRead);
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE $where
      ORDER BY a.published_at DESC
    ''', args);
    return rows.map(Article.fromMap).toList();
  }

  /// WHERE clause and args for the visible set.
  ///
  /// With [showRead] on, every unblocked article — read ones are dimmed by the
  /// UI and retired at the next refresh. With it off, unread only, **plus**
  /// saved articles: those are exempt from retirement, so hiding them once read
  /// would make a bookmark vanish from the feed while still sitting in
  /// Bookmarks.
  (String, List<Object?>) _visibilityClause(int? folderId, bool showRead) {
    final buf = StringBuffer();
    final args = <Object?>[];
    if (folderId != null) {
      buf.write('f.folder_id = ? AND ');
      args.add(folderId);
    }
    buf.write('a.is_blocked = 0');
    if (!showRead) buf.write(' AND (a.is_read = 0 OR a.is_saved = 1)');
    return (buf.toString(), args);
  }

  Future<List<Article>> getSaved() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_saved = 1
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getBlocked() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 1
      ORDER BY a.fetched_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await _db;
    final pattern = '%${query.trim()}%';
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 0
        AND (a.title LIKE ? OR a.description LIKE ?)
      ORDER BY a.published_at DESC
      LIMIT 100
    ''', [pattern, pattern]);
    return rows.map(Article.fromMap).toList();
  }

  // ── Counts ─────────────────────────────────────────────────────────────────

  /// Total unread count across all folders.
  /// Unread articles the list would actually show, across every folder.
  ///
  /// [windowDays] is the display window — `cleanup_age_days`, the same value
  /// the Filter bubble's Article age slider sets and `_applyDisplayFilters`
  /// applies. Without it the badge counted every unread row in the database,
  /// including ones aged out of the display window and therefore unreachable:
  /// 428 against a visible list of 5, permanently, and widening as the
  /// database aged.
  ///
  /// A null `published_at` is counted, matching the list, which shows such an
  /// article rather than hiding it silently.
  Future<int> getTotalUnreadCount({int windowDays = kFetchDayLimit}) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
        AND (a.published_at IS NULL OR a.published_at >= ?)
    ''', [displayCutoffMs(windowDays)]);
    return result.first['cnt'] as int;
  }

  /// Unread count for a single folder.
  /// As [getTotalUnreadCount], scoped to one folder.
  Future<int> getUnreadCount(int folderId,
      {int windowDays = kFetchDayLimit}) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_read = 0 AND a.is_blocked = 0
        AND (a.published_at IS NULL OR a.published_at >= ?)
    ''', [folderId, displayCutoffMs(windowDays)]);
    return result.first['cnt'] as int;
  }

  /// Unread counts for every folder in one query, keyed by folder_id.
  /// Per-folder unread counts, filtered exactly as [getTotalUnreadCount] is.
  Future<Map<int, int>> getAllFolderUnreadCounts(
      {int windowDays = kFetchDayLimit}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT f.folder_id, COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
        AND (a.published_at IS NULL OR a.published_at >= ?)
      GROUP BY f.folder_id
    ''', [displayCutoffMs(windowDays)]);
    return {for (final row in rows) row['folder_id'] as int: row['cnt'] as int};
  }

  // ── Mark read / unread ─────────────────────────────────────────────────────

  /// Marks read. Deliberately does **not** delete anything — retirement is a
  /// separate explicit call, which is what lets "Show read ON" defer it to the
  /// next refresh while "OFF" retires on scroll.
  Future<void> markAsRead(int articleId) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<void> markAsUnread(int articleId) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<void> markManyRead(List<int> articleIds) async {
    if (articleIds.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final id in articleIds) {
      batch.update(
        TableNames.articles,
        {'is_read': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markAllAsRead() async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'is_blocked = 0',
    );
  }

  Future<void> markAllAsReadByFolder(int folderId) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${TableNames.articles}
      SET is_read = 1
      WHERE feed_id IN (
        SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
      ) AND is_blocked = 0
    ''', [folderId]);
  }

  // ── Retirement ─────────────────────────────────────────────────────────────

  /// Retires [articleIds]: the user is finished with them.
  ///
  /// Saved articles are exempt — marked read and kept, under either show-read
  /// setting, until un-bookmarked. Everything else is tombstoned and deleted.
  ///
  /// Tombstone first, delete second, both in one transaction. The other order
  /// leaves a window where an interrupted retirement has deleted rows with
  /// nothing to stop the next fetch restoring them.
  ///
  /// Returns the number of rows deleted.
  Future<int> retireArticles(List<int> articleIds) async {
    if (articleIds.isEmpty) return 0;
    var deleted = 0;
    for (var i = 0; i < articleIds.length; i += _retireChunkSize) {
      final end = (i + _retireChunkSize).clamp(0, articleIds.length);
      deleted += await _retireChunk(articleIds.sublist(i, end));
    }
    return deleted;
  }

  /// Ids per retirement transaction.
  ///
  /// Each chunk binds its id list three times — the saved-exempt update, the
  /// tombstone select and the delete — plus one timestamp, so the ceiling is
  /// roughly `3N + 1` variables. At 200 that is ~601, comfortably under
  /// SQLite's old 999 default as well as the current 32,766. The count is
  /// invisible at the call site, which is why it is bounded here rather than
  /// trusted to stay small.
  static const int _retireChunkSize = 200;

  Future<int> _retireChunk(List<int> articleIds) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ph = List.filled(articleIds.length, '?').join(',');

    return db.transaction((txn) async {
      final savedMarked = await txn.rawUpdate('''
        UPDATE ${TableNames.articles}
        SET is_read = 1
        WHERE id IN ($ph) AND is_saved = 1
      ''', articleIds);
      if (savedMarked > 0) {
        DiagLog.read(
            id: -savedMarked, trigger: 'retirement:saved', offset: -1);
      }

      await txn.rawInsert('''
        INSERT OR IGNORE INTO ${TableNames.deletedArticles}
          (feed_id, guid, deleted_at)
        SELECT feed_id, guid, ?
        FROM ${TableNames.articles}
        WHERE id IN ($ph) AND is_saved = 0
      ''', [now, ...articleIds]);

      return txn.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE id IN ($ph) AND is_saved = 0
      ''', articleIds);
    });
  }

  /// Retires every read, unsaved article in scope.
  ///
  /// This is what makes "Show read ON" mean *deferred* retirement rather than
  /// a different outcome. With the toggle off nothing is read by the time this
  /// runs, so it is a cheap no-op — call it unconditionally rather than
  /// branching on the setting.
  Future<int> retireAllRead({int? folderId}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final scope = folderId == null
        ? ''
        : 'AND feed_id IN (SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?)';
    final args = folderId == null ? <Object?>[] : <Object?>[folderId];

    return db.transaction((txn) async {
      await txn.rawInsert('''
        INSERT OR IGNORE INTO ${TableNames.deletedArticles}
          (feed_id, guid, deleted_at)
        SELECT feed_id, guid, ?
        FROM ${TableNames.articles}
        WHERE is_read = 1 AND is_saved = 0 $scope
      ''', [now, ...args]);

      return txn.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1 AND is_saved = 0 $scope
      ''', args);
    });
  }

  /// Drops **every** tombstone, so anything the feeds still carry can be
  /// re-inserted by the next fetch.
  ///
  /// This is the only route back from retirement, which is otherwise
  /// irreversible by design. It cannot resurrect an article the feed has
  /// stopped offering — nothing outside the fetch window comes back — and it
  /// touches nothing but the tombstone table: feeds, folders, keywords,
  /// bookmarks and surviving articles are all untouched.
  ///
  /// Returns the number of tombstones cleared.
  Future<int> clearAllTombstones() async {
    final db = await _db;
    return db.delete(TableNames.deletedArticles);
  }

  /// How many tombstones are currently held.
  Future<int> tombstoneCount() async {
    final db = await _db;
    final rows = await db
        .rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.deletedArticles}');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Drops tombstones old enough that the feed has stopped offering the
  /// article anyway.
  Future<int> pruneTombstones() async {
    final db = await _db;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: kTombstoneDayLimit))
        .millisecondsSinceEpoch;
    return db.delete(TableNames.deletedArticles,
        where: 'deleted_at < ?', whereArgs: [cutoff]);
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Delete read (and not saved) articles older than [days] days (default: [kFetchDayLimit]).
  /// [days] is clamped to [5, 20].
  /// Scoped to [folderId] if provided; otherwise applies to all feeds.
  /// Returns the number of rows deleted.
  /// Tombstone pruning rides along here rather than at the call sites:
  /// runCleanup already runs on cold start and background refresh, which is
  /// exactly the cadence a tombstone table needs, and doing it here means a
  /// new cleanup caller cannot forget it.
  Future<int> runCleanup({int? folderId, int days = kFetchDayLimit}) async {
    final db = await _db;
    await pruneTombstones();
    final clampedDays = days.clamp(5, 20);
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: clampedDays))
        .millisecondsSinceEpoch;
    // Unread articles past the *widest* window the user can select. Cleanup
    // used to touch read articles only, so unread ones aged out of the display
    // window and then stayed in the database for ever — invisible to the list,
    // but still counted by the badge. The floor is deliberately
    // kUnreadRetentionDays rather than [days]: an article dropped under a
    // 2-day setting could still have been recovered by widening the Article
    // age slider, and only past 15 days is it unreachable by any setting.
    final unreadCutoffMs = displayCutoffMs(kUnreadRetentionDays);

    if (folderId == null) {
      final read = await db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1
          AND is_saved = 0
          AND published_at < ?
      ''', [cutoffMs]);
      final unread = await db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 0
          AND is_saved = 0
          AND published_at IS NOT NULL
          AND published_at < ?
      ''', [unreadCutoffMs]);
      return read + unread;
    } else {
      final read = await db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1
          AND is_saved = 0
          AND published_at < ?
          AND feed_id IN (
            SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
          )
      ''', [cutoffMs, folderId]);
      final unread = await db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 0
          AND is_saved = 0
          AND published_at IS NOT NULL
          AND published_at < ?
          AND feed_id IN (
            SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
          )
      ''', [unreadCutoffMs, folderId]);
      return read + unread;
    }
  }

  // ── Saved / bookmarks ──────────────────────────────────────────────────────

  Future<void> setSaved(int articleId, {required bool saved}) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_saved': saved ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // ── Thumbnails ─────────────────────────────────────────────────────────────

  Future<void> updateThumbnailPath(int articleId, String path) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'thumbnail_path': path},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // ── Keyword blocking ───────────────────────────────────────────────────────

  Future<void> retroactivelyBlock(String keyword, bool wholeWord) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.articles,
      columns: ['id', 'title', 'description'],
      where: 'is_blocked = 0',
    );
    final batch = db.batch();
    for (final row in rows) {
      final haystack = KeywordMatcher.buildHaystack(
        row['title'] as String,
        row['description'] as String?,
      );
      if (KeywordMatcher.matches(keyword, haystack, wholeWord: wholeWord)) {
        batch.update(
          TableNames.articles,
          {'is_blocked': 1, 'blocked_keyword': keyword},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> unblockByKeyword(String keyword) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_blocked': 0, 'blocked_keyword': null},
      where: 'blocked_keyword = ?',
      whereArgs: [keyword],
    );
  }

}
