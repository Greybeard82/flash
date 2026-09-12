# Flash: Product Requirements Document

**Version:** 3.0
**Describes:** app version 0.1.0+6 (build 6)
**Last updated:** 11 September 2026
**Owner:** David, DVM Software

**This is the only PRD.** It replaces every earlier PRD (all v1.x and v2.x copies, in the repo, in Claude projects and in local folders) and the retired `schema.md`. It describes what the app does today, what it deliberately does not do, and what is decided but not yet built.

**Rule:** any change in behaviour updates this file in the same commit. If this file and the code disagree, one of them is a bug. There is no version history inside this document; git history is the history.

---

## 1. Product

Flash is an Android RSS and Atom reader, the spiritual successor to the discontinued Palabre. It is account-free and local-first: feeds, articles, read state and settings live in an on-device SQLite database. It removes noise with keyword blocking, surfaces what matters with keyword alerts, and summarises articles with AI, on-device where the phone supports it.

| | |
|---|---|
| Public name | Flash RSS Reader |
| Package | `io.getflash.app` |
| Publisher | DVM Software (sole trader, Barcelona) |
| Website | https://flashrssapp.github.io (home, privacy, support, terms) |
| Contact | flashrssapp@gmail.com |
| Source | GitHub `Greybeard82/flash` |

---

## 2. Principles

1. **Native Android feel.** Material 3 components, predictive back, edge-to-edge layout, haptics on long-press and confirmations.
2. **Readable instantly.** The cached list is shown before any network work starts.
3. **Local-first and private.** No account, no sign-in, no analytics. The network is used only for feeds, favicons, article pages, Feedly search, and cloud summaries on devices without Gemini Nano.
4. **The article list never moves under the reader.** Rows are removed only while a list is being rebuilt, and every programmatic scroll closes the mark-read gate first (§6.5).
5. **Reversible where it matters.** Hiding (blocklist) is reversible; deletion is reserved for articles the user has finished with.

---

## 3. Platform

- **Android only.** No iOS project exists in the repo.
- **SDK levels:** minimum SDK 24 (Android 7.0), target SDK 36, both inherited from the Flutter Gradle plugin.
- **Form factors:**
  - **Phones** (smallest width under 600dp): locked to portrait.
  - **Tablets and unfolded foldables** (smallest width 600dp and up): locked to landscape. The manifest opts out of Android 16's large-screen orientation override (`PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`), so the lock holds on Android 16. That opt-out stops working once the app targets API 37 (§12).
  - **Android TV:** supported; leanback declared optional, touchscreen not required.
- **Languages:** English, German, Spanish, French, Italian. The app follows the device locale with English as fallback. There is no in-app language picker.
- **Distribution:** Google Play, closed testing track, release-signed Android App Bundle. Signing credentials live in `android/key.properties`, which is not committed.

---

## 4. Architecture

### 4.1 Stack

| Area | Technology |
|---|---|
| App | Flutter / Dart |
| Database | SQLite via `sqflite`, schema **v18** (`PRAGMA user_version` is the only version record) |
| Feeds | `http`, `dart_rss` (RSS 2.0, Atom 1.0), `xml` (OPML), `html` (article extraction) |
| Background work | `workmanager` |
| Notifications | `flutter_local_notifications` |
| AI | Gemini Nano through ML Kit GenAI Prompt API (native plugin `GeminiNanoPlugin.kt`); cloud fallback through Firebase AI Logic (`firebase_ai`), protected by Firebase App Check (`firebase_app_check`, Play Integrity) |
| Reading | `flutter_inappwebview` |
| Images | `cached_network_image`, `flutter_svg`, `shimmer` |
| System | `url_launcher`, `share_plus`, `file_picker`, `app_badge_plus`, `home_widget`, `path_provider`, `intl` |

Native Kotlin: `MainActivity.kt` (orientation lock, TV detection, window background colour channel), `GeminiNanoPlugin.kt`, `UnreadWidgetProvider.kt`.

