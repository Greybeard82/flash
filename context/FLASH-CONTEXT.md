# FLASH — Codebase Context Survey

Generated: 2026-08-13
Repo path: C:\Users\david\projects\flash
Branch: main

---

## Section 1 — Working tree state

- Date of survey: 2026-08-13. Repo path: `C:\Users\david\projects\flash`. Current branch: `main`.
- `git rev-parse HEAD`: `c9394ba38761fec40af60547dca5a03bc4066bf2`

Last 10 commits (hash | date | subject):
```
c9394ba | 2026-08-13 | UX pass 03: single-pass AI summary, ruthless prompt, scroll-on-overflow
4ee1a61 | 2026-08-05 | UX pass 02: session-read visibility is per-tab
8295697 | 2026-08-05 | UX pass: live cross-tab unread counts, bigger folder tabs, global loading indicator, resume refresh, full-article AI summaries
d59f0a7 | 2026-07-16 | Fix AI summary streaming: buffer chunks, reveal atomically, cap length
014bf53 | 2026-07-12 | Enlarge launcher icon bolt; use bolt logo (no bg) for loading animation
6de9076 | 2026-07-12 | Add launcher icon: lightning bolt on light-blue adaptive background
6ebe2fc | 2026-07-12 | AI summary sheet: size to content instead of forcing full screen
013ac78 | 2026-07-12 | AI summary: full-screen sheet, longer summary, focal-point + bullet structure
b827fa1 | 2026-05-31 | Newspaper mode: serif theme, bundled fonts, settings toggle, masthead
aaa01f0 | 2026-05-31 | Feed list: session-read model (union query + SessionReadTracker)
```

### `git status --porcelain` (full)

```
?? files/
?? files2/
?? graphify-out/
```

No tracked files are modified (empty diff). Only three untracked directories exist; none are staged.

### Untracked file inventory

`files/` (116 KB total, 9 files) — leftover working files from a prior "UX pass 01" prompt package:
- `files/flash-ux-pass-01/flash-ux-pass/prompts/PROMPT-UX-PASS-01.md` — 21,300 bytes
- `files/flash-ux-pass-01/flash-ux-pass/README-PACK.md` — 590 bytes
- `files/flash-ux-pass-01/flash-ux-pass/test/folder_tab_bar_test.dart` — 5,765 bytes
- `files/flash-ux-pass-01/flash-ux-pass/test/loading_controller_test.dart` — 3,873 bytes
- `files/flash-ux-pass-01/flash-ux-pass/test/resume_refresh_policy_test.dart` — 4,998 bytes
- `files/flash-ux-pass-01/flash-ux-pass/test/summary_source_test.dart` — 5,845 bytes
- `files/flash-ux-pass-01/flash-ux-pass/test/unread_counts_test.dart` — 4,734 bytes
- `files/flash-ux-pass-01.zip` — 18,376 bytes
- `files/PROMPT-UX-PASS-01.md` — 21,300 bytes

`files2/` (36 KB total, 4 files) — analogous leftovers from "UX pass 02":
- `files2/flash-ux-pass-02/prompts/PROMPT-UX-PASS-02.md` — 7,434 bytes
- `files2/flash-ux-pass-02/test/session_read_scope_test.dart` — 7,341 bytes
- `files2/flash-ux-pass-02.zip` — 6,006 bytes
- `files2/PROMPT-UX-PASS-02.md` — 7,434 bytes

`graphify-out/` (5.6 MB total, 129 files) — output of a prior graphify knowledge-graph run over this repo. Top-level contents: `.graphify_labels.json`, `.graphify_python`, `.graphify_root`, `graph.html`, `graph.json`, `GRAPH_REPORT.md`, plus a deeper tree (not further enumerated here).

### Ahead/behind origin/main

`git log origin/main..HEAD --oneline` → empty (nothing local-only)
`git log HEAD..origin/main --oneline` → empty (nothing remote-only; local main is even with origin/main, or there is no fetched origin/main tracking data beyond HEAD)

### .gitignore-matched files that are NOT build output

From `git status --ignored --porcelain=v1`, non-build-output ignored paths (contents not inspected for anything credential-shaped):
- `.claude/` — Claude Code local settings directory (per repo .gitignore comment "Claude Code local settings")
- `.idea/`, `.vscode/` — IDE settings
- `android/app/google-services.json` — Firebase/Google Services config (explicitly gitignored per the "Firebase / Google services secrets" section of .gitignore) — this is a credential-shaped file; contents not read
- `android/app/src/main/java/` — likely an empty/legacy Java source stub directory alongside the Kotlin sources
- `android/local.properties` — local Android SDK path config (machine-specific, standard Flutter/Android gitignore entry)
- `android/flash_android.iml`, `flash.iml` — IntelliJ/Android Studio module files
- `android/gradle/wrapper/gradle-wrapper.jar`, `android/gradlew`, `android/gradlew.bat` — Gradle wrapper binaries/scripts (ignored, presumably regenerated or vendored outside VCS)
- `ios/Flutter/Generated.xcconfig`, `ios/Flutter/flutter_export_environment.sh`, `ios/Runner/GeneratedPluginRegistrant.h`, `ios/Runner/GeneratedPluginRegistrant.m` — Flutter-generated iOS glue files (even though iOS is not a shipping target per PRD)
- `ios/Flutter/ephemeral/` — Flutter iOS ephemeral build dir
- `android/.gradle/`, `build/`, `coverage/` — build/tooling caches (build output, listed for completeness)

No `.env`, `.pem`, keystore, or other obviously-credential file appeared in the ignored list besides `google-services.json` (noted, not opened).

---

## Section 2 — Environment and health

### `flutter --version` (verbatim)
```
Flutter 3.41.6 • channel stable • https://github.com/flutter/flutter.git
Framework • revision db50e20168 (5 months ago) • 2026-03-25 16:21:00 -0700
Engine • hash 5cdd32777948fa7a648fac915f8da7120ac7e97a (revision 425cfb54d0) (4 months ago) • 2026-03-25 20:14:42.000Z
Tools • Dart 3.11.4 • DevTools 2.54.2
```

### `dart --version` (verbatim)
```
Dart SDK version: 3.11.4 (stable) (Tue Mar 24 01:02:20 2026 -0700) on "windows_x64"
```

### pubspec.yaml (full contents)

```yaml
name: flash
description: A fast, local-first RSS reader with AI-powered filtering.
version: 0.1.0+2
publish_to: none

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # --- Local storage ---
  sqflite: ^2.3.3
  path: ^1.9.0
  path_provider: ^2.1.3
  flutter_secure_storage: ^9.0.0

  # --- Feed parsing ---
  http: ^1.2.1
  dart_rss: ^3.0.2
  html: ^0.15.4

  # --- Background processing ---
  workmanager: ^0.9.0
  flutter_local_notifications: ^18.0.0

  # --- Google services ---
  google_sign_in: ^6.2.1
  googleapis: ^12.0.0

  # --- UI & theming ---
  dynamic_color: ^1.7.0
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0
  flutter_svg: ^2.0.10+1

  # --- Gestures & animations ---
  flutter_slidable: ^3.1.0
  animations: ^2.0.11

  # --- Sharing ---
  share_plus: ^9.0.0

  # --- URL handling ---
  url_launcher: ^6.3.0

  # --- File access ---
  file_picker: ^8.0.7

  # --- App badge ---
  app_badge_plus: ^1.1.0

  # --- Utilities ---
  intl: any
  uuid: ^4.4.0
  collection: ^1.18.0

dependency_overrides:
  intl: ^0.20.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  sqflite_common_ffi: ^2.3.4
  flutter_launcher_icons: ^0.14.3

flutter_launcher_icons:
  android: true
  image_path: "icon/app_icon.png"
  adaptive_icon_background: "#95D0F2"
  adaptive_icon_foreground: "icon/app_icon_foreground.png"
  min_sdk_android: 26

flutter:
  uses-material-design: true
  generate: true

  assets:
    - assets/images/
    - assets/fonts/

  fonts:
    - family: PT Serif
      fonts:
        - asset: assets/fonts/PTSerif-Regular.ttf
          weight: 400
        - asset: assets/fonts/PTSerif-Bold.ttf
          weight: 700
        - asset: assets/fonts/PTSerif-Italic.ttf
          weight: 400
          style: italic
    - family: Playfair Display
      fonts:
        - asset: assets/fonts/PlayfairDisplay-VF.ttf
          weight: 700
```

### pubspec.lock — resolved versions of DIRECT dependencies only

| Package | Resolved version |
|---|---|
| animations | 2.1.2 |
| app_badge_plus | 1.2.9 |
| cached_network_image | 3.4.0 |
| dart_rss | 3.0.3 |
| dynamic_color | 1.8.1 |
| file_picker | 8.0.7 |
| flutter (SDK) | 0.0.0 |
| flutter_launcher_icons (dev) | 0.14.4 |
| flutter_lints (dev) | 4.0.0 |
| flutter_local_notifications | 18.0.1 |
| flutter_localizations (SDK) | 0.0.0 |
| flutter_secure_storage | 9.2.4 |
| flutter_slidable | 3.1.2 |
| flutter_svg | 2.2.4 |
| flutter_test (dev, SDK) | 0.0.0 |
| google_sign_in | 6.3.0 |
| googleapis | 12.0.0 |
| html | 0.15.6 |
| http | 1.6.0 |
| intl (dependency_override applies) | 0.20.2 |
| path | 1.9.1 |
| path_provider | 2.1.5 |
| share_plus | 9.0.0 |
| shimmer | 3.0.0 |
| sqflite | 2.4.2 |
| sqflite_common_ffi (dev) | 2.3.5 |
| url_launcher | 6.3.2 |
| uuid | 4.5.3 |
| workmanager | 0.9.0+3 |
| collection | 1.19.1 |

SDK constraints (from lockfile): `dart: ">=3.10.3 <4.0.0"`, `flutter: ">=3.38.4"`.

### `flutter analyze`

```
Analyzing flash...
No issues found! (ran in 29.5s)
```

Clean — no mutation needed; `flutter pub get` was not required to run analyze successfully.

### `flutter test`

Full run completed with exit reporting "Some tests failed." Wall-clock: tests progressed from `00:00` to `00:05` (roughly 5 seconds of harness time as reported by the `flutter test` timer prefix; overall command wall time was longer including build/analysis startup).

**Totals: 304 tests attempted, 303 passed, 1 failed, 0 skipped** (test runner counter reached `+303 -1` before the final "Some tests failed." line; the counter format is `+<passed> -<failed>`).

**Failing test (full name + failure message):**

- File: `test/article_summary_sheet_test.dart`
- Test name (verbatim): `a maximum-budget summary fits on one Pixel-class page with no overflow and no scrolling`
- Failure:
```
The following TestFailure was thrown running a test:
Expected: a value less than <914.2857142857143>
  Actual: <1281.0>
   Which: is not a value less than <914.2857142857143>
```
  Thrown from `test/article_summary_sheet_test.dart` line 197, inside the test's anonymous closure (stack frame `main.<anonymous closure>` at `article_summary_sheet_test.dart:197:5`).

Note: sqflite emits a repeated non-fatal informational banner during the run:
```
*** sqflite warning ***
You are changing sqflite default factory.
Be aware of the potential side effects. Any library using sqflite
will have this factory as the default for all operations.
*** sqflite warning ***
```
This appears many times (once per test file/suite using `sqflite_common_ffi`) and is not a failure.

### Flakiness check

Reran the single failing test file directly: `flutter test test/article_summary_sheet_test.dart`. The same test failed again with the identical expectation (`Expected: a value less than <914.2857142857143>`, `Actual: <1281.0>`) at the same line (197). **Not flaky — reproduces deterministically.**

---

## Section 3 — Layout

### lib/ tree (line counts)

```
lib/app.dart                                    287
lib/db/database.dart                            130
lib/db/schema.dart                              143
lib/l10n/app_localizations.dart                1123
lib/l10n/app_localizations_de.dart              557
lib/l10n/app_localizations_en.dart              552
lib/l10n/app_localizations_es.dart              556
lib/l10n/app_localizations_fr.dart              557
lib/l10n/app_localizations_it.dart              556
lib/main.dart                                    32
lib/models/article.dart                         121
lib/models/content_block.dart                    29
lib/models/feed.dart                            116
lib/models/folder.dart                           45
lib/models/keyword_alert.dart                    38
lib/models/keyword_block.dart                    40
lib/models/settings.dart                         83
lib/models/unread_counts.dart                    76
lib/repositories/article_repository.dart        332
lib/repositories/feed_repository.dart           146
lib/repositories/folder_repository.dart          76
lib/repositories/keyword_alert_repository.dart   52
lib/repositories/keyword_repository.dart         57
lib/repositories/settings_repository.dart        54
lib/screens/article_summary_sheet.dart          411
lib/screens/bookmarks_screen.dart               163
lib/screens/feed_screen.dart                    809
lib/screens/feeds_screen.dart                  1130
lib/screens/keyword_alerts_screen.dart          261
lib/screens/keyword_blocklist_screen.dart       376
lib/screens/onboarding_screen.dart              160
lib/screens/reader_screen.dart                  284
lib/screens/search_screen.dart                  159
lib/screens/settings_screen.dart                818
lib/services/article_extractor.dart             179
lib/services/backup_serializer.dart             106
lib/services/drive_backup_service.dart          107
lib/services/favicon_service.dart                39
lib/services/feedly_service.dart                 62
lib/services/gemini_nano_service.dart            94
lib/services/loading_controller.dart             43
lib/services/local_backup_service.dart           60
lib/services/opml_service.dart                  223
lib/services/refresh_service.dart               139
lib/services/rss_service.dart                   276
lib/services/session_read_tracker.dart           46
lib/services/share_service.dart                  14
lib/services/summary_cache.dart                  33
lib/services/summary_formatter.dart              96
lib/services/summary_source.dart                 51
lib/services/thumbnail_service.dart               48
lib/theme/app_theme.dart                        288
lib/utils/constants.dart                          2
lib/utils/date_utils.dart                        21
lib/utils/form_factor.dart                       24
lib/utils/html_utils.dart                        44
lib/utils/keyword_matcher.dart                   21
lib/utils/reading_time.dart                      12
lib/utils/resume_refresh_policy.dart             27
lib/widgets/article_card.dart                   281
lib/widgets/empty_state.dart                     54
lib/widgets/feed_card.dart                      108
lib/widgets/folder_tab_bar.dart                 186
lib/widgets/global_loading_indicator.dart        63
lib/widgets/notification_banner.dart             87
lib/widgets/radial_menu.dart                    329
lib/widgets/shimmer_card.dart                    65
lib/widgets/unread_badge.dart                    37
```

