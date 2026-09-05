class TableNames {
  static const String folders = 'folders';
  static const String feeds = 'feeds';
  static const String articles = 'articles';
  static const String keywordBlocklist = 'keyword_blocklist';
  static const String keywordAlerts = 'keyword_alerts';
  static const String articleSummaries = 'article_summaries';
  static const String settings = 'settings';
  static const String deletedArticles = 'deleted_articles';
  static const String alertMatches = 'alert_matches';
  static const String alertNotificationIds = 'alert_notification_ids';
}

class SchemaStatements {
  static const String createFolders = '''
    CREATE TABLE folders (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL,
      position   INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
  ''';

  static const String createFeeds = '''
    CREATE TABLE feeds (
      id                   INTEGER PRIMARY KEY AUTOINCREMENT,
      folder_id            INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      title                TEXT    NOT NULL,
      url                  TEXT    NOT NULL UNIQUE,
      site_url             TEXT,
      favicon_path         TEXT,
      description          TEXT,
      article_limit        INTEGER,
      last_fetched_at      INTEGER,
      last_fetch_error     TEXT,
      consecutive_failures INTEGER NOT NULL DEFAULT 0,
      is_dead              INTEGER NOT NULL DEFAULT 0 CHECK(is_dead IN (0,1)),
      position             INTEGER NOT NULL DEFAULT 0,
      created_at           INTEGER NOT NULL
    )
  ''';

  static const String createFeedsIndex = '''
    CREATE INDEX idx_feeds_folder_id ON feeds(folder_id)
  ''';

  static const String createArticles = '''
    CREATE TABLE articles (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      feed_id        INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
      guid           TEXT    NOT NULL,
      title          TEXT    NOT NULL,
      url            TEXT    NOT NULL,
      description    TEXT,
      thumbnail_url  TEXT,
      thumbnail_path TEXT,
      published_at   INTEGER,
      fetched_at     INTEGER NOT NULL,
      is_read        INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1)),
      is_blocked     INTEGER NOT NULL DEFAULT 0 CHECK(is_blocked IN (0,1)),
      is_saved       INTEGER NOT NULL DEFAULT 0 CHECK(is_saved IN (0,1)),
      blocked_keyword TEXT
    )
  ''';

  /// The v13 `articles` table under a temporary name, for the v13 migration's
  /// table rebuild.
  ///
  /// Deliberately spelled out rather than string-substituted from
  /// [createArticles]: this is the statement that decides whether a user's
  /// library survives an upgrade, and it should be readable on its own. The
  /// two are pinned together by a test that compares the column set of a
  /// migrated database against a freshly created one, so drift fails the
  /// build rather than silently shipping.
  static const String createArticlesRebuildV13 = '''
    CREATE TABLE articles_new (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      feed_id        INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
      guid           TEXT    NOT NULL,
      title          TEXT    NOT NULL,
      url            TEXT    NOT NULL,
      description    TEXT,
      thumbnail_url  TEXT,
      thumbnail_path TEXT,
      published_at   INTEGER,
      fetched_at     INTEGER NOT NULL,
      is_read        INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1)),
      is_blocked     INTEGER NOT NULL DEFAULT 0 CHECK(is_blocked IN (0,1)),
      is_saved       INTEGER NOT NULL DEFAULT 0 CHECK(is_saved IN (0,1)),
      blocked_keyword TEXT
    )
  ''';

  /// The v16 `articles` table under a temporary name, for the v16 migration's
  /// table rebuild.
  ///
  /// Spelled out for the same reason [createArticlesRebuildV13] is, and
  /// deliberately not reusing it even though the two currently agree
  /// character for character: that constant is pinned to the shape v13
  /// actually produced by a test, so the day a column is added it stops
  /// describing the live table and starts describing history. Substituting it
  /// here would silently rebuild a user's library into the wrong shape.
  ///
  /// The difference from [createArticles] is the absence of
  /// `matched_alert_keyword`, which v16 drops — the match now lives in
  /// [createAlertMatches]. A test compares a migrated database's column list
  /// against a freshly created one, so drift between the two fails the build.
  static const String createArticlesRebuildV16 = '''
    CREATE TABLE articles_new (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      feed_id        INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
      guid           TEXT    NOT NULL,
      title          TEXT    NOT NULL,
      url            TEXT    NOT NULL,
      description    TEXT,
      thumbnail_url  TEXT,
      thumbnail_path TEXT,
      published_at   INTEGER,
      fetched_at     INTEGER NOT NULL,
      is_read        INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1)),
      is_blocked     INTEGER NOT NULL DEFAULT 0 CHECK(is_blocked IN (0,1)),
      is_saved       INTEGER NOT NULL DEFAULT 0 CHECK(is_saved IN (0,1)),
      blocked_keyword TEXT
    )
  ''';