### 4.2 Startup order

Firebase initialise → App Check activate → form factor detection → open database (runs migrations) → load ad/tracker blocklist → initialise notifications and request permission (Android 13+) → handle a notification that cold-launched the app → register background refresh → first frame.

### 4.3 Cross-screen signals

The four main screens are kept alive in an `IndexedStack`, so they learn about changes through notifiers rather than rebuilds:

| Notifier | Purpose |
|---|---|
| `FeedsChangedNotifier` | Feed or category structure changed. Pinged from repository writes. Records a pending change that the Flash tab consumes on its next visibility transition (a new feed means a fetch), and broadcasts (debounced 300ms) so an on-screen Categories list reloads itself. |
| `ReadStateNotifier`, `SavedStateNotifier`, `BlockedStateNotifier` | Read, bookmark and block changes made outside the feed screen. |
| `AlertsChangedNotifier` | Alert matches added, read or removed. |
| `SettingsNotifier` | A setting changed elsewhere. |

---

## 5. Navigation and layout

### 5.1 Phone (width under 600dp)

- **Bottom navigation:** Flash, Categories, Bookmarks, Alerts. Alerts carries a badge with the total number of alert entries (read and unread).
- **Settings** is not a tab. It opens from Quick Settings → **More settings**, and Quick Settings is available from the app bar of all four screens.
- **Flash app bar:** title (or the Newspaper masthead), a small spinning refresh icon while a background fetch runs, the **Filter** button and the **Quick Settings** button. Below the title, **category pills**: All, then one per category, each with an unread badge. Swiping horizontally pages between categories.
- **Flash floating buttons** (bottom right, fading while the list scrolls): Refresh, Search, Mark all read. Shown only when at least one feed exists.

### 5.2 Rail tier (600 to 839dp wide, or Android TV)

A `NavigationRail` with the same four destinations, and the current section's actions (the phone's floating buttons) listed underneath them. Content fills the rest. Because tablets are landscape-locked, a tablet normally reaches this tier only in split-screen or on TV.

### 5.3 Three-column (840dp and wider, not TV)

- **Columns:** sections bar (72dp) → article list (340 to 420dp) → reading pane (420 to 880dp).
- **Divider:** the one between list and reading pane can be dragged; double-tapping it resets the split.
- **Wide screens:** content columns are centred while the sections bar stays flush to the screen edge.
- **Reading:** tapping an article shows it in the reading pane; a placeholder is shown until one is picked.

### 5.4 Swap sides (both wide tiers)

- **What it does:** a **Swap sides** button, pinned to the bottom of the bar, mirrors the column order for right-handed use. Three-column becomes reading pane / list / bar; the rail tier becomes content / rail.
- **Pure mirror:** widths, top-aligned bar entries and every gesture stay the same.
- **Animation:** columns slide over 220ms, or jump instantly when system animations are off.
- **No remount:** swapping never rebuilds the screens (feed scroll position and an open article survive). While swapped, dragging the divider right narrows the list.
- **Persistence:** stored under `layout_swapped`.
- **Where it doesn't apply:** phones have no bar; TV never shows the button.

### 5.5 Android TV

Extended rail with labels, text scaled 1.4×, no three-column layout, no Swap sides. Article cards have no swipe and no long-press menu; D-pad select opens the article.

---

## 6. Features

### 6.1 Onboarding

Shown on first launch until completed.

- **Content:** app icon, name, tagline ("Fast, local-first RSS with AI-powered filtering."), then "Start with a few feeds", the helper line "Popular publishers, sorted into categories. Remove any of them later.", and the starter pack picker with every category ticked.
- **Scrolling:** the middle scrolls; both buttons are pinned to the bottom.
- **Start reading** seeds the ticked categories, completes onboarding and lands on the Flash tab, whose first fetch fills the list. Disabled when nothing is ticked.
- **Skip, I'll add my own** completes onboarding with no feeds and opens Categories.
- **While seeding:** both buttons are disabled; if seeding fails they re-enable.

