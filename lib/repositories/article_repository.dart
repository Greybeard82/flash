import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/article.dart';
import '../utils/keyword_matcher.dart';
import '../utils/constants.dart';

class ArticleRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  // ── Insert ─────────────────────────────────────────────────────────────────

  /// Insert articles for a feed using INSERT OR IGNORE to deduplicate.
  /// An existing row (same feed_id + guid) is silently skipped — never reset to unread.
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
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 0, ?)
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
      ]);
    }
    await batch.commit(noResult: true);
  }

  // ── Read queries ───────────────────────────────────────────────────────────

  /// Unblocked articles across all folders that are visible under the current
  /// read-visibility rule. Newest first.
  ///
  /// [readSinceMs] null hides every read article. Otherwise an article read
  /// at or after that instant stays visible. See [kShowReadBufferHours].
  Future<List<Article>> getAllArticles({int? readSinceMs}) async {
    final db = await _db;
    final (where, args) = _visibilityClause(null, readSinceMs);
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
    int? readSinceMs,
  }) async {
    final db = await _db;
    final (where, args) = _visibilityClause(folderId, readSinceMs);
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
  /// Fixed arity, unlike the session-id union this replaces, which emitted one
  /// `?` per article read since launch and would eventually have run into
  /// SQLite's variable limit on a long session.
  ///
  /// A NULL `read_at` never satisfies `>=`, so articles read before the v11
  /// migration are treated as outside the window. Intended.
  (String, List<Object?>) _visibilityClause(int? folderId, int? readSinceMs) {
    final buf = StringBuffer();
    final args = <Object?>[];
    if (folderId != null) {
      buf.write('f.folder_id = ? AND ');
      args.add(folderId);
    }
    buf.write('a.is_blocked = 0 AND (a.is_read = 0');
    if (readSinceMs != null) {
      buf.write(' OR a.read_at >= ?');
      args.add(readSinceMs);
    }
    buf.write(')');
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
  Future<int> getTotalUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
    ''');
    return result.first['cnt'] as int;
  }

  /// Unread count for a single folder.
  Future<int> getUnreadCount(int folderId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_read = 0 AND a.is_blocked = 0
    ''', [folderId]);
    return result.first['cnt'] as int;
  }

  /// Unread counts for every folder in one query, keyed by folder_id.
  Future<Map<int, int>> getAllFolderUnreadCounts() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT f.folder_id, COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
      GROUP BY f.folder_id
    ''');
    return {for (final row in rows) row['folder_id'] as int: row['cnt'] as int};
  }

  // ── Mark read / unread ─────────────────────────────────────────────────────

  /// [readAt] defaults to now. `COALESCE` so re-marking an already-read
  /// article keeps its original read time rather than silently extending its
  /// stay in the show-read window.
  Future<void> markAsRead(int articleId, {int? readAt}) async {
    final db = await _db;
    final ts = readAt ?? DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate('''
      UPDATE ${TableNames.articles}
      SET is_read = 1, read_at = COALESCE(read_at, ?)
      WHERE id = ?
    ''', [ts, articleId]);
  }

  Future<void> markAsUnread(int articleId) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${TableNames.articles}
      SET is_read = 0, read_at = NULL
      WHERE id = ?
    ''', [articleId]);
  }

  Future<void> markManyRead(List<int> articleIds, {int? readAt}) async {
    if (articleIds.isEmpty) return;
    final db = await _db;
    final ts = readAt ?? DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in articleIds) {
      batch.rawUpdate('''
        UPDATE ${TableNames.articles}
        SET is_read = 1, read_at = COALESCE(read_at, ?)
        WHERE id = ?
      ''', [ts, id]);
    }
    await batch.commit(noResult: true);
  }

  /// [readAt] is required and overwrites any existing value, because the two
  /// callers mean different things by it. *Mark all as read* passes
  /// [kDismissedReadAt] — a dismissal, gone for good. The end-of-feed dwell
  /// timer passes a real timestamp — passive reading, restorable like any
  /// other. Defaulting this would silently pick one of those for the other.
  Future<void> markAllAsRead({required int readAt}) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1, 'read_at': readAt},
      where: 'is_blocked = 0',
    );
  }

  Future<void> markAllAsReadByFolder(
    int folderId, {
    required int readAt,
  }) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${TableNames.articles}
      SET is_read = 1, read_at = ?
      WHERE feed_id IN (
        SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
      ) AND is_blocked = 0
    ''', [readAt, folderId]);
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Delete read (and not saved) articles older than [days] days (default: [kFetchDayLimit]).
  /// [days] is clamped to [5, 20].
  /// Scoped to [folderId] if provided; otherwise applies to all feeds.
  /// Returns the number of rows deleted.
  Future<int> runCleanup({int? folderId, int days = kFetchDayLimit}) async {
    final db = await _db;
    final clampedDays = days.clamp(5, 20);
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: clampedDays))
        .millisecondsSinceEpoch;
    if (folderId == null) {
      return db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1
          AND is_saved = 0
          AND published_at < ?
      ''', [cutoffMs]);
    } else {
      return db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1
          AND is_saved = 0
          AND published_at < ?
          AND feed_id IN (
            SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
          )
      ''', [cutoffMs, folderId]);
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
