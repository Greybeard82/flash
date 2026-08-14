import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'schema.dart';

class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;
  static String? _testPath;

  AppDatabase._();

  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  /// For unit tests only — opens a fresh in-memory DB for each test.
  /// Call in setUp; call close() in tearDown to free the connection.
  @visibleForTesting
  static void useForTesting() {
    _testPath = inMemoryDatabasePath; // ':memory:'
    _instance = null;
    _db = null;
  }

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (_testPath != null) {
      path = _testPath!;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'flash.db');
    }

    return openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: _testPath == null, // fresh DB per test when testing
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
    if (oldVersion < 5) {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_articles_guid_feed ON articles(feed_id, guid)',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES ('schema_version', '3', $now)",
      );
    }
    if (oldVersion < 6) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) VALUES ('cleanup_age_days', '7', $now)",
      );
    }
    if (oldVersion < 7) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) VALUES ('newspaper_mode', 'false', $now)",
      );
    }
    if (oldVersion < 8) {
      // Reader mode removed: purge its settings and per-domain compat cache.
      await db.execute(
        "DELETE FROM settings WHERE key IN ('reader_mode', 'article_font_size') "
        "OR key LIKE 'reader_compat_%'",
      );
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
