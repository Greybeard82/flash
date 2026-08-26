# Flash — SQLite Database Schema
**Version:** 1.0  
**Engine:** SQLite via `sqflite` Flutter package  
**Versioning:** Schema versioned from day one. All changes must go through `onUpgrade` migration callbacks — never drop and recreate in production.

---

## Overview

| Table | Purpose |
|---|---|
| `folders` | User-defined feed categories / tabs |
| `feeds` | RSS/Atom feed subscriptions |
| `articles` | Fetched article records |
| `keyword_blocklist` | Keywords that hide + auto-read matching articles |
| `opinion_patterns` | Heuristic patterns for opinion filter (Stage 1) |
| `article_summaries` | Cached Claude Haiku AI summaries per article |
| `settings` | Key-value store for all app settings |

---

## Tables

### `folders`

Represents a user-created category tab.

```sql
CREATE TABLE folders (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT    NOT NULL,
  position     INTEGER NOT NULL DEFAULT 0,  -- tab order, 0-indexed
  created_at   INTEGER NOT NULL             -- Unix timestamp (ms)
);
```

**Notes:**
- The "All" tab is virtual -- not stored here, always rendered first in the UI
- The "Opinions" folder is auto-created with `name = 'Opinions'` and `position = 9999` (always last) when the opinion filter is first enabled
- `position` is rewritten for all rows on drag-reorder -- no gaps

---

### `feeds`

Represents a subscribed RSS or Atom feed.

```sql
CREATE TABLE feeds (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  folder_id             INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  title                 TEXT    NOT NULL,
  url                   TEXT    NOT NULL UNIQUE,  -- RSS/Atom feed URL
  site_url              TEXT,                     -- homepage URL (for favicon)
  favicon_path          TEXT,                     -- local cache path to favicon image
  description           TEXT,
  article_limit         INTEGER,                  -- NULL = use global setting
  last_fetched_at       INTEGER,                  -- Unix timestamp (ms), NULL if never
  last_fetch_error      TEXT,                     -- last error message, NULL if healthy
  consecutive_failures  INTEGER NOT NULL DEFAULT 0,
  is_dead               INTEGER NOT NULL DEFAULT 0 CHECK(is_dead IN (0,1)),  -- 1 if 7+ consecutive failures
  position              INTEGER NOT NULL DEFAULT 0,  -- order within folder
  created_at            INTEGER NOT NULL             -- Unix timestamp (ms)
);

CREATE INDEX idx_feeds_folder_id ON feeds(folder_id);
```

**Notes:**
- `article_limit NULL` means fall back to the global `settings` value for `article_limit`
- `is_dead` is set to 1 automatically after 7 consecutive fetch failures
- `favicon_path` stores a relative path inside the app's local cache directory
- `url` must be unique -- duplicate feed URLs are rejected at the app layer before insert

---

### `articles`

Represents a single fetched article from a feed.

```sql
CREATE TABLE articles (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  feed_id         INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  guid            TEXT    NOT NULL,         -- RSS <guid> or Atom <id> -- unique per feed
  title           TEXT    NOT NULL,
  url             TEXT    NOT NULL,         -- article link
  description     TEXT,                     -- RSS <description> or Atom <summary>
  thumbnail_url   TEXT,                     -- resolved image URL (og:image or media:thumbnail)
  thumbnail_path  TEXT,                     -- local cache path after download
  published_at    INTEGER,                  -- Unix timestamp (ms), NULL if not provided
  fetched_at      INTEGER NOT NULL,         -- Unix timestamp (ms) when Flash fetched it
  is_read         INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1)),
  read_at         INTEGER,                  -- Unix timestamp (ms) when read; NULL if unread
  is_blocked      INTEGER NOT NULL DEFAULT 0 CHECK(is_blocked IN (0,1)),  -- matched keyword blocklist
  is_opinion      INTEGER NOT NULL DEFAULT 0 CHECK(is_opinion IN (0,1)),  -- moved to Opinions folder
  opinion_source  TEXT,                     -- 'heuristic' | 'ai' | NULL
  blocked_keyword TEXT                      -- which keyword triggered the block, for audit view
);

CREATE UNIQUE INDEX idx_articles_guid_feed ON articles(feed_id, guid);
CREATE INDEX idx_articles_feed_id         ON articles(feed_id);
CREATE INDEX idx_articles_is_read         ON articles(is_read);
CREATE INDEX idx_articles_read_at         ON articles(read_at);
CREATE INDEX idx_articles_is_blocked      ON articles(is_blocked);
CREATE INDEX idx_articles_is_opinion      ON articles(is_opinion);
CREATE INDEX idx_articles_published_at    ON articles(published_at DESC);
```

