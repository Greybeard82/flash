# Graph Report - flash  (2026-08-13)

## Corpus Check
- 148 files · ~117,082 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2462 nodes · 2947 edges · 102 communities (90 shown, 12 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 34 edges (avg confidence: 0.92)
- Token cost: 358,727 input · 0 output

## Community Hubs (Navigation)
- app_localizations
- app_localizations_en
- app_localizations_it
- app_localizations_de
- app_localizations_es
- app_localizations_fr
- feed_screen
- feeds_screen
- content_block / article_extractor
- app_theme / GeminiNanoPlugin
- settings_screen
- article_summary_sheet_test / folder_tab_bar_test
- refresh_service
- app
- feeds_screen / article_summary_sheet
- folder_tab_bar
- session_read_scope_test / session_read_tracker
- radial_menu
- schema
- opml_service / backup_serializer
- article_repository
- drive_backup_service / PRD-Flash
- article
- keyword_blocklist_screen
- resume_refresh_policy_test / summary_source_test
- article_summary_sheet
- SceneDelegate / AppDelegate
- reader_screen
- keyword_alerts_screen
- rss_service_test
- feed
- refresh_service_test
- PROMPT-UX-PASS-02 / PRD-Flash
- MANUAL_QA / PRD-Flash
- article_card
- backup_serializer_test / newspaper_mode_test
- settings
- article_repository_test
- notification_banner
- PROMPT-UX-PASS-01 / PRD-Flash
- favicon_service / thumbnail_service
- PRD-Flash / l10n
- bookmarks_screen
- schema / PRD-Flash
- rss_service / article_repository
- feed_repository
- feeds_screen / article_card
- search_screen
- pubspec / PRD-Flash
- session_read_tracker_test
- cleanup_settings_test
- main
- loading_controller
- gemini_nano_service
- database
- unread_counts
- opml_service_test
- VERIFICATION_REPORT / MANUAL_QA
- onboarding_screen
- feedly_service
- date_utils / empty_state
- global_loading_indicator
- unread_counts_test
- folder_repository
- unread_badge / shimmer_card
- SCAFFOLD_PROMPT / PRD-Flash
- loading_controller_test / loading_controller
- keyword_alert_repository
- keyword_alert
- feed_card / feed
- keyword_repository
- app_localizations / app_localizations_de
- folder
- keyword_block
- form_factor
- feed_behavior_test
- settings_repository
- resume_refresh_policy
- feed_screen / bookmarks_screen
- share_service
- PRD-Flash
- keyword_matcher
- database / gemini_nano_service
- bolt_logo
- constants
- refresh_service
- app_icon / app_icon_foreground
- tv_banner
- ic_launcher_foreground
- ic_launcher
- README
- Icon-App-1024x1024@1x
- LaunchImage
- Community 98
- SCAFFOLD_PROMPT
- SCAFFOLD_PROMPT

## God Nodes (most connected - your core abstractions)
1. `GeminiNanoPlugin` - 14 edges
2. `PROMPT-UX-PASS-01.md (files root)` - 12 edges
3. `AppLocalizations` - 11 edges
4. `PROMPT-UX-PASS-02.md (files2 root)` - 10 edges
5. `ArticleRepository` - 8 edges
6. `Article Feed / Card Layout` - 8 edges
7. `Static Audit — PRD vs Code` - 7 edges
8. `ContentBlock` - 6 edges
9. `ArticleExtractor` - 6 edges
10. `_visitChildren` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Real Claude Haiku Summary QA (Anthropic API)` --conceptually_related_to--> `Anthropic API (Claude Haiku) — Not Implemented`  [AMBIGUOUS]
  MANUAL_QA.md → PRD-Flash.md
- `Cross-Tab Unread Counts QA` --conceptually_related_to--> `B1 — Cross-Tab Unread Counts Update Live`  [INFERRED]
  MANUAL_QA.md → files/PROMPT-UX-PASS-01.md
- `settings table` --conceptually_related_to--> `Anthropic API (Claude Haiku) — Not Implemented`  [INFERRED]
  schema.md → PRD-Flash.md
- `Hard Requirement 1 — Folder Tabs at Bottom` --conceptually_related_to--> `Thumb Zone Design`  [INFERRED]
  SCAFFOLD_PROMPT.md → PRD-Flash.md
- `Dynamic Colour Theming QA` --conceptually_related_to--> `Material You / Dynamic Colour Theming`  [INFERRED]
  MANUAL_QA.md → PRD-Flash.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Session-Read Scoping Feature Delivery** — files2_prompt_ux_pass_02, ux_pass_02_session_read_tracker_scoped, prd_flash_session_read_model, manual_qa_session_read_per_tab [INFERRED 0.85]
- **On-Device AI Summary Pipeline** — prd_flash_ai_article_summary, article_extractor_dart, ux_pass_01_summary_source, gemininanoplugin_kt, article_summary_sheet_dart [INFERRED 0.85]
- **UX Pass 01 Delivery (docs, tests, code)** — files_pack_prompt_ux_pass_01, ux_pass_01_unread_counts_model, ux_pass_01_loading_controller, folder_tab_bar_dart, manual_qa, prd_flash [INFERRED 0.75]

## Communities (102 total, 12 thin omitted)

### Community 0 - "app_localizations"
Cohesion: 0.01
Nodes (180): app_localizations_de.dart, app_localizations_en.dart, app_localizations_es.dart, app_localizations_fr.dart, app_localizations_it.dart, class, add, addAFeed (+172 more)

### Community 1 - "app_localizations_en"
Cohesion: 0.01
Nodes (164): app_localizations.dart, add, addAFeed, addAFeedButton, addAlertKeyword, addAlertKeywordSubtitle, addFeed, addFirstFeed (+156 more)

### Community 2 - "app_localizations_it"
Cohesion: 0.01
Nodes (164): add, addAFeed, addAFeedButton, addAlertKeyword, addAlertKeywordSubtitle, addFeed, addFirstFeed, addKeyword (+156 more)

### Community 3 - "app_localizations_de"
Cohesion: 0.01
Nodes (163): add, addAFeed, addAFeedButton, addAlertKeyword, addAlertKeywordSubtitle, addFeed, addFirstFeed, addKeyword (+155 more)

### Community 4 - "app_localizations_es"
Cohesion: 0.01
Nodes (163): add, addAFeed, addAFeedButton, addAlertKeyword, addAlertKeywordSubtitle, addFeed, addFirstFeed, addKeyword (+155 more)

### Community 5 - "app_localizations_fr"
Cohesion: 0.01
Nodes (163): add, addAFeed, addAFeedButton, addAlertKeyword, addAlertKeywordSubtitle, addFeed, addFirstFeed, addKeyword (+155 more)

### Community 6 - "feed_screen"
Cohesion: 0.03
Nodes (69): animation, _articleRepo, _articles, _articlesForTab, _bannerKey, _boot, _booting, _buildContent (+61 more)

### Community 7 - "feeds_screen"
Cohesion: 0.03
Nodes (69): _addByUrl, _addByUrlBody, _addFromFeedly, _adding, articleRepo, build, _buildList, _chevronController (+61 more)

### Community 8 - "content_block / article_extractor"
Cohesion: 0.05
Nodes (44): caption, ContentBlock, HeadingBlock, ImageBlock, items, level, ListBlock, ordered (+36 more)

### Community 9 - "app_theme / GeminiNanoPlugin"
Cohesion: 0.07
Nodes (29): GeminiNanoPlugin, MainActivity, Color, FlutterActivity, FlutterEngine, FlutterPlugin, GenerativeModel, base (+21 more)

### Community 10 - "settings_screen"
Cohesion: 0.05
Nodes (42): DateTime?, GoogleSignInAccount?, keyword_alerts_screen.dart, keyword_blocklist_screen.dart, _backupBusy, _backupNow, _backupService, _buildBackupSection (+34 more)

### Community 11 - "article_summary_sheet_test / folder_tab_bar_test"
Cohesion: 0.06
Nodes (36): allUnreadCount, _folder, folderUnreadCounts, _harness, main, selectedIndex, Map, NeverScrollableScrollPhysics (+28 more)

### Community 12 - "refresh_service"
Cohesion: 0.06
Nodes (32): alertRepo, alerts, allUnblocked, androidInit, articleRepo, _doRefresh, feedList, feedRepo (+24 more)

### Community 13 - "app"
Cohesion: 0.06
Nodes (31): _applyTheme, build, _buildScreenStack, _checkOnboarding, createState, _currentIndex, dispose, _feedRefreshTrigger (+23 more)

### Community 14 - "feeds_screen / article_summary_sheet"
Cohesion: 0.10
Nodes (32): _AppShell, _AppShellState, ArticleSummarySheet, _ArticleSummarySheetState, _LoadingDots, _LoadingDotsState, BookmarksScreen, _BookmarksScreenState (+24 more)

### Community 15 - "folder_tab_bar"
Cohesion: 0.07
Nodes (30): GlobalKey, accent, allUnreadCount, barHeight, build, createState, didUpdateWidget, dispose (+22 more)

### Community 16 - "session_read_scope_test / session_read_tracker"
Cohesion: 0.07
Nodes (27): allScope, gaming, main, tech, tracker, _visible, add, addAll (+19 more)

### Community 17 - "radial_menu"
Cohesion: 0.07
Nodes (26): _actionButton, article, build, _controller, createState, _dismiss, dispose, enabled (+18 more)

### Community 18 - "schema"
Cohesion: 0.08
Nodes (25): articles, articleSummaries, createArticles, createArticlesFeedIdIndex, createArticlesFeedReadPublishedIndex, createArticlesGuidIndex, createArticlesIsBlockedIndex, createArticlesIsReadIndex (+17 more)

### Community 19 - "opml_service / backup_serializer"
Cohesion: 0.10
Nodes (22): BackupSerializer, restoreFromMap, toMap, validate, exportBackup, importBackup, LocalBackupService, _esc (+14 more)

### Community 20 - "article_repository"
Cohesion: 0.08
Nodes (23): async, getAllArticles, getAllFolderUnreadCounts, getArticlesByFolder, getBlocked, getSaved, getTotalUnreadCount, getUnreadCount (+15 more)

### Community 21 - "drive_backup_service / PRD-Flash"
Cohesion: 0.09
Nodes (22): backup_serializer.dart, GoogleSignInAccount? get, http.BaseClient, _AuthClient, backup, currentUser, DriveBackupService, _fileName (+14 more)

### Community 22 - "article"
Cohesion: 0.09
Nodes (22): DateTime? get, Article, blockedKeyword, copyWith, description, feedFaviconPath, feedId, feedTitle (+14 more)

### Community 23 - "keyword_blocklist_screen"
Cohesion: 0.09
Nodes (22): _addKeyword, _AddKeywordSheet, _AddKeywordSheetState, _articleRepo, _blockedArticles, build, _controller, createState (+14 more)

### Community 24 - "resume_refresh_policy_test / summary_source_test"
Cohesion: 0.11
Nodes (15): main, now, policy, main, package:flash/models/content_block.dart, package:flash/services/summary_source.dart, package:flash/utils/keyword_matcher.dart, package:flash/utils/resume_refresh_policy.dart (+7 more)

### Community 25 - "article_summary_sheet"
Cohesion: 0.10
Nodes (20): article, build, _controller, createState, debugReason, dispose, _done, _errorMessage (+12 more)

### Community 26 - "SceneDelegate / AppDelegate"
Cohesion: 0.11
Nodes (14): Any, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterSceneDelegate, AppDelegate, Bool (+6 more)

### Community 27 - "reader_screen"
Cohesion: 0.10
Nodes (19): double get, article, _blocks, build, _buildBlock, _buildBody, _cancelled, createState (+11 more)

### Community 28 - "keyword_alerts_screen"
Cohesion: 0.11
Nodes (19): _AddAlertSheet, _AddAlertSheetState, _addKeyword, build, _controller, createState, _delete, dispose (+11 more)

### Community 29 - "rss_service_test"
Cohesion: 0.10
Nodes (19): package:flash/services/rss_service.dart, accepted, applyThresholds, _art, articleLimit, cutoffMs, dayLimit, db (+11 more)

### Community 30 - "feed"
Cohesion: 0.11
Nodes (18): articleLimit, consecutiveFailures, copyWith, createdAt, description, faviconPath, folderId, fromMap (+10 more)

### Community 31 - "refresh_service_test"
Cohesion: 0.11
Nodes (18): _art, _count, db, folderId, insert, insertArticles, main, _now (+10 more)

### Community 32 - "PROMPT-UX-PASS-02 / PRD-Flash"
Cohesion: 0.12
Nodes (18): test/feed_behavior_test.dart, PROMPT-UX-PASS-02.md (pack), PROMPT-UX-PASS-02.md (files2 root), Cross-Tab Unread Counts QA, Session-Read Visibility Per-Tab QA, Build Status (Shipped / Not Yet Built), Folder / Category Management, Live Cross-Tab Unread Badges (+10 more)

### Community 33 - "MANUAL_QA / PRD-Flash"
Cohesion: 0.12
Nodes (17): folder_tab_bar.dart, GeminiNanoPlugin.kt (android native), AI Summary Reads Full Article QA, Cold-Start Performance QA, Folder Tab Size QA, Folder Tabs Position QA, Haptic Feedback QA, Onboarding QA (+9 more)

### Community 34 - "article_card"
Cohesion: 0.11
Nodes (17): article, build, dimmed, faviconPath, feedTitle, onBookmark, onMarkRead, onMarkUnread (+9 more)

### Community 35 - "backup_serializer_test / newspaper_mode_test"
Cohesion: 0.12
Nodes (15): dart:convert, package:flash/db/database.dart, package:flash/models/feed.dart, package:flash/models/folder.dart, package:flash/models/keyword_block.dart, package:flash/models/settings.dart, package:flash/repositories/settings_repository.dart, package:flash/services/backup_serializer.dart (+7 more)

### Community 36 - "settings"
Cohesion: 0.12
Nodes (16): anthropicApiKeySet, AppSettings, articleFontSize, articleLimit, cleanupAgeDays, copyWith, driveBackupEnabled, driveLastBackupAt (+8 more)

### Community 37 - "article_repository_test"
Cohesion: 0.12
Nodes (16): _art, _count, db, f1, insert, main, _now, _old (+8 more)

### Community 38 - "notification_banner"
Cohesion: 0.12
Nodes (15): Animation, AnimationController, build, createState, _ctrl, dismiss, dispose, initState (+7 more)

### Community 39 - "PROMPT-UX-PASS-01 / PRD-Flash"
Cohesion: 0.16
Nodes (15): ArticleExtractor (article_extractor.dart), article_summary_sheet.dart, PROMPT-UX-PASS-01.md (pack), PROMPT-UX-PASS-01.md (files root), Global Loading Indicator QA, Resume Refresh QA, article_extractor.dart, Reader Mode / In-App Reader (+7 more)

### Community 40 - "favicon_service / thumbnail_service"
Cohesion: 0.15
Nodes (14): dart:io, dart:typed_data, FaviconService, fetchAndCache, _googleFaviconBase, _saveFavicon, downloadAndCache, fetchOgImage (+6 more)

### Community 41 - "PRD-Flash / l10n"
Cohesion: 0.12
Nodes (13): Background Refresh (configurable interval), Bookmarks, Build & Distribution, Feed Health / Dead Feed Detection, Feed Management, Fetch Thresholds, Keyword Alerts, Localisation (EN/DE/ES/FR/IT) (+5 more)

### Community 42 - "bookmarks_screen"
Cohesion: 0.12
Nodes (15): _articleRepo, _articles, build, createState, initState, _load, _loading, _markRead (+7 more)

### Community 43 - "schema / PRD-Flash"
Cohesion: 0.16
Nodes (15): Real Claude Haiku Summary QA (Anthropic API), Anthropic API (Claude Haiku) — Not Implemented, Article Auto-Cleanup, Gemini Nano On-Device AI, Open Questions, Opinion Filter (planned, not shipped), database.dart, article_summaries table (+7 more)

### Community 44 - "rss_service / article_repository"
Cohesion: 0.13
Nodes (14): ArticleRepository, applyFetchThresholds, _articleRepo, _extractRssThumbnail, _feedRepo, _fromAtomItems, _fromRssItems, _parse (+6 more)

### Community 45 - "feed_repository"
Cohesion: 0.13
Nodes (14): async, delete, FeedRepository, getAll, getByFolder, getById, getByUrl, getUnreadCountForFeed (+6 more)

### Community 46 - "feeds_screen / article_card"
Cohesion: 0.13
Nodes (15): _SummaryText, _UnavailableMessage, _BootingAnimation, _NewspaperMasthead, _ConfirmSheet, _FeedActionsSheet, _FolderActionsSheet, _ReorderableFeedRow (+7 more)

### Community 47 - "search_screen"
Cohesion: 0.13
Nodes (14): build, _controller, createState, _debounce, dispose, initState, _lastQuery, _loading (+6 more)

### Community 48 - "pubspec / PRD-Flash"
Cohesion: 0.14
Nodes (14): Google Drive Backup/Restore QA, Backup System (Google Drive + Local File), Feed Parsing (http + dart_rss), Newspaper Mode, SQLite Local Storage (sqflite), WorkManager Background Refresh, dart_rss dependency, google_sign_in dependency (+6 more)

### Community 49 - "session_read_tracker_test"
Cohesion: 0.13
Nodes (14): package:flash/db/schema.dart, _art, db, folderId, _idForGuid, insert, _insertAndMaybeMarkRead, insertArticles (+6 more)

### Community 50 - "cleanup_settings_test"
Cohesion: 0.13
Nodes (14): package:flash/repositories/article_repository.dart, package:flash/utils/constants.dart, _art, _count, db, folderId, insert, main (+6 more)

### Community 51 - "main"
Cohesion: 0.14
Nodes (13): app.dart, androidInit, androidPlugin, init, initialize, main, plugin, refreshService (+5 more)

### Community 52 - "loading_controller"
Cohesion: 0.14
Nodes (13): bool get, int get, _activeCount, begin, end, instance, isBusy, label (+5 more)

### Community 53 - "gemini_nano_service"
Cohesion: 0.14
Nodes (13): dart:async, _available, _channel, GeminiNanoService, _handleNativeCall, _instance, summarizeStream, _summaryBuffer (+5 more)

### Community 54 - "database"
Cohesion: 0.14
Nodes (13): AppDatabase, close, _db, _initDatabase, _instance, _onCreate, _onUpgrade, _testPath (+5 more)

### Community 55 - "unread_counts"
Cohesion: 0.14
Nodes (13): all, applyManyRead, applyRead, applyUnread, byFolder, clearedAll, clearedFolder, empty (+5 more)

### Community 56 - "opml_service_test"
Cohesion: 0.14
Nodes (13): package:flash/services/opml_service.dart, return, attr, _feed, feedPattern, _folder, folderPattern, main (+5 more)

### Community 57 - "VERIFICATION_REPORT / MANUAL_QA"
Cohesion: 0.18
Nodes (13): article_card.dart, article_repository.dart, feed_screen.dart, keyword_matcher.dart, Swipe Mark-as-Read QA, opml_service.dart, Keyword Blocking, keyword_blocklist table (+5 more)

### Community 58 - "onboarding_screen"
Cohesion: 0.15
Nodes (12): ColorScheme, IconData, build, _Bullet, colorScheme, _finish, icon, OnboardingScreen (+4 more)

### Community 59 - "feedly_service"
Cohesion: 0.15
Nodes (12): description, faviconUrl, FeedlyResult, FeedlyService, feedUrl, looksLikeUrl, search, _searchBase (+4 more)

### Community 60 - "date_utils / empty_state"
Cohesion: 0.17
Nodes (10): ../l10n/app_localizations.dart, diff, formatRelativeTime, formatRelativeTimestamp, now, timeYearsAgo, build, EmptyState (+2 more)

### Community 61 - "global_loading_indicator"
Cohesion: 0.18
Nodes (11): build, createState, _delayToken, dispose, GlobalLoadingIndicator, _GlobalLoadingIndicatorState, initState, _onControllerChanged (+3 more)

### Community 62 - "unread_counts_test"
Cohesion: 0.18
Nodes (9): gaming, main, seed, tech, package:flash/models/unread_counts.dart, gaming, main, seed (+1 more)

### Community 63 - "folder_repository"
Cohesion: 0.18
Nodes (10): async, delete, FolderRepository, getAll, getById, getNextPosition, insert, reorder (+2 more)

### Community 64 - "unread_badge / shimmer_card"
Cohesion: 0.18
Nodes (9): _box, build, ShimmerCard, build, count, small, UnreadBadge, package:flutter/material.dart (+1 more)

### Community 65 - "SCAFFOLD_PROMPT / PRD-Flash"
Cohesion: 0.18
Nodes (10): Dynamic Colour Theming QA, Material You / Dynamic Colour Theming, Long-Press Radial Menu, dynamic_color dependency, app_theme.dart, Phase 1 Definition of Done, Hard Requirement 3 — Dual Accent Color ThemeData, Hard Requirement 1 — Folder Tabs at Bottom (+2 more)

### Community 66 - "loading_controller_test / loading_controller"
Cohesion: 0.24
Nodes (8): ChangeNotifier, c, main, LoadingController, package:flash/services/loading_controller.dart, StateError, c, main

### Community 67 - "keyword_alert_repository"
Cohesion: 0.20
Nodes (9): ../db/schema.dart, async, delete, findHits, getAll, insert, KeywordAlertRepository, setWholeWord (+1 more)

### Community 68 - "keyword_alert"
Cohesion: 0.20
Nodes (9): int?, copyWith, createdAt, fromMap, id, keyword, KeywordAlert, toMap (+1 more)

### Community 69 - "feed_card / feed"
Cohesion: 0.20
Nodes (9): Feed, build, feed, _FeedAvatar, FeedCard, onDelete, onEdit, onTap (+1 more)

### Community 70 - "keyword_repository"
Cohesion: 0.20
Nodes (9): async, delete, findMatch, getAll, insert, KeywordRepository, setWholeWord, package:sqflite/sqflite.dart (+1 more)

### Community 71 - "app_localizations / app_localizations_de"
Cohesion: 0.25
Nodes (9): AppLocalizations, _AppLocalizationsDelegate, AppLocalizationsDe, AppLocalizationsEn, AppLocalizationsEs, AppLocalizationsFr, AppLocalizationsIt, of (+1 more)

### Community 72 - "folder"
Cohesion: 0.22
Nodes (8): copyWith, createdAt, Folder, fromMap, id, name, position, toMap

### Community 73 - "keyword_block"
Cohesion: 0.22
Nodes (8): copyWith, createdAt, fromMap, id, keyword, KeywordBlock, toMap, wholeWord

### Community 74 - "form_factor"
Cohesion: 0.22
Nodes (8): _channel, FormFactor, init, _isTV, package:flutter/services.dart, static bool, static bool get, static const

### Community 75 - "feed_behavior_test"
Cohesion: 0.22
Nodes (8): package:flash/models/article.dart, _article, _dimArticle, _dimIds, _dimUnread, main, _markReadSwipe, _unionQuery

### Community 76 - "settings_repository"
Cohesion: 0.25
Nodes (7): ../db/database.dart, Future, async, getAll, setMany, SettingsRepository, ../models/settings.dart

### Community 77 - "resume_refresh_policy"
Cohesion: 0.33
Nodes (5): Duration, minBackgroundDuration, minFetchInterval, ResumeRefreshPolicy, shouldFetch

### Community 78 - "feed_screen / bookmarks_screen"
Cohesion: 0.33
Nodes (6): _openArticle, build, _openArticle, _open, build, MaterialPageRoute

### Community 79 - "share_service"
Cohesion: 0.33
Nodes (5): shareArticle, ShareService, shareUrl, ../models/article.dart, package:share_plus/share_plus.dart

### Community 80 - "PRD-Flash"
Cohesion: 0.40
Nodes (6): Article Feed / Card Layout, Auto-Refresh on Open (cold-start bolt animation), Mark All as Read (no confirmation), Mark as Read — On Scroll, NotificationBanner, Auto-Refresh on Resume (ResumeRefreshPolicy)

### Community 81 - "keyword_matcher"
Cohesion: 0.50
Nodes (3): buildHaystack, KeywordMatcher, matches

### Community 82 - "database / gemini_nano_service"
Cohesion: 0.67
Nodes (3): @visibleForTesting, useForTesting, resetForTesting

### Community 83 - "bolt_logo"
Cohesion: 0.67
Nodes (3): Yellow/orange lightning bolt glyph with black outline, Bolt Logo Image (Flash App Loading/Launcher Icon), Flash (news/RSS reader app)

## Ambiguous Edges - Review These
- `Real Claude Haiku Summary QA (Anthropic API)` → `Anthropic API (Claude Haiku) — Not Implemented`  [AMBIGUOUS]
  MANUAL_QA.md · relation: conceptually_related_to

## Knowledge Gaps
- **1931 isolated node(s):** `allScope`, `gaming`, `tech`, `tracker`, `_visible` (+1926 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Real Claude Haiku Summary QA (Anthropic API)` and `Anthropic API (Claude Haiku) — Not Implemented`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `BackupSerializer` connect `drive_backup_service / PRD-Flash` to `pubspec / PRD-Flash`?**
  _High betweenness centrality (0.074) - this node is a cross-community bridge._
- **Why does `AppLocalizations` connect `app_localizations / app_localizations_de` to `app_localizations`, `article_summary_sheet`?**
  _High betweenness centrality (0.055) - this node is a cross-community bridge._
- **Why does `Backup System (Google Drive + Local File)` connect `pubspec / PRD-Flash` to `PRD-Flash / l10n`, `drive_backup_service / PRD-Flash`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **What connects `allScope`, `gaming`, `tech` to the rest of the system?**
  _1931 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `app_localizations` be split into smaller, more focused modules?**
  _Cohesion score 0.011049723756906077 - nodes in this community are weakly interconnected._
- **Should `app_localizations_en` be split into smaller, more focused modules?**
  _Cohesion score 0.012121212121212121 - nodes in this community are weakly interconnected._