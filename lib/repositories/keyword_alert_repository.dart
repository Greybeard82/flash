import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/keyword_alert.dart';
import '../utils/keyword_matcher.dart';

class KeywordAlertRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  Future<List<KeywordAlert>> getAll() async {
    final db = await _db;
    final rows = await db.query(TableNames.keywordAlerts, orderBy: 'keyword ASC');
    return rows.map(KeywordAlert.fromMap).toList();
  }

  Future<KeywordAlert> insert(KeywordAlert kw) async {
    final db = await _db;
    final id = await db.insert(TableNames.keywordAlerts, kw.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return kw.copyWith(id: id);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete(TableNames.keywordAlerts, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setWholeWord(int id, bool wholeWord) async {
    final db = await _db;
    await db.update(TableNames.keywordAlerts, {'whole_word': wholeWord ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Checks title + description against a list of alerts.
  /// Returns the first matching [KeywordAlert], or null. Mirrors
  /// `KeywordRepository.findMatch` so the two systems never diverge on what
  /// "matches" means.
  static KeywordAlert? findMatch(
      String title, String? description, List<KeywordAlert> alerts) {
    if (alerts.isEmpty) return null;
    final haystack = KeywordMatcher.buildHaystack(title, description);
    for (final alert in alerts) {
      if (KeywordMatcher.matches(alert.keyword, haystack, wholeWord: alert.wholeWord)) {
        return alert;
      }
    }
    return null;
  }
}
