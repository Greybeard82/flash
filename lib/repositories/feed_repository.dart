import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/feed.dart';
import '../services/feeds_changed_notifier.dart';

class FeedRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<List<Feed>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      TableNames.feeds,
      orderBy: 'position ASC',
    );
    return rows.map(Feed.fromMap).toList();
  }

  Future<List<Feed>> getByFolder(int folderId) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.feeds,
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'position ASC',
    );
    return rows.map(Feed.fromMap).toList();
  }

  Future<Feed?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.feeds,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Feed.fromMap(rows.first);
  }

  Future<Feed?> getByUrl(String url) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.feeds,
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Feed.fromMap(rows.first);
  }

  Future<Feed> insert(Feed feed) async {
    final db = await _db;
    final id = await db.insert(TableNames.feeds, feed.toMap());
    FeedsChangedNotifier.instance.feedAdded();
    return feed.copyWith(id: id);
  }

  Future<void> update(Feed feed) async {
    final db = await _db;
    await db.update(
      TableNames.feeds,
      feed.toMap(),
      where: 'id = ?',
      whereArgs: [feed.id],
    );
    FeedsChangedNotifier.instance.structureChanged();
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete(
      TableNames.feeds,
      where: 'id = ?',
      whereArgs: [id],
    );
    FeedsChangedNotifier.instance.structureChanged();
  }

  Future<void> updateFetchResult({
    required int feedId,
    required int? lastFetchedAt,
    required String? lastFetchError,
    required int consecutiveFailures,
    required bool isDead,
  }) async {
    final db = await _db;
    await db.update(
      TableNames.feeds,
      {
        'last_fetched_at': lastFetchedAt,
        'last_fetch_error': lastFetchError,
        'consecutive_failures': consecutiveFailures,
        'is_dead': isDead ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [feedId],
    );
  }

  Future<void> updateFaviconPath(int feedId, String path) async {
    final db = await _db;
    await db.update(
      TableNames.feeds,
      {'favicon_path': path},
      where: 'id = ?',
      whereArgs: [feedId],
    );
  }

  Future<Map<int, int>> getUnreadCounts() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT feed_id, COUNT(*) as count
      FROM ${TableNames.articles}
      WHERE is_read = 0 AND is_blocked = 0
      GROUP BY feed_id
    ''');
    return {
      for (final row in rows)
        row['feed_id'] as int: row['count'] as int,
    };
  }


  /// Moves [feed] into [folderId] and renumbers positions for
  /// [destinationOrder] — the destination folder's full feed list, in its
  /// final desired order, with [feed] already included at its drop index.
  /// Used for both a cross-category drag (folder_id changes) and a
  /// same-category reorder (folder_id is unchanged, only position moves).
  Future<void> moveToFolder(
    Feed feed,
    int folderId,
    List<Feed> destinationOrder,
  ) async {
    final db = await _db;
    final batch = db.batch();
    batch.update(
      TableNames.feeds,
      {'folder_id': folderId},
      where: 'id = ?',
      whereArgs: [feed.id],
    );
    for (int i = 0; i < destinationOrder.length; i++) {
      batch.update(
        TableNames.feeds,
        {'position': i},
        where: 'id = ?',
        whereArgs: [destinationOrder[i].id],
      );
    }
    await batch.commit(noResult: true);
    FeedsChangedNotifier.instance.structureChanged();
  }

}