  static const String createArticlesGuidIndex = '''
    CREATE UNIQUE INDEX idx_articles_guid_feed ON articles(feed_id, guid)
  ''';
  static const String createArticlesFeedIdIndex = '''
    CREATE INDEX idx_articles_feed_id ON articles(feed_id)
  ''';
  static const String createArticlesIsReadIndex = '''
    CREATE INDEX idx_articles_is_read ON articles(is_read)
  ''';
  static const String createArticlesIsBlockedIndex = '''
    CREATE INDEX idx_articles_is_blocked ON articles(is_blocked)
  ''';
  static const String createArticlesPublishedAtIndex = '''
    CREATE INDEX idx_articles_published_at ON articles(published_at DESC)
  ''';

  // Composite indexes for common filter+sort combinations
  static const String createArticlesReadPublishedIndex = '''
    CREATE INDEX idx_articles_read_published ON articles(is_read, published_at DESC)
  ''';
  static const String createArticlesFeedReadPublishedIndex = '''
    CREATE INDEX idx_articles_feed_read_published ON articles(feed_id, is_read, published_at DESC)
  ''';

  static const String createKeywordBlocklist = '''
    CREATE TABLE keyword_blocklist (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      keyword    TEXT    NOT NULL UNIQUE COLLATE NOCASE,
      whole_word INTEGER NOT NULL DEFAULT 0 CHECK(whole_word IN (0,1)),
      created_at INTEGER NOT NULL
    )
  ''';

  static const String createKeywordAlerts = '''
    CREATE TABLE keyword_alerts (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      keyword    TEXT    NOT NULL UNIQUE,
      whole_word INTEGER NOT NULL DEFAULT 0 CHECK(whole_word IN (0,1)),
      created_at INTEGER NOT NULL
    )
  ''';

  /// One alert match, as a row of its own rather than a column on the article
  /// it arrived on.
  ///
  /// `articles.matched_alert_keyword` gave a match no existence apart from the
  /// article row, so everything that removes an article removed the alert with
  /// it: retirement deleted the row, cleanup deleted the row on age, and the
  /// tombstone written on the way out stopped the next refresh bringing it
  /// back. The thing the user explicitly asked to be told about was the thing
  /// that quietly deleted itself. The interim patch — forcing `is_saved = 1`
  /// on every match — kept it on screen only by filing it in Bookmarks next to
  /// deliberately saved articles, indistinguishable from them, and one
  /// un-bookmark away from deletion.
  ///
  /// So every field the Alerts card renders is copied in here at match time.
  /// This is a snapshot, not a view: it has to keep rendering after the
  /// article row is gone and after the feed is gone too, which is why
  /// `feed_id` carries NO foreign key and `folder_id` is a point-in-time copy
  /// rather than a live lookup. A stale `folder_id` naming a folder that no
  /// longer exists must read as "no folder", never as a crash or a cascade.
  /// [createDeletedArticles] is the precedent: it outlives the article it
  /// names for exactly the same reason.
  ///
  /// UNIQUE(feed_id, guid, keyword) is the whole of the dedup story. It makes
  /// INSERT OR IGNORE the only write the match path needs, so a re-seen
  /// article cannot add a second copy or notify twice, and an article hitting
  /// three keywords is three rows — the attribution first-match-wins used to
  /// throw away.
  static const String createAlertMatches = '''
    CREATE TABLE alert_matches (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      feed_id           INTEGER NOT NULL,
      guid              TEXT    NOT NULL,
      keyword           TEXT    NOT NULL,
      title             TEXT    NOT NULL,
      url               TEXT    NOT NULL,
      description       TEXT,
      thumbnail_url     TEXT,
      thumbnail_path    TEXT,
      feed_title        TEXT,
      feed_favicon_path TEXT,
      folder_id         INTEGER,
      published_at      INTEGER,
      matched_at        INTEGER NOT NULL,
      is_read           INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1))
    )
  ''';