### 6.2 Starter pack

- **What it is:** an optional, fixed set of feeds. Offered in exactly three places: onboarding, the Flash empty state and the Categories empty state.
- **Category names** (World News, Tech, Fitness / Health, Travelling, Sports) are localised when seeded. After that they are ordinary user data: renameable, never re-translated.

| Category | Feeds |
|---|---|
| World News | BBC News (World), The Guardian (World), The New York Times (World) |
| Tech | Ars Technica, The Verge, WIRED |
| Fitness / Health | Muscle & Fitness |
| Travelling | The Points Guy |
| Sports | BBC Sport, ESPN (Top News), Sky Sports |

- **Reuse before create:** a category whose trimmed name matches case-insensitively is reused. This rule lives in `folder_matching.dart` and is shared with OPML import.
- **Skip, never move:** an already-subscribed URL is skipped and left where it is, so adding the pack twice changes nothing.
- **Writes:** database writes only. Favicons are fetched in the background afterwards.
- **Live gate:** `test/starter_pack_live_test.dart` (run with `--dart-define=LIVE_NETWORK=true`) sends every pack feed through the real fetch pipeline. Each feed must yield at least one article inside the 7-day fetch window, and each category at least five. Single-feed categories are listed in `kSingleFeedStarterCategories`.

### 6.3 Categories and feeds

- **Categories screen:** categories are collapsed by default, and expansion lasts only for the session. Each feed row shows favicon, name, domain, a warning icon when the feed is unhealthy, its unread count (capped at "999+"), and a menu with Edit and Remove.
- **Add a feed** (extended "Add feed" button, or the section action on wide layouts), in a bottom sheet:
  - **Category:** pick from chips, or create one inline. A category is required.
  - **Paste a URL,** or search Feedly by keyword; results show follower counts.
  - **Validation:** the URL is fetched and parsed. Duplicates are refused with "already added".
  - **First fetch:** runs immediately, with the blocklist and alerts applied.
- **Edit feed:** name and category.
- **Remove feed:** confirmed; its cached articles are deleted.
- **Rename or delete a category:** deleting is confirmed and removes its feeds and articles.
- **Reorder:**
  - **Feeds:** long-press to drag within or between categories. A collapsed category's header still accepts drops, the list auto-scrolls near the edges, and there's haptic feedback on pick-up.
  - **Categories:** reordered by the handle in their header.
- **Feed health:**
  - **A failed fetch** records the error and shows the warning icon.
  - **Seven consecutive failures** mark the feed dead. Dead feeds are still fetched, and one success restores them.
- **Favicons:** fetched from Google's favicon service (64px) and cached on the device; a letter monogram is used when none is available.
- **Empty state:** "No feeds yet" with **Add starter pack**.

### 6.4 The Flash feed

- **Card:**
  - **Top line:** favicon, publisher (feed name), relative time.
  - **Title:** always weight 600. Read state never changes the weight, because a weight change would reflow the card.
  - **Thumbnail** on the right: taken from `media:content`, `media:thumbnail` or the enclosure, and cached.
  - **Summary button** beside the thumbnail (§6.8).
- **Read cards dim:** lower text opacity plus a greyscale thumbnail and favicon, animated over about 180ms, with no change in layout.
- **Day dividers:** Today, Yesterday, the weekday name within the last week, then day and month. Grouping is by calendar day; a future publish date counts as today.
- **Order:** newest first by default, or oldest first (Filter bubble).
- **Tab badges:**
  - **Counted** from the database: unread, unblocked articles published within the last 7 days.
  - **Bottom of a tab:** reaching it zeroes that tab's badge for display only, until new articles arrive or the app cold-starts.
