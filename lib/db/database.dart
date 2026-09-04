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
      version: 14,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: _testPath == null, // fresh DB per test when testing
      // Foreign keys are OFF for the duration of open, and switched back on in
      // onOpen once any migration has finished.
      //
      // This is not a preference, it is the only place the pragma can be set.
      // The v13 migration rebuilds `articles`, and `article_summaries` holds
      // `article_id REFERENCES articles(id) ON DELETE CASCADE` — so dropping
      // the old table with enforcement on would cascade every summary row
      // away, and the later RENAME would repoint that clause at a table that
      // is about to disappear. `PRAGMA foreign_keys` is a silent no-op inside
      // a transaction, and sqflite runs onCreate/onUpgrade inside one, so
      // issuing it there would appear to work and do nothing.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        if (kDebugMode) {
          // The device's SQLite version decides which DDL is even parseable.
          // `DROP COLUMN` needs 3.35 and min SDK 26 ships ~3.18, and there is
          // no other way to read this off a phone — sqlite3 is not on the
          // device and the host's version says nothing about it.
          final v = await db.rawQuery('SELECT sqlite_version() AS v');
          final fk = await db.rawQuery('PRAGMA foreign_keys');
          debugPrintSynchronously('[SQLITE] version=${v.first['v']} '
              'foreign_keys=${fk.first.values.first}');
        }
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
    await db.execute(SchemaStatements.createDeletedArticles);
    await db.execute(SchemaStatements.createDeletedArticlesGuidIndex);
    await db.execute(SchemaStatements.createDeletedArticlesAgeIndex);

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
    if (oldVersion < 9) {
      // The 'schema_version' settings row duplicated PRAGMA user_version and
      // had drifted permanently to '3' (seeded at that value, and rewritten
      // to it by the oldVersion < 5 step above). Nothing ever read it, so it
      // was a second, always-wrong answer to "what schema is this DB on".
      // PRAGMA user_version is now the only source of truth.
      await db.execute("DELETE FROM settings WHERE key = 'schema_version'");
    }
    if (oldVersion < 10) {
      // End-of-feed auto mark-as-read became configurable. Seed the previous
      // hardcoded behaviour (on, 5s) so upgrading users see no change.
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) "
        "VALUES ('auto_mark_read_at_bottom', 'true', $now)",
      );
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) "
        "VALUES ('auto_mark_read_at_bottom_seconds', '5', $now)",
      );
    }
    if (oldVersion < 11) {
      // Read visibility moved from an in-memory session set to a persisted
      // timestamp, so "Show read" can offer a 48-hour restore window that
      // survives a restart.
      final cols = await db.rawQuery('PRAGMA table_info(${TableNames.articles})');
      if (!cols.any((c) => c['name'] == 'read_at')) {
        await db.execute(
          'ALTER TABLE ${TableNames.articles} ADD COLUMN read_at INTEGER',
        );
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_articles_read_at ON articles(read_at)',
      );
      // Articles already read before this migration keep read_at NULL and so
      // fall outside every buffer window. That is intended: there is no
      // honest timestamp to give them, and pretending they were read "now"
      // would dump the entire backlog into the list on first launch.
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) "
        "VALUES ('show_read', 'true', $now)",
      );
    }
    if (oldVersion < 12) {
      // The Anthropic / Claude Haiku summary path was specified but never
      // built: no client, no key entry, nothing that ever read this flag.
      // Summaries run on-device through Gemini Nano. Same treatment as the
      // reader-mode keys in the v8 step — a settings row nothing consults is
      // a standing invitation to write code that trusts it.
      await db.execute(
        "DELETE FROM settings WHERE key = 'anthropic_api_key_set'",
      );
    }
    if (oldVersion < 13) {
      // Retirement replaces the 48-hour show-read window. read_at existed only
      // to answer "is this recent enough to un-hide", and nothing un-hides any
      // more — a retired article is gone, not hidden.
      await db.execute(SchemaStatements.createDeletedArticles);
      await db.execute(SchemaStatements.createDeletedArticlesGuidIndex);
      await db.execute(SchemaStatements.createDeletedArticlesAgeIndex);

      await db.execute('DROP INDEX IF EXISTS idx_articles_read_at');
      final cols = await db.rawQuery('PRAGMA table_info(${TableNames.articles})');
      if (cols.any((c) => c['name'] == 'read_at')) {
        await _dropReadAtByRebuild(db, cols);
      }

      // Articles already marked read are deliberately NOT retired here. They
      // are read rows with no tombstone; the first refresh retires them
      // through the normal path. A migration that silently destroys several
      // hundred articles on first launch is indistinguishable from a bug.
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) "
        "VALUES ('mark_all_read_confirm', 'true', $now)",
      );
    }
    if (oldVersion < 14) {
      // Alerts get the same shape blocklist already has: a column recording
      // which alert (if any) a genuinely-new article matched, so the Keyword
      // Alerts panel has something to list and a repeat notification isn't
      // possible for an article that already matched on a prior fetch.
      final cols = await db.rawQuery('PRAGMA table_info(${TableNames.articles})');
      if (!cols.any((c) => c['name'] == 'matched_alert_keyword')) {
        await db.execute(
          'ALTER TABLE ${TableNames.articles} ADD COLUMN matched_alert_keyword TEXT',
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.execute(
        "INSERT OR IGNORE INTO settings (key, value, updated_at) "
        "VALUES ('color_palette', 'orange', $now)",
      );
    }
  }

  /// Removes `read_at` by rebuilding the table.
  ///
  /// `ALTER TABLE ... DROP COLUMN` needs SQLite 3.35 (March 2021). Android 12
  /// ships 3.32 and the PRD claims min SDK 26, whose SQLite is older still, so
  /// the direct statement threw `near "DROP": syntax error` inside the
  /// migration transaction — which failed the open, killed `main()`, and left
  /// a permanently blank app with no recovery but clearing app data. Since the
  /// backup format covers neither articles nor read state nor bookmarks, that
  /// meant losing the library.
  ///
  /// The rebuild below is the pre-3.35 idiom and works on every version, so
  /// there is deliberately no branch on `sqlite_version()`: one code path is
  /// one path to test, and the version-specific one would be the path that
  /// never ran on the maintainer's device.
  ///
  /// Foreign keys are already OFF here — see the `onConfigure` note in
  /// [_initDatabase]. That is load-bearing, not hygiene.
  Future<void> _dropReadAtByRebuild(
      Database db, List<Map<String, Object?>> cols) async {
    // Columns to carry over: everything the old table has except read_at,
    // intersected with what the new table declares. Enumerated rather than
    // `SELECT *` so the copy cannot silently depend on column order — and
    // derived from the live table rather than hardcoded because a database
    // upgrading from v1 may predate columns the v13 schema takes for granted.
    const newColumns = {
      'id', 'feed_id', 'guid', 'title', 'url', 'description', 'thumbnail_url',
      'thumbnail_path', 'published_at', 'fetched_at', 'is_read', 'is_blocked',
      'is_saved', 'blocked_keyword',
    };
    final carried = [
      for (final c in cols)
        if (c['name'] != 'read_at' && newColumns.contains(c['name']))
          c['name'] as String,
    ];
    final list = carried.join(', ');

    await db.execute(SchemaStatements.createArticlesRebuildV13);
    await db.execute(
      'INSERT INTO articles_new ($list) SELECT $list FROM ${TableNames.articles}',
    );
    await db.execute('DROP TABLE ${TableNames.articles}');
    await db.execute('ALTER TABLE articles_new RENAME TO ${TableNames.articles}');

    // DROP TABLE takes every index on it with it, silently. Nothing complains
    // until a query is merely slow, or a duplicate article appears because the
    // UNIQUE(feed_id, guid) index that dedup depends on is no longer there.
    await db.execute(SchemaStatements.createArticlesGuidIndex);
    await db.execute(SchemaStatements.createArticlesFeedIdIndex);
    await db.execute(SchemaStatements.createArticlesIsReadIndex);
    await db.execute(SchemaStatements.createArticlesIsBlockedIndex);
    await db.execute(SchemaStatements.createArticlesPublishedAtIndex);
    await db.execute(SchemaStatements.createArticlesReadPublishedIndex);
    await db.execute(SchemaStatements.createArticlesFeedReadPublishedIndex);
    // idx_articles_read_at is deliberately not recreated — its column is gone.

    // Throwing here aborts the migration and rolls the whole transaction back,
    // which is the right outcome: a database with dangling references is worse
    // than one still on the old schema.
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError(
        'v13 articles rebuild left ${violations.length} foreign key '
        'violation(s); migration aborted and rolled back.',
      );
    }
  }

  /// Runs the real [_onUpgrade] path against the open database as though it
  /// were coming from [fromVersion]. Migrations are otherwise only reachable
  /// via openDatabase's own version bookkeeping, which makes them impossible
  /// to exercise in a test — and untested migrations are how the stale
  /// `schema_version` row survived five schema bumps unnoticed.
  @visibleForTesting
  Future<void> migrateForTesting({required int fromVersion}) async {
    final db = await database;
    await _onUpgrade(db, fromVersion, 14);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
