# Product Requirements Document
## Flash — Android RSS Reader

**Version:** 1.1  
**Status:** Active  
**Author:** David  
**Last Updated:** April 2026

---

## 1. Product Overview

Flash is a locally-hosted, account-free Android RSS/Atom feed reader with a native Material You interface. It aggregates news from user-defined feeds, organizes them into folders, and intelligently filters out noise — through keyword blocking and AI-assisted opinion detection — so the user reads only the content they care about.

All data lives on-device. Google Drive backup is optional and non-destructive. No account is required to use core functionality.

---

## 2. Goals

- Replicate and improve upon the core experience of Palabre (discontinued)
- Fix the broken keyword blocking feature that existed in Palabre's final version
- Feel, behave, and animate like a native Android application — not a cross-platform wrapper
- Keep the experience fast, distraction-free, and fully offline-capable for reading cached headlines

---

## 3. Platform & Technical Stack

### 3.1 Target Platform
- **Android only** — minimum SDK 26 (Android 8.0 Oreo), target SDK 35
- No iOS support in v1.0

### 3.2 Framework
- **Flutter** — chosen for near-native Android performance, Material 3 widget library, and strong Dart ecosystem for local storage and background tasks

### 3.3 Native Android Feel — Non-Negotiable Requirement
The app must look, behave, and animate as if it were written in native Kotlin with Jetpack Compose. This is a hard requirement, not a nice-to-have.

Specific mandates:
- Use **Material 3 (Material You)** design system throughout — `flutter_material_you` or equivalent
- Respect system **dynamic color theming** (Android 12+) — the app palette must adapt to the user's wallpaper-derived color scheme
- Use **standard Android navigation patterns**: bottom navigation bar, back gesture support, predictive back animation (Android 14+)
- All transitions must use **Material motion system**: shared element transitions, container transforms, fade-through for tab switches
- **Haptic feedback** on swipe actions, long-press, and confirmation dialogs using Android's `HapticFeedbackConstants`
- **Edge-to-edge layout** with proper window inset handling (status bar, navigation bar, notch)
- Swipe gestures must have **momentum and physics** consistent with native Android list behavior (`ListView`/`RecyclerView` feel)
- **Pull-to-refresh** must use the Material 3 `RefreshIndicator` pattern
- Typography must use **Roboto** (or system default) — no custom fonts that break the native feel
- All dialogs, bottom sheets, and snackbars must be standard Material 3 components
- The app must pass a visual inspection by an Android developer as "native-looking"

### 3.4 Local Storage
- **SQLite via `sqflite`** — feeds, articles, read state, folders, blocklist, settings
- Schema versioned with migration support from day one

### 3.5 Background Processing
- **`workmanager`** Flutter plugin — periodic background feed refresh, respects Android battery optimization (Doze mode)

### 3.6 Feed Parsing
- HTTP fetch via `http` or `dio` package
- RSS 2.0 and Atom 1.0 parsing via `webfeed` or `dart_rss`
- Favicon fetching: `https://www.google.com/s2/favicons?sz=64&domain=[domain]`

### 3.7 AI Opinion Detection (Optional Feature)
- **Claude Haiku API** (`claude-haiku-4-5`) via Anthropic REST API
- User must supply their own API key in Settings
- Key stored in **Android Keystore** (encrypted, not plaintext)

### 3.8 Google Drive Backup (Optional Feature)
- `google_sign_in` + Drive REST API v3
- Saves a single JSON file to `/Flash/backup.json` in user's Drive

---

## 4. Features

### 4.1 Feed Management

**Add Feed**
- User inputs a URL; app validates and attempts to fetch + parse as RSS or Atom
- On success: preview feed title, favicon, and first 3 articles before confirming
- On failure: display feed health error with suggested fix (wrong URL, feed offline, not RSS)
- Feeds can be assigned to a folder at add time or later

**Edit / Remove Feed**
- Long-press or swipe to access edit/delete options
- Deletion is soft-confirmed via a snackbar with undo

**Feed Health Indicator**
- Feeds that fail to fetch on last refresh display a warning icon
- Tapping shows last error message and timestamp
- Feeds unreachable for 7+ consecutive days are marked "dead"