- **Tap:** marks the article read (it dims in place and is not removed) and opens it (§6.7).
- **Long-press:** radial menu with **Bookmark / Saved** and **Share** (Android share sheet).
- **No swipe gestures** in the main feed: horizontal movement pages between categories.
- **Refresh** (pull-to-refresh or the Refresh button): fetches the current tab's feeds (All means every feed). It never runs cleanup.
- **Scroll position:** remembered per tab as an article anchor, not a pixel offset, and restored after returning from the system browser.
- **Empty state:** "Nothing here yet." with **Add a feed** and **Add starter pack**.

### 6.5 Read state and article lifecycle

An article moves **unread → read → retired**. Retiring deletes the row and writes a tombstone. **Saved (bookmarked) articles are never retired or cleaned up.**

**Marking read**
- **On scroll** (Quick Settings, default on): an article is marked read when its vertical midpoint passes above the top of the viewport. The database write is immediate; the dim is debounced 150ms.
- **Scroll gates:** a write happens only if a person moved the list (the gate closes before every programmatic scroll and reopens on a real user scroll), row heights are measured rather than guessed, and at least 600ms have passed since the app resumed.
- **Where it applies:** only the Flash feed. Bookmarks, Search and Alerts never mark read on scroll.
- **Other ways:** tapping an article, Mark all read, and the Bookmarks swipe.

**Show read** (Filter bubble, default on)
- **On:** read articles stay visible, dimmed, until the next retirement.
- **Off:** read articles are left out of the list on its next reload.
- **Either way:** a read bookmark never appears in the Flash feed; it lives in Bookmarks.

**Retirement**
- **What it does:** deletes every read, unsaved article (optionally scoped to one category) and records `(feed_id, guid)` in `deleted_articles`, so a later fetch cannot re-insert it.
- **When it runs:** cold start, resume, a refresh, a tab switch, and Mark all read. Never during a scroll.
- **Undo:** there is no undo and no recovery screen.
- **Tombstone lifetime:** 8 days (fetch window plus one).

**Cleanup** (cold start, background refresh, Mark all read)
- **Read, unsaved articles** older than the 7-day cleanup window are deleted.
- **Unread, unsaved articles** older than 15 days are deleted.
- **Tombstones** past their lifetime are pruned.

**Mark all read**
- **Confirmation:** a dialog with "Don't show again"; re-enable it with **Confirm mark all as read** in Quick Settings.
- **All tab:** marks everything read (including alert entries), retires, cleans up, refreshes all feeds and reloads.
- **Category tab:** does the same within that category, refreshes only that category's feeds and shows a confirmation banner.
- **Reversible?** No.

**After a refresh**
- **Nothing newly visible:** the list does not move.
- **New articles:** the list reloads and jumps to the top, as a programmatic scroll (so nothing is marked read by the jump).

### 6.6 Refreshing and fetching

- **Cold start:** retire read → cleanup → show the cached list → fetch all feeds in the background behind the app-bar spinner. A shimmer skeleton covers only the initial database read.
- **Resume:**
  - **Every return** retires read articles and reloads from the database.
  - **A network fetch** also runs if the app was away at least 30 seconds and the last fetch is at least 5 minutes old. No cleanup on this path.
- **Manual:** pull-to-refresh or the Refresh button.
- **Background:** a WorkManager periodic task.
  - **Intervals:** eight options — 30 minutes, then 1, 2, 3, 4, 5 and 6 hours (default 3 hours), then **Manual only**, which cancels the task.
  - **Network:** requires any connection, or an unmetered one when **Refresh on Wi-Fi only** is on.
  - **What it does:** runs cleanup, fetches every feed and posts alert notifications. Android may defer it under Doze.
- **Fetch rules** (per feed, before anything is written):
  - **Dates:** items are sorted by publish date. Items with no date, or older than 7 days, are discarded.
  - **Cap:** at most 100 items are accepted. A per-feed override column exists but has no UI.
  - **Identity:** the item's guid, else its link. Items with neither are skipped.
  - **Deduplication:** inserts ignore `(feed_id, guid)` duplicates and tombstoned guids, so a re-fetch never resets read state or resurrects a retired article.
  - **Blocklist and alerts:** the blocklist is applied before insert; alert matching runs after insert, on genuinely new articles only.
