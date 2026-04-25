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

  /// Returns the keywords that match any article title/description in [articles].
  /// [articles] is a list of (title, description?) pairs from newly fetched articles.
  static List<String> findHits(
    List<({String title, String? description})> articles,
    List<KeywordAlert> alerts,
  ) {
    final hits = <String>{};
    for (final alert in alerts) {
      for (final article in articles) {
        final haystack = KeywordMatcher.buildHaystack(article.title, article.description);
        if (KeywordMatcher.matches(alert.keyword, haystack, wholeWord: alert.wholeWord)) {
          hits.add(alert.keyword);
          break;
        }
      }
    }
    return hits.toList();
  }
}
