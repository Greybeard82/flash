import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'schema.dart';

class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;

  AppDatabase._();

  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'flash.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.execute(SchemaStatements.createFolders);
    await db.execute(SchemaStatements.createFeeds);
    await db.execute(SchemaStatements.createFeedsIndex);
    await db.execute(SchemaStatements.createArticles);
    await db.execute(SchemaStatements.createArticlesGuidIndex);
    await db.execute(SchemaStatements.createArticlesFeedIdIndex);
    await db.execute(SchemaStatements.createArticlesIsReadIndex);
    await db.execute(SchemaStatements.createArticlesIsBlockedIndex);
    await db.execute(SchemaStatements.createArticlesIsOpinionIndex);
    await db.execute(SchemaStatements.createArticlesPublishedAtIndex);
    await db.execute(SchemaStatements.createKeywordBlocklist);
    await db.execute(SchemaStatements.createOpinionPatterns);
    await db.execute(SchemaStatements.createArticleSummaries);
    await db.execute(SchemaStatements.createSettings);

    // Seed default settings
    final batch = db.batch();
    for (final s in defaultSettings) {
      batch.insert(TableNames.settings, {
        'key': s['key'],
        'value': s['value'],
        'updated_at': now,
      });
    }

    // Seed default opinion patterns
    for (final p in defaultOpinionPatterns) {
      batch.insert(TableNames.opinionPatterns, {
        'pattern': p['pattern'],
        'match_field': p['match_field'],
        'is_default': 1,
        'created_at': now,
      });
    }

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
    // if (oldVersion < 2) { ... }
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