- **HTTP:** plain GET with a 20-second timeout (15 seconds when validating a new feed).

### 6.7 Opening articles: built-in viewer and Clean mode

- **Open articles in the built-in viewer** (Settings → Reading, default on):
  - **On:** phones open a full-screen reading pane; three-column shows the article in the right-hand pane.
  - **Off:** articles open in the system browser.
- **Reading pane top bar:** close, title, a `{publisher} · {date}` line (localised absolute date), and open in browser.
- **Web view protections:**
  - **Ads and trackers:** requests to about 140 known domains (`assets/blocklists/ad_tracker_domains.json`) are blocked.
  - **Cookie banners** from common consent platforms are hidden, never accepted or rejected.
  - **Web notification permission requests** are answered "denied".
  - **Pop-ups and new windows** are blocked.
- **Clean mode** (Settings → Reading, default on):
  - **Extraction:** when an article opens, a separate download extracts its text in the background.
  - **The offer:** if there is enough prose, a floating toggle appears. Switching between the publisher's page and the clean view never reloads the page.
  - **Default view:** always the publisher's page.
  - **No clean version:** a quiet banner says so, once per URL.
  - **Caching:** results are kept for the session (50 entries).
  - **Cost:** one extra download per opened article; turning the setting off removes it.

### 6.8 AI summaries

- **Trigger:** the summary button on any article card.
- **Backend:**
  - **Gemini Nano first**, on-device through the ML Kit GenAI Prompt API: free, private, works offline.
  - **Cloud fallback** only when Nano is unavailable: Firebase AI Logic, model `gemini-3.5-flash-lite`. The API key stays server-side and App Check (Play Integrity) must attest a genuine build.
  - **Neither available:** an "unavailable" message.
- **Input:** the article page is extracted (capped at 2,500 characters, with a short time budget). If that fails, the RSS description is used and the sheet notes "Based on the article preview only."
- **Length** (Quick Settings):

| Length | Max words | Max bullets |
|---|---|---|
| Short | 130 | 4 |
| Standard (default) | 320 | 6 |
| Detailed | 450 | 9 |

- **Prompt and clean-up:** both backends use the same prompt builder. `SummaryFormatter` strips preambles and markdown and enforces the limits.
- **Sheet:**
  - **Size:** up to 90% of the screen.
  - **Status line:** "Reading the article…" then "Writing the summary…".
  - **Reveal:** the text appears only when complete, and is selectable.
  - **Header:** the article title plus the `{publisher} · {date}` line.
  - **Footer:** a disclaimer (a cloud variant when the cloud was used) and **Copy**.
  - **Failures:** a plain-language reason, with expandable details.
- **Cache:** in memory, per URL and length, 50 entries, for the session.

### 6.9 Search

- **Opened from:** the Search button or section action.
- **Scope:** article titles and descriptions, excluding blocked articles, capped at 100 results.
- **Typing:** debounced 350ms, and results from a superseded query are discarded.
- **Results:** use the standard card, and open articles the same way as the feed.

### 6.10 Bookmarks

- **Bookmark or unbookmark:** from the long-press menu on any card whose article still exists.
- **The tab:** lists every saved article, newest first, read or unread.
- **Swipe:** right-to-left marks read, left-to-right marks unread; the card springs back.
- **Mark all read:** a section action, shown only while unread bookmarks exist.
- **Protection:** saved articles are exempt from retirement and cleanup.
- **Backup:** bookmarks are not included in backups.

### 6.11 Keyword blocklist

- **Managed from:** Filter bubble → **Keyword blocklist**. Each entry is a keyword or phrase, with an optional **whole word only** setting.
- **Matching:** case-insensitive against title plus description; substring by default, word boundaries when whole-word is on.
- **When it's applied:** at fetch time, and retroactively to every existing article when a keyword is added.
- **Effect:** blocked articles are **hidden, not deleted and not marked read**. They disappear from the feed, search and unread counts, and never trigger alerts.
- **The panel:** each keyword is a collapsible group showing a live count and the articles it hid. Long-press a group to edit; removing or editing a keyword unblocks what it hid.
- **Backup:** blocklist keywords are included.

