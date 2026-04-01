import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/settings.dart';

class SettingsRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<AppSettings> getAll() async {
    final db = await _db;
    final rows = await db.query(TableNames.settings);
    final map = <String, String>{
      for (final row in rows)
        row['key'] as String: row['value'] as String,
    };
    return AppSettings.fromMap(map);
  }

  Future<String?> get(String key) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.settings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      TableNames.settings,
      {'key': key, 'value': value, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setMany(Map<String, String> values) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final entry in values.entries) {
      batch.insert(
        TableNames.settings,
        {'key': entry.key, 'value': entry.value, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
