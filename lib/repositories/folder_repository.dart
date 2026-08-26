import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/folder.dart';
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

  Future<Folder?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.folders,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Folder.fromMap(rows.first);
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
