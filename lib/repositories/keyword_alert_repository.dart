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

  Future<void> setKeyword(int id, String keyword) async {
    final db = await _db;
    await db.update(TableNames.keywordAlerts, {'keyword': keyword},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Checks title + description against a list of alerts and returns **every**
  /// [KeywordAlert] that matched, in the order [alerts] were given.
  ///
  /// This deliberately no longer mirrors `KeywordRepository.findMatch`, which
  /// still stops at the first hit. The two only ever agreed by accident: the
  /// blocklist has one question to answer — whether to hide the article — and
  /// a second matching keyword tells it nothing it does not already know. An
  /// alert has to say *which* keywords fired, because the card carries a badge
  /// for each and each keyword's panel has to list it. Under first-match-wins
  /// an article hitting two alerts was filed under one of them and the other
  /// panel stayed wrongly empty.
  ///
  /// [KeywordMatcher] is still shared, so the two systems continue to agree on
  /// what "matches" means at the character level; they now differ only on how
  /// many answers they need.
  static List<KeywordAlert> findAllMatches(
      String title, String? description, List<KeywordAlert> alerts) {
    if (alerts.isEmpty) return const [];
    final haystack = KeywordMatcher.buildHaystack(title, description);
    return [
      for (final alert in alerts)
        if (KeywordMatcher.matches(alert.keyword, haystack,
            wholeWord: alert.wholeWord))
          alert,
    ];
  }
}