**Notes:**
- `guid` uniqueness is scoped per feed (`feed_id + guid`) -- different feeds can have colliding GUIDs
- `read_at` (added v11) drives read *visibility*, not deletion. The feed shows an article when `is_read = 0 OR read_at >= cutoff`, where the cutoff is 48 hours ago while the Show read setting is on, and NULL while it is off. Rows read before v11 carry `read_at IS NULL` and so never match the second half -- deliberate, since there is no honest read time to give them
- `read_at = 0` (the epoch) is a sentinel meaning "dismissed": written by Mark all as read, it is outside every possible window, so those articles never return when Show read is switched back on
- `is_blocked = 1` articles are hidden from all feed views but retained in DB for the audit view
- `is_opinion = 1` articles are excluded from normal folder views and shown only in the Opinions tab
- `thumbnail_path` is populated lazily on first scroll into view -- `thumbnail_url` is stored immediately on fetch
- Auto-cleanup deletes the oldest `is_read = 1` articles when count exceeds the feed's effective limit
- Blocked articles (`is_blocked = 1`) are counted toward the limit and cleaned up first

---

### `keyword_blocklist`

Stores user-defined keywords that trigger article hiding.

```sql
CREATE TABLE keyword_blocklist (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  keyword        TEXT    NOT NULL UNIQUE COLLATE NOCASE,
  whole_word     INTEGER NOT NULL DEFAULT 0 CHECK(whole_word IN (0,1)),  -- 1 = whole word match only
  created_at     INTEGER NOT NULL  -- Unix timestamp (ms)
);
```

**Notes:**
- `COLLATE NOCASE` handles case-insensitive storage and deduplication
- Matching logic at app layer: partial match by default, whole-word optional per keyword
- Matched against `articles.title` + `articles.description` at parse time
- On blocklist change, existing unread articles are re-evaluated immediately

---

### `opinion_patterns`

Stores heuristic patterns for Stage 1 opinion detection.

```sql
CREATE TABLE opinion_patterns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern     TEXT    NOT NULL UNIQUE COLLATE NOCASE,
  match_field TEXT    NOT NULL DEFAULT 'both' CHECK(match_field IN ('title', 'category', 'both')),
  is_default  INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN (0,1)),  -- 1 = shipped with app, 0 = user-added
  created_at  INTEGER NOT NULL  -- Unix timestamp (ms)
);
```

**Default patterns (seeded on first install):**

| Pattern | Field |
|---|---|
| `opinion` | both |
| `editorial` | both |
| `commentary` | both |
| `op-ed` | both |
| `column` | both |
| `analysis` | both |
| `perspective` | both |
| `letters` | category |
| `Why I` | title |
| `The case for` | title |
| `We need to` | title |
| `It's time to` | title |
| `Opinion:` | title |
| `Column:` | title |

**Notes:**
- `is_default = 1` patterns can be disabled by the user but not deleted (re-seeded on reset)
- User-added patterns (`is_default = 0`) can be fully deleted
- `match_field = 'category'` checks only the RSS `<category>` tag
- `match_field = 'title'` checks only `articles.title`
- `match_field = 'both'` checks title + description + category

---

### `article_summaries`

Cache for Claude Haiku AI summaries. Avoids repeat API calls.