**Favicon**
- Fetched automatically on feed add
- Displayed next to feed name throughout the app
- Falls back to a generated monogram avatar if unavailable

---

### 4.2 Folder / Category Management

- User can create, rename, and delete folders
- Feeds are assigned to exactly one folder (or "Uncategorized" by default)
- Folders appear as tabs in the main feed view
- Tab order is user-reorderable via long-press drag
- Each folder tab displays an unread count badge
- A special **"All"** tab aggregates all feeds across all folders
- A special **"Opinions"** folder is auto-created and managed by the opinion filter (see 4.7); it cannot be deleted while the feature is active

---

### 4.3 Article Feed

**Layout**
- Card-based list: title, source name with favicon, relative timestamp, and a thumbnail image
- Thumbnail sourcing priority: (1) `<media:content>` or `<media:thumbnail>` from feed metadata, (2) Open Graph `og:image` fetched from the article URL head, (3) first `<img>` tag in article body, (4) generic placeholder with source initial if none found
- Thumbnails are fetched and cached locally on first article load -- no re-fetching on scroll
- Thumbnail dimensions: fixed 72x72dp square, `cover` crop, rounded corners (8dp), right-aligned on the card
- Articles sorted newest to oldest, always — no user-configurable sort order
- Unread articles have full visual weight; read articles are visually de-emphasized (reduced opacity, lighter text weight)

**Article List Persistence — Hardcoded Behaviour**
- Articles **stay in the list permanently** once loaded, even after being marked as read — they never disappear mid-session
- Read articles are visually de-emphasised (reduced opacity, lighter weight) but remain in place
- The **scroll position is always restored** exactly when the user returns to the feed — whether from the in-app reader, the system browser, or any other screen. The list never jumps or resets.
- These two behaviours are non-negotiable UX requirements, not settings. There is no user toggle for them.

**Mark as Read — On Scroll**
- As articles scroll past the midpoint of the screen, they are automatically marked as read
- This matches the behavior of Palabre and Reeder
- Mark-as-read on scroll can be disabled in Settings for users who prefer explicit read marking

**Mark as Read — Other Methods**
- Swipe left: mark as read
- Swipe right: mark as unread
**Mark All as Read — Hardcoded Behaviour**
This action has a precise three-step sequence that must not be changed:
1. **Immediately clears the list** — the article list empties the moment the button is tapped, giving instant visual feedback
2. **Refreshes all feeds** in the current tab/folder to fetch any new articles published since the last refresh
3. **Reloads unread-only** — only articles that arrived during the refresh step are shown; nothing previously read reappears

A one-time confirmation dialog is shown on the first use only (suppressed on all subsequent taps).

**Long-press Quick Actions (Radial Menu)**
- Long-press on any card opens a circular radial context menu centred on the card -- identical in interaction pattern to Palabre's original radial menu
- The radial has exactly 2 action buttons arranged around a central X dismiss button:
  - **Share** (top-left) -- triggers Android native share sheet
  - **✦ Summary** (top-right) -- triggers AI article summary (see section 4.9)
- Central X button dismisses the menu with no action
- Tapping outside the radial also dismisses it
- Background cards are dimmed while the radial is open
- Radial animates in with a quick radial expand (scale + fade, ~150ms)
- Mark as read / unread remains swipe-only (left = read, right = unread) and is not in the radial menu
- "Mark all as read" button: available per feed, per folder, and globally via long-press on the folder tab

**Pull-to-Refresh**
- Swipe down from the top of the feed triggers an immediate refresh of all feeds in the current folder
- Material 3 `RefreshIndicator` animation

**Manual Refresh FAB**
- A floating action button (mini, bottom-right) sits above the folder tab row on the Feed screen
- Tapping it triggers an immediate refresh of the current folder's feeds
- Shows a `CircularProgressIndicator` while refreshing, disabled during the refresh to prevent double-taps
- Only visible when at least one feed has been added (hidden on the empty state screen)

**Open Article**
- Tapping a card opens the article URL in the system default browser (Chrome, Firefox, etc.)
- No in-app webview

**Share Article**
- Available via long-press quick action menu
- Triggers Android native share sheet with article title + URL

---

### 4.4 Keyword Blocking

This is the flagship feature, fixing Palabre's broken implementation.