### test/ tree (line counts)

```
test/article_repository_test.dart          332
test/article_summary_sheet_test.dart       244
test/backup_serializer_test.dart           233
test/cleanup_settings_test.dart            207
test/feed_behavior_test.dart               295
test/folder_tab_bar_test.dart              172
test/keyword_matcher_test.dart             100
test/loading_controller_test.dart          140
test/native_summary_contract_test.dart     126
test/newspaper_mode_test.dart               70
test/opml_service_test.dart                211
test/refresh_service_test.dart             153
test/resume_refresh_policy_test.dart       181
test/rss_service_test.dart                 214
test/session_read_scope_test.dart          216
test/session_read_tracker_test.dart        278
test/summary_cache_test.dart               110
test/summary_formatter_test.dart           201
test/summary_latency_test.dart             183
test/summary_source_test.dart              169
test/unread_counts_test.dart               155
test/widget_test.dart                        8
```

### android/app/src/main/kotlin/io/getflash/app/ (line counts)

```
GeminiNanoPlugin.kt   160
MainActivity.kt        45
```

### Platform directories

`macos/`, `windows/`, `web/`, `linux/` directories **do not exist** in this repo. Only `android/` and `ios/` platform folders are present (iOS is present on disk but explicitly out of scope per PRD v1.0 — "No iOS support in v1.0").

---

## Section 4 — API surface of lib/

Signatures only, no bodies. Excludes `lib/l10n/`.

### lib/main.dart
Purpose: app entry point — initializes bindings, DB, and runs `FlashApp`.
Imports: `app.dart`, `db/database.dart`, `services/refresh_service.dart`, `repositories/settings_repository.dart` (approximate; exact list not fully enumerated per file due to space).
Top-level: `void main() async`

### lib/app.dart (287 lines)
Purpose: root `MaterialApp` widget, theme wiring, localization delegates, dynamic color, initial route/onboarding gate.
Public classes: `FlashApp` (StatelessWidget or StatefulWidget) — builds `MaterialApp` with `DynamicColorBuilder`, locale delegates, and theme mode from settings.

### lib/models/article.dart (121 lines) — see Section 5 (full contents reproduced there)

### lib/models/content_block.dart (29 lines)
Purpose: sealed-style union of article content block types used by the extractor and `SummarySource`.
Public classes: `sealed class ContentBlock`; subtypes `HeadingBlock(String text)`, `ParagraphBlock(String text)`, `QuoteBlock(String text)`, `ListBlock(List<String> items)`, `ImageBlock(...)` (fields inferred from usage in `summary_source.dart`).

### lib/models/feed.dart (116 lines)
Purpose: `Feed` data model — id, folderId, title, url, siteUrl, faviconPath, description, articleLimit, lastFetchedAt, lastFetchError, consecutiveFailures, isDead, position, createdAt; `fromMap`/`toMap`/`copyWith` per DB schema (`feeds` table).

### lib/models/folder.dart (45 lines)
Purpose: `Folder` model — id, name, position, createdAt; `fromMap`/`toMap`.

### lib/models/keyword_alert.dart (38 lines)
Purpose: `KeywordAlert` model mirroring `keyword_alerts` table — id, keyword, wholeWord, createdAt.

### lib/models/keyword_block.dart (40 lines)
Purpose: `KeywordBlock` model mirroring `keyword_blocklist` table — id, keyword, wholeWord, createdAt.

### lib/models/settings.dart (83 lines)
Purpose: `AppSettings` typed wrapper over the key/value `settings` table (parses string values into typed getters, e.g. `cleanupAgeDays` clamped 5–20 per `cleanup_settings_test.dart`).

### lib/models/unread_counts.dart (76 lines) — full contents reproduced in Section 6/10 discussion; summary:
Public class `UnreadCounts`: fields `final int all`, `final Map<int,int> byFolder`; constructors `UnreadCounts({required int all, required Map<int,int> byFolder})`, `UnreadCounts.empty()`, factory `UnreadCounts.fromRepository({required int total, required Map<int,int> byFolder})`; methods `int forFolder(int folderId)`, `UnreadCounts applyRead(int? folderId)`, `UnreadCounts applyUnread(int? folderId)`, `UnreadCounts applyManyRead(Iterable<int?> folderIds)`, `UnreadCounts clearedAll()`, `UnreadCounts clearedFolder(int folderId)`; overrides `operator ==`, `hashCode`.

### lib/repositories/article_repository.dart (332 lines) — full contents in Section 5.

### lib/repositories/feed_repository.dart (146 lines)
Purpose: CRUD + query for `feeds` table (getAll, add, update, delete, position reorder, failure tracking).
Imports: `../db/database.dart`, `../db/schema.dart`, `../models/feed.dart`.

### lib/repositories/folder_repository.dart (76 lines)
Purpose: CRUD for `folders` table.
Imports: `../db/database.dart`, `../db/schema.dart`, `../models/folder.dart`.

### lib/repositories/keyword_alert_repository.dart (52 lines)
Purpose: CRUD for `keyword_alerts`; static helper `findHits(...)` used by `RefreshService` to compute keyword-alert notification hits against newly-unblocked articles.
Public: `class KeywordAlertRepository` with `Future<List<KeywordAlert>> getAll()`, `static List<String> findHits(List<({String title, String? description})> items, List<KeywordAlert> alerts)` (signature inferred from call site in `refresh_service.dart`).

### lib/repositories/keyword_repository.dart (57 lines)
Purpose: CRUD for `keyword_blocklist`.

### lib/repositories/settings_repository.dart (54 lines)
Purpose: key/value accessor over `settings` table.
Public: `class SettingsRepository` with `Future<String?> get(String key)`, `Future<void> set(String key, String value)`, `Future<AppSettings> getAll()`.

### lib/screens/article_summary_sheet.dart (411 lines)
Purpose: bottom-sheet UI presenting the AI (Gemini Nano) summary of an article; streaming reveal, scroll-on-overflow behavior (subject of the one failing test).
Public class: `ArticleSummarySheet` (likely StatefulWidget) taking article title/content; private `_ArticleSummarySheetState` fields inferred to include stream subscription, revealed text buffer, and a `ScrollController`.

### lib/screens/bookmarks_screen.dart (163 lines)
Purpose: saved/bookmarked articles list screen.

### lib/screens/feed_screen.dart (809 lines) — key excerpt in Section 6/12; contains `_refreshCountsFromDb()`, `_flushMarkReadUI()`, `_openArticle()`, session-read scope wiring, scroll-debounced mark-read.

### lib/screens/feeds_screen.dart (1130 lines)
Purpose: largest screen file — feed/folder management (add/edit/remove feed, reorder, folder tabs, OPML import/export entry points).

### lib/screens/keyword_alerts_screen.dart (261 lines)
Purpose: manage keyword alert list (add/remove alert keywords).

### lib/screens/keyword_blocklist_screen.dart (376 lines)
Purpose: manage keyword blocklist (add/remove/whole-word toggle, retroactive blocking trigger).

### lib/screens/onboarding_screen.dart (160 lines)
Purpose: first-run onboarding flow gated by `onboarding_complete` setting.

### lib/screens/reader_screen.dart (284 lines)
Purpose: in-app article reader (extracted content rendering, font size, reader mode).

### lib/screens/search_screen.dart (159 lines)
Purpose: article search UI backed by `ArticleRepository.search`.

### lib/screens/settings_screen.dart (818 lines)
Purpose: all user-facing settings (theme, refresh interval, article limits, backup, newspaper mode, reader mode, mark-read-on-scroll, etc.) — see Section 10.

### lib/services/article_extractor.dart (179 lines)
Purpose: parses fetched HTML into `ContentBlock` list for reader + summary source.

### lib/services/backup_serializer.dart (106 lines)
Purpose: serializes folders/feeds/keywords to a versioned backup map (version always 1 per tests) and restores from it; explicitly excludes read/unread state, API keys, bookmarks.

### lib/services/drive_backup_service.dart (107 lines)
Purpose: Google Drive backup/restore using `googleapis` + `google_sign_in`.

### lib/services/favicon_service.dart (39 lines)
Purpose: fetch/cache feed favicons.

### lib/services/feedly_service.dart (62 lines)
Purpose: Feedly API key integration (import via `feedly_api_key` setting).

### lib/services/gemini_nano_service.dart (94 lines) — full contents in Section 5.

### lib/services/loading_controller.dart (43 lines) — full contents in Section 5.

### lib/services/local_backup_service.dart (60 lines)
Purpose: local file export/import of backup JSON via `file_picker`.

### lib/services/opml_service.dart (223 lines)
Purpose: OPML generate/parse for feed import/export; XML escaping of folder/feed names.

### lib/services/refresh_service.dart (139 lines) — full contents in Section 5.

### lib/services/rss_service.dart (276 lines)
Purpose: fetch + parse RSS/Atom feeds (`dart_rss`), apply fetch-day/article-count thresholds, resolve GUIDs, store via `ArticleRepository`, apply keyword blocking on ingest.
Key statics used by tests: `resolveGuid`, `applyFetchThresholds` (per `rss_service_test.dart` group names).

### lib/services/session_read_tracker.dart (46 lines) — full contents in Section 5.

### lib/services/share_service.dart (14 lines)
Purpose: thin wrapper around `share_plus` for sharing article URLs.

### lib/services/summary_cache.dart (33 lines)
Purpose: bounded (50-entry) URL-keyed cache for generated AI summaries; evicts oldest on 51st insert (LRU-ish); empty/whitespace puts are no-ops and do not evict existing entries.

### lib/services/summary_formatter.dart (96 lines)
Purpose: post-processes raw model output — strips "Summary:" preambles and markdown bold, normalizes bullet markers to `"- "`, caps to 8 bullets, applies a word ceiling, collapses whitespace; idempotent.

### lib/services/summary_source.dart (51 lines) — full contents in Section 5.

### lib/services/thumbnail_service.dart (48 lines)
Purpose: downloads/caches article thumbnail images to local paths, updates `thumbnail_path` via `ArticleRepository.updateThumbnailPath`.

### lib/theme/app_theme.dart (288 lines)
Purpose: Material 3 theme construction incl. dynamic color, dark/light, and `flashNewspaperTheme` (light theme on a newsprint paper surface, ink text color, spot-red primary accent, serif body/display fonts — per `newspaper_mode_test.dart`).

### lib/utils/constants.dart (2 lines) — full contents in Section 5.

### lib/utils/date_utils.dart (21 lines)
Purpose: relative time formatting helpers (feeds `timeJustNow`/`timeMinAgo`/etc. ARB keys).

### lib/utils/form_factor.dart (24 lines)
Purpose: device form-factor detection (e.g. TV via the `io.getflash.app/device` `isTV` channel).

### lib/utils/html_utils.dart (44 lines)
Purpose: HTML text-cleanup helpers.

### lib/utils/keyword_matcher.dart (21 lines)
Purpose: `KeywordMatcher.buildHaystack(title, description)` and `KeywordMatcher.matches(keyword, haystack, {wholeWord})` — case-insensitive substring or whole-word regex matching.

### lib/utils/reading_time.dart (12 lines)
Purpose: estimated reading time calculation from word count.

### lib/utils/resume_refresh_policy.dart (27 lines) — full contents in Section 5.

### lib/widgets/article_card.dart (281 lines)
Purpose: feed-list article row/card widget (thumbnail, title, dim-on-read opacity, swipe actions host).

### lib/widgets/empty_state.dart (54 lines)
Purpose: generic empty-state placeholder widget.

### lib/widgets/feed_card.dart (108 lines)
Purpose: feed row widget for feeds/folder management screen.

### lib/widgets/folder_tab_bar.dart (186 lines)
Purpose: top folder tab bar; declares a public height constant (≥56dp per test), enforces ≥48dp tap targets, shows/hides unread badges (hidden at zero).

### lib/widgets/global_loading_indicator.dart (63 lines)
Purpose: app-wide loading indicator bound to `LoadingController.instance`.

### lib/widgets/notification_banner.dart (87 lines)
Purpose: in-app banner (e.g. new-articles/keyword-alert banners).

### lib/widgets/radial_menu.dart (329 lines)
Purpose: radial/contextual menu widget (largest widget file besides article_card).

### lib/widgets/shimmer_card.dart (65 lines)
Purpose: shimmer loading placeholder card (uses `shimmer` package).

### lib/widgets/unread_badge.dart (37 lines)
Purpose: small unread-count badge widget used by folder tabs.

---

## Section 5 — Hot files, verbatim

### lib/services/summary_source.dart

```dart
import '../models/content_block.dart';

/// Turns extracted [ContentBlock]s into the plain text handed to the model.
class SummarySource {
  static const int defaultMaxChars = 2500;

  static String fromBlocks(
    List<ContentBlock>? blocks, {
    String? fallback,
    int maxChars = defaultMaxChars,
  }) {
    if (blocks == null || blocks.isEmpty) return fallback ?? '';

    final parts = <String>[];
    for (final block in blocks) {
      switch (block) {
        case HeadingBlock():
          parts.add(block.text);
        case ParagraphBlock():
          parts.add(block.text);
        case QuoteBlock():
          parts.add(block.text);
        case ListBlock():
          parts.add(block.items.join('\n'));
        case ImageBlock():
          break;
      }
    }

    var text = parts.join('\n\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (text.isEmpty) return fallback ?? '';
    if (text.length > maxChars) text = _truncate(text, maxChars);
    return text;
  }

  static String _truncate(String text, int maxChars) {
    const ellipsis = '…';
    final limit = maxChars - ellipsis.length;
    if (limit <= 0) return ellipsis.substring(0, maxChars);

    var cut = text.substring(0, limit);
    final lastSpace = cut.lastIndexOf(RegExp(r'\s'));
    if (lastSpace > 0) cut = cut.substring(0, lastSpace);
    return cut.trimRight() + ellipsis;
  }

  /// Roughly: is there enough text here to be worth summarising?
  static bool isSubstantial(String text) => text.trim().length >= 400;
}
```

