class TableNames {
  static const String folders = 'folders';
  static const String feeds = 'feeds';
  static const String articles = 'articles';
  static const String keywordBlocklist = 'keyword_blocklist';
  static const String keywordAlerts = 'keyword_alerts';
  static const String articleSummaries = 'article_summaries';
  static const String settings = 'settings';
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

  static const String createArticleSummaries = '''
    CREATE TABLE article_summaries (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      article_id   INTEGER NOT NULL UNIQUE REFERENCES articles(id) ON DELETE CASCADE,
      summary      TEXT    NOT NULL,
      model        TEXT    NOT NULL,
      generated_at INTEGER NOT NULL
    )
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
  {'key': 'anthropic_api_key_set', 'value': 'false'},
  {'key': 'google_account_email', 'value': 'null'},
  {'key': 'onboarding_complete', 'value': 'false'},
  {'key': 'schema_version', 'value': '3'},
  {'key': 'cleanup_age_days', 'value': '7'},
  {'key': 'article_font_size', 'value': 'medium'},
  {'key': 'reader_mode', 'value': 'false'},
  {'key': 'newspaper_mode', 'value': 'false'},
];