**Blocklist Management**
- Accessible from Settings > Keyword Blocklist
- User adds plain-text keywords or phrases (e.g. "Elon Musk", "crypto", "sponsored")
- No limit on number of blocked keywords

**Matching Logic**
- Checked against article **title** and **description/summary** fields
- Case-insensitive
- Partial word match (e.g. "crypto" blocks "cryptocurrency")
- Optional whole-word-only toggle per keyword for power users

**Behavior on Match**
- Matching articles are **not displayed** in any feed
- They are automatically **marked as read** in the database
- A subtle notice at the top of the feed shows "X articles hidden by keyword filter" with a tap-to-audit option
- Audit view shows all blocked articles with the matching keyword highlighted — read-only, no way to accidentally unblock

**Performance**
- Matching runs locally at parse time — zero latency, zero API calls
- Blocklist is loaded into memory on app start and re-evaluated on any blocklist change

---

### 4.5 Article Auto-Cleanup

- Each feed stores a maximum number of read articles locally (default: 100 per feed, configurable in Settings per feed or globally)
- When the limit is exceeded, the oldest read articles are deleted from the database
- Unread articles are never auto-deleted regardless of age
- Blocked articles count toward the limit and are cleaned up first

---

### 4.6 Background Refresh

- Configurable interval: 15 minutes, 30 minutes, 1 hour, 3 hours, 6 hours, manual only
- Default: 30 minutes
- Respects Android battery optimization — refresh may be delayed under Doze mode
- On refresh, new articles are fetched, parsed, and filtered (keyword block + opinion filter if enabled) before being written to the database
- No push notification on refresh — the app is silent in the background

---

### 4.7 Opinion Filter

**Purpose**
Automatically moves articles detected as opinion pieces, editorials, or commentary to the dedicated Opinions folder, keeping the main feed as factual news only.

**Two-Stage Detection**

Stage 1 — Heuristic (always active, free):
- Checks RSS category/tag fields for values like: opinion, editorial, commentary, column, analysis, op-ed, perspective, letters
- Checks title for patterns like: "Why I", "The case for", "We need to", "It's time to", "Opinion:", "Column:"
- Case-insensitive, configurable list of patterns in Settings

Stage 2 — Claude Haiku AI (optional, requires API key):
- Enabled via toggle in Settings > Opinion Filter
- Requires user's own Anthropic API key (stored in Android Keystore)
- Prompt sent per article: title + first 300 characters of description
- Classification: `opinion` or `news` — binary, no confidence scores surfaced to user
- Articles already caught by Stage 1 are not re-sent to the API (cost saving)
- API calls are batched per refresh cycle, not per article
- On API failure: article stays in main feed (fail open, never fail to opinion)

**Behavior on Detection**
- Article is silently moved to the Opinions folder
- Opinions folder unread badge updates accordingly
- User can browse Opinions at any time via the bottom navigation
- No way to "un-opinion" an article in v1.0 (flagged for v1.1)

**Cost Estimate**
- Claude Haiku: approximately $0.001 per 100 articles classified
- Typical usage (50 new articles/day, 30-day month): under €0.02/month

---

### 4.8 Google Drive Backup

**What is Backed Up**
- Feed list (URLs, names, folder assignments, favicon cache paths)
- Folder list and order
- Keyword blocklist
- App settings

**What is NOT Backed Up**
- Article read/unread state
- Article content or cache
- API keys

**Behavior**
- Optional — user must opt in from Settings > Backup
- Requires Google sign-in (OAuth 2.0 via `google_sign_in`)
- Saves to `/Flash/backup.json` in the user's Google Drive root
- Manual backup: "Backup now" button in Settings
- Manual restore: "Restore from Drive" button in Settings
- On restore: user is shown a diff (X feeds, Y folders, Z keywords) before confirming
- Auto-backup: optional toggle — backs up automatically whenever feed list or blocklist changes

### 4.9 AI Article Summary

**Purpose**
On-demand plain-English summary of any article, without the user needing to open a browser.

**Trigger**
Long-press card → bottom sheet → "Summarise with AI"

**How It Works**
1. App fetches the full article URL via HTTP
2. Extracts readable body text (strips nav, ads, boilerplate) using a lightweight HTML parser (`html` Dart package)
3. Sends title + first 2,000 characters of body to Claude Haiku with a fixed system prompt:
   > "Summarise this news article in 4 concise bullet points. Be factual and neutral. No preamble."
