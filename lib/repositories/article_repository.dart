import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/article.dart';

class ArticleRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<List<Article>> getForFeed(int feedId, {bool includeRead = true}) async {
    final db = await _db;
    final where = includeRead
        ? 'a.feed_id = ? AND a.is_blocked = 0 AND a.is_opinion = 0'
        : 'a.feed_id = ? AND a.is_read = 0 AND a.is_blocked = 0 AND a.is_opinion = 0';
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
      WHERE f.folder_id = ? AND a.is_blocked = 0 AND a.is_opinion = 0 $whereExtra
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
      WHERE a.is_blocked = 0 AND a.is_opinion = 0 $whereExtra
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getOpinions() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title as feed_title, f.favicon_path as feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_opinion = 1 AND a.is_blocked = 0
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<void> insertMany(List<Article> articles) async {
    final db = await _db;
    final batch = db.batch();
    for (final article in articles) {
      batch.insert(
        TableNames.articles,
        article.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
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
    final needle = keyword.toLowerCase();
    final pattern = wholeWord
        ? RegExp(r'\b' + RegExp.escape(needle) + r'\b', caseSensitive: false)
        : null;

    final batch = db.batch();
    for (final row in rows) {
      final haystack =
          '${(row['title'] as String).toLowerCase()} ${((row['description'] as String?) ?? '').toLowerCase()}';
      final matches =
          pattern != null ? pattern.hasMatch(haystack) : haystack.contains(needle);
      if (matches) {
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

  Future<int> getUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM ${TableNames.articles}
      WHERE is_read = 0 AND is_blocked = 0 AND is_opinion = 0
    ''');
    return result.first['count'] as int;
  }

  Future<int> getUnreadCountForFolder(int folderId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_read = 0 AND a.is_blocked = 0 AND a.is_opinion = 0
    ''', [folderId]);
    return result.first['count'] as int;
  }
}
