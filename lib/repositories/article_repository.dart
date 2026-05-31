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

  /// All unread, unblocked articles across all folders, newest first.
  Future<List<Article>> getAllArticles() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  /// Unread, unblocked articles for a specific folder, newest first.
  Future<List<Article>> getArticlesByFolder(int folderId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_read = 0 AND a.is_blocked = 0
      ORDER BY a.published_at DESC
    ''', [folderId]);
    return rows.map(Article.fromMap).toList();
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
        AND f.folder_id IS NOT NULL
      GROUP BY f.folder_id
    ''');
    return {for (final row in rows) row['folder_id'] as int: row['cnt'] as int};
  }

  // ── Mark read / unread ─────────────────────────────────────────────────────

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

  // ── Backward-compatible aliases ────────────────────────────────────────────

  Future<void> markRead(int id) => markAsRead(id);
  Future<void> markUnread(int id) => markAsUnread(id);
}
