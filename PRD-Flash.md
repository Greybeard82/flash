# Product Requirements Document
## Flash — Android RSS Reader

**Version:** 2.4
**Status:** Active — reflecting shipped state
**Author:** David
**Last Updated:** August 2026

---

## 1. Product Overview

Flash is a locally-hosted, account-free Android RSS/Atom feed reader with a native Material You interface. It aggregates news from user-defined feeds, organises them into folders, and intelligently filters out noise — through keyword blocking and AI-assisted summarisation — so the user reads only the content they care about.

All data lives on-device. Google Drive backup and local file backup are both available as optional, non-destructive exports. No account is required to use core functionality.

---

## 2. Goals

- Replicate and improve upon the core experience of Palabre (discontinued)
- Fix the broken keyword blocking feature that existed in Palabre's final version
- Feel, behave, and animate like a native Android application — not a cross-platform wrapper
- Keep the experience fast, distraction-free, and fully offline-capable for reading cached headlines

---

## 3. Platform & Technical Stack

### 3.1 Target Platform
- **Primary:** Android — minimum SDK 26 (Android 8.0 Oreo), target SDK 35
- **Package:** `io.getflash.app`
- No iOS support in v1.0

### 3.2 Framework
- **Flutter** — near-native Android performance, Material 3 widget library, strong Dart ecosystem for local storage and background tasks

### 3.3 Native Android Feel — Non-Negotiable Requirement
The app must look, behave, and animate as if it were written in native Kotlin with Jetpack Compose.

Specific mandates:
- **Material 3 (Material You)** design system throughout
- **Dynamic colour theming** (Android 12+) — palette adapts to the user's wallpaper-derived colour scheme via `dynamic_color`
- **Standard Android navigation patterns**: bottom navigation bar, back gesture support, predictive back
- **Haptic feedback** on swipe actions, long-press, and confirmations via `HapticFeedback`
- **Edge-to-edge layout** with proper window inset handling
- **Pull-to-refresh** uses Material 3 `RefreshIndicator`
- Typography: Roboto / system default — no custom fonts
- All dialogs, bottom sheets, and snackbars are standard Material 3 components

**Exception — Newspaper mode (opt-in):** When the user enables Newspaper mode in Settings, the app deliberately departs from the above. It switches to a printed-newspaper aesthetic: newsprint paper background, serif type (PT Serif body, Playfair Display headlines), and a red spot-colour accent. Both fonts are bundled as OFL-licensed TTF assets — no runtime font fetching. This mode overrides the System/Light/Dark theme choice. It is OFF by default and has no effect on the native-feel rules above when disabled.

### 3.4 Local Storage
- **SQLite via `sqflite`** — feeds, articles, read state, folders, blocklist, settings, keyword alerts
- Schema versioned with migration support

### 3.5 Background Processing
- **`workmanager`** — periodic background feed refresh, respects Android battery optimisation (Doze mode)

### 3.6 Feed Parsing
- HTTP via `http` package
- RSS 2.0 and Atom 1.0 via `dart_rss`
- Favicon fetching via Google's favicon service (`sz=64`)

### 3.7 On-Device AI
- **Gemini Nano** via a native Android plugin (`GeminiNanoPlugin.kt`) for on-device AI features
- No API key required for Gemini Nano features

### 3.8 Cloud AI (Optional) — Not Implemented
- **Anthropic API** (Claude Haiku) for AI article summaries was the original plan; it was never built
- The shipped summary feature is entirely on-device via Gemini Nano (§3.7) — no API key, no network call, no cloud dependency

### 3.9 Backup
- **Google Drive** via `google_sign_in` + Drive appdata scope — saves `flash_backup.json` to the app's private Drive folder
- **Local file backup** via share sheet — exports the same JSON format to any destination the user chooses (Downloads, email, cloud storage, etc.)
- Both use a shared serialisation format (`BackupSerializer`) — backups are interchangeable between methods