  static const String createAlertMatchesUniqueIndex = '''
    CREATE UNIQUE INDEX idx_alert_matches_unique
      ON alert_matches(feed_id, guid, keyword)
  ''';

  static const String createAlertMatchesKeywordIndex = '''
    CREATE INDEX idx_alert_matches_keyword ON alert_matches(keyword)
  ''';

  static const String createAlertMatchesMatchedAtIndex = '''
    CREATE INDEX idx_alert_matches_matched_at ON alert_matches(matched_at DESC)
  ''';

  /// A stable notification id per set of keywords, allocated by rowid.
  ///
  /// Every alert notification used to be posted under the hardcoded id 2, so
  /// each new alert replaced the previous one in the shade and a user who was
  /// away for an hour found a single notification standing for everything they
  /// had missed. The id has to be stable across posts for one keyword set —
  /// otherwise the same alert stacks up again on every refresh — and different
  /// between sets, which is more state than a pure function can carry.
  ///
  /// `key` is the sorted keywords joined by NUL, a character no keyword can
  /// contain, so one set cannot forge another's id. Rows are never deleted:
  /// re-adding a keyword should reuse the id it had, not consume a new one.
  static const String createAlertNotificationIds = '''
    CREATE TABLE alert_notification_ids (
      id  INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT NOT NULL UNIQUE
    )
  ''';

  static const String createArticleSummaries = '''
    CREATE TABLE article_summaries (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      article_id   INTEGER NOT NULL UNIQUE REFERENCES articles(id) ON DELETE CASCADE,
      summary      TEXT    NOT NULL,
      model        TEXT    NOT NULL,
      generated_at INTEGER NOT NULL
    )
  ''';

  /// Guids the user has retired, so a re-fetch cannot resurrect them.
  ///
  /// Article rows used to survive being read, which is what made
  /// INSERT OR IGNORE on (feed_id, guid) a working dedup. Retirement deletes
  /// the row, taking the guid with it — and the article is still in the feed's
  /// XML and still inside the fetch window, so without this table the next
  /// refresh re-inserts everything the user just cleared.
  static const String createDeletedArticles = '''
    CREATE TABLE IF NOT EXISTS deleted_articles (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      feed_id    INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
      guid       TEXT    NOT NULL,
      deleted_at INTEGER NOT NULL
    )
  ''';

  static const String createDeletedArticlesGuidIndex = '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_deleted_articles_guid_feed
      ON deleted_articles(feed_id, guid)
  ''';

  static const String createDeletedArticlesAgeIndex = '''
    CREATE INDEX IF NOT EXISTS idx_deleted_articles_deleted_at
      ON deleted_articles(deleted_at)
  ''';

  static const String createSettings = '''
    CREATE TABLE settings (
      key        TEXT PRIMARY KEY,
      value      TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

}

// Default seeded settings
const List<Map<String, dynamic>> defaultSettings = [
  {'key': 'theme', 'value': 'system'},
  {'key': 'refresh_interval_minutes', 'value': '30'},
  {'key': 'article_limit', 'value': '100'},
  {'key': 'mark_read_on_scroll', 'value': 'true'},
  {'key': 'drive_backup_enabled', 'value': 'false'},
  {'key': 'drive_last_backup_at', 'value': 'null'},
  {'key': 'feedly_api_key', 'value': 'null'},
  {'key': 'google_account_email', 'value': 'null'},
  {'key': 'onboarding_complete', 'value': 'false'},
  // NB: no 'schema_version' row. PRAGMA user_version — set by the `version:`
  // passed to openDatabase in database.dart — is the single source of truth
  // for the schema version. A settings row duplicating it drifted to a stale
  // '3' and was removed in the v9 migration.
  {'key': 'cleanup_age_days', 'value': '7'},
  {'key': 'newspaper_mode', 'value': 'false'},
  {'key': 'show_read', 'value': 'true'},
  {'key': 'mark_all_read_confirm', 'value': 'true'},
  {'key': 'color_palette', 'value': 'orange'},
];