### lib/services/gemini_nano_service.dart

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Flutter wrapper around the native Gemini Nano (Android AICore) bridge.
///
/// All methods degrade gracefully when the device doesn't support AICore.
class GeminiNanoService {
  static const _channel = MethodChannel('io.getflash.app/gemini_nano');

  static GeminiNanoService? _instance;
  static GeminiNanoService get instance => _instance ??= GeminiNanoService._();

  /// Test-only: clears the singleton (and its cached availability) so each
  /// test starts from a clean state. No-op impact on production code paths.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  GeminiNanoService._() {
    // Handle native→Flutter calls (streaming summary chunks)
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  // ── Availability ─────────────────────────────────────────────────────────

  bool? _available;
  String? _unavailableReason;

  String? get unavailableReason => _unavailableReason;

  Future<bool> get isAvailable async {
    if (_available != null) return _available!;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
    } on PlatformException catch (e) {
      // Don't cache DOWNLOADING — let it retry next open
      _available = e.code == 'NANO_DOWNLOADING' ? null : false;
      _unavailableReason = e.code == 'NANO_DOWNLOADING' ? e.message : '${e.code}: ${e.message}';
    } catch (e) {
      _available = false;
      _unavailableReason = e.toString();
    }
    return _available ?? false;
  }

  // ── Streaming summarise ───────────────────────────────────────────────────

  StreamController<String>? _summaryController;
  String _summaryBuffer = '';

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'summaryChunk':
        _summaryBuffer += (call.arguments as String? ?? '');
        _summaryController?.add(_summaryBuffer);
      case 'summaryDone':
        await _summaryController?.close();
        _summaryController = null;
      case 'summaryError':
        _summaryController?.addError(call.arguments as String? ?? 'Unknown error');
        await _summaryController?.close();
        _summaryController = null;
    }
  }

  /// Starts streaming a summary. Returns a [Stream<String>] that emits the
  /// accumulated text so far on each new chunk, finishing when generation ends.
  /// Returns null if unavailable.
  Future<Stream<String>?> summarizeStream(String title, String content, {String locale = 'en'}) async {
    if (!await isAvailable) return null;

    // Cancel any in-progress summary
    await _summaryController?.close();
    _summaryBuffer = '';
    _summaryController = StreamController<String>();

    // Fire-and-forget — result is null (acknowledged immediately by native)
    unawaited(_channel.invokeMethod<void>('summarize', {
      'title': title,
      'content': content,
      'locale': locale,
    }).catchError((_) {
      _summaryController?.addError('Failed to start summarization');
      _summaryController?.close();
      _summaryController = null;
    }));

    return _summaryController!.stream;
  }

}
```

### lib/services/session_read_tracker.dart

```dart
/// Scope key for the All tab. Negative so it can never collide with a
/// folder_id, which is a positive autoincrement value.
const int kAllScope = -1;

/// In-memory, scope-keyed sets of article IDs read during the current app
/// session. Empty at process start; never persisted to disk.
///
/// An article read in one scope (tab) is visible only in that scope for the
/// rest of the session — not in any other.
class SessionReadTracker {
  SessionReadTracker._();
  static final SessionReadTracker instance = SessionReadTracker._();

  final Map<int, Set<int>> _byScope = {};

  Set<int> idsForScope(int scope) =>
      Set.unmodifiable(_byScope[scope] ?? const <int>{});

  bool isReadInScope(int id, int scope) =>
      _byScope[scope]?.contains(id) ?? false;

  Set<int> get allIds => _byScope.values.expand((s) => s).toSet();

  void add(int id, {required int scope}) {
    _byScope.putIfAbsent(scope, () => {}).add(id);
  }

  void addAll(Iterable<int> ids, {required int scope}) {
    if (ids.isEmpty) return;
    _byScope.putIfAbsent(scope, () => {}).addAll(ids);
  }

  void removeEverywhere(int id) {
    for (final scopeSet in _byScope.values) {
      scopeSet.remove(id);
    }
  }

  void clearScope(int scope) {
    _byScope[scope]?.clear();
  }

  void clear() {
    _byScope.clear();
  }
}
```

### lib/services/loading_controller.dart

```dart
import 'package:flutter/foundation.dart';

/// Global, reference-counted busy flag. One instance, app-wide.
class LoadingController extends ChangeNotifier {
  static final LoadingController instance = LoadingController._();

  LoadingController._();

  int _activeCount = 0;
  final List<String?> _labels = [];

  bool get isBusy => _activeCount > 0;
  int get activeCount => _activeCount;
  String? get label => _labels.isEmpty ? null : _labels.last;

  void begin([String? label]) {
    _activeCount++;
    _labels.add(label);
    notifyListeners();
  }

  void end() {
    if (_activeCount == 0) return;
    _activeCount--;
    if (_labels.isNotEmpty) _labels.removeLast();
    notifyListeners();
  }

  Future<T> run<T>(Future<T> Function() action, {String? label}) async {
    begin(label);
    try {
      return await action();
    } finally {
      end();
    }
  }

  void reset() {
    _activeCount = 0;
    _labels.clear();
    notifyListeners();
  }
}
```

### lib/services/refresh_service.dart

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import '../models/feed.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import 'rss_service.dart';

const String kRefreshTaskName = 'flash_feed_refresh';
const String kRefreshTaskUniqueName = 'flash_feed_refresh_periodic';
const String _kKeywordChannelId = 'flash_keyword_alerts';
const String _kKeywordChannelName = 'Keyword alerts';
const int _kKeywordNotificationId = 2;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kRefreshTaskName) {
      try {
        // Background job: run cleanup first, then fetch.
        await _doRefresh(runCleanup: true);
      } catch (_) {}
    }
    return true;
  });
}

Future<FlutterLocalNotificationsPlugin> _initPlugin() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));
  return plugin;
}

Future<void> _showKeywordNotification(List<String> keywords) async {
  final plugin = await _initPlugin();
  final label = keywords.length == 1
      ? '"${keywords.first}"'
      : keywords.map((k) => '"$k"').join(', ');
  await plugin.show(
    _kKeywordNotificationId,
    'Flash — keyword alert',
    'New articles matching $label',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _kKeywordChannelId,
        _kKeywordChannelName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showWhen: true,
      ),
    ),
  );
}

/// Core refresh logic shared across cold start, background, and pull-to-refresh.
///
/// [runCleanup] — true for cold start and background; false for pull-to-refresh.
/// [feeds] — if provided, only these feeds are fetched; otherwise all feeds.
Future<int> _doRefresh({bool runCleanup = false, List<Feed>? feeds}) async {
  final articleRepo = ArticleRepository();
  final feedRepo = FeedRepository();
  final keywordRepo = KeywordRepository();
  final alertRepo = KeywordAlertRepository();
  final settingsRepo = SettingsRepository();

  // Cleanup must complete before any inserts (cold start and background only).
  if (runCleanup) {
    final settings = await settingsRepo.getAll();
    await articleRepo.runCleanup(days: settings.cleanupAgeDays);
  }

  final keywords = await keywordRepo.getAll();
  final alerts = await alertRepo.getAll();
  final rssService = RssService(articleRepo, feedRepo);
  final feedList = feeds ?? await feedRepo.getAll();

  int totalNew = 0;
  final allUnblocked = <({String title, String? description})>[];

  await Future.wait(feedList.map((feed) async {
    final result = await rssService.fetchAndStore(feed, keywords: keywords);
    totalNew += result.newCount;
    allUnblocked.addAll(result.unblocked);
  }));

  if (alerts.isNotEmpty && allUnblocked.isNotEmpty) {
    final hits = KeywordAlertRepository.findHits(allUnblocked, alerts);
    if (hits.isNotEmpty) await _showKeywordNotification(hits);
  }

  return totalNew;
}

class RefreshService {
  final SettingsRepository _settingsRepo;

  RefreshService(this._settingsRepo);

  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
    await schedulePeriodicRefresh();
  }

  Future<void> schedulePeriodicRefresh({bool forceReschedule = false}) async {
    final intervalStr =
        await _settingsRepo.get('refresh_interval_minutes') ?? '30';
    final intervalMinutes = int.tryParse(intervalStr) ?? 30;

    if (intervalMinutes == 0) {
      await Workmanager().cancelByUniqueName(kRefreshTaskUniqueName);
      return;
    }

    await Workmanager().registerPeriodicTask(
      kRefreshTaskUniqueName,
      kRefreshTaskName,
      frequency: Duration(minutes: intervalMinutes),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: forceReschedule
          ? ExistingPeriodicWorkPolicy.replace
          : ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Fetch all feeds.
  /// [coldStart] — true on app cold open; runs cleanup before fetching.
  Future<int> refreshAll({bool coldStart = false}) =>
      _doRefresh(runCleanup: coldStart);

  /// Refresh a single feed without running cleanup.
  Future<int> refreshFeed(Feed feed) =>
      _doRefresh(runCleanup: false, feeds: [feed]);
}
```

### lib/repositories/article_repository.dart

```dart
import 'package:sqflite/sqflite.dart';
import '../db/database.dart';
import '../db/schema.dart';
import '../models/article.dart';
import '../utils/keyword_matcher.dart';
import '../utils/constants.dart';

class ArticleRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  // ── Insert ─────────────────────────────────────────────────────────────────

  /// Insert articles for a feed using INSERT OR IGNORE to deduplicate.
  /// An existing row (same feed_id + guid) is silently skipped — never reset to unread.
  Future<void> insertArticles(int feedId, List<Article> articles) async {
    if (articles.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    final fetchedAt = DateTime.now().millisecondsSinceEpoch;
    for (final a in articles) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO ${TableNames.articles}
        (feed_id, guid, title, url, description, thumbnail_url, thumbnail_path,
         published_at, fetched_at, is_read, is_blocked, is_saved, blocked_keyword)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 0, ?)
      ''', [
        feedId,
        a.guid,
        a.title,
        a.url,
        a.description,
        a.thumbnailUrl,
        a.thumbnailPath,
        a.publishedAt,
        fetchedAt,
        a.isBlocked ? 1 : 0,
        a.blockedKeyword,
      ]);
    }
    await batch.commit(noResult: true);
  }

  // ── Read queries ───────────────────────────────────────────────────────────

  /// Unblocked articles across all folders that are either unread OR in
  /// [sessionReadIds] (read this session). Newest first.
  Future<List<Article>> getAllArticles({Set<int> sessionReadIds = const {}}) async {
    final db = await _db;
    final (where, args) = _unionClause(null, sessionReadIds);
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE $where
      ORDER BY a.published_at DESC
    ''', args);
    return rows.map(Article.fromMap).toList();
  }

  /// Unblocked articles for a specific folder that are either unread OR in
  /// [sessionReadIds] (read this session). Newest first.
  Future<List<Article>> getArticlesByFolder(
    int folderId, {
    Set<int> sessionReadIds = const {},
  }) async {
    final db = await _db;
    final (where, args) = _unionClause(folderId, sessionReadIds);
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE $where
      ORDER BY a.published_at DESC
    ''', args);
    return rows.map(Article.fromMap).toList();
  }

  /// Builds the WHERE clause and args for the union query.
  /// Scope: all folders when [folderId] is null; a specific folder otherwise.
  (String, List<Object?>) _unionClause(int? folderId, Set<int> sessionReadIds) {
    final buf = StringBuffer();
    final args = <Object?>[];
    if (folderId != null) {
      buf.write('f.folder_id = ? AND ');
      args.add(folderId);
    }
    buf.write('a.is_blocked = 0 AND (a.is_read = 0');
    if (sessionReadIds.isNotEmpty) {
      buf.write(
        ' OR a.id IN (${List.filled(sessionReadIds.length, '?').join(',')})',
      );
      args.addAll(sessionReadIds);
    }
    buf.write(')');
    return (buf.toString(), args);
  }

  Future<List<Article>> getSaved() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_saved = 1
      ORDER BY a.published_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getBlocked() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 1
      ORDER BY a.fetched_at DESC
    ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await _db;
    final pattern = '%${query.trim()}%';
    final rows = await db.rawQuery('''
      SELECT a.*, f.title AS feed_title, f.favicon_path AS feed_favicon_path
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_blocked = 0
        AND (a.title LIKE ? OR a.description LIKE ?)
      ORDER BY a.published_at DESC
      LIMIT 100
    ''', [pattern, pattern]);
    return rows.map(Article.fromMap).toList();
  }

  // ── Counts ─────────────────────────────────────────────────────────────────

  /// Total unread count across all folders.
  Future<int> getTotalUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
    ''');
    return result.first['cnt'] as int;
  }

  /// Unread count for a single folder.
  Future<int> getUnreadCount(int folderId) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE f.folder_id = ? AND a.is_read = 0 AND a.is_blocked = 0
    ''', [folderId]);
    return result.first['cnt'] as int;
  }

  /// Unread counts for every folder in one query, keyed by folder_id.
  Future<Map<int, int>> getAllFolderUnreadCounts() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT f.folder_id, COUNT(*) AS cnt
      FROM ${TableNames.articles} a
      JOIN ${TableNames.feeds} f ON a.feed_id = f.id
      WHERE a.is_read = 0 AND a.is_blocked = 0
        AND f.folder_id IS NOT NULL
      GROUP BY f.folder_id
    ''');
    return {for (final row in rows) row['folder_id'] as int: row['cnt'] as int};
  }

  // ── Mark read / unread ─────────────────────────────────────────────────────

  Future<void> markAsRead(int articleId) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<void> markAsUnread(int articleId) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  Future<void> markManyRead(List<int> articleIds) async {
    if (articleIds.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final id in articleIds) {
      batch.update(
        TableNames.articles,
        {'is_read': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markAllAsRead() async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_read': 1},
      where: 'is_blocked = 0',
    );
  }

  Future<void> markAllAsReadByFolder(int folderId) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${TableNames.articles}
      SET is_read = 1
      WHERE feed_id IN (
        SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
      ) AND is_blocked = 0
    ''', [folderId]);
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Delete read (and not saved) articles older than [days] days (default: [kFetchDayLimit]).
  /// [days] is clamped to [5, 20].
  /// Scoped to [folderId] if provided; otherwise applies to all feeds.
  /// Returns the number of rows deleted.
  Future<int> runCleanup({int? folderId, int days = kFetchDayLimit}) async {
    final db = await _db;
    final clampedDays = days.clamp(5, 20);
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: clampedDays))
        .millisecondsSinceEpoch;
    if (folderId == null) {
      return db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1
          AND is_saved = 0
          AND published_at < ?
      ''', [cutoffMs]);
    } else {
      return db.rawDelete('''
        DELETE FROM ${TableNames.articles}
        WHERE is_read = 1
          AND is_saved = 0
          AND published_at < ?
          AND feed_id IN (
            SELECT id FROM ${TableNames.feeds} WHERE folder_id = ?
          )
      ''', [cutoffMs, folderId]);
    }
  }

  // ── Saved / bookmarks ──────────────────────────────────────────────────────

  Future<void> setSaved(int articleId, {required bool saved}) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_saved': saved ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // ── Thumbnails ─────────────────────────────────────────────────────────────

  Future<void> updateThumbnailPath(int articleId, String path) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'thumbnail_path': path},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  // ── Keyword blocking ───────────────────────────────────────────────────────

  Future<void> retroactivelyBlock(String keyword, bool wholeWord) async {
    final db = await _db;
    final rows = await db.query(
      TableNames.articles,
      columns: ['id', 'title', 'description'],
      where: 'is_blocked = 0',
    );
    final batch = db.batch();
    for (final row in rows) {
      final haystack = KeywordMatcher.buildHaystack(
        row['title'] as String,
        row['description'] as String?,
      );
      if (KeywordMatcher.matches(keyword, haystack, wholeWord: wholeWord)) {
        batch.update(
          TableNames.articles,
          {'is_blocked': 1, 'blocked_keyword': keyword},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> unblockByKeyword(String keyword) async {
    final db = await _db;
    await db.update(
      TableNames.articles,
      {'is_blocked': 0, 'blocked_keyword': null},
      where: 'blocked_keyword = ?',
      whereArgs: [keyword],
    );
  }

  // ── Backward-compatible aliases ────────────────────────────────────────────

  Future<void> markRead(int id) => markAsRead(id);
  Future<void> markUnread(int id) => markAsUnread(id);
}
```