4. Response is displayed in a Material 3 bottom sheet with a loading indicator while the API call completes
5. Summary is **cached locally** per article URL -- tapping Summarise a second time shows the cached result instantly, no repeat API call

**UI**
- Trigger: tap ✦ Summary in the radial menu
- While loading: a half-screen modal slides up immediately with a loading skeleton/spinner and the article headline as the title
- On response: skeleton is replaced with the summary content
- Modal height: 50% of screen height, fixed (not draggable/expandable in v1.0)
- Modal content:
  - Article headline at the top (2 lines max, bold)
  - 4 bullet point summary, clean typography
  - **All text in the modal must be selectable** -- user can highlight and copy any part of the summary
  - Footer: small muted "Powered by Claude" label + "Open article" button
- Dismiss: tap anywhere outside the modal, or swipe down on the modal
- Modal is a custom overlay (not a standard `ModalBottomSheet`) to achieve the 50% fixed height and selectable text behaviour

**Error States**
- No API key set: bottom sheet shows "Add your Anthropic API key in Settings to use AI features" with a shortcut button to Settings
- Network error or API failure: "Couldn't load summary. Tap to retry." -- never a blank state
- Article behind paywall / fetch blocked: "This article couldn't be retrieved. Open it in your browser to read in full."

**Cost Estimate**
- Claude Haiku input: ~600 tokens per summary, output ~150 tokens
- Approximately €0.0001 per summary (effectively free at personal usage volumes)

**Requirements**
- Requires the same Anthropic API key used for opinion filtering (single key, shared across AI features)
- On-demand only -- nothing is pre-summarised in the background
- Works on any article regardless of category or folder

--- — Thumb Zone Design

This is a core UX principle for Flash, not an afterthought. The app is designed to be operated entirely with one hand, with a thumb of any reach. This directly influences layout, component placement, and interaction patterns throughout the app.

### 5.1 Thumb Zone Rules

The screen is divided into three zones based on one-handed thumb reach on a standard Android phone (roughly 150mm screen height):

- **Green zone** (bottom ~40% of screen): Primary actions, most-used controls. Everything the user taps frequently lives here.
- **Yellow zone** (middle ~35%): Secondary actions, readable content. Reachable with a stretch.
- **Red zone** (top ~25%): Static, rarely tapped. Display-only or very infrequent actions only.

### 5.2 What Lives Where

**Bottom of screen (always):**
- Bottom navigation bar (Feed, Feeds, Opinions, Settings)
- Folder/category tabs — placed at the BOTTOM of the feed view, not the top, using a `BottomAppBar` or custom bottom tab row. This is a deliberate departure from the typical top-tab pattern and is a hard requirement.
- Floating action button for Add Feed (bottom right)
- Swipe gesture targets (full-width cards, swipeable anywhere)
- "Mark all as read" — triggered via long-press on the bottom tab, not a top menu item (also available as a mini FAB on the feed screen)
- Pull-to-refresh remains a downward swipe (natural thumb gesture)

**Middle of screen:**
- Article cards (the bulk of the scrollable content)
- Feed health warnings

**Top of screen (display only — minimal tap targets):**
- App name / logo
- Last refresh timestamp
- Search icon (tapped infrequently — acceptable in top bar)
- No critical actions, no navigation, no frequently used buttons

### 5.3 Interaction Design Constraints

- Minimum tap target size: **48x48dp** on all interactive elements (Android accessibility guideline — strictly enforced)
- No important actions reachable only via top app bar in normal usage flow
- Context menus and action sheets open as **bottom sheets** (sliding up from the bottom), never as dropdowns from the top
- Dialogs that require confirmation use **bottom sheet dialogs**, not centered modal dialogs
- Settings screen uses a standard scrollable list — no tabs, no top navigation within settings
- Long-press interactions are preferred over top-right overflow menus for common actions

### 5.4 Folder Tabs Implementation Note

Placing tabs at the bottom is a non-standard Flutter pattern. Implementation options in order of preference:
1. Custom `BottomAppBar` with horizontal `ListView` for tabs + `PageView` for content
2. `TabBar` widget repositioned to bottom via `Scaffold` customization
3. Third-party package if needed (e.g. `bottom_navy_bar` or custom implementation)

