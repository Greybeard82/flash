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
      version: 4,
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
    await db.execute(SchemaStatements.createArticlesPublishedAtIndex);
    await db.execute(SchemaStatements.createArticlesReadPublishedIndex);
    await db.execute(SchemaStatements.createArticlesFeedReadPublishedIndex);
    await db.execute(SchemaStatements.createKeywordBlocklist);
    await db.execute(SchemaStatements.createKeywordAlerts);
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

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final cols = await db.rawQuery('PRAGMA table_info(${TableNames.articles})');
      final hasIsSaved = cols.any((c) => c['name'] == 'is_saved');
      if (!hasIsSaved) {
        await db.execute(
          'ALTER TABLE ${TableNames.articles} ADD COLUMN is_saved INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 3) {
      await db.execute(SchemaStatements.createKeywordAlerts);
    }
    if (oldVersion < 4) {
      await db.execute(SchemaStatements.createArticlesReadPublishedIndex);
      await db.execute(SchemaStatements.createArticlesFeedReadPublishedIndex);
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