### 6.12 Keyword alerts and the Alerts tab

- **Managing keywords:** from Filter bubble → **Keyword alerts**, or the Alerts tab's add action. Each keyword has an optional whole-word setting and a live entry count; long-press to edit; deletion is confirmed.
- **Matching:** newly inserted, unblocked articles only, against title plus description.
- **Storage:** every match is saved as a snapshot row in `alert_matches` (a copy of the article and feed details), so entries survive retirement, cleanup and even deleting the feed.
- **The Alerts tab:**
  - **Layout:** entries grouped by keyword in collapsible sections; an article matching several keywords shows all of them as badges.
  - **Reading:** an entry dims and stays; there is no mark-read-on-scroll and no swipe.
  - **Long-press menu:** Bookmark (says so when the article is already gone), Share, Remove. Remove deletes the entry and cannot be undone.
  - **Section actions:** add keyword, Mark all read.
  - **Pull to refresh:** re-reads the database; it does not fetch.
- **Notifications:**
  - **Grouping:** each refresh posts one notification per matched keyword set, bundled under one group, with a stable ID per keyword set.
  - **Tap:** opens the Alerts tab, including from a cold start.
  - **Scope:** posted from foreground and background refreshes alike.

### 6.13 Launcher badge, home screen widget, notifications

- **Icon badge** (Quick Settings, default on):
  - **Mechanism:** Flash posts a silent "N unread articles" notification, because the launcher draws its badge from it. One UI shows a number capped at 99; the Pixel launcher shows a dot. The `app_badge_plus` broadcast is also sent.
  - **Cancelled** when the count is zero or the setting is off.
- **Home screen widget:** 1×1, shows the unread count, opens the app on tap, and updates with the badge.
- **Permissions and channels:**
  - **Permission:** notification permission is requested at launch on Android 13+.
  - **Kinds:** Flash posts exactly two kinds of notification: keyword alerts and the unread badge.

### 6.14 Backup and restore

- **Settings → Local backup → Export** writes `flash_backup_YYYYMMDD_HHMM.json` through the system file picker.
- **The file contains:** a format version (1) and timestamp; categories (name, position); feeds (title, URL, category name, position, site URL, description); blocklist keywords (keyword, whole-word).
- **The file does not contain:** articles, read state, bookmarks, alert keywords, alert entries or settings.
- **Import:**
  - **Validation:** you pick a `.json` file, and it is validated completely before anything is deleted.
  - **Confirmation:** "Restore from backup?"
  - **Effect:** all categories, feeds and blocklist keywords are replaced; articles return with the next fetch.
- **Android Auto Backup** also backs up the app's data to the user's Google account (`backup_rules.xml`).

### 6.15 OPML import and export

**Settings → OPML.** Import **merges and never replaces**, so it has no confirmation dialog.

**Import**
- **File picking:** any file type can be picked, because Android's `.opml` MIME mapping is unreliable; the content is validated instead.
- **What counts as a feed:** any `<outline>` with an `http` or `https` `xmlUrl`. Everything else is skipped.
- **Folders, one level:** a feed goes into the category named after its top-level parent outline, however deeply it is nested. Feeds with no parent go into "Imported".
- **Names:**
  - **Feed title:** `title`, else `text`, else the URL host.
  - **Category name:** `text`, else `title`.
  - **Site URL:** taken from `htmlUrl`.
- **Merging:**
  - **Categories:** reused by trimmed, case-insensitive name (shared rule with the starter pack).
  - **Feeds:** already-subscribed URLs are skipped and never moved or renamed; duplicates within the file keep the first occurrence.
  - **Order:** new categories and feeds are appended.