### 3.10 Localisation
- Supported languages: **English, German, Spanish, French, Italian**
- Uses Flutter's `flutter_localizations` with ARB files
- System locale is detected automatically; user can override in Settings

---

## 4. Features

### 4.1 Feed Management

**Add Feed**
- User inputs a URL; app validates and fetches + parses as RSS or Atom
- On success: feed is added with title and favicon resolved automatically
- On failure: error shown with suggested fix
- Feeds are assigned to a folder at add time or can be moved later
- Feedly search integration for feed discovery

**Edit / Remove Feed**
- Swipe to delete, tap to edit
- Deletion confirmed via dialog

**Feed Health**
- Feeds that fail to fetch show a warning indicator
- Consecutive failure count tracked; feeds failing for 7+ days marked dead

**Favicon**
- Fetched and cached locally on feed add
- Displayed throughout the app next to feed name and in article cards
- Falls back to a generated monogram avatar if unavailable

---

### 4.2 Folder / Category Management

- User can create, rename, and delete folders
- Feeds are assigned to exactly one folder
- Folders appear as **scrollable tabs at the bottom** of the feed view (above the nav bar) — not at the top
- Tab order is user-reorderable
- Each folder tab shows an unread count badge
- Badges update **live from any tab** — reading an article in the All tab (via scroll, swipe, tap, or mark-all-read) immediately decrements that article's folder badge too, without switching tabs or reloading. An unawaited authoritative re-query self-heals any drift within a scroll pause. Badge counts come from `is_read` in the DB and are scope-independent, so this was already correct before session-read scoping existed and is unaffected by it.
- A read article, however, leaves every *other* tab's visible list immediately (session-read visibility is per-tab — see §4.3) even though its badge count updates everywhere at once — the count and the visibility are tracked independently.
- A special **"All"** tab aggregates articles across all folders
- All category tabs behave identically to "All" — same session-read model, scroll, and mark-all-read rules apply (category mark-all-read also refreshes that folder's feeds)

---

### 4.3 Article Feed

**Layout**
- Card-based list: title, source favicon, source name, relative timestamp, reading time estimate, and a thumbnail
- Thumbnail priority: (1) `<media:content>` / `<media:thumbnail>`, (2) Open Graph `og:image`, (3) first `<img>` in body, (4) monogram placeholder
- Thumbnails fetched and cached locally — no re-fetching on scroll
- Thumbnail: 72×72dp square, cover crop, 8dp rounded corners, right-aligned
- Articles sorted newest-to-oldest — no user-configurable sort order
- Unread articles have full visual weight; read articles are dimmed (reduced opacity, lighter font weight)

**Auto-Refresh on Open**
- On every cold open, Flash silently fetches all feeds in the background immediately after loading the cached article list from the database
- A full-screen lightning bolt (⚡) pulse animation replaces the content area during the cold-start fetch; the FABs are hidden until the fetch completes
- Before fetching, stale articles (read, unsaved, older than the configured cleanup window) are purged from the database
- This ensures the list is always up to date within seconds of opening the app

**Auto-Refresh on Resume**
- Returning to Flash from the background after being away **≥30 seconds**, with no fetch in the last 5 minutes, triggers a silent network fetch (`ResumeRefreshPolicy`, both thresholds configurable)
- Unlike cold open, this fetch runs with **no cleanup** — purging read articles mid-session would break the session-read list-persistence guarantee above — and shows no boot animation, since the user is already looking at their list
- Scroll position is captured before the fetch and restored after; because new articles insert above the current position, the list can still visually shift when there's fresh content — a known limitation, not yet anchor-corrected
- A brief excursion (e.g. popping out to the browser and back) never triggers a fetch; only DB state is reloaded

**What the feed shows — the session-read model**

The feed displays: **all non-blocked articles in scope that are either unread, or were read during the current app session** (the "session read set"). This single rule governs every tab and every action:

- **Session read set:** an in-memory set of article IDs read since the app launched. It is empty on every cold open and is never persisted to disk.
- **Cold open:** session set is empty → only unread articles appear. Previously-read articles remain in the DB (for deduplication) but do not show.
- **Scoped per tab:** the session read set is keyed by scope — `kAllScope` for the All tab, the folder's id for a category tab (`SessionReadTracker`). An article marked read is added to the *current* tab's scope only, and stays in the list, dimmed in place, for the rest of the session — **but only in that tab**. It is absent entirely from every other tab, not dimmed, not present. The rule is symmetric: an article read in a category tab is equally gone from All.
- **Why it stays visible in its own tab:** scrolling past the top of the viewport marks an article read; if it then vanished from the list being actively scrolled, everything below it would jump up under the user's thumb. The list-stability and exact-scroll-restoration guarantees above are unchanged — this only narrows their scope from "every tab" to "the tab it was read in".
- **Tab switching:** the query re-runs for the new tab's scope, passing that scope's own session set — not a shared global one.
- **Mark as unread:** clears the article from every scope, so it reappears everywhere immediately.
- **App restart / cold open:** every scope is cleared → fresh unread-only view everywhere.

**Mark as Read — On Scroll**
- Articles are automatically marked as read as they scroll past the midpoint of the viewport
- DB write is immediate; the visual dim is debounced 150ms to avoid flicker during fast scrolling
- Can be disabled in Settings

**Mark as Read — Swipe**
- Swipe in either direction (left or right): mark as read, add to session set
- Article dims in-place — it is never removed from the list mid-session

**Mark as Unread — Swipe**
- Long-press → radial menu (see below), or dedicated swipe gesture: mark as unread, remove from session set
- Article restores full visual weight and is hidden on the next tab reload

**Mark All as Read — No Confirmation, Immediate Execution**

Behaviour differs by tab:

- **All tab:** marks every article read in DB → **clears the entire session set** → runs age-based cleanup → plays cold-start (⚡) animation → refreshes all feeds → reloads. Result: only newly fetched unread articles are shown.
- **Category tab:** marks every article in that folder read in DB → **removes that folder's article IDs from the session set** → runs cleanup for that folder only → **refreshes that folder's feeds** → reloads → shows a `NotificationBanner` confirmation. Result: only newly fetched unread articles for that folder are shown.

No confirmation dialog is ever shown. Scroll position for the affected tab resets to top after reload.

**Scroll position**
- The **scroll position is always restored exactly** when the user returns to the feed — whether from the system browser or switching tabs
- Switching to a different category tab resets that tab's scroll to the top (correct behaviour); the previous tab's position is saved and restored when switching back
- These behaviours have no user toggle — they are hardcoded

**Long-Press Radial Menu**
- Long-press any article card to open a radial context menu centred on the card
- Two action buttons:
  - **Share** — triggers Android native share sheet
  - **✦ Summary** — opens AI article summary sheet
- Central × button and tapping outside both dismiss the menu
- Background dims while the menu is open
- Menu animates in with radial expand (scale + fade, ~150ms)

**Pull-to-Refresh**
- Swipe down from the top of the feed list triggers an immediate refresh of all feeds in the current tab
- Uses Material 3 `RefreshIndicator`

**FAB Cluster (bottom-right)**
Three mini FABs, visible only when at least one feed exists:
- **Refresh** — refreshes current tab's feeds; shows spinner while active
- **Search** — opens the Search screen
- **Mark all read** — executes the mark-all-read sequence above

**Open Article**
- Tap a card to open the article; the card dims in-place immediately (marks as read, added to session set); exact scroll position is restored on return — no reload
- Opens directly in the system browser

---

### 4.4 Search

- Full-text search across article titles and descriptions
- Debounced (350ms) as the user types
- Race-condition safe — stale results from a previous query are discarded
- Results use the same read/unread visual treatment as the feed
- Tapping a result opens the article in the system browser

---

### 4.5 Bookmarks

- Any article can be bookmarked via long-press radial menu or swipe action
- Bookmarked articles appear in the Bookmarks tab in the bottom navigation
- Bookmarks persist independently of read state — a bookmarked article can be read or unread
- Removing a bookmark removes it from the Bookmarks list immediately

---

### 4.6 Keyword Blocking

Flagship feature — fixes Palabre's broken implementation.

**Blocklist Management**
- Settings > Keyword Blocklist
- Plain-text keywords or phrases (e.g. "Elon Musk", "crypto", "sponsored")
- Optional whole-word-only toggle per keyword

**Matching Logic**
- Checked against article title and description/summary
- Case-insensitive, partial-word match by default
- Whole-word mode available per keyword

**Behaviour on Match**
- Article is hidden from all feed views
- Automatically marked as read in the database
- Retroactive blocking: newly added keywords are applied to all existing unread articles immediately

**Performance**
- Runs locally at parse time — zero latency, zero API calls

---

### 4.7 Keyword Alerts

- User can add keywords to an alert list
- When a new article matches an alert keyword, it is highlighted or surfaced separately
- Managed via Settings > Keyword Alerts screen

---

### 4.8 Article Auto-Cleanup

- **Age-based:** read, unsaved articles whose `published_at` is older than the configured cleanup window are deleted automatically
- The cleanup window defaults to **7 days** and is user-configurable from **5 to 20 days** (Settings → Article cleanup window)
- Unread articles are never deleted, regardless of age
- Bookmarked (saved) articles are never deleted, regardless of read state or age
- Cleanup runs on every cold open and every background refresh, **before** new articles are fetched
- Pull-to-refresh does **not** trigger cleanup — previously read articles remain visible for the session
- Per-folder cleanup is also supported (used by "Mark all as read" on a category tab)

---

### 4.9 Fetch Thresholds

Applied to every feed fetch before articles are written to the database:

- Articles are sorted newest-to-oldest by `published_at`
- Articles with `published_at` older than 7 days are discarded — they would be cleaned up immediately anyway
- Articles with no `published_at` are always discarded
- At most 100 articles per feed per fetch are accepted (the 100 newest within the 7-day window)
- GUID resolution: feed-level guid is preferred; if absent, the article URL is used as the GUID; if neither exists, the article is skipped (no random or timestamp-based GUIDs)
- Duplicate (feed\_id + guid) articles are silently ignored on insert — re-fetching never resets the read state of existing articles

### 4.10 Background Refresh

- Configurable interval: 15 min, 30 min, 1h, 3h, 6h, Manual only
- Default: 30 minutes
- Respects Android battery optimisation (Doze mode)
- On refresh: articles fetched, parsed, keyword-filtered, and written to the database
- No notifications on background refresh — entirely silent

---

### 4.11 AI Article Summary

**Trigger:** Long-press card → radial menu → ✦ Summary

Entirely **on-device** via **Gemini Nano** (Android AICore, `GeminiNanoPlugin.kt`) — no API key, no network call, no cloud dependency. Unavailable on devices without AICore support (Pixel 8 Pro / 9 Pro class, Android 14+).

**Flow:**
1. On open, the sheet checks an in-memory session cache (`SummaryCache`, keyed by article URL, 50-entry LRU) — a hit renders immediately with no native call at all.
2. On a cache miss, the sheet checks Nano availability, then extracts the article's full body from its URL (`ArticleExtractor` → `SummarySource`, capped at 2,500 characters, raced against a hard 2-second budget) rather than summarising the short RSS teaser. If extraction fails, times out, or the result is too short to be substantial, it falls back to the RSS description and the sheet shows a quiet "Based on the article preview only." note in the footer.
3. Generation is a **single streaming pass** on the native side (`GeminiNanoPlugin.kt`, 20-second timeout): a ruthless, fact-only prompt instructs the model to lead with the headline's promise on line one, then up to five single-fact bullet lines, banning filler phrasing ("aims to", "is expected to", etc.) and inference beyond what the source states.
4. Nothing is rendered until the stream completes: chunks are buffered silently as they arrive, then run through `SummaryFormatter` (strips stray preambles/markdown, normalises bullet markers, backstops at 180 words / 8 bullets) and the full clamped result is revealed in one step — no partial/flickering text is ever shown. A successful result is written to the cache for the rest of the session.

**UI:**
- Bottom sheet sized to its content (not forced full-screen, capped at 90% of screen height) slides up immediately, showing an animated loading indicator with a status line: "Reading the article…" during extraction, then "Writing the summary…" once generation starts
- Content scrolls only when it exceeds the sheet — `ClampingScrollPhysics`, not a fixed one-page assumption; a compliant summary still fits on one page at default text scale
- All text is selectable
- Footer: disclaimer + "Copy" button (+ the teaser-only note when applicable)
- Dismiss: tap outside or swipe down

**Error States:**
- Device doesn't support Gemini Nano: unavailable message with the reason
- Model still downloading: retry-shortly message
- Stream error or empty result: unavailable message, no partial text ever shown

---

### 4.12 Backup & Restore

**Backup format:** Single JSON file (`flash_backup.json`) containing folders, feeds, and keyword blocklist. Version-tagged for forward compatibility.

**What is backed up:**
- Folder list and order
- Feed list (URL, title, folder assignment, position)
- Keyword blocklist

**What is NOT backed up:**
- Article content or read/unread state
- API keys
- Bookmarks (stored locally, not in backup)

**Google Drive Backup:**
- Requires Google sign-in (OAuth 2.0)
- Saved to app's private Drive appdata folder (not visible in Drive UI)
- "Backup now" and "Restore from Drive" buttons in Settings
- Shows feed/folder/keyword counts before confirming restore

**Local File Backup:**
- Exports JSON via system share sheet — user saves wherever they want
- Import via file picker (`.json` only)
- Same format as Drive backup — files are interchangeable

**Restore behaviour:** Wipes all existing folders, feeds, and keywords, then re-inserts from the backup file. Articles are re-fetched on the next refresh.

---

### 4.13 OPML Import / Export

- Import: reads an OPML file and adds all feeds, preserving folder structure where possible
- Export: generates a standard OPML file shared via the system share sheet
- Accessible from Settings

---

### 4.14 Onboarding

- Shown on first launch only
- Walks the user through adding their first feed and creating a folder
- Once completed, the flag is persisted and onboarding never appears again

---

## 5. Thumb Zone Design

Core UX principle — the app is designed for one-handed operation.

### 5.1 Zone Map

| Zone | Screen area | What lives here |
|---|---|---|
| Green (primary) | Bottom ~40% | Nav bar, folder tabs, FABs, swipe targets |
| Yellow (secondary) | Middle ~35% | Article cards (scrollable content) |
| Red (display only) | Top ~25% | App name, no frequent tap targets |

### 5.2 Layout Rules

- **Folder tabs are at the bottom**, directly above the nav bar — not at the top. This is a hard requirement.
- Folder tab bar is **60dp tall** (`FolderTabBar.barHeight`), with each tab enforcing a 48×48dp minimum tap target — verified by a widget test, not just eyeballed
- FABs are bottom-right, stacked vertically
- Context menus and action sheets open as **bottom sheets**, never top dropdowns
- Minimum tap target: **48×48dp** on all interactive elements
- Long-press interactions preferred over top-bar overflow menus

---

## 6. Navigation Structure

```
Bottom Navigation Bar (always visible):
├── Flash (⚡) — main article feed, tabbed by folder
├── Categories — manage feeds and folders
├── Bookmarks — saved articles
└── Settings — all configuration

Folder Tab Bar (above nav bar, scrollable horizontal):
├── All
├── [User folders...]
└── (scrollable, no add button in tab bar itself)

Top Bar (display only):
└── App name "Flash"

Content area:
└── Article cards (scrollable)
```

---

## 7. Settings

| Setting | Default | Options |
|---|---|---|
| Theme | System | Light, Dark, System |
| Background refresh interval | 30 min | 15m, 30m, 1h, 3h, 6h, Manual |
| Mark as read on scroll | On | On, Off |
| Google Drive backup | — | Sign in / Sign out, Backup now, Restore |
| Local backup | — | Export, Import |
| OPML | — | Import, Export |
| Keyword blocklist | — | Manage list |
| Keyword alerts | — | Manage list |
| Article cleanup window | 7 days | 5–20 days (stepper) |
| Newspaper mode | Off | On/Off |
| Language | System | EN, DE, ES, FR, IT |

---

## 8. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Cold start to feed visible | < 1.5 seconds |
| Feed refresh (20 feeds, Wi-Fi) | < 8 seconds |
| Scroll performance | 60 fps minimum, 120 fps on capable devices |
| Offline readability | All cached headlines available with no network |
| Database size (typical use) | < 50 MB for 20 feeds × 100 articles |
| Crash-free sessions | > 99.5% |
| Min Android version | Android 8.0 (SDK 26) |
| Target Android version | Android 15 (SDK 35) |

---

## 9. Build & Distribution

- **Framework:** Flutter + Android SDK
- **Package ID:** `io.getflash.app`
- **Dev environment:** VS Code + Claude Code
- **Builds:** `flutter run --release` installed directly to device via USB
- **Source control:** GitHub (`Greybeard82/flash`)
- **CI:** None in v1.0
- **Distribution:** Sideloaded APK for personal use; Play Store not required for v1.0

---

## 10. Build Status

### Shipped
- Feed add/remove/edit, folder management
- RSS 2.0 + Atom 1.0 parsing, favicon fetching, thumbnail fetching and caching
- Card list UI with shimmer loading state
- Mark as read on scroll, swipe gestures (read/unread)
- Pull-to-refresh, manual refresh FAB
- Auto-refresh on cold open with lightning bolt animation
- Age-based article cleanup (configurable 5–20 day window, default 7 days, runs on cold start + background refresh)
- Fetch thresholds: 7-day age filter + 100-article cap per feed; deterministic GUID resolution
- INSERT OR IGNORE deduplication — re-fetch never resets read state
- Per-tab scroll position preservation
- `NotificationBanner` slide-in widget (replaces snackbar for confirmations)
- Article search (full-text, debounced, race-safe)
- Bookmarks screen
- Keyword blocklist with retroactive blocking
- Keyword alerts
- Background refresh via WorkManager
- Article auto-cleanup
- Onboarding flow
- Google Drive backup + restore
- Local file backup + restore (via share sheet)
- OPML import + export
- AI article summary — on-device Gemini Nano, single streaming pass, no API key
- Localisation: EN, DE, ES, FR, IT
- Dynamic colour theming (Material You)
- Unread badges on folder tabs and app icon, updating live from any tab
- Empty state screens
- Settings screen with all options
- Session-read model: mark-all-read on a category tab now also refreshes that folder's feeds
- Newspaper mode: opt-in serif theme (bundled PT Serif / Playfair Display OFL fonts), masthead nameplate on the feed screen, DB-persisted toggle in Settings
- Folder tab bar: 60dp height, 48×48dp minimum tap targets, ripple feedback, auto-scroll to selected tab
- Global loading indicator: a top-edge progress bar backed by a reference-counted `LoadingController`, covering every user-initiated async operation app-wide
- Resume refresh: returning from background after ≥30s triggers a silent, cleanup-free network fetch (5-minute minimum interval)

### Not Yet Built
- iOS support
- Push notifications for keyword alerts
- Home screen widget
- Tablet-optimised layout
- Per-feed custom refresh intervals
- Multi-account Google Drive
- Live sync across devices

---

## 11. Open Questions

- **Opinion filter:** Planned but not yet implemented — the dedicated Opinions folder and Claude Haiku classification pipeline are not shipped
- **Restore merge vs replace:** Current behaviour is replace (wipe then re-insert); merge with duplicate-URL detection is a future improvement
- **Play Store:** No decision yet on public distribution