The standard `TabBar`/`TabBarView` at the top is explicitly not acceptable for this app.

---

## 6. Navigation Structure

All navigation elements live at the bottom of the screen. Nothing requiring a tap is anchored to the top.

```
Bottom Navigation Bar:
├── Feed (home icon) — main article list, tabbed by folder
├── Feeds (list icon) — manage feeds and folders
├── Opinions (shield icon) — opinion-filtered articles
└── Settings (gear icon) — all configuration

Above Bottom Nav — Folder Tabs (bottom of screen, scrollable horizontal):
├── All
├── [User folders...]
└── (+ add folder)

Top Bar (display only — no critical tap targets):
├── App name
└── Refresh timestamp / search icon

Content area (scrollable, between top bar and folder tabs):
└── Article cards
```

---

## 6. Settings

| Setting | Default | Options |
|---|---|---|
| Theme | System | Light, Dark, System |
| Background refresh interval | 30 min | 15m, 30m, 1h, 3h, 6h, Manual |
| Mark as read on scroll | On | On, Off |
| Max articles per feed | 100 | 50, 100, 200, 500, Unlimited |
| Opinion filter — heuristic | On | On, Off |
| Opinion filter — AI (Claude Haiku) | Off | On, Off |
| Anthropic API key | — | Text input (masked, stored in Keystore) |
| Google Drive backup | Off | On, Off |
| Google account | — | Sign in / Sign out |
| Keyword blocklist | — | Manage list |
| Opinion filter heuristic patterns | Default list | Manage list |

---

## 7. Out of Scope for v1.0

- iOS support
- Push notifications
- Home screen widget
- Per-feed custom refresh intervals
- Tablet-optimized layout
- Multi-account Google Drive
- Sync across devices (Drive backup is one-way restore, not live sync)

**Previously listed as out of scope but now implemented:**
- Starred / saved articles (Bookmarks screen — shipped)
- OPML import / export (shipped)
- In-app article reader (Reader screen with article extraction — shipped)
- Article search (Search screen — shipped)
- Text size / font controls (reader font size setting — shipped)
- Localisation / i18n (EN, DE, ES, FR, IT — shipped)

---

## 8. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Cold start time | < 1.5 seconds to feed visible |
| Feed refresh (20 feeds) | < 8 seconds on Wi-Fi |
| Scroll performance | 60fps minimum, 120fps on capable devices |
| Offline readability | All fetched headlines available with no network |
| Database size (typical use) | < 50MB for 20 feeds, 100 articles each |
| Crash-free sessions | > 99.5% |
| Min Android version | Android 8.0 (SDK 26) |
| Target Android version | Android 15 (SDK 35) |

---

## 9. Build & Distribution

- Built with Flutter + Android SDK
- Development environment: Cursor IDE
- Debug builds: installed directly via `flutter run` or ADB sideload
- Release builds: signed APK for personal use; Play Store submission not required for v1.0
- CI: none required for v1.0

---

## 10. Phased Build Plan

### Phase 1 — Core (MVP)
Feed add/remove, folder management, RSS/Atom parsing, local SQLite storage, card list UI, read on scroll, pull-to-refresh, background refresh, mark read/unread, swipe gestures, long-press menu, share, unread badges, favicon, article count auto-cleanup, native Material 3 UI

### Phase 2 — Filtering
Keyword blocklist (full implementation), opinion filter heuristic stage, blocked articles audit view

### Phase 3 — AI + Backup
Claude Haiku opinion filter, AI article summary (on-demand, cached), Google Drive backup/restore, API key management

### Phase 4 — Polish
Animations, edge-to-edge refinement, predictive back, performance optimization, feed health indicators, onboarding flow

---

## 11. Open Questions

- **App name:** TBD — replace all instances of `Flash` once decided
- **Launcher icon:** TBD
- **Opinion filter confidence threshold:** Should borderline articles stay in main feed or go to Opinions? Propose: fail open (stay in main feed if uncertain)
- **Restore behavior:** Should restoring from Drive merge with existing feeds or replace them? Propose: merge, with duplicate detection by URL