- **Writes:** database writes only; favicons are fetched afterwards. The Flash tab fetches on return, and an on-screen Categories list reloads immediately.
- **Result banner:** "Feeds added: N · Folders created: N · Skipped: N". An unreadable or invalid file shows an error and changes nothing.

**Export**
- **Format:** OPML 2.0, one parent outline per category in Categories order.
- **Feed outlines:** each carries `type="rss"`, `text` and `title` (same value), `xmlUrl`, and `htmlUrl` when known.
- **Saving:** `flash_feeds_YYYYMMDD.opml`, through the system file picker.
- **Limitation:** an empty category does not survive a round trip.

### 6.16 Appearance

- **Theme** (Quick Settings): System, Light or Dark. System follows the OS live, and the native window background follows the app's theme, so there's no white flash.
- **Colour palette** (Quick Settings): Green, Blue, **Orange (default)**, Red, Teal & Orange, generated with `ColorScheme.fromSeed`. There is no wallpaper-based dynamic colour.
- **Newspaper mode** (Quick Settings, default off): newsprint background, PT Serif body text, Playfair Display headlines, and a masthead on the Flash tab. It overrides the theme choice (the selector greys out). Fonts are bundled under the OFL.
- **Motion:** 220ms page transitions with predictive back.

### 6.17 Privacy, compliance and contact

- **Data:** no account; all data stays on the device except the network uses listed in §2.
- **Firebase:** used only for cloud summaries.
- **Google Play News and Magazines policy:**
  - **Fresh content on install:** the starter pack.
  - **Publisher and absolute date:** on the summary sheet and in the reading pane.
  - **Contact reachable in-app:** Settings → About → **Contact & support** opens https://flashrssapp.github.io/support.html, which must match the URL in the Play Console declaration exactly. **Email us** opens a `mailto:` to the contact address.
- **Privacy policy:** https://flashrssapp.github.io/privacy.html, linked from Settings → About.
- **Pinned by tests:** both URLs are fixed by unit tests.

---

## 7. Settings reference

