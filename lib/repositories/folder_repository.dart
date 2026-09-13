import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/folder.dart';
import '../theme/category_colors.dart' show nextCategoryColorIndex;
import '../services/feeds_changed_notifier.dart';

class FolderRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<List<Folder>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      TableNames.folders,
      orderBy: 'position ASC',
    );
    return rows.map(Folder.fromMap).toList();
  }

  /// The hue a new category should take: the lowest of the six nobody is
  /// using, so the first six categories are six different colours rather than
  /// a run of the same one.
  ///
  /// Read at creation time and then stored, never re-derived — a category's
  /// colour must not change because a different one was deleted.
  Future<int> nextColorIndex() async {
    final existing = await getAll();
    return nextCategoryColorIndex(existing.map((f) => f.colorIndex));
  }

  Future<Folder> insert(Folder folder) async {
    final db = await _db;
    final id = await db.insert(TableNames.folders, folder.toMap());
    FeedsChangedNotifier.instance.structureChanged();
    return folder.copyWith(id: id);
  }

  Future<void> update(Folder folder) async {
    final db = await _db;
    await db.update(
      TableNames.folders,
      folder.toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
    FeedsChangedNotifier.instance.structureChanged();
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete(
      TableNames.folders,
      where: 'id = ?',
      whereArgs: [id],
    );
    FeedsChangedNotifier.instance.structureChanged();
  }

  Future<void> reorder(List<Folder> folders) async {
    final db = await _db;
    final batch = db.batch();
    for (int i = 0; i < folders.length; i++) {
      batch.update(
        TableNames.folders,
        {'position': i},
        where: 'id = ?',
        whereArgs: [folders[i].id],
      );
    }
    await batch.commit(noResult: true);
    FeedsChangedNotifier.instance.structureChanged();
  }

  Future<int> getNextPosition() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM ${TableNames.folders}',
    );
    return result.first['next'] as int;
  }
}
