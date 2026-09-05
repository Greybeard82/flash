import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/keyword_matcher.dart';
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
      version: 16,
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
    await db.execute(SchemaStatements.createAlertMatches);
    await db.execute(SchemaStatements.createAlertMatchesUniqueIndex);
    await db.execute(SchemaStatements.createAlertMatchesKeywordIndex);
    await db.execute(SchemaStatements.createAlertMatchesMatchedAtIndex);
    await db.execute(SchemaStatements.createAlertNotificationIds);

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
    // `newVersion < 16` is what stops this destroying bookmarks. On a device
    // coming from v3–v14 both blocks run in one pass, and this one writes
    // `is_saved = 1` *and* `matched_alert_keyword` onto articles that were
    // never touched by any alert before — including ones the user bookmarked
    // by hand months ago. The v16 block below then runs
    // `is_saved = 0 WHERE matched_alert_keyword IS NOT NULL` over exactly that
    // freshly-invented set, and the hand-made bookmark is gone. The clear is
    // correct for a device that really ran v15 (there the auto-bookmark did
    // happen and is what it is undoing); it is pure data loss for a device
    // that skipped straight past it.
    //
    // Nothing is lost by skipping: v16's own re-scan covers the same ground
    // and covers it better — every matching keyword rather than first-match-
    // wins, written into `alert_matches` where retirement cannot reach it. The
    // block is kept, rather than deleted, because it is the record of what
    // v15 actually did to the devices that ran it, and a test migrating to
    // exactly 15 still needs to see that.
    if (oldVersion < 15 && newVersion < 16) {
      // v14's ALTER TABLE left matched_alert_keyword NULL on every article
      // that already existed — matching only ever ran at insert time, so
      // nothing had a chance to evaluate a row already in the table before
      // this. Re-run it once here, against every alert configured as of this
      // upgrade, same matching (and first-match-wins order) the live insert
      // path uses, and the same auto-bookmark fetchAndStore now applies to a
      // fresh match — see the note on ArticleRepository.retroactivelyMatchAlert
      // for why is_saved is what keeps a match from being deleted later.
      final alerts = await db.query(TableNames.keywordAlerts);
      if (alerts.isNotEmpty) {
        final unmatched = await db.query(
          TableNames.articles,
          columns: ['id', 'title', 'description'],
          where: 'matched_alert_keyword IS NULL',
        );
        for (final row in unmatched) {
          final haystack = KeywordMatcher.buildHaystack(
            row['title'] as String,
            row['description'] as String?,
          );
          for (final alert in alerts) {
            final keyword = alert['keyword'] as String;
            final wholeWord = (alert['whole_word'] as int) == 1;
            if (KeywordMatcher.matches(keyword, haystack, wholeWord: wholeWord)) {
              await db.update(
                TableNames.articles,
                {'matched_alert_keyword': keyword, 'is_saved': 1},
                where: 'id = ?',
                whereArgs: [row['id']],
              );
              break;
            }
          }
        }
      }
    }
    if (oldVersion < 16) {
      // An alert match stops being a column on the article and becomes a row
      // of its own — see SchemaStatements.createAlertMatches for why. As a
      // column it was destroyed by retirement, by cleanup and by the tombstone
      // system, and the `is_saved = 1` that held it on screen filled Bookmarks
      // with entries the user never saved.
      //
      // Every step below is written to be safe to run twice. sqflite runs the
      // upgrade inside a transaction, so a failure part-way rolls back and the
      // next open retries the whole block — against a database that may
      // already have the new tables, or may already have lost the old column.
      if (!await _tableExists(db, TableNames.alertMatches)) {
        await db.execute(SchemaStatements.createAlertMatches);
        await db.execute(SchemaStatements.createAlertMatchesUniqueIndex);
        await db.execute(SchemaStatements.createAlertMatchesKeywordIndex);
        await db.execute(SchemaStatements.createAlertMatchesMatchedAtIndex);
      }
      if (!await _tableExists(db, TableNames.alertNotificationIds)) {
        await db.execute(SchemaStatements.createAlertNotificationIds);
      }

      // Fetched once and reused for both the guard and the rebuild below, the
      // same way the v13 step does it.
      final cols = await db.rawQuery('PRAGMA table_info(${TableNames.articles})');
      final hadColumn = cols.any((c) => c['name'] == 'matched_alert_keyword');

      if (hadColumn) {
        // Every match v14/v15 recorded becomes a snapshot row. One statement
        // rather than a Dart loop: the join to feeds is the entire job, and
        // SQLite does it in a single pass with nothing to get out of step.
        //
        // matched_at takes fetched_at because it is the only honest answer
        // available for a row that predates this table — published_at would
        // sort a back-dated article to the bottom of a tab ordered by when the
        // user was told. is_blocked = 1 is excluded because the blocklist wins
        // over an alert everywhere now, which it did not before: the live
        // fetch path bailed out on a blocked article, but v15's own re-scan
        // wrote matched_alert_keyword regardless, so a blocked article can
        // arrive here already carrying a match it should never have had.
        //
        // The EXISTS guard is what stops this creating rows nothing can ever
        // remove. The column was never cleared when an alert was deleted, so a
        // user who ran "zelda" for a week and then deleted it still has
        // articles stamped 'zelda'. Without the guard those become permanent
        // alert_matches rows, and only three things delete a match: the user
        // bins it, its keyword is deleted, or its keyword is edited. The last
        // two cannot fire for a keyword that is already gone, so the Alerts tab
        // would show a 'zelda' chip the user cannot find in Manage keywords and
        // cannot clear except by binning every article one at a time.
        //
        // Compared with `=` rather than a case-insensitive collation on
        // purpose: the column was written verbatim from a keyword_alerts row,
        // so exact equality is precisely the question being asked — is there
        // still a keyword this row can be managed through?
        //
        // A keyword that still exists but whose whole_word rule was tightened
        // after the match is deliberately kept. It stays attributable to a live
        // keyword, so deleting or editing that keyword clears it, and dropping
        // it would throw away an alert that genuinely fired at the time.
        await db.execute('''
          INSERT OR IGNORE INTO ${TableNames.alertMatches}
            (feed_id, guid, keyword, title, url, description, thumbnail_url,
             thumbnail_path, feed_title, feed_favicon_path, folder_id,
             published_at, matched_at, is_read)
          SELECT a.feed_id, a.guid, a.matched_alert_keyword, a.title, a.url,
                 a.description, a.thumbnail_url, a.thumbnail_path,
                 f.title, f.favicon_path, f.folder_id, a.published_at,
                 a.fetched_at, a.is_read
          FROM ${TableNames.articles} a
          JOIN ${TableNames.feeds} f ON a.feed_id = f.id
          WHERE a.matched_alert_keyword IS NOT NULL AND a.is_blocked = 0
            AND EXISTS (
              SELECT 1 FROM ${TableNames.keywordAlerts} ka
              WHERE ka.keyword = a.matched_alert_keyword
            )
        ''');
      }

      // Then re-scan everything, because the column could only ever hold one
      // answer. v14 matched at insert time and stopped at the first hit, so an
      // article about Zelda and Mario was filed under whichever alert was
      // configured first and the other keyword's panel stayed permanently
      // empty for it. The attribution is not recoverable from anywhere except
      // a fresh pass over the stored articles, and this is the only chance to
      // take it. Read articles are included: an alert the user already read is
      // still an alert they asked for, and it belongs in the tab.
      //
      // Deliberately no `break` here — that is the whole point of the pass.
      // The v15 block above keeps its break because it is the record of what
      // v15 actually did.
      final alerts = await db.query(TableNames.keywordAlerts);
      if (alerts.isNotEmpty) {
        final rows = await db.rawQuery('''
          SELECT a.feed_id, a.guid, a.title, a.url, a.description,
                 a.thumbnail_url, a.thumbnail_path, a.published_at,
                 a.fetched_at, a.is_read, f.title AS feed_title,
                 f.favicon_path AS feed_favicon_path, f.folder_id AS folder_id
          FROM ${TableNames.articles} a
          JOIN ${TableNames.feeds} f ON a.feed_id = f.id
          WHERE a.is_blocked = 0
        ''');
        for (final row in rows) {
          final haystack = KeywordMatcher.buildHaystack(
            row['title'] as String,
            row['description'] as String?,
          );
          for (final alert in alerts) {
            final keyword = alert['keyword'] as String;
            final wholeWord = (alert['whole_word'] as int) == 1;
            if (KeywordMatcher.matches(keyword, haystack, wholeWord: wholeWord)) {
              await db.insert(
                TableNames.alertMatches,
                {
                  'feed_id': row['feed_id'],
                  'guid': row['guid'],
                  'keyword': keyword,
                  'title': row['title'],
                  'url': row['url'],
                  'description': row['description'],
                  'thumbnail_url': row['thumbnail_url'],
                  'thumbnail_path': row['thumbnail_path'],
                  'feed_title': row['feed_title'],
                  'feed_favicon_path': row['feed_favicon_path'],
                  'folder_id': row['folder_id'],
                  'published_at': row['published_at'],
                  'matched_at': row['fetched_at'],
                  'is_read': row['is_read'],
                },
                // The unique index carries the dedup, so the backfill above
                // and a second run of this pass both cost nothing.
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        }
      }

      if (hadColumn) {
        // Only for a database that actually ran v15.
        //
        // v15 is the version that introduced the auto-bookmark: at v14 the
        // fetch path wrote `matched_alert_keyword` and nothing else, and
        // `is_saved` was never touched by the alert system at all (compare
        // d51318b:lib/services/rss_service.dart, which copies only
        // matchedAlertKeyword, with 392d47d, which adds `isSaved: true`).
        //
        // So on a device coming from v14, every `is_saved = 1` sitting on a
        // matched article is a bookmark the user made by hand, and clearing it
        // is pure data loss with nothing to justify it. Devices below v14
        // never had the column, and the v15 step that would have invented
        // values for them is skipped — so this reaches exactly the databases
        // where the auto-bookmark really happened.
        //
        // For those, every previously-matched article loses its bookmark,
        // including one the user bookmarked on purpose. That is a deliberate,
        // accepted trade-off: is_saved is a single flag with no provenance, so
        // nothing distinguishes an auto-bookmark the alert system forced on
        // from one the user tapped, and the alternative is leaving thousands
        // of phantom entries in a tab whose entire meaning is "I chose this".
        // The article itself is not lost — it is in the Alerts tab, unless its
        // keyword had already been deleted, in which case the user had
        // already said they were not interested.
        if (oldVersion >= 15) {
          await db.execute(
            'UPDATE ${TableNames.articles} SET is_saved = 0 '
            'WHERE matched_alert_keyword IS NOT NULL',
          );
        }
        await _dropMatchedAlertKeywordByRebuild(db, cols);
      }
    }
  }

  Future<bool> _tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    );
    return rows.isNotEmpty;
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

  /// Removes `matched_alert_keyword` by rebuilding the table.
  ///
  /// Same route, and the same reasons, as [_dropReadAtByRebuild] — its comment
  /// explains why `ALTER TABLE ... DROP COLUMN` cannot be used and why foreign
  /// keys being off here is load-bearing rather than tidy. This one drops the
  /// column that used to hold an alert match. The match is a row in
  /// `alert_matches` now, and a column nothing writes and nothing reads is an
  /// invitation to write code that trusts it — this one especially, since it
  /// would look authoritative while recording at most one of an article's
  /// keywords.
  Future<void> _dropMatchedAlertKeywordByRebuild(
      Database db, List<Map<String, Object?>> cols) async {
    // Columns to carry over: everything the old table has except
    // matched_alert_keyword, intersected with what the new table declares.
    // Enumerated rather than `SELECT *` so the copy cannot silently depend on
    // column order — and derived from the live table rather than hardcoded
    // because a database upgrading from v1 may predate columns the v16 schema
    // takes for granted.
    const newColumns = {
      'id', 'feed_id', 'guid', 'title', 'url', 'description', 'thumbnail_url',
      'thumbnail_path', 'published_at', 'fetched_at', 'is_read', 'is_blocked',
      'is_saved', 'blocked_keyword',
    };
    final carried = [
      for (final c in cols)
        if (c['name'] != 'matched_alert_keyword' &&
            newColumns.contains(c['name']))
          c['name'] as String,
    ];
    final list = carried.join(', ');

    await db.execute(SchemaStatements.createArticlesRebuildV16);
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

    // Throwing here aborts the migration and rolls the whole transaction back,
    // which is the right outcome: a database with dangling references is worse
    // than one still on the old schema.
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError(
        'v16 articles rebuild left ${violations.length} foreign key '
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
    await _onUpgrade(db, fromVersion, 16);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