| Setting | Default | Where | Options | Key |
|---|---|---|---|---|
| Theme | System | Quick Settings | System, Light, Dark | `theme` |
| Summary length | Standard | Quick Settings | Short, Standard, Detailed | `summary_length` |
| Colour palette | Orange | Quick Settings | Green, Blue, Orange, Red, Teal & Orange | `color_palette` |
| Newspaper mode | Off | Quick Settings | On, Off | `newspaper_mode` |
| Mark as read on scroll | On | Quick Settings | On, Off | `mark_read_on_scroll` |
| Confirm mark all as read | On | Quick Settings | On, Off (also set by the dialog's "Don't show again") | `mark_all_read_confirm` |
| Icon badge | On | Quick Settings | On, Off | `unread_badge_notification` |
| Article order | Newest first | Filter bubble | Newest first, Oldest first | `article_sort_order` |
| Show read | On | Filter bubble | On, Off | `show_read` |
| Built-in viewer | On | Settings → Reading | On, Off | `use_embedded_webview` |
| Clean mode | On | Settings → Reading | On, Off | `clean_mode_enabled` |
| Background refresh | Every 3 hours | Settings → Refresh | 30 min, 1–6 h, Manual only | `refresh_interval_minutes` |
| Refresh on Wi-Fi only | Off | Settings → Refresh | On, Off | `refresh_wifi_only` |
| Swap sides | Not swapped | Tablet bar button | Normal, Swapped | `layout_swapped` |

The Filter bubble's two settings are staged behind **Apply**. The bubble also links to the keyword blocklist and alerts panels.

**Settings screen sections:** Reading, Refresh, Local backup, OPML, About (Contact & support, Email us, Privacy policy).

**Fixed values with no UI:** max articles per feed (100, `article_limit`), cleanup window (7 days, `cleanup_age_days`), onboarding flag (`onboarding_complete`).

---

## 8. Data model (schema v18)

| Table | Holds |
|---|---|
| `folders` | Categories: name, position |
| `feeds` | Subscriptions: category, title, URL (unique), site URL, favicon path, description, dormant per-feed article limit, fetch health (last fetch, last error, consecutive failures, dead flag), position |
| `articles` | Fetched items: feed, guid (unique per feed), title, URL, description, thumbnail, published and fetched times, read, blocked (+ keyword), saved |
| `deleted_articles` | Tombstones `(feed_id, guid, deleted_at)` for retired articles |
| `keyword_blocklist` | Block keywords with whole-word flag |
| `keyword_alerts` | Alert keywords with whole-word flag |
| `alert_matches` | Permanent alert snapshots: one row per (feed, guid, keyword), with copied article and feed details and its own read flag |
| `alert_notification_ids` | Stable notification ID per keyword set |
| `settings` | Key/value pairs (§7) |

Foreign keys are enforced, with cascading deletes from categories to feeds to articles. Every migration from v1 to v18 must keep working on devices at any older version.

---

## 9. Non-functional targets

| Requirement | Target |
|---|---|
| Cold start to cached list | Under 1 second |
| Refresh of 20 feeds on Wi-Fi | Under 8 seconds |
| Scrolling | 60fps minimum, 120fps on capable devices |
| Offline | All cached articles readable with no network |
| Database size | Under 50 MB for 20 feeds at 100 articles |
| Crash-free sessions | Above 99.5% |

---

## 10. Known limitations

- **Gemini Nano** exists on few devices; everyone else needs a connection for summaries.
- **TV:** no long-press menu, so cards can't be bookmarked or shared there.
- **Divider:** dragging the reading-pane divider scrolls the web page back to its top (a web view reflow).
- **German rail width:** at large text scale, the rail grows to about 190dp in German because of the "Mark all read" label.
- **Single-feed starter categories** (Fitness / Health, Travelling) can look empty after a quiet publishing week.
- **Fixed limits:** max articles per feed and the cleanup window can't be changed by the user.
- **Backup gaps:** alert keywords, bookmarks and settings aren't in the backup file.
- **OPML:** empty categories are lost in a round trip.
- **Clean mode** costs an extra download per opened article.

---

## 11. Not supported

iOS; accounts and sync across devices; in-app language choice; per-feed refresh intervals or limits in the UI; merge-style backup restore; Google Drive backup (removed); in-app purchases (not yet built, §12).

---

## 12. Decided, not built

- **Monetisation.** A free tier with a banner ad while reading and a daily cap on AI summaries; a one-time unlock of about €4 removes both. No subscription. Premium limits lock gracefully rather than blocking the app. Anyone who installs before the paid version keeps everything permanently (promised on the website). Google Play Billing is not integrated yet.
- **Portrait tablets.** Tablets are landscape-locked for now. Targeting API 37 removes the ability to lock orientation on large screens, so portrait tablet layouts must be supported before the app moves to API 37.
- **Phone split view** (being specified). A mode on phones that puts the reading pane on top and the article list below it, reusing the tablet reading pane. Open questions: minimum screen height, default split, Clean mode as default, and its interaction with mark-read-on-scroll.
- **Google TV redesign** (mocked up). D-pad grid, a focused summary view, cloud summaries (no Nano on TV).

---

## 13. Release status (11 September 2026)

- **Build 3** (starter pack, Play compliance fixes): submitted to Play review on the closed testing track after the 11 September policy removal.
- **Build 4:** superseded, never uploaded.
- **Build 5:** superseded by build 6, never uploaded.
- **Build 6** (OPML, Swap sides, tablet landscape lock, cleanup): to upload after build 3 is approved. On that day, merge the website's `opml` branch, which restores the OPML copy on the site.

---

## 14. Repository documents

| File | Role |
|---|---|
| `PRD-Flash.md` | This document: the single source of truth for behaviour |
| `MANUAL_QA.md` | On-device checks that automated tests can't cover; must agree with this PRD |
| `CLAUDE.md` | Rules for coding agents, including the absolute ban on changing settings on physical devices |
| `README.md` | Short orientation pointing to the three files above |