```sql
CREATE TABLE article_summaries (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  article_id   INTEGER NOT NULL UNIQUE REFERENCES articles(id) ON DELETE CASCADE,
  summary      TEXT    NOT NULL,  -- rendered bullet point text (plain text, newline-separated)
  model        TEXT    NOT NULL,  -- e.g. 'claude-haiku-4-5' -- for future model tracking
  generated_at INTEGER NOT NULL   -- Unix timestamp (ms)
);
```

**Notes:**
- `UNIQUE` on `article_id` -- one summary per article, ever
- `ON DELETE CASCADE` -- summary is cleaned up when the article is cleaned up
- `summary` stored as plain text with newlines between bullet points -- no markdown
- `model` stored so future model upgrades can invalidate old summaries if needed

---

### `settings`

Flat key-value store for all app configuration.

```sql
CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL  -- Unix timestamp (ms)
);
```

**Seeded default values on first install:**

| Key | Default Value | Description |
|---|---|---|
| `theme` | `system` | `system` / `light` / `dark` |
| `refresh_interval_minutes` | `30` | Background refresh interval |
| `article_limit` | `100` | Global max read articles per feed |
| `mark_read_on_scroll` | `true` | Auto-mark read as articles scroll past |
| `opinion_filter_heuristic` | `true` | Stage 1 heuristic opinion detection |
| `opinion_filter_ai` | `false` | Stage 2 Claude Haiku opinion detection |
| `drive_backup_enabled` | `false` | Auto-backup to Google Drive on change |
| `drive_last_backup_at` | `null` | Unix timestamp (ms) of last Drive backup |
| `feedly_api_key` | `null` | Feedly feed search API key |
| `google_account_email` | `null` | Signed-in Google account, NULL if not connected |
| `onboarding_complete` | `false` | Whether first-launch empty state has been dismissed |
| `show_read` | `true` | Keep read articles visible for 48 hours (see `articles.read_at`) |

**Notes:**
- `value` is always stored as TEXT -- app layer handles type casting (int, bool, etc.)
- No API keys are stored here. `anthropic_api_key_set` was seeded until v12 for a Claude Haiku summary path that was specified and never built -- no client, no key entry, nothing that read the flag. The v12 migration deletes it; summaries run on-device through Gemini Nano, which needs no key

---

## Relationships

```
folders
  └── feeds (folder_id → folders.id, CASCADE DELETE)
        └── articles (feed_id → feeds.id, CASCADE DELETE)
              └── article_summaries (article_id → articles.id, CASCADE DELETE)
```

Deleting a folder cascades to its feeds, which cascades to their articles, which cascades to summaries. No orphaned records.

---

## Migration Strategy

All schema changes go through `sqflite`'s `onUpgrade` callback:

```dart
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE feeds ADD COLUMN new_column TEXT');
  }
  if (oldVersion < 3) {
    // next migration
  }
}
```

**Rules:**
- Never DROP TABLE in a migration -- add columns with defaults instead
- The schema version is `PRAGMA user_version`, set by the `version:` passed to `openDatabase` in `database.dart`. Bump that and nothing else
- There is **no `schema_version` settings row**. One existed until v9, was never read, drifted permanently to `'3'` while the real version reached 8, and was deleted by the v9 migration. `audit_schema_integrity_test.dart` asserts it never comes back -- a second, always-wrong answer to "what schema is this?" is worse than none
- `kExpectedSchemaVersion` in `audit_schema_integrity_test.dart` is kept in sync **by hand**. Bump it in the same commit as the `version:` bump, or that test fails
- Test every migration path (v1→v3 must work, not just v2→v3)

---

## Auto-Cleanup Query

Run after every feed fetch. Deletes oldest read articles beyond the effective limit:

```sql
DELETE FROM articles
WHERE feed_id = :feedId
  AND is_read = 1
  AND id NOT IN (
    SELECT id FROM articles
    WHERE feed_id = :feedId
      AND is_read = 1
    ORDER BY published_at DESC
    LIMIT :effectiveLimit
  );
```

Where `:effectiveLimit` = `feeds.article_limit` if not NULL, else `settings.article_limit`.
