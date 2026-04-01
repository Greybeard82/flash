# Flash — Claude Code Scaffold Prompt
# Phase 1 MVP

Paste the entire contents of this file into Claude Code to begin building Flash.

---

You are building **Flash**, a native Android RSS reader app in Flutter. This is Phase 1 (MVP) only. Read every instruction carefully before writing any code. The details here are deliberate and non-negotiable.

All product decisions are documented in `PRD-Flash.md`. All database decisions are in `schema.md`. Both files are in this project root -- read them before starting.

---

## What you are building in Phase 1

A working Android APK that does the following:

1. Launches to an empty state with a prompt to add the first feed
2. Lets the user search for feeds by name (Feedly API) or paste a URL directly
3. Lets the user create folders/categories and assign feeds to them
4. Fetches and parses RSS 2.0 and Atom 1.0 feeds
5. Displays articles as cards (title, source, favicon, timestamp, thumbnail)
6. Marks articles as read as they scroll past the midpoint of the screen
7. Supports swipe left (mark read) and swipe right (mark unread) on cards
8. Supports pull-to-refresh (swipe down) and background auto-refresh
9. Shows unread count badges per feed and per folder tab
10. Opens articles in the external browser on tap
11. Shows a radial context menu on long-press with Share and a placeholder AI Summary button (disabled in Phase 1 -- enabled in Phase 3)
12. Auto-cleans up old read articles per feed based on a configurable limit
13. Persists everything locally in SQLite -- no account, no sync, no network required after fetch
14. Supports dark and light mode following the system setting
15. Fetches and caches favicons per feed

Do NOT build in Phase 1:
- Keyword blocking (Phase 2)
- Opinion filter (Phase 2 + 3)
- AI summary (Phase 3)
- Google Drive backup (Phase 3)
- Anthropic or Feedly API key management UI (Phase 3)

---

## HARD REQUIREMENTS -- Read these first

These are the three things most likely to go wrong if you use default Flutter patterns. Do not skip them.

### Hard Requirement 1 -- Folder tabs at the BOTTOM

This is the single most important layout decision in the app. The folder/category tabs MUST be at the bottom of the screen, not the top.

Do NOT use Flutter's default `TabBar` + `TabBarView` at the top of the screen. That pattern is explicitly rejected.

