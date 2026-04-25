import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/article.dart';
import '../utils/keyword_matcher.dart';

class ArticleRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<List<Article>> getForFeed(int feedId, {bool includeRead = true}) async {
    final db = await _db;
    final where = includeRead
        ? 'a.feed_id = ? AND a.is_blocked = 0'
        : 'a.feed_id = ? AND a.is_read = 0 AND a.is_blocked = 0';
    final rows = await db.rawQuery('''
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE $where
      ORDER BY a.published_at DESC
    ''', [feedId]);
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getForFolder(int folderId, {bool includeRead = true}) async {
    final db = await _db;
    final whereExtra = includeRead ? '' : 'AND a.is_read = 0';
    final rows = await db.rawQuery('''
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_blocked = 0 $whereExtra
      ORDER BY a.published_at DESC
    ''', [folderId]);
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getAll({bool includeRead = true}) async {
    final db = await _db;
    final whereExtra = includeRead ? '' : 'AND a.is_read = 0';
    final rows = await db.rawQuery('''
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 0 $whereExtra
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getBlocked() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
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
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 0
        AND (a.title LIKE ? OR a.description LIKE ?)
      ORDER BY a.published_at DESC
      LIMIT 100
    ''', [pattern, pattern]);
    return rows.map(Article.fromMap).toList();
  }

  Future<int> insertMany(List<Article> articles) async {
    if (articles.isEmpty) return 0;
    final db = await _db;
    int newCount = 0;
    for (final article in articles) {
      final id = await db.insert(
        TableNames.articles,
        article.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (id != 0) newCount++;
    }
    return newCount;
  }

  Future<void> markRead(int articleId) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<void> markUnread(int articleId) async {
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

  Future<void> markAllReadForFeed(int feedId) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'feed_id = ? AND is_blocked = 0',
      whereArgs: [feedId],
    );
  }

  Future<void> markAllReadForFolder(int folderId) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${TableNames.articles}
      SET is_read = 1
      WHERE feed_id IN (
        SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
      ) AND is_blocked = 0
    ''', [folderId]);
  }

  Future<void> markAllRead() async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'is_blocked = 0',
    );
  }

  Future<void> runAutoCleanup(int feedId, int effectiveLimit) async {
    final db = await _db;
    await db.rawDelete(
      SchemaStatements.autoCleanup,
      [feedId, feedId, effectiveLimit],
    );
  }

  Future<void> updateThumbnailPath(int articleId, String path) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'thumbnail_path': path},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// When a keyword is newly added, scan all unblocked articles and block matches.
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

  /// When a keyword is deleted, unblock all articles it had blocked.
  Future<void> unblockByKeyword(String keyword) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_blocked': 0, 'blocked_keyword': null},
      where: 'blocked_keyword = ?',
      whereArgs: [keyword],
    );
  }

  Future<List<Article>> getSaved() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_saved = 1
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<void> setSaved(int articleId, {required bool saved}) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_saved': saved ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<int> getUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM ${TableNames.articles}
      WHERE is_read = 0 AND is_blocked = 0    ''');
    return result.first['count'] as int;
  }

  Future<int> getUnreadCountForFolder(int folderId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_read = 0 AND a.is_blocked = 0    ''', [folderId]);
    return result.first['count'] as int;
  }

  /// Returns unread counts for every folder in a single query, keyed by folder_id.
  /// Use this instead of calling [getUnreadCountForFolder] in a loop.
  Future<Map<int, int>> getAllFolderUnreadCounts() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT f.folder_id, COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0        AND f.folder_id IS NOT NULL
      GROUP BY f.folder_id
    ''');
    return {for (final row in rows) row['folder_id'] as int: row['cnt'] as int};
  }
}