### lib/db/schema.dart

```dart
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
```

### lib/db/database.dart

```dart
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
      version: 7,
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
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
```

### lib/models/article.dart

```dart
class Article {
  final int? id;
  final int feedId;
  final String guid;
  final String title;
  final String url;
  final String? description;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final int? publishedAt;
  final int fetchedAt;
  final bool isRead;
  final bool isBlocked;
  final bool isSaved;
  final String? blockedKeyword;

  // Joined fields (not stored in DB)
  final String? feedTitle;
  final String? feedFaviconPath;

  const Article({
    this.id,
    required this.feedId,
    required this.guid,
    required this.title,
    required this.url,
    this.description,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.publishedAt,
    required this.fetchedAt,
    this.isRead = false,
    this.isBlocked = false,
    this.isSaved = false,
    this.blockedKeyword,
    this.feedTitle,
    this.feedFaviconPath,
  });

  factory Article.fromMap(Map<String, dynamic> map) {
    return Article(
      id: map['id'] as int?,
      feedId: map['feed_id'] as int,
      guid: map['guid'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      description: map['description'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      publishedAt: map['published_at'] as int?,
      fetchedAt: map['fetched_at'] as int,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      isBlocked: (map['is_blocked'] as int? ?? 0) == 1,
      isSaved: (map['is_saved'] as int? ?? 0) == 1,
      blockedKeyword: map['blocked_keyword'] as String?,
      feedTitle: map['feed_title'] as String?,
      feedFaviconPath: map['feed_favicon_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'feed_id': feedId,
      'guid': guid,
      'title': title,
      'url': url,
      'description': description,
      'thumbnail_url': thumbnailUrl,
      'thumbnail_path': thumbnailPath,
      'published_at': publishedAt,
      'fetched_at': fetchedAt,
      'is_read': isRead ? 1 : 0,
      'is_blocked': isBlocked ? 1 : 0,
      'is_saved': isSaved ? 1 : 0,
      'blocked_keyword': blockedKeyword,
    };
  }

  Article copyWith({
    int? id,
    int? feedId,
    String? guid,
    String? title,
    String? url,
    String? description,
    String? thumbnailUrl,
    String? thumbnailPath,
    int? publishedAt,
    int? fetchedAt,
    bool? isRead,
    bool? isBlocked,
    bool? isSaved,
    String? blockedKeyword,
    String? feedTitle,
    String? feedFaviconPath,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      url: url ?? this.url,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isRead: isRead ?? this.isRead,
      isBlocked: isBlocked ?? this.isBlocked,
      isSaved: isSaved ?? this.isSaved,
      blockedKeyword: blockedKeyword ?? this.blockedKeyword,
      feedTitle: feedTitle ?? this.feedTitle,
      feedFaviconPath: feedFaviconPath ?? this.feedFaviconPath,
    );
  }

  DateTime? get publishedDateTime => publishedAt != null
      ? DateTime.fromMillisecondsSinceEpoch(publishedAt!)
      : null;
}
```

### lib/utils/constants.dart

```dart
const int kFetchDayLimit = 7;
const int kFetchArticleLimit = 100;
```

### lib/utils/resume_refresh_policy.dart

```dart
/// Decides whether returning to the app from the background should trigger
/// a network fetch. A DB reload always happens on resume; this policy only
/// gates the network call.
class ResumeRefreshPolicy {
  final Duration minBackgroundDuration;
  final Duration minFetchInterval;

  const ResumeRefreshPolicy({
    this.minBackgroundDuration = const Duration(seconds: 30),
    this.minFetchInterval = const Duration(minutes: 5),
  });

  bool shouldFetch({
    required DateTime? pausedAt,
    required DateTime resumedAt,
    required DateTime? lastFetchAt,
  }) {
    if (pausedAt == null) return false;
    if (pausedAt.isAfter(resumedAt)) return false;
    if (resumedAt.difference(pausedAt) < minBackgroundDuration) return false;
    if (lastFetchAt != null) {
      if (lastFetchAt.isAfter(resumedAt)) return false;
      if (resumedAt.difference(lastFetchAt) < minFetchInterval) return false;
    }
    return true;
  }
}
```

### android/app/src/main/kotlin/io/getflash/app/GeminiNanoPlugin.kt

```kotlin
package io.getflash.app

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

class GeminiNanoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var model: GenerativeModel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "io.getflash.app/gemini_nano")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        model?.close()
        model = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable"   -> checkAvailability(result)
            "summarize"     -> {
                val title   = call.argument<String>("title") ?: ""
                val content = call.argument<String>("content") ?: ""
                val locale  = call.argument<String>("locale") ?: "en"
                summarize(title, content, locale, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun getModel(): GenerativeModel {
        if (model == null) model = Generation.getClient()
        return model!!
    }

    private fun checkAvailability(result: MethodChannel.Result) {
        scope.launch {
            try {
                val status = getModel().checkStatus()
                when (status) {
                    FeatureStatus.AVAILABLE -> mainThread { result.success(true) }
                    FeatureStatus.DOWNLOADABLE -> {
                        scope.launch {
                            try { getModel().download().collect {} } catch (_: Exception) {}
                        }
                        mainThread {
                            result.error("NANO_DOWNLOADING",
                                "Gemini Nano model is downloading. Try again in a moment.", null)
                        }
                    }
                    FeatureStatus.DOWNLOADING -> mainThread {
                        result.error("NANO_DOWNLOADING",
                            "Gemini Nano model is still downloading. Try again in a moment.", null)
                    }
                    else -> mainThread {
                        result.error("NANO_UNAVAILABLE", "Feature status: $status", null)
                    }
                }
            } catch (e: Exception) {
                mainThread { result.error("NANO_UNAVAILABLE", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun langInstructionFor(locale: String): String = when (locale) {
        "es" -> "Write the summary in Spanish."
        "fr" -> "Write the summary in French."
        "de" -> "Write the summary in German."
        "it" -> "Write the summary in Italian."
        else -> "Write the summary in English."
    }

    private fun writePrompt(title: String, langInstruction: String, source: String): String {
        return """
You are a ruthless news summariser. Report only what the article text states.

$langInstruction

RULES
1. The headline makes a promise. Deliver it in the first line. If the headline
   names a count of things ("4 games", "three changes"), list exactly those
   things, one per line, before anything else.
2. Facts only: names, numbers, dates, prices, versions, outcomes, who did what.
   Every line must contain at least one concrete fact.
3. Never write filler such as "aims to", "is expected to", "will likely",
   "is set to", "generating excitement", "fans are eager", "remains to be seen",
   or "details are scarce". If a thing is not stated, leave it out entirely.
4. Do not restate the headline. Do not describe what the article is about.
   Report what it says.
5. Never infer, guess, or fill gaps with general knowledge.
6. 120 words maximum. Shorter is always better. Stop when the facts run out.
7. No preamble, no sign-off, no headers, no markdown bold.

FORMAT
Line 1: the single most important fact, one sentence.
Then up to 5 lines, each starting with "- ", each a distinct fact.
If the article names specific items, one line per item:
  - Name — what it is, under 12 words.

IF THE TEXT IS THIN
If the text below is only a teaser and lacks the details the headline promises,
output the facts that are present and then stop. Do not compensate for missing
detail by writing longer.

ARTICLE
Title: $title

$source

Summary:
""".trimIndent()
    }

    // Streams chunks back to Flutter via reverse invokeMethod calls so text
    // appears as it generates rather than waiting for the full response.
    private fun summarize(title: String, body: String, locale: String, result: MethodChannel.Result) {
        // Acknowledge immediately so Flutter's await returns
        result.success(null)
        scope.launch {
            try {
                // 2500 chars covers the lede and substantive middle of a news
                // article — where list-type payloads live — and cuts
                // time-to-first-token materially versus sending the whole body.
                val trimmed = body.take(2500)
                val langInstruction = langInstructionFor(locale)
                val prompt = writePrompt(title, langInstruction, "Content: $trimmed")

                withTimeout(20_000) {
                    getModel().generateContentStream(prompt).collect { response ->
                        val chunk = response.candidates.firstOrNull()?.text ?: ""
                        if (chunk.isNotEmpty()) {
                            mainThread { channel.invokeMethod("summaryChunk", chunk) }
                        }
                    }
                }
                mainThread { channel.invokeMethod("summaryDone", null) }
            } catch (e: Exception) {
                mainThread { channel.invokeMethod("summaryError", e.message ?: "Unknown error") }
            }
        }
    }

    private fun mainThread(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}
```

### android/app/src/main/kotlin/io/getflash/app/MainActivity.kt

```kotlin
package io.getflash.app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "io.getflash.app/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(GeminiNanoPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTV" -> {
                        val mgr = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(mgr.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Re-apply the correct window background whenever the app regains focus
    // (e.g. returning from browser). Since uiMode is in configChanges the
    // Activity never restarts on dark/light toggle, so the background set at
    // launch can go stale. This keeps it in sync.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            val isNight = (resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            window.setBackgroundDrawable(
                ColorDrawable(if (isNight) Color.parseColor("#0D1B2A") else Color.WHITE)
            )
        }
    }
}
```

---

## Section 6 — Data layer

### Schema version

- `AppDatabase._initDatabase()` (`lib/db/database.dart:43`) opens with `version: 7`.
- `defaultSettings` in `lib/db/schema.dart` seeds a row `{'key': 'schema_version', 'value': '3'}` — **these two numbers differ** (sqflite DB version = 7; the seeded `schema_version` setting value = `'3'`). The setting is a separate, apparently stale/unrelated app-level counter last bumped explicitly at oldVersion<5 migration (`INSERT OR REPLACE ... ('schema_version', '3', ...)`), while the sqflite `version:` argument has since advanced to 7 via migrations 5→6 and 6→7 without a corresponding bump to the `schema_version` setting row.

### Tables (from schema.dart)

**folders**: `id INTEGER PK AUTOINCREMENT`, `name TEXT NOT NULL`, `position INTEGER NOT NULL DEFAULT 0`, `created_at INTEGER NOT NULL`.

**feeds**: `id INTEGER PK AUTOINCREMENT`, `folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE`, `title TEXT NOT NULL`, `url TEXT NOT NULL UNIQUE`, `site_url TEXT`, `favicon_path TEXT`, `description TEXT`, `article_limit INTEGER`, `last_fetched_at INTEGER`, `last_fetch_error TEXT`, `consecutive_failures INTEGER NOT NULL DEFAULT 0`, `is_dead INTEGER NOT NULL DEFAULT 0 CHECK(is_dead IN (0,1))`, `position INTEGER NOT NULL DEFAULT 0`, `created_at INTEGER NOT NULL`. Index: `idx_feeds_folder_id ON feeds(folder_id)`.

**articles**: `id INTEGER PK AUTOINCREMENT`, `feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE`, `guid TEXT NOT NULL`, `title TEXT NOT NULL`, `url TEXT NOT NULL`, `description TEXT`, `thumbnail_url TEXT`, `thumbnail_path TEXT`, `published_at INTEGER`, `fetched_at INTEGER NOT NULL`, `is_read INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0,1))`, `is_blocked INTEGER NOT NULL DEFAULT 0 CHECK(is_blocked IN (0,1))`, `is_saved INTEGER NOT NULL DEFAULT 0 CHECK(is_saved IN (0,1))`, `blocked_keyword TEXT`. Indexes: `idx_articles_guid_feed UNIQUE (feed_id, guid)`, `idx_articles_feed_id (feed_id)`, `idx_articles_is_read (is_read)`, `idx_articles_is_blocked (is_blocked)`, `idx_articles_published_at (published_at DESC)`, `idx_articles_read_published (is_read, published_at DESC)`, `idx_articles_feed_read_published (feed_id, is_read, published_at DESC)`.

**keyword_blocklist**: `id INTEGER PK AUTOINCREMENT`, `keyword TEXT NOT NULL UNIQUE COLLATE NOCASE`, `whole_word INTEGER NOT NULL DEFAULT 0 CHECK(whole_word IN (0,1))`, `created_at INTEGER NOT NULL`.

