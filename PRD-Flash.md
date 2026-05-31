# Product Requirements Document
## Flash — Android RSS Reader

**Version:** 2.1
**Status:** Active — reflecting shipped state
**Author:** David
**Last Updated:** May 2026

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

### 3.8 Cloud AI (Optional)
- **Anthropic API** (Claude Haiku) for AI article summaries
- User supplies their own API key in Settings; stored securely on-device

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

**What the feed shows — the session-read model**

The feed displays: **all non-blocked articles in scope that are either unread, or were read during the current app session** (the "session read set"). This single rule governs every tab and every action:

- **Session read set:** an in-memory set of article IDs read since the app launched. It is empty on every cold open and is never persisted to disk.
- **Cold open:** session set is empty → only unread articles appear. Previously-read articles remain in the DB (for deduplication) but do not show.
- **During a session:** any article marked as read (scroll, swipe, tap) is added to the session set. It stays in the list, dimmed in place, for the rest of the session.
- **Tab switching:** the query re-runs for the new tab's scope, passing the same global session set. An article read in one tab is visible (dimmed) in any other tab it belongs to.
- **App restart / cold open:** session set is cleared → fresh unread-only view.

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
- The **scroll position is always restored exactly** when the user returns to the feed — whether from the in-app reader, the system browser, or switching tabs
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
- If **Reader Mode** is on (Settings toggle): opens the in-app Reader screen with extracted article text
  - Pre-flight HTML check determines if the URL serves readable HTML
  - Per-domain compatibility is cached (`reader_compat_<domain>`) to avoid repeated checks
  - Falls back to the system browser for incompatible domains
- If Reader Mode is off: opens directly in the system browser

---

### 4.4 In-App Reader

- Full-screen reading experience with extracted article body
- Article text is extracted from the URL using a lightweight HTML parser, stripping navigation, ads, and boilerplate (`article_extractor.dart`)
- Configurable font size: Small, Medium, Large (set in Settings, applied globally)
- Reader mode is per-article-open, not per-feed
- Falls back to browser if extraction fails for a given domain

---

### 4.5 Search

- Full-text search across article titles and descriptions
- Debounced (350ms) as the user types
- Race-condition safe — stale results from a previous query are discarded
- Results use the same read/unread visual treatment as the feed
- Tapping a result opens the article (respects Reader Mode setting)

---

### 4.6 Bookmarks

- Any article can be bookmarked via long-press radial menu or swipe action
- Bookmarked articles appear in the Bookmarks tab in the bottom navigation
- Bookmarks persist independently of read state — a bookmarked article can be read or unread
- Removing a bookmark removes it from the Bookmarks list immediately

---

### 4.7 Keyword Blocking

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

### 4.8 Keyword Alerts

- User can add keywords to an alert list
- When a new article matches an alert keyword, it is highlighted or surfaced separately
- Managed via Settings > Keyword Alerts screen

---

### 4.9 Article Auto-Cleanup

- **Age-based:** read, unsaved articles whose `published_at` is older than the configured cleanup window are deleted automatically
- The cleanup window defaults to **7 days** and is user-configurable from **5 to 20 days** (Settings → Article cleanup window)
- Unread articles are never deleted, regardless of age
- Bookmarked (saved) articles are never deleted, regardless of read state or age
- Cleanup runs on every cold open and every background refresh, **before** new articles are fetched
- Pull-to-refresh does **not** trigger cleanup — previously read articles remain visible for the session
- Per-folder cleanup is also supported (used by "Mark all as read" on a category tab)

---

### 4.10 Fetch Thresholds

Applied to every feed fetch before articles are written to the database:

- Articles are sorted newest-to-oldest by `published_at`
- Articles with `published_at` older than 7 days are discarded — they would be cleaned up immediately anyway
- Articles with no `published_at` are always discarded
- At most 100 articles per feed per fetch are accepted (the 100 newest within the 7-day window)
- GUID resolution: feed-level guid is preferred; if absent, the article URL is used as the GUID; if neither exists, the article is skipped (no random or timestamp-based GUIDs)
- Duplicate (feed\_id + guid) articles are silently ignored on insert — re-fetching never resets the read state of existing articles

### 4.11 Background Refresh

- Configurable interval: 15 min, 30 min, 1h, 3h, 6h, Manual only
- Default: 30 minutes
- Respects Android battery optimisation (Doze mode)
- On refresh: articles fetched, parsed, keyword-filtered, and written to the database
- No notifications on background refresh — entirely silent

---

### 4.12 AI Article Summary

**Trigger:** Long-press card → radial menu → ✦ Summary

**Flow:**
1. Full article URL is fetched and readable body is extracted
2. Title + first 2,000 characters sent to Claude Haiku:
   > "Summarise this news article in 4 concise bullet points. Be factual and neutral. No preamble."
3. Response shown in a bottom sheet; summary is cached per article URL

**UI:**
- Half-screen bottom sheet slides up immediately with a loading skeleton
- On response: skeleton replaced with 4 bullet points
- All text is selectable
- Footer: "Powered by Claude" + "Open article" button
- Dismiss: tap outside or swipe down

**Error States:**
- No API key: prompt to add key in Settings
- Network/API failure: "Couldn't load summary. Tap to retry."
- Paywall/blocked: "This article couldn't be retrieved. Open it in your browser."

**Cost:** ~€0.0001 per summary at Claude Haiku pricing

---

### 4.13 Backup & Restore

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

### 4.14 OPML Import / Export

- Import: reads an OPML file and adds all feeds, preserving folder structure where possible
- Export: generates a standard OPML file shared via the system share sheet
- Accessible from Settings

---

### 4.15 Onboarding

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
| Reader mode | Off | On, Off |
| Article font size | Medium | Small, Medium, Large |
| Anthropic API key | — | Text input (masked) |
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
- In-app Reader with article extraction, per-domain compatibility caching
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
- AI article summary (Claude Haiku, cached)
- Gemini Nano integration
- Localisation: EN, DE, ES, FR, IT
- Dynamic colour theming (Material You)
- Unread badges on folder tabs and app icon
- Empty state screens
- Settings screen with all options

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

- **Launcher icon:** Not yet finalised
- **Opinion filter:** Planned but not yet implemented — the dedicated Opinions folder and Claude Haiku classification pipeline are not shipped
- **Restore merge vs replace:** Current behaviour is replace (wipe then re-insert); merge with duplicate-URL detection is a future improvement
- **Play Store:** No decision yet on public distribution
