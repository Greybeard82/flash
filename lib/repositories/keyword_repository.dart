import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/keyword_block.dart';

class KeywordRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<List<KeywordBlock>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      TableNames.keywordBlocklist,
      orderBy: 'keyword ASC',
    );
    return rows.map(KeywordBlock.fromMap).toList();
  }

  Future<KeywordBlock> insert(KeywordBlock kw) async {
    final db = await _db;
    final id = await db.insert(TableNames.keywordBlocklist, kw.toMap());
    return kw.copyWith(id: id);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete(
      TableNames.keywordBlocklist,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setWholeWord(int id, bool wholeWord) async {
    final db = await _db;
    await db.update(
      TableNames.keywordBlocklist,
      {'whole_word': wholeWord ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Checks title + description against a list of keywords.
  /// Returns the first matching KeywordBlock, or null.
  static KeywordBlock? findMatch(
      String title, String? description, List<KeywordBlock> keywords) {
    if (keywords.isEmpty) return null;
    final haystack =
        '${title.toLowerCase()} ${(description ?? '').toLowerCase()}';
    for (final kw in keywords) {
      final needle = kw.keyword.toLowerCase();
      if (kw.wholeWord) {
        final pattern = RegExp(
          r'\b' + RegExp.escape(needle) + r'\b',
          caseSensitive: false,
        );
        if (pattern.hasMatch(haystack)) return kw;
      } else {
        if (haystack.contains(needle)) return kw;
      }
    }
    return null;
  }
}