**keyword_alerts**: `id INTEGER PK AUTOINCREMENT`, `keyword TEXT NOT NULL UNIQUE`, `whole_word INTEGER NOT NULL DEFAULT 0 CHECK(whole_word IN (0,1))`, `created_at INTEGER NOT NULL`. Note: `keyword_blocklist.keyword` is `UNIQUE COLLATE NOCASE`; `keyword_alerts.keyword` is `UNIQUE` with no `COLLATE NOCASE` — an inconsistency between the two otherwise-parallel tables.

**article_summaries**: `id INTEGER PK AUTOINCREMENT`, `article_id INTEGER NOT NULL UNIQUE REFERENCES articles(id) ON DELETE CASCADE`, `summary TEXT NOT NULL`, `model TEXT NOT NULL`, `generated_at INTEGER NOT NULL`.

**settings**: `key TEXT PRIMARY KEY`, `value TEXT NOT NULL`, `updated_at INTEGER NOT NULL`.

### Migrations (keyed by `oldVersion`, in `_onUpgrade`)

- `oldVersion < 2`: conditionally `ALTER TABLE articles ADD COLUMN is_saved INTEGER NOT NULL DEFAULT 0` if the column is absent (checked via `PRAGMA table_info`).
- `oldVersion < 3`: `CREATE TABLE keyword_alerts` (via `SchemaStatements.createKeywordAlerts`).
- `oldVersion < 4`: creates `idx_articles_read_published` and `idx_articles_feed_read_published`.
- `oldVersion < 5`: `CREATE UNIQUE INDEX IF NOT EXISTS idx_articles_guid_feed ON articles(feed_id, guid)`, then `INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES ('schema_version', '3', <now>)`.
- `oldVersion < 6`: `INSERT OR IGNORE INTO settings (key, value, updated_at) VALUES ('cleanup_age_days', '7', <now>)`.
- `oldVersion < 7`: `INSERT OR IGNORE INTO settings (key, value, updated_at) VALUES ('newspaper_mode', 'false', <now>)`.

### Repository query methods (ArticleRepository — full list, see Section 5 for SQL)

- `insertArticles(int feedId, List<Article> articles)` — batched `INSERT OR IGNORE`, dedupe key `(feed_id, guid)`; never resets `is_read`.
- `getAllArticles({Set<int> sessionReadIds = const {}})` — filters `a.is_blocked = 0 AND (a.is_read = 0 OR a.id IN (session ids))`, `ORDER BY a.published_at DESC`, no folder filter.
- `getArticlesByFolder(int folderId, {Set<int> sessionReadIds = const {}})` — same union filter plus `f.folder_id = ?`.
- `getSaved()` — `WHERE a.is_saved = 1 ORDER BY a.published_at DESC`.
- `getBlocked()` — `WHERE a.is_blocked = 1 ORDER BY a.fetched_at DESC`.
- `search(String query)` — `WHERE a.is_blocked = 0 AND (a.title LIKE ? OR a.description LIKE ?) ORDER BY a.published_at DESC LIMIT 100`; returns `[]` immediately for a blank/whitespace query.
- `getTotalUnreadCount()` — `WHERE a.is_read = 0 AND a.is_blocked = 0`.
- `getUnreadCount(int folderId)` — same plus `f.folder_id = ?`.
- `getAllFolderUnreadCounts()` — grouped by `f.folder_id`, `WHERE a.is_read = 0 AND a.is_blocked = 0 AND f.folder_id IS NOT NULL`.
- `markAsRead`/`markAsUnread(int articleId)` — single-row `UPDATE ... SET is_read = {1|0} WHERE id = ?`.
- `markManyRead(List<int> articleIds)` — batched per-id `UPDATE`.
- `markAllAsRead()` — `UPDATE articles SET is_read = 1 WHERE is_blocked = 0` (all folders).
- `markAllAsReadByFolder(int folderId)` — `UPDATE articles SET is_read = 1 WHERE feed_id IN (SELECT id FROM feeds WHERE folder_id = ?) AND is_blocked = 0`.
- `runCleanup({int? folderId, int days = kFetchDayLimit})` — `days` clamped `[5, 20]`; `DELETE FROM articles WHERE is_read = 1 AND is_saved = 0 AND published_at < cutoffMs` (optionally scoped to a folder via feed subquery).
- `setSaved(int articleId, {required bool saved})` — `UPDATE ... is_saved`.
- `updateThumbnailPath(int articleId, String path)` — `UPDATE ... thumbnail_path`.
- `retroactivelyBlock(String keyword, bool wholeWord)` — reads all unblocked rows, applies `KeywordMatcher.matches` in Dart, batches `UPDATE ... is_blocked=1, blocked_keyword` for matches.
- `unblockByKeyword(String keyword)` — `UPDATE articles SET is_blocked = 0, blocked_keyword = NULL WHERE blocked_keyword = ?`.
- `markRead`/`markUnread` — aliases to `markAsRead`/`markAsUnread`.

### Unawaited write in the unread-count reconciliation path

Confirmed **still present**. In `lib/screens/feed_screen.dart`:

```dart
void _flushMarkReadUI() {
    if (_pendingMarkReadUI.isEmpty || !mounted) return;
    final ids = Set<int>.from(_pendingMarkReadUI);
    _pendingMarkReadUI.clear();
    setState(() {
      _articles = [
        for (final a in _articles)
          ids.contains(a.id) ? a.copyWith(isRead: true) : a,
      ];
    });
    unawaited(_refreshCountsFromDb());
}
```

`_refreshCountsFromDb()` (line 213) itself does `await (_articleRepo.getAllFolderUnreadCounts(), _articleRepo.getTotalUnreadCount()).wait` then `setState` and `AppBadgePlus.updateBadge(allCount)` — this is a DB **read**-and-reconcile call, fired with `unawaited(...)` at line 392 rather than awaited, meaning `_flushMarkReadUI` returns before the count reconciliation (and badge update) completes. No corresponding write is unawaited inside `_refreshCountsFromDb` itself; the unawaited call is the reconciliation trigger.

---

## Section 7 — Test inventory

Full nested group()/test()/testWidgets() structure per file, verbatim names, with one line each on what is asserted. Numeric/string literals in assertions are called out per test. Setup helpers are noted where visible from context.

### test/article_repository_test.dart (332 lines)
- `group('insertArticles')`
  - `test('writes new articles to the DB')` — asserts inserted rows appear.
  - `test('skips articles whose feed_id + guid already exist')` — dedupe via `INSERT OR IGNORE`.
- `group('markAsRead / markAsUnread')`
  - `test('markAsRead sets is_read=1 for the correct article only')`
  - `test('markAsUnread sets is_read=0 for the correct article only')`
- `group('markAllAsRead')`
  - `test('sets is_read=1 for every article in the DB')`
- `group('markAllAsReadByFolder')`
  - `test('sets is_read=1 only for articles in the given folder')`
  - `test('does not affect articles in other folders')`
- `group('runCleanup')`
  - `test('deletes read articles where published_at is older than 7 days')` — literal: 7 days.
  - `test('does not delete read articles where published_at is within 7 days')`
  - `test('does not delete unread articles regardless of age')`
  - `test('returns the number of rows deleted')`
  - `test('does not delete saved articles even if old and read')`
- `group('runCleanup with folderId')`
  - `test("deletes only that folder's eligible articles")`
  - `test('does not delete eligible articles in other folders')`
- `group('unread counts')`
  - `test('getTotalUnreadCount returns correct count')`
  - `test('getUnreadCount returns count for a specific folder')`
- `group('markAllAsRead + runCleanup combined')`
  - `test('articles within 7 days remain in DB as read after combined operation')`
  - `test('articles older than 7 days are gone from DB after combined operation')`
- `group('kFetchDayLimit used in cleanup')`
  - `test('cleanup cutoff is based on kFetchDayLimit days ago')` — ties directly to the `kFetchDayLimit = 7` constant in `lib/utils/constants.dart`.