Correct implementation:
- Use a `PageView` for the tab content (swipeable between folders)
- Build a custom horizontal scrollable tab row anchored to the bottom of the screen, sitting directly above the `BottomNavigationBar`
- The tab row shows folder names with unread count badges
- Active tab has an accent-colored indicator above it (not below -- since it's at the bottom)
- Tab row is scrollable horizontally when there are many folders
- "All" tab is always first and cannot be removed

The layout stack from top to bottom on the Feed screen:
```
StatusBar
TopAppBar (app name + search icon -- display only, no critical actions)
PageView (article cards -- takes all remaining space)
Folder Tab Row (scrollable, bottom-anchored)
BottomNavigationBar
```

### Hard Requirement 2 -- Radial context menu on long-press

Do NOT use a `BottomSheet` or `PopupMenuButton` for the long-press action. Flash uses a circular radial context menu, identical in concept to Palabre's original implementation.

Implementation:
- Long-press a card triggers an `OverlayEntry` that covers the screen with a dim background
- A circular radial menu animates in (scale + fade, 150ms) centred on the pressed card
- The radial has exactly 3 elements:
  - Top-left button: **Share** (active in Phase 1)
  - Top-right button: **✦ Summary** (visible but disabled/greyed out in Phase 1)
  - Centre: **X** dismiss button
- Tapping outside the radial dismisses it
- Each button is a `Material` circle with an icon + label beneath it
- The radial uses `AnimatedScale` + `AnimatedOpacity` for its entrance animation
- Background cards are dimmed to 60% opacity while radial is open

### Hard Requirement 3 -- Dual accent color ThemeData

Flash uses different accent colors for dark and light mode. Do NOT use a single color for both.

```dart
// Dark mode accent
const darkAccent = Color(0xFFFFD60A);      // Electric yellow
const darkAccentPressed = Color(0xFFFFF176); // Light yellow

// Light mode accent  
const lightAccent = Color(0xFFB8960A);     // Deep amber gold
const lightAccentPressed = Color(0xFFCC5500); // Burnt sienna

// Dark mode background
const darkBg = Color(0xFF0D1B2A);
const darkSurface = Color(0xFF162338);

// Light mode background
const lightBg = Color(0xFFFFFFFF);
const lightSurface = Color(0xFFF4F4F8);
```

Wire these into `ThemeData.light()` and `ThemeData.dark()` via `ColorScheme.fromSeed()` or manual `ColorScheme` construction. The `dynamic_color` package is installed -- use it to wrap the MaterialApp so Android 12+ dynamic color is supported, with the above as fallback.

---

## Project structure

Scaffold the following folder structure inside `lib/`:

```
lib/
  main.dart
  app.dart                  # MaterialApp, ThemeData, routing
  
  db/
    database.dart           # SQLite init, migrations, singleton
    schema.dart             # Table name constants + CREATE TABLE strings
  
  models/
    folder.dart
    feed.dart
    article.dart
    settings.dart
  
  repositories/
    folder_repository.dart
    feed_repository.dart
    article_repository.dart
    settings_repository.dart
  
  services/
    rss_service.dart        # Fetch + parse RSS/Atom feeds
    favicon_service.dart    # Fetch + cache favicons
    thumbnail_service.dart  # Resolve + cache article thumbnails
    refresh_service.dart    # Background workmanager job
    feedly_service.dart     # Feedly feed search API
    share_service.dart      # Native share sheet
  
  screens/
    feed_screen.dart        # Main article list (home)
    feeds_screen.dart       # Manage feeds + folders
    opinions_screen.dart    # Placeholder for Phase 2
    settings_screen.dart    # App settings
  
  widgets/
    article_card.dart       # Single article card
    radial_menu.dart        # Long-press radial context menu
    folder_tab_bar.dart     # Custom bottom folder tab row
    feed_card.dart          # Feed item in feeds management screen
    empty_state.dart        # First launch empty state
    unread_badge.dart       # Unread count badge
    shimmer_card.dart       # Loading skeleton for article cards
  
  theme/
    app_theme.dart          # ThemeData light + dark, color constants
  
  utils/
    date_utils.dart         # Relative timestamp formatting
    html_utils.dart         # Strip HTML tags from descriptions
```

---

## Database

Implement the schema exactly as defined in `schema.md`. Key points:

- Initialise SQLite in `database.dart` as a singleton using `sqflite`
- Run all `CREATE TABLE` statements in `onCreate`
- Seed default `settings` values in `onCreate`
- Use `onUpgrade` for future migrations -- write it now even if empty
- Store timestamps as Unix milliseconds (INTEGER)
- Use `CASCADE DELETE` on all foreign keys as specified in the schema

---

## Feed parsing

In `rss_service.dart`:
- Fetch feed URL via `http` package
- Try parsing as RSS 2.0 first via `dart_rss`, fall back to Atom 1.0
- Extract per article: `guid`, `title`, `url`, `description`, `published_at`, `thumbnail_url`
- For `thumbnail_url`: check `media:content`, `media:thumbnail`, then `enclosure` tags
- If no thumbnail in feed metadata, attempt to extract `og:image` from the article URL HTML head (use `html` package, fetch lazily on scroll not at parse time)
- Insert new articles into SQLite, skip duplicates by `feed_id + guid`
- Run auto-cleanup after every fetch (query is in `schema.md`)
- Update `feeds.last_fetched_at`, `feeds.last_fetch_error`, `feeds.consecutive_failures` after every attempt

---

## Background refresh

In `refresh_service.dart`:
- Register a `workmanager` periodic task on app start
- Task name: `flash_feed_refresh`
- Frequency: read from `settings.refresh_interval_minutes`
- On execution: fetch all feeds, parse, insert new articles, run cleanup
- Respect Android battery optimisation -- do not use `setExact`

---

## Feedly feed search

In `feedly_service.dart`:
- Endpoint: `https://cloud.feedly.com/v3/search/feeds?query={query}&count=10`
- No auth required for basic search
- Parse response: extract `feedId` (strip `feed/` prefix for the RSS URL), `title`, `website`, `subscribers`, `description`
- Show results as a list of cards with favicon, title, subscriber count
- If the user types a full URL instead of a search term, bypass Feedly and go straight to `rss_service.dart` URL detection
- Handle network errors gracefully with a retry option

---

## Read on scroll

In `article_card.dart` / `feed_screen.dart`:
- Use a `ListView.builder` with a `ScrollController`
- Track visible items using item positions
- When an unread article's card scrolls past the vertical midpoint of the screen, mark it as read in SQLite
- Batch DB writes -- don't write on every scroll frame. Use a 500ms debounce
- This behaviour can be toggled off via `settings.mark_read_on_scroll`

---

## Thumbnail loading

- `cached_network_image` handles async loading + disk caching
- Show a `shimmer` placeholder while loading
- On error: show a grey placeholder with the source initial (first letter of feed title)
- Thumbnail dimensions: 72x72dp, `BoxFit.cover`, `BorderRadius.circular(8)`

---

## Theme + colors

In `app_theme.dart`:
- Define `flashLightTheme` and `flashDarkTheme` using the exact hex values in Hard Requirement 3
- Wrap `MaterialApp` with `DynamicColorBuilder` from the `dynamic_color` package
- If dynamic color is available (Android 12+), use it
- If not, fall back to Flash's Electric Midnight palette
- Use Material 3: `useMaterial3: true`
- `BottomNavigationBar` background: `darkSurface` in dark mode, `lightSurface` in light mode

---

## Navigation

- Use `BottomNavigationBar` with 4 items: Feed, Feeds, Opinions, Settings
- Feed screen is the default (index 0)
- Opinions screen is a placeholder in Phase 1 (just shows "Coming in Phase 2")
- Use `IndexedStack` to preserve state across tab switches -- do not rebuild screens on tab change

---

## Empty state (first launch)

In `empty_state.dart`:
- Show on Feed screen when there are zero feeds in the database
- Content: Flash logo/icon, headline "Nothing here yet.", subtext "Add your first feed to get started.", large primary button "Add a feed"
- Button navigates to the feed search screen
- Once the first feed is added, the empty state never shows again

---

## Settings screen

Implement the full settings screen in Phase 1 with these controls:
- Theme: System / Light / Dark (segmented button)
- Background refresh interval: dropdown (15m, 30m, 1h, 3h, 6h, Manual)
- Mark as read on scroll: toggle switch
- Max articles per feed: dropdown (50, 100, 200, 500, Unlimited)
- Section headers: "Reading", "Refresh", "Storage"
- AI Features section: show as locked/greyed out with "Available in a future update" label
- Google Drive section: show as locked/greyed out with "Available in a future update" label

---

## One-handed usability rules

These apply to every screen, not just the feed:
- Minimum tap target: 48x48dp on all interactive elements
- All action sheets, pickers, and confirmation dialogs open as bottom sheets -- never centred modals
- No critical actions in the top app bar
- Snackbars anchor to the bottom, above the navigation bar
- FAB (Add Feed button) sits bottom-right on the Feeds screen

---

## What to build first (suggested order)

1. `app_theme.dart` -- get colors and ThemeData right before anything renders
2. `database.dart` + `schema.dart` -- foundation everything else depends on
3. Models + repositories -- typed data layer
4. `main.dart` + `app.dart` + bottom navigation shell
5. Empty state on Feed screen
6. Feed search + add flow (Feedly search + URL fallback + category assignment)
7. RSS parsing + article storage
8. Article card UI + feed screen list
9. Folder tab bar (bottom-anchored)
10. Read on scroll + swipe gestures
11. Radial context menu
12. Background refresh
13. Settings screen
14. Favicon + thumbnail loading
15. Unread badges

---

## Definition of done for Phase 1

Phase 1 is complete when:
- [ ] App builds with `flutter build apk --release` without errors
- [ ] APK installs and runs on a physical Android device
- [ ] User can search for a feed by name and add it to a folder
- [ ] User can create, rename and delete folders
- [ ] Articles load and display with titles, sources, timestamps and thumbnails
- [ ] Folder tabs are at the BOTTOM of the screen
- [ ] Swiping left marks an article as read, swiping right marks unread
- [ ] Pull to refresh works
- [ ] Background refresh runs on schedule
- [ ] Long-press shows the radial menu with Share (working) and Summary (disabled)
- [ ] Share opens the Android native share sheet
- [ ] Tapping an article opens it in the external browser
- [ ] Dark and light mode both look correct with the Electric Midnight palette
- [ ] Settings screen saves and persists all Phase 1 settings
- [ ] Empty state shows on first launch and disappears after first feed is added
- [ ] App feels native -- Material 3, proper animations, haptic feedback on gestures

---

## Reference files in this project root

- `PRD-Flash.md` -- full product spec, all decisions
- `schema.md` -- complete SQLite schema with indexes, seeds, and cleanup query
- `pubspec.yaml` -- all dependencies already resolved

Start with `app_theme.dart`. Ask me before making any product decisions not covered in the PRD.