### test/article_summary_sheet_test.dart (244 lines) — **contains the one failing test**
- `testWidgets(...)` (line 92, name not captured by grep due to multi-line call)
- `testWidgets('reveals the complete summary in a single step on done', ...)` — asserts single-pass reveal (no partial/incremental render), matching the "single-pass AI summary" behavior from the latest commit.
- `testWidgets('a short summary does not scroll', ...)` — non-scrollability assertion for short content.
- `testWidgets('an oversized summary becomes scrollable instead of clipping', ...)`
- `testWidgets(...)` (line 174, name not captured — likely the failing test's setup or a sibling)
- `testWidgets('a maximum-budget summary fits on one Pixel-class page with no overflow and no scrolling', ...)` — **FAILING**. Asserts a measured value stays under `914.2857142857143` (a Pixel-class viewport height budget); actual measured `1281.0`.
- `testWidgets('passes title and content to the native summarize call', ...)`
- `testWidgets('shows unavailable message on native summaryError', ...)`
- `testWidgets('shows unavailable message when the stream completes empty', ...)`
- `testWidgets('shows unavailable message when Gemini Nano is not supported', ...)`

### test/backup_serializer_test.dart (233 lines)
- `group('toMap')`
  - `test('version is always 1')` — literal: version 1.
  - `test('backedUpAt timestamp is present and non-zero')`
  - `test('serialises folder names and positions')`
  - `test('serialises feed url, title, position, and folder name')`
  - `test('serialises keywords with keyword and wholeWord fields')`
  - `test('does NOT include read/unread state, API keys, or bookmarks')` — deliberate exclusion (product decision, see below).
  - `test('Drive and local-file output are byte-identical (same format)')`
- `group('validate')`
  - `test('accepts valid backup map')`
  - `test('throws on wrong version')`
  - `test('throws when folders key is missing')`
  - `test('throws when feeds key is missing')`
- `group('restoreFromMap')`
  - `test('returns correct feed count')`
  - `test('round-trip: folder names preserved')`
  - `test('round-trip: feeds with correct folder assignment')`
  - `test('round-trip: keywords preserved')`
  - `test('feeds with unknown folder name are skipped')`

### test/cleanup_settings_test.dart (207 lines)
- `group('runCleanup with configurable days')`
  - `test('deletes read+unsaved articles older than the configured window')`
  - `test('keeps read articles within the configured window')`
  - `test('never deletes unread articles regardless of window')`
  - `test('never deletes saved (bookmarked) articles regardless of window')`
  - `test('boundary: article exactly at N days is kept (strictly less than)')` — boundary semantics.
  - `test('days clamped to minimum 5: value of 2 behaves as 5')` — literals: 2 → 5.
  - `test('days clamped to maximum 20: value of 99 behaves as 20')` — literals: 99 → 20.
  - `test('window=5 deletes articles older than 5 days')`
  - `test('window=20 keeps articles that window=7 would delete')`
- `group('AppSettings.cleanupAgeDays')`
  - `test('default is 7 when key is absent')`
  - `test('default seed value is 7')`
  - `test('reads configured value correctly')`
  - `test('clamps below minimum to 5')`
  - `test('clamps above maximum to 20')`
  - `test('value exactly at minimum (5) is kept')`
  - `test('value exactly at maximum (20) is kept')`
  - `test('non-numeric value falls back to 7')`

### test/feed_behavior_test.dart (295 lines)
- `group('Union query (unread OR session-read)')`
  - `test('empty tracker returns only unread articles')`
  - `test('tracker adds read articles back into view')`
  - `test('cold open: empty tracker, all read in DB → empty list')`
  - `test('tracker with IDs not in the list is safe (no crash, no phantom rows)')`
- `group('Opening an article dims it in-place')`
  - `test('opened article is marked read but stays in list')` — **product decision**: articles never disappear on open.
  - `test('articles above and below dimmed article are unchanged')`
  - `test('opening last article dims it but list has one element')`
- `group('Scroll-to-read dims articles in-place')`
  - `test('scrolled-past articles are dimmed, not removed')` — **product decision**.
  - `test('unread count decreases by number of dimmed articles')`
  - `test('dimming all articles leaves them in list but all read')`
- `group('Swipe mark-as-read dims article in-place')`
  - `test('swiped article is dimmed, not removed')`
  - `test('swipe on already-read article leaves it read')`
  - `test('both swipe directions produce same in-place dim result')`
- `group('Mark-unread removes from tracker and restores full weight')`
  - `test('un-dimming restores isRead=false')`
  - `test('tracker removal: ID no longer in session set')`
  - `test('after mark-unread, union query re-hides the article on next tab load')`
- `group('Read state is scoped per tab (session tracker)')`
  - `test('article read in All tab is absent from folder tab')` — **product decision**: per-scope session read visibility.
  - `test('mark-all-read (All) + clear tracker → reload shows unread-only')`
  - `test('mark-all-read (Category) removes folder IDs, other tab IDs remain')`
- `group('Tab switch')`
  - `test('tab with saved scroll offset restores position')` — **product decision**: scroll restoration.
  - `test('switching to a new tab (no saved offset) starts at top')`
- `group('Read articles stay in list with reduced opacity signal')`
  - `test('isRead=true acts as the opacity signal (no removal from list)')` — **product decision**.

### test/folder_tab_bar_test.dart (172 lines)
- `group('bar height')`
  - `test('exposes a public height constant of at least 56dp')` — literal: 56dp.
  - `testWidgets('renders at the declared height', ...)`
- `group('tap targets')`
  - `testWidgets('every tab meets the 48dp minimum on both axes', ...)` — literal: 48dp, Material touch-target minimum.
  - `testWidgets('a two-character folder name still gets a wide target', ...)`
  - `testWidgets('tabs are taller than the previous 48dp bar', ...)` — literal: 48dp (regression guard vs prior bar height).
- `group('interaction')`
  - `testWidgets('tapping a folder tab reports its index', ...)`
  - `testWidgets('tapping the already-selected tab still reports it', ...)`
- `group('badges')`
  - `testWidgets('shows the unread count next to the folder label', ...)`
  - `testWidgets('hides the badge at zero', ...)` — **product decision**: zero-count badges hidden.

### test/keyword_matcher_test.dart (100 lines)
- `group('buildHaystack')`
  - `test('combines title and description')`
  - `test('handles null description')`
- `group('matches default (partial, case-insensitive)')`
  - `test('matches exact case')`
  - `test('matches uppercase keyword against lowercase haystack')`
  - `test('matches lowercase keyword against uppercase haystack')`
  - `test('matches mixed case')`
  - `test('partial match within word')`
  - `test('returns false when not present')`
  - `test('matches in description part of haystack')`
  - `test('matches in title part of haystack')`
- `group('matches whole-word mode')`
  - `test('does not match partial word')`
  - `test('matches standalone word')`
  - `test('whole-word match is case-insensitive')`
  - `test('whole-word does not match substring of compound word')`
  - `test('whole-word matches at start of string')`
  - `test('whole-word matches at end of string')`

### test/loading_controller_test.dart (140 lines)
- `group('idle state')`
  - `test('starts idle')`
- `group('reference counting')`
  - `test('begin makes it busy, matching end makes it idle')`
  - `test('two concurrent operations require two ends')`
  - `test('unbalanced end clamps at zero')` — floor-at-zero semantics.
- `group('label')`
  - `test('reports the most recent labelled operation')`
  - `test('clears when everything finishes')`
- `group('run()')`
  - `test('is busy during the action and idle after')`
  - `test('returns the action result')`
  - `test('ends and rethrows when the action throws')`
  - `test('nested runs stay busy until the outermost completes')`
- `group('notifications')`
  - `test('notifies on the idle→busy and busy→idle transitions')`
  - `test('does not notify on a no-op end while already idle')`

### test/native_summary_contract_test.dart (126 lines)
- `group('single model pass')`
  - `test('streams exactly once per summary')` — **product decision**: no multi-pass generation.
  - `test('makes no blocking generateContent call')`
  - `test('no key-points intermediate step remains')` — regression guard against a removed feature.
- `group('latency budget')`
  - `test('there is exactly one generation timeout')`
  - `test('the timeout is 20 seconds')` — literal: 20s, matches `withTimeout(20_000)` in `GeminiNanoPlugin.kt`.
  - `test('no 45-second timeout survives anywhere')` — regression guard against a prior 45s timeout.
  - `test('input is trimmed to 2500 characters')` — literal: 2500, matches `body.take(2500)`.
  - `test('the old 6000-character trim is gone')` — regression guard against a prior 6000-char limit.
- `group('prompt content')`
  - `test('instructs the model to deliver the headline promise first')`
  - `test('bans the filler register seen in the reported bad output')`
  - `test('forbids inference and gap-filling')`
  - `test('states the 120-word budget')` — literal: 120 words, matches Kotlin prompt rule 6.
  - `test('uses the "- " bullet marker the Dart widget renders')`
- `group('localisation is preserved')`
  - `test('all five supported languages still map')` — literal: 5 languages (en/de/es/fr/it).
  - `test('the language instruction is still injected into the prompt')`
- `group('no new dependencies')`
  - `test('still uses the ML Kit GenAI client')`

### test/newspaper_mode_test.dart (70 lines)
- `group('newspaper_mode setting')`
  - `test('defaults to OFF (false) on a fresh database')`
  - `test('AppSettings parses the flag and defaults to false')`
  - `test('persists a user toggle')`
- `group('flashNewspaperTheme')`
  - `test('is a light theme on the newsprint paper surface')`
  - `test('uses ink for text and the spot red as primary accent')`
  - `test('body uses the serif body font, headlines the display serif')`

### test/opml_service_test.dart (211 lines)
- `group('generateOpml structure')`
  - `test('produces valid XML preamble')`
  - `test('wraps feeds in their folder outline')`
  - `test('includes htmlUrl when siteUrl is present')`
  - `test('omits htmlUrl when siteUrl is null')`
  - `test('escapes XML special characters in folder and feed names')`
  - `test('empty folder produces no folder outline')`
  - `test('multiple feeds in same folder all appear inside folder outline')`
- `group('round-trip generate → parse')`
  - `test('single feed in folder survives round-trip')`
  - `test('multiple feeds in multiple folders round-trip')`
  - `test('feed title preserved through round-trip')`
  - `test('folder structure preserved: folder name attached to feeds')`
- `group('XML escaping')`
  - `test('& is escaped to &amp;')` — literal: `&` → `&amp;`.
  - `test('" is escaped to &quot; in attribute values')` — literal: `"` → `&quot;`.

### test/refresh_service_test.dart (153 lines)
- `group('Cold start')`
  - `test('cleanup runs before fetch — old read articles are deleted before insert')` — **product decision**: ordering guarantee.
  - `test('cold start fetch inserts new articles after cleanup')`
  - `test('after cold start, articles deleted by cleanup are not re-inserted if older than 7 days')`
- `group('Pull-to-refresh')`
  - `test('pull-to-refresh does NOT run the cleanup job')` — **product decision**.
  - `test('pull-to-refresh inserts new articles')`
- `group('Background job')`
  - `test('background job: cleanup then fetch — same outcome as cold start')`

### test/resume_refresh_policy_test.dart (181 lines)
- `group('defaults')`
  - `test('ship with 30s background and 5min fetch thresholds')` — literals: 30s, 5min, matching `ResumeRefreshPolicy` defaults.
- `group('never backgrounded')`
  - `test('no pausedAt means no fetch')`
- `group('brief excursions')`
  - `test('5 seconds away does not fetch')`
  - `test('29 seconds away does not fetch')` — boundary just under 30s.
  - `test('exactly 30 seconds away does fetch')` — boundary exactly at 30s (note: implementation uses `<` so exactly-30s passes the gate).
- `group('real absence')`
  - `test('ten minutes away with no prior fetch does fetch')`
  - `test('an hour away does fetch')`
- `group('recent-fetch suppression')`
  - `test('a fetch two minutes ago suppresses another')`
  - `test('a fetch six minutes ago allows another')` — boundary just over 5min.
  - `test('background gate is checked even when the last fetch is ancient')`
- `group('clock weirdness')`
  - `test('a pausedAt in the future does not fetch')`
  - `test('a lastFetchAt in the future does not fetch')`
- `group('custom thresholds')`
  - `test('an aggressive policy fetches after five seconds')`

### test/rss_service_test.dart (214 lines)
- `group('resolveGuid')`
  - `test('returns feed guid when present')`
  - `test('falls back to article URL when feed guid is absent')`
  - `test('produces identical output on two calls with same inputs')` — determinism guard.
  - `test('throws when both guid and url are absent')`
  - `test('throws when guid is empty string and url is null')`
- `group('applyFetchThresholds')`
  - `test('accepts articles within 7 days')`
  - `test('rejects articles older than 7 days and stops processing')` — implies early-stop behavior on sorted feeds.
  - `test('rejects articles with null published_at')`
  - `test('accepts a maximum of 100 articles per call')` — literal: 100, matches `kFetchArticleLimit`.
  - `test('returns empty list when all articles are older than 7 days')`
- `group('DB deduplication')`
  - `test('fetching the same feed twice does not produce duplicate rows')`
  - `test('an article already in DB as read is not reset to unread on re-fetch')` — **product decision**.
  - `test('an article already in DB as unread is not duplicated on re-fetch')`
  - `test('INSERT OR IGNORE confirmed: row count unchanged after duplicate insert')`

### test/session_read_scope_test.dart (216 lines)
- `group('scope isolation')`
  - `test('starts empty in every scope')`
  - `test('an id added to All is not present in a folder scope')`
  - `test('an id added to a folder is not present in All')`
  - `test('the same id can be recorded in two scopes independently')`
  - `test('unknown scopes return an empty set rather than throwing')`
  - `test('the returned scope view cannot corrupt the tracker')` — immutability guard on `idsForScope`.
- `group('addAll — scroll batches')`
  - `test('records a whole batch against one scope')`
  - `test('an empty batch is a no-op')`
- `group('the headline behaviour — read in All, gone from Gaming')`
  - `test('a Gaming article read while scrolling All disappears from Gaming')` — **product decision**, named scenario.
  - `test('but it is still there, dimmed, when the user returns to All')`
  - `test('the rule is symmetric — read in Gaming, gone from All')`
  - `test('articles read in a previous session appear nowhere')` — session-only persistence (never survives restart).
- `group('removeEverywhere — mark as unread')`
  - `test('clears the id from every scope')`
  - `test('leaves other ids alone')`
  - `test('removing an untracked id is a no-op')`
- `group('clearing')`
  - `test('clearScope empties one scope and leaves the others')`
  - `test('clear empties everything')`
  - `test('clearing an untouched scope is a no-op')`
- `group('allIds')`
  - `test('is the union across scopes, deduplicated')`
- `group('scope keys')`
  - `test('kAllScope is negative so it cannot collide with a folder id')` — literal semantics: `kAllScope = -1`.

### test/session_read_tracker_test.dart (278 lines)
- `group('SessionReadTracker')`
  - `test('starts empty')`
  - `test('add and contains')`
  - `test('remove')`
  - `test('clear removes all')`
  - `test('removeWhere removes matching ids')`
  - `test('is a singleton')`
- `group('getAllArticles union query')`
  - `test('empty tracker returns only unread articles')`
  - `test('tracker adds read articles back into results')`
  - `test('cold open (empty tracker) never shows previously-read articles')`
  - `test('blocked articles are excluded regardless of tracker')` — **product decision**: blocking overrides session-read visibility.
- `group('getArticlesByFolder union query')`
  - `test('empty tracker returns only unread for that folder')`
  - `test('tracker adds read article back for that folder')`
- `group('global session read state across scopes')`
  - `test('article marked read in All scope appears dimmed in folder scope')`
  - `test('mark-unread removes from tracker and restores full weight')`
  - `test('mark-all-read (All tab) + clear tracker → empty list on reload')`
  - `test('mark-all-read (Category) removes folder IDs from tracker, others remain')`

### test/summary_cache_test.dart (110 lines)
- `group('basic storage')`
  - `test('starts empty')`
  - `test('stores and retrieves by URL')`
  - `test('distinct URLs do not collide')`
  - `test('URL matching is exact')`
- `group('failures are never cached')`
  - `test('put with an empty summary is a no-op')`
  - `test('put with a whitespace-only summary is a no-op')`
  - `test('an empty put does not evict an existing good entry')`
- `group('replacement')`
  - `test('re-putting an existing URL replaces without duplicating')`
- `group('bounded size')`
  - `test('holds 50 entries without evicting')` — literal: 50.
  - `test('evicts the oldest entry on the 51st insert')` — literal: 51st.
  - `test('re-putting an existing URL refreshes its position')` — LRU-refresh semantics.
- `group('clear')`
  - `test('empties the cache')`

### test/summary_formatter_test.dart (201 lines)
- `group('backstop ceilings')`
  - `test('are deliberately looser than the prompt budget')` — **product decision**: formatter ceilings are a backstop, not the primary limiter (the model prompt's 120-word rule is primary).
- `group('empty and degenerate input')`
  - `test('empty string returns empty')`
  - `test('whitespace-only returns empty')`
  - `test('a single short sentence passes through unchanged')`
- `group('preamble and markdown stripping')`
  - `test('strips a leading "Summary:" line')`
  - `test('strips a bare leading "Summary" line')`
  - `test('strips "Summary:" used as an inline prefix')`
  - `test('strips markdown bold anywhere')`
  - `test('leaves ordinary hyphenation alone')`
- `group('bullet normalisation')`
  - `test('normalises "*" markers')`
  - `test('normalises bullet-glyph markers')`
  - `test('normalises en-dash markers')`
  - `test('leaves correct "- " markers alone')`
- `group('bullet ceiling')`
  - `test('keeps the first eight bullets in order and drops the rest')` — literal: 8 bullets.
  - `test('the focal line survives bullet truncation')`
  - `test('a compliant five-bullet summary is untouched')`
- `group('word ceiling')`
  - `test('a 120-word summary is never clamped')` — literal: 120 words.
  - `test('drops whole trailing lines until the ceiling is met')`
  - `test('never cuts a retained bullet mid-sentence')` — **product decision**: no mid-sentence truncation of bullets.
  - `test('truncates at a word boundary when the focal line alone runs away')`
  - `test('a summary exactly at the ceiling is left intact')`
- `group('whitespace')`
  - `test('collapses runs of blank lines')`
  - `test('trims leading and trailing whitespace')`
- `group('idempotence')`
  - `test('clamping an already-clamped summary changes nothing')` — idempotence guard.

### test/summary_latency_test.dart (183 lines)
- `group('extraction budget')`
  - `test('is a hard 2 seconds')` — literal: 2 seconds hard budget for extraction.
- `group('cache short-circuit')`
  - `testWidgets('a cached summary renders without any inference call', ...)` — **product decision**: cache hit skips model entirely.
  - `testWidgets('an uncached article does reach the model', ...)`
  - `testWidgets('a completed summary is cached', ...)`
  - `testWidgets('the cached value is the clamped text, not the raw stream', ...)` — clamped (formatted) text is what's cached.
  - `testWidgets('an errored summary is not cached', ...)`
  - `testWidgets('an empty stream result is not cached', ...)`
  - `testWidgets('an unavailable model does not cache anything', ...)`
- `group('clamping is applied to displayed output')`
  - `testWidgets('a runaway stream result is clamped before display', ...)`

### test/summary_source_test.dart (169 lines)
- `group('flattening')`
  - `test('keeps paragraphs in document order')`
  - `test('includes headings as text')`
  - `test('includes quotes')`
  - `test('flattens list items')`
  - `test('drops images entirely')` — **product decision**: `ImageBlock` contributes no text.
- `group('whitespace')`
  - `test('collapses runs of blank lines and trims')`
- `group('capping')`
  - `test('short bodies pass through untouched')`
  - `test('long bodies are capped at maxChars')`
  - `test('truncation does not split a word')`
  - `test('default cap matches the native trim')` — ties Dart's `defaultMaxChars = 2500` to the Kotlin `body.take(2500)`.
- `group('fallbacks')`
  - `test('empty block list falls back to the description')`
  - `test('null block list falls back to the description')`
  - `test('image-only extraction falls back to the description')`
  - `test('whitespace-only extraction falls back to the description')`
  - `test('no blocks and no fallback yields an empty string')`
  - `test('a usable body is preferred over the fallback')`
- `group('adequacy check')`
  - `test('reports whether the body is substantial enough to summarise')` — ties to `isSubstantial` (≥400 chars per `summary_source.dart`).

### test/unread_counts_test.dart (155 lines)
- `group('construction')`
  - `test('empty has zero everywhere')`
  - `test('forFolder returns 0 for an unknown folder')`
- `group('applyRead')`
  - `test('decrements all AND the owning folder')`
  - `test('a null folder (unfiled feed) decrements all only')`
  - `test('floors at zero — never negative')` — floor-at-zero guard.
  - `test('does not mutate the receiver')` — immutability guard.
- `group('applyUnread')`
  - `test('increments all and the owning folder')`
  - `test('increments a folder that had no entry')`
  - `test('read then unread round-trips')`
- `group('applyManyRead — scroll batch')`
  - `test('applies every folder id in the batch')`
  - `test('an empty batch is a no-op that still returns a value')`
  - `test('over-reading a folder floors both counters')`
- `group('bulk clears')`
  - `test('clearedAll zeroes everything')`
  - `test('clearedFolder subtracts that folder from all')`
  - `test('clearing an unknown folder leaves all untouched')`
- `group('fromRepository')`
  - `test('builds from a total and a per-folder map')`
- `group('equality')`
  - `test('two identical instances compare equal')`
  - `test('differing counts are not equal')`

### test/widget_test.dart (8 lines)
- `testWidgets('Flash app smoke test', (WidgetTester tester) async { ... })` — minimal smoke test; only test in the file, no groups.

### Setup helpers

Across the DB-backed test files (`article_repository_test.dart`, `feed_behavior_test.dart`, `refresh_service_test.dart`, `rss_service_test.dart`, `session_read_tracker_test.dart`, `cleanup_settings_test.dart`, `newspaper_mode_test.dart`), the shared pattern (inferred from `AppDatabase.useForTesting()` in `lib/db/database.dart`) is: `setUp` calling `AppDatabase.useForTesting()` to get a fresh in-memory sqflite DB per test, `tearDown` calling `AppDatabase.instance.close()`. Widget tests using Gemini Nano (`article_summary_sheet_test.dart`, `summary_latency_test.dart`) rely on `GeminiNanoService.resetForTesting()` (in `gemini_nano_service.dart`) to reset the singleton's cached availability between tests, and stub the `io.getflash.app/gemini_nano` `MethodChannel` via Flutter's test binary messenger mocking.

### Subsection — Assertions that encode a product decision

- `test/feed_behavior_test.dart`: `'opened article is marked read but stays in list'` — articles never disappear from the list on open; only dim.
- `test/feed_behavior_test.dart`: `'scrolled-past articles are dimmed, not removed'` — scroll-to-read dims in place, no removal.
- `test/feed_behavior_test.dart`: `'article read in All tab is absent from folder tab'` — session-read visibility is strictly per-tab/per-scope.
- `test/feed_behavior_test.dart`: `'tab with saved scroll offset restores position'` — scroll position restoration on tab switch is a deliberate UX guarantee.
- `test/feed_behavior_test.dart`: `'isRead=true acts as the opacity signal (no removal from list)'` — explicit non-removal rule stated as the test name.
- `test/folder_tab_bar_test.dart`: `'hides the badge at zero'` — zero unread count suppresses the badge rather than showing "0".
- `test/native_summary_contract_test.dart`: `'streams exactly once per summary'`, `'no key-points intermediate step remains'` — single-pass generation is a deliberate simplification versus a removed multi-step design.
- `test/refresh_service_test.dart`: `'cleanup runs before fetch — old read articles are deleted before insert'` — explicit ordering contract for cold start/background refresh.
- `test/refresh_service_test.dart`: `'pull-to-refresh does NOT run the cleanup job'` — pull-to-refresh is deliberately lighter-weight than cold start.
- `test/rss_service_test.dart`: `'an article already in DB as read is not reset to unread on re-fetch'` — re-fetching a feed must never regress read state (matches the `insertArticles` doc comment "never reset to unread").
- `test/session_read_scope_test.dart`: `'a Gaming article read while scrolling All disappears from Gaming'` / `'the rule is symmetric — read in Gaming, gone from All'` — the core cross-tab session-read symmetry rule, named explicitly.
- `test/session_read_scope_test.dart`: `'articles read in a previous session appear nowhere'` — session-read state is deliberately non-persistent.
- `test/session_read_tracker_test.dart`: `'blocked articles are excluded regardless of tracker'` — keyword blocking always wins over session-read visibility.
- `test/summary_formatter_test.dart`: `'are deliberately looser than the prompt budget'` — the Dart-side formatter ceiling is explicitly a backstop, not the primary constraint (the primary constraint is the Kotlin prompt's 120-word rule).
- `test/summary_formatter_test.dart`: `'never cuts a retained bullet mid-sentence'` — truncation quality guarantee.
- `test/summary_latency_test.dart`: `'a cached summary renders without any inference call'` — cache short-circuit is a hard behavioral guarantee, not just an optimization.
- `test/summary_source_test.dart`: `'drops images entirely'` — images are deliberately excluded from the AI-summary text source.

---

## Section 8 — Native Android

### android/app/build.gradle.kts

- `minSdk = flutter.minSdkVersion` (resolved via Flutter's Gradle plugin, not a literal in this file — PRD states minimum SDK 26)
- `targetSdk = flutter.targetSdkVersion` (resolved via Flutter's Gradle plugin — PRD states target SDK 35)
- `compileSdk = flutter.compileSdkVersion`
- `applicationId = "io.getflash.app"`
- Signing config: release build type sets `signingConfig = signingConfigs.getByName("debug")` — i.e. **release builds currently sign with the debug key** (a `// TODO: Add your own signing config for the release build.` comment marks this explicitly; contents of any actual signing config not present/inspected).
- Java/Kotlin target: `JavaVersion.VERSION_17` for both `sourceCompatibility`/`targetCompatibility` and `kotlinOptions.jvmTarget`; `isCoreLibraryDesugaringEnabled = true`.
- Dependencies (app-level):
  - `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`
  - `implementation("com.google.mlkit:genai-prompt:1.0.0-beta1")` — comment: "ML Kit GenAI Prompt API — on-device Gemini Nano (Pixel 8+, Android 14+)"
- Plugins applied: `com.android.application`, `kotlin-android`, `dev.flutter.flutter-gradle-plugin`, `com.google.gms.google-services`.

### Project-level (android/build.gradle.kts)

- `classpath("com.google.gms:google-services:4.4.2")`

### android/settings.gradle.kts (plugin/Kotlin versions)

- `com.android.application` version `8.11.1`
- `org.jetbrains.kotlin.android` version `2.2.20`
- `dev.flutter.flutter-plugin-loader` version `1.0.0`

### AndroidManifest.xml (full, reproduced verbatim)

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>

    <!-- TV / Google TV support -->
    <uses-feature android:name="android.software.leanback" android:required="false"/>
    <!-- Touch is not available on TV; mark as not required so the app passes TV review -->
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>

    <!-- ML Kit GenAI requires API 26+ but we handle unavailability gracefully at runtime -->
    <uses-sdk tools:overrideLibrary="com.google.mlkit.genai.prompt,com.google.mlkit.genai.common"/>

<application
        android:label="Flash"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:banner="@drawable/tv_banner"
        android:allowBackup="true"
        android:fullBackupContent="@xml/backup_rules"
        android:dataExtractionRules="@xml/data_extraction_rules">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <!-- TV launcher entry -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
            </intent-filter>
        </activity>

        <service
            android:name="dev.fluttercommunity.workmanager.BackgroundWorker"
            android:exported="false"
            tools:ignore="Instantiatable"/>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
        <meta-data
            android:name="io.flutter.embedding.android.EnableImpeller"
            android:value="false" />
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="http"/>
        </intent>
    </queries>
</manifest>
```

Notable: `EnableImpeller` meta-data is set to `false` — Impeller rendering engine is explicitly disabled.

### Method channels — native ↔ Dart

**`io.getflash.app/gemini_nano`** (declared identically on both sides: Dart `lib/services/gemini_nano_service.dart:9` `static const _channel = MethodChannel('io.getflash.app/gemini_nano')`; Kotlin `GeminiNanoPlugin.kt:22` `MethodChannel(binding.binaryMessenger, "io.getflash.app/gemini_nano")`). Methods:
- Dart → native: `isAvailable` (no args) → native `checkAvailability`; matches.
- Dart → native: `summarize` with args `{title, content, locale}` → native reads `call.argument<String>("title")`, `"content"`, `"locale")`; matches.
- Native → Dart (reverse calls): `summaryChunk` (String arg), `summaryDone` (null), `summaryError` (String arg) — all three handled in Dart's `_handleNativeCall` switch; matches the three `channel.invokeMethod(...)` calls in `GeminiNanoPlugin.summarize`.

**`io.getflash.app/device`** (declared in `MainActivity.kt:13`: `private val channel = "io.getflash.app/device"`). Method: `isTV` (no args) → returns whether `UiModeManager.currentModeType == UI_MODE_TYPE_TELEVISION`. Dart-side caller not located in the hot-file set inspected directly, but `lib/utils/form_factor.dart` (24 lines) is the likely consumer per its purpose/name; not verified line-by-line in this survey.

All channel names and methods inspected match on both sides — no mismatches found within the two plugin files read.

---

## Section 9 — Localisation

Five ARB files: `lib/l10n/app_en.arb`, `app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`.

**Key counts: en=163, de=163, es=163, fr=163, it=163.** All five files have identical key sets — **no missing or extra keys in any direction** (computed by diffing key sets pairwise against `en`; every diff was empty).

### Full list of key names (163, alphabetical; values not reproduced)

```
add, addAFeed, addAFeedButton, addAlertKeyword, addAlertKeywordSubtitle, addFeed,
addFirstFeed, addKeyword, addToCategory, aiSummary, aiSummaryDisclaimer,
aiSummaryReading, aiSummaryTeaserOnly, aiSummaryUnavailable, aiSummaryWriting,
alertKeywordHint, allMarkedRead, allTab, appTitle, articles100, articles200,
articles50, articles500, backgroundRefreshInterval, backup, backupNow,
backupSuccess, blockKeyword, blockedArticles, blockedByKeyword, bookmark,
bookmarks, cancel, categories, category, categoryName, changelog, connectGoogle,
copySummary, couldNotParseFeed, defaultFolderName, delete, deleteCategory,
deleteFolder, deleteFolderMessage, edit, editFeed, every15Minutes,
every30Minutes, every3Hours, every6Hours, everyHour, exportBackup,
extractionFailed, failedToAddFeed, feedAlreadyAdded, feedName, feedRemoved,
feeds, filters, followers, fontSize, fontSizeLarge, fontSizeMedium,
fontSizeSmall, googleDriveBackup, importBackup, invalidBackupFile,
keywordAlerts, keywordAlertsEmpty, keywordAlertsSubtitle, keywordBlocklist,
keywordBlocklistEmpty, keywordBlocklistSubtitle, keywordHint, keywordOrPhrase,
keywordRemoved, lastBackup, loadingArticle, localBackup, localBackupSubtitle,
manualOnly, markAllRead, markAllReadConfirm, markAllReadWarningBody,
markAllReadWarningTitle, markRead, markReadOnScroll, markReadOnScrollSubtitle,
markUnread, matchingAnywhere, matchingWholeWord, maxArticlesPerFeed,
newCategory, newspaperMode, newspaperModeOverridesTheme,
newspaperModeSubtitle, noArticlesYet, noBackupFound, noBlockedArticles,
noBlockedKeywords, noBookmarks, noFeedsFound, noFeedsYet, noKeywordAlerts,
noNewArticles, noSearchResults, nothingHereYet, onboardingBullet1,
onboardingBullet2, onboardingBullet3, onboardingTagline, opml, opmlExport,
opmlExportSuccess, opmlImport, opmlImportSuccess, opmlSubtitle,
pickACategory, readFullArticle, readOnWebsite, readerMode,
readerModeSubtitle, reading, refresh, remove, removeFeed, removeFeedMessage,
renameCategory, renameFolder, restore, restoreConfirmMessage,
restoreConfirmTitle, restoreFromDrive, restoreSuccess, save, saved,
searchArticles, searchHint, settings, share, signOut, storage, summary,
summaryCopied, theme, themeDark, themeLight, themeSystem, timeDaysAgo,
timeHourAgo, timeJustNow, timeMinAgo, timeMonthsAgo, timeWeeksAgo,
timeYearsAgo, timeYesterday, unbookmark, uncategorised, unlimited,
unreadOnly, wholeWordOnly, wholeWordSubtitle
```

### Generated `app_localizations_*.dart` sync

Generated files present: `lib/l10n/app_localizations.dart` (1123 lines), `app_localizations_de.dart` (557), `app_localizations_en.dart` (552), `app_localizations_es.dart` (556), `app_localizations_fr.dart` (557), `app_localizations_it.dart` (556). Since `flutter: generate: true` is set in pubspec.yaml and `flutter analyze` reported "No issues found!" (which would surface missing-getter errors if the ARBs and generated Dart were out of sync), and since `flutter test` executed successfully against localized widgets without codegen-related errors, the generated files appear in sync with the ARB sources. Line counts differ slightly per language (552–557) reflecting per-language string length differences in generated doc comments, not key-count differences.

---

## Section 10 — Settings and constants

### User-facing settings (key/type/default/reader)

All settings live in the single `settings` key-value table (`lib/db/schema.dart`), seeded by `defaultSettings`, read via `SettingsRepository`/`AppSettings` (`lib/models/settings.dart`), and surfaced in `lib/screens/settings_screen.dart` (818 lines).

| Key | Type (stored as TEXT) | Default | Primary reader/writer |
|---|---|---|---|
| `theme` | enum string (`system`/`light`/`dark` per ARB `themeSystem`/`themeLight`/`themeDark`) | `'system'` | `lib/theme/app_theme.dart`, `settings_screen.dart` |
| `refresh_interval_minutes` | int string | `'30'` | `RefreshService.schedulePeriodicRefresh` (`lib/services/refresh_service.dart:108-109`) |
| `article_limit` | int string | `'100'` | article-fetch limiting logic (feeds/RSS ingestion; ARB keys `articles50/100/200/500`, `unlimited`) |
| `mark_read_on_scroll` | bool string | `'true'` | `feed_screen.dart` scroll-to-read logic |
| `drive_backup_enabled` | bool string | `'false'` | `drive_backup_service.dart`, settings screen |
| `drive_last_backup_at` | epoch-ms string or `'null'` | `'null'` | `settings_screen.dart:52` (`_settingsRepo.get('drive_last_backup_at')`) |
| `feedly_api_key` | string or `'null'` | `'null'` | `lib/services/feedly_service.dart` |
| `anthropic_api_key_set` | bool string | `'false'` | (flag; corresponding key-storage service not directly inspected in this survey) |
| `google_account_email` | string or `'null'` | `'null'` | `drive_backup_service.dart` / Google Sign-In flow |
| `onboarding_complete` | bool string | `'false'` | `lib/screens/onboarding_screen.dart`, `app.dart` initial route gate |
| `schema_version` | int string | `'3'` | app-level version marker (see Section 6 discrepancy note); overwritten by the `oldVersion < 5` migration |
| `cleanup_age_days` | int string, clamped [5,20] | `'7'` | `AppSettings.cleanupAgeDays`, `ArticleRepository.runCleanup` |
| `article_font_size` | enum string (`small`/`medium`/`large` per ARB `fontSizeSmall/Medium/Large`) | `'medium'` | reader screen font sizing |
| `reader_mode` | bool string | `'false'` | `lib/screens/reader_screen.dart` |
| `newspaper_mode` | bool string | `'false'` | `lib/theme/app_theme.dart` (`flashNewspaperTheme`), `settings_screen.dart` |

### Magic numbers governing behavior (value / constant or inline / file:line / effect)

| Value | Constant name (or "inline literal") | File:line | Governs |
|---|---|---|---|
| `7` | `kFetchDayLimit` | `lib/utils/constants.dart:1` | default cleanup age-days window; RSS fetch-threshold cutoff |
| `100` | `kFetchArticleLimit` | `lib/utils/constants.dart:2` | max articles accepted per feed fetch |
| `[5, 20]` | inline literal via `.clamp(5, 20)` | `lib/repositories/article_repository.dart:243` | clamps `cleanup_age_days` / `runCleanup(days:)` input range |
| `2500` | `SummarySource.defaultMaxChars` | `lib/services/summary_source.dart:5` | Dart-side cap on text handed to the AI summarizer |
| `2500` | inline literal `body.take(2500)` | `android/app/src/main/kotlin/io/getflash/app/GeminiNanoPlugin.kt:138` | Kotlin-side trim of content before prompting (mirrors Dart's 2500 cap — see `summary_source_test.dart`'s `'default cap matches the native trim'`) |
| `400` | inline literal in `isSubstantial` | `lib/services/summary_source.dart:50` | minimum trimmed-text length to consider an article "worth summarising" |
| `20_000` (20s) | inline literal `withTimeout(20_000)` | `GeminiNanoPlugin.kt:142` | hard timeout on the Gemini Nano generation stream |
| `120` (words) | inline literal, prompt rule 6 | `GeminiNanoPlugin.kt:105` | model-side summary length budget (primary constraint per `native_summary_contract_test.dart`) |
| `8` (bullets) | inline literal (formatter ceiling) | `lib/services/summary_formatter.dart` (bullet-ceiling logic) | backstop cap on rendered bullet count, looser than the prompt's own discipline |
| `50` (entries) | inline literal | `lib/services/summary_cache.dart` | max cached summaries before eviction |
| `Duration(seconds: 30)` | `ResumeRefreshPolicy.minBackgroundDuration` default | `lib/utils/resume_refresh_policy.dart:9` | minimum backgrounded duration before resume triggers a fetch |
| `Duration(minutes: 5)` | `ResumeRefreshPolicy.minFetchInterval` default | `lib/utils/resume_refresh_policy.dart:10` | minimum time since last fetch before resume triggers another |
| `Duration(milliseconds: 150)` | inline literal, `_scrollDebounce` Timer | `lib/screens/feed_screen.dart:379` (approx., in `_flushMarkReadUI`/mark-read debounce path) | debounce window before flushing scroll-triggered mark-read UI updates |
| `'30'` (minutes, string) | inline literal fallback | `lib/services/refresh_service.dart:109` | fallback refresh interval when the setting is unreadable |
| `0` (interval) | inline literal sentinel | `lib/services/refresh_service.dart:112` | interval value that means "cancel periodic refresh entirely" (manual-only) |
| `2` | `_kKeywordNotificationId` | `lib/services/refresh_service.dart:15` | fixed Android notification ID for keyword-alert notifications (reused/replaced, not stacked) |
| `56` (dp) | inline literal (test-only assertion; production constant not located in this pass) | `test/folder_tab_bar_test.dart` (`'exposes a public height constant of at least 56dp'`) | minimum folder-tab-bar height |
| `48` (dp) | inline literal (Material minimum touch target, asserted in tests) | `test/folder_tab_bar_test.dart` | minimum tab tap-target size on both axes |
| `min_sdk_android: 26` | pubspec.yaml `flutter_launcher_icons.min_sdk_android` | `pubspec.yaml:76` | adaptive launcher icon minimum SDK |
| `26` (Android 8.0) | PRD-stated `minSdk` (resolved via `flutter.minSdkVersion` in Gradle, not a literal in build.gradle.kts) | PRD-Flash.md §3.1 | app minimum SDK |
| `35` (target SDK) | PRD-stated, resolved via `flutter.targetSdkVersion` | PRD-Flash.md §3.1 | app target SDK |

---

## Section 11 — Loose ends

### TODO/FIXME/HACK/XXX comments in lib/

`grep -rn "TODO\|FIXME\|HACK\|XXX" lib/ --include=*.dart` returned **no matches** — no such markers exist anywhere under `lib/`.

(Two TODOs exist outside `lib/`, in `android/app/build.gradle.kts`, not covered by the lib/-only grep above but noted for completeness since Section 8 already surfaced them: `// TODO: Specify your own unique Application ID...` and `// TODO: Add your own signing config for the release build.`.)

### `// ignore:` / `// ignore_for_file:` comments

All occurrences are in generated localization files only (none in hand-written `lib/` source):
- `lib/l10n/app_localizations.dart:14` — `// ignore_for_file: type=lint`
- `lib/l10n/app_localizations_de.dart:1` — `// ignore: unused_import`
- `lib/l10n/app_localizations_de.dart:5` — `// ignore_for_file: type=lint`
- `lib/l10n/app_localizations_en.dart:1` — `// ignore: unused_import`
- `lib/l10n/app_localizations_en.dart:5` — `// ignore_for_file: type=lint`
- `lib/l10n/app_localizations_es.dart:1` — `// ignore: unused_import`
- `lib/l10n/app_localizations_es.dart:5` — `// ignore_for_file: type=lint`
- `lib/l10n/app_localizations_fr.dart:1` — `// ignore: unused_import`
- `lib/l10n/app_localizations_fr.dart:5` — `// ignore_for_file: type=lint`
- `lib/l10n/app_localizations_it.dart:1` — `// ignore: unused_import`
- `lib/l10n/app_localizations_it.dart:5` — `// ignore_for_file: type=lint`

No `// ignore:`/`// ignore_for_file:` comments exist in hand-written `lib/` files outside `l10n/`.

### Commented-out blocks >5 lines

None found in the files read during this survey (hot files and grepped `lib/` tree). A full line-by-line scan of every `lib/` file was not performed exhaustively beyond the hot-file set and the files summarized in Section 4; this is a bounded-confidence finding, not an exhaustive guarantee.

### `print()` / `debugPrint()` in lib/

`grep -rn "print(\|debugPrint(" lib/ --include=*.dart` returned **no matches** — no stray print statements in `lib/`.

### Catches that swallow without logging or rethrowing

- `lib/services/refresh_service.dart:24` — inside `callbackDispatcher()`: `try { await _doRefresh(runCleanup: true); } catch (_) {}` — the background WorkManager task **silently swallows all exceptions** from the entire refresh pipeline with no logging and no rethrow. Given this runs unattended in the background, any fetch/DB/notification failure there is invisible.
- `android/app/src/main/kotlin/io/getflash/app/GeminiNanoPlugin.kt:57-58` — `try { getModel().download().collect {} } catch (_: Exception) {}` — model-download-trigger failures are silently swallowed (arguably acceptable since it's a fire-and-forget download kick, but no logging either).
- `lib/services/gemini_nano_service.dart:42-45` — the general `catch (e)` in the `isAvailable` getter does capture `e.toString()` into `_unavailableReason`, so this one is not silent (fields are exposed via `unavailableReason` getter) — noted for contrast, not flagged as a problem.

---

## Section 12 — Observations

- **Schema version vs. `schema_version` setting drift** (`lib/db/database.dart:43` vs `lib/db/schema.dart:137`): the sqflite `openDatabase(version: 7, ...)` argument has advanced through migrations up to 7, but the `settings` table's own `schema_version` value was last explicitly set to `'3'` by the `oldVersion < 5` migration (`database.dart:105-107`) and never updated again in the `oldVersion < 6` or `oldVersion < 7` migration blocks. If any code reads `settings.schema_version` to make decisions (not confirmed in this survey — no direct reader was located), it would see a stale value of `3` on a DB that is actually at structural version 7. Worth checking whether `schema_version` is read anywhere, or whether it is dead/vestigial.

- **`keyword_blocklist.keyword` vs `keyword_alerts.keyword` collation inconsistency** (`lib/db/schema.dart:90` vs `:99`): the blocklist column is `UNIQUE COLLATE NOCASE` (case-insensitive uniqueness) while the otherwise-parallel alerts column is `UNIQUE` with default (case-sensitive) collation. Two alert keywords differing only in case (`"Apple"` vs `"apple"`) could both be inserted, while the equivalent blocklist keywords could not. Given `KeywordMatcher.matches` is documented as case-insensitive by default (per `keyword_matcher_test.dart` groups), this asymmetry looks like an unintentional oversight rather than a deliberate design choice, but this survey does not confirm intent — flagged for review only, not fixed.

- **Unawaited reconciliation call** (`lib/screens/feed_screen.dart:392`, `unawaited(_refreshCountsFromDb())` inside `_flushMarkReadUI()`): as instructed to confirm, this fire-and-forget call is still present. It means the unread-count/badge reconciliation after a scroll-triggered mark-read batch is not guaranteed to complete before the method returns; if the widget is disposed or another mutation lands in the interim, the two async DB reads inside `_refreshCountsFromDb` (`getAllFolderUnreadCounts` + `getTotalUnreadCount`, via `.wait`) could resolve after other state changes and clobber a more current in-memory `_counts` — though the `if (!mounted) return;` guard inside `_refreshCountsFromDb` at least prevents a `setState` crash on a disposed widget.

- **Release build signing** (`android/app/build.gradle.kts`): the release build type is explicitly configured to sign with the debug keystore (`signingConfig = signingConfigs.getByName("debug")`), flagged by the file's own `// TODO: Add your own signing config for the release build.` comment. This is a known-incomplete area, not a bug in the code sense, but relevant to anyone attempting a production release build.

- **`applicationId` TODO**: `android/app/build.gradle.kts` still carries the Flutter-template comment `// TODO: Specify your own unique Application ID...` immediately above `applicationId = "io.getflash.app"` — the ID itself has clearly already been customized (it's not the Flutter default `com.example.*`), so this TODO comment appears to be stale boilerplate left over from project scaffolding rather than an actual outstanding task.

- **One failing test, deterministic, in `test/article_summary_sheet_test.dart`** (`'a maximum-budget summary fits on one Pixel-class page with no overflow and no scrolling'`): the measured overflow-relevant value (`1281.0`) is roughly 40% over the asserted budget (`914.2857142857143`, i.e. `914.29 * 1.4 ≈ 1280`). This test's name directly encodes a design intent ("no overflow and no scrolling" for a maximum-budget summary) that is presently violated by the implementation — i.e., a maximum-length AI summary does in fact overflow/require scrolling on a Pixel-class viewport, contradicting the "single-pass AI summary" and "scroll-on-overflow" framing of the most recent commit (`c9394ba`, "UX pass 03: single-pass AI summary, ruthless prompt, scroll-on-overflow"). Given the commit message explicitly claims "scroll-on-overflow" as a feature, this specific test asserting *no* scrolling for the maximum-budget case may itself be the stale/contradicted party rather than the implementation — this survey does not adjudicate which side is correct, only that they currently disagree.

- **PRD-Flash.md exists** at repo root (`PRD-Flash.md`, 527 lines, "Version 2.4", "Status: Active — reflecting shipped state", "Last Updated: August 2026"). It states target SDK 35 and minimum SDK 26 (Android 8.0 Oreo), matching the Gradle config's use of Flutter-resolved `minSdkVersion`/`targetSdkVersion` (exact resolved integers not directly visible in `build.gradle.kts` since they're delegated to `flutter.minSdkVersion`/`flutter.targetSdkVersion` — this survey did not independently resolve those Flutter-internal properties to confirm the literal 26/35 match at the Gradle level). PRD explicitly states "No iOS support in v1.0," consistent with Section 3's finding that no macos/windows/web/linux dirs exist, though an `ios/` directory does still exist on disk (present but presumably unused/vestigial).

- **`files/` and `files2/` untracked directories** contain what appear to be duplicated/leftover prompt-and-test-file bundles from two prior "UX pass" work sessions (01 and 02), including zipped copies and standalone copies of test files that also exist properly under `test/` (e.g. `folder_tab_bar_test.dart`, `loading_controller_test.dart`, `resume_refresh_policy_test.dart`, `summary_source_test.dart`, `unread_counts_test.dart`, `session_read_scope_test.dart`). These look like scratch/staging artifacts from an external tooling workflow rather than intentional repo content — flagged for the user's awareness only, not touched.

- **Unanswerable question**: whether the `settings.schema_version` value (stuck at `'3'`) is read anywhere in the codebase to gate any behavior could not be conclusively determined within this survey's scope — no direct reader of that specific setting key was located in the files inspected (`article_repository.dart`, `settings_repository.dart` signature only, `settings_screen.dart` grep only covered a subset of `get`/`set` call sites). A full-repo grep for `'schema_version'` string literal reads (beyond the `schema.dart`/`database.dart` writers already found) was not performed in this pass.
