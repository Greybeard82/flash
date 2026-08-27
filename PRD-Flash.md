# Product Requirements Document
## Flash — Android RSS Reader

**Version:** 2.9
**Status:** Active — reflecting shipped state
**Author:** David
**Last Updated:** 27 August 2026 (pass 07)

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
- **Primary:** Android — minimum SDK 26 (Android 8.0 Oreo), target SDK 36 — inherited from `flutter.targetSdkVersion`, not pinned in `build.gradle.kts`
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
- Schema versioned with migration support. Currently **v13**; `PRAGMA user_version` is the single source of truth (a duplicate `schema_version` settings row existed until v9, drifted permanently to "3", and was deleted)
- `deleted_articles` (v13) is the tombstone table: `(feed_id, guid, deleted_at)` with a unique index on the pair and an index on the age. It is what makes retirement safe — see §4.10. `articles.read_at` existed from v11 to v13 to drive a 48-hour show-read window; both are gone, because nothing un-hides any more

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
- System locale is detected automatically. There is **no in-app language picker** — the app follows the device locale and falls back to English for anything unsupported

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

**Feed changes reach the article list**
- Adding, removing, renaming, re-homing or reordering a feed or category updates the Flash tab the next time it becomes visible
- All four main screens are kept alive in an `IndexedStack`, so the feed screen is never rebuilt on a plain tab switch. Without a signal, adding six feeds and walking back to Flash showed exactly the list you left, until a manual refresh
- `FeedsChangedNotifier` is pinged from the **repository writes**, not from the screens, so OPML import, backup restore and onboarding are covered by the same choke point. It *records* rather than broadcasts: the feed list is by definition off-screen when these writes happen, so the change is queued and consumed on the next visibility transition — six feeds added in a row cost one refresh, not six
- Adding a feed queues a network fetch (a new feed has no articles yet); every other change only re-queries locally

**Reorder / Move Feeds — Long-Press Drag**
- Long-press a feed row on the Categories screen to pick it up, then drag to reorder it within its category **or** drop it into a different one
- Drop targets highlight as the drag hovers; dragging near the top or bottom edge auto-scrolls the list
- A category header is itself a drop target, so a collapsed category can still receive a feed
- Haptic feedback on pick-up, matching the app's other long-press gestures
- Order and category assignment persist immediately; a failed write reports and reloads rather than leaving the list showing an arrangement that was never saved
- Categories themselves are reordered by their own drag handle in the header

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
- Badges update **live from any tab** — reading an article in the All tab (via scroll, swipe, tap, or mark-all-read) immediately decrements that article's folder badge too, without switching tabs or reloading. An unawaited authoritative re-query self-heals any drift within a scroll pause. Badge counts come from `is_read` in the DB, independent of whether Show read is keeping the row on screen.
- With **Show read** on, a read article **stays visible, dimmed in place, in every tab** (see §4.3) — its badge count drops everywhere at once, but the row itself never disappears out from under the reader.
- **Reaching the bottom of a feed zeroes that tab's badge immediately**, even though articles at the bottom are still unread. Reaching the end means the user has seen it. This is display-only: nothing is written, the All badge falls back to the sum over the categories that have *not* been zeroed, and the true count returns as soon as new articles arrive for that scope or the app cold-starts.
- A special **"All"** tab aggregates articles across all folders
- All category tabs behave identically to "All" — same read-visibility rule, scroll, and mark-all-read behaviour apply (category mark-all-read also refreshes that folder's feeds)
- **Categories are collapsed by default.** Entering the Categories screen always shows a tidy list of headers; expanding one is a deliberate act each time. Expansion is per-session state keyed by folder id — it is not persisted. The consequence for drag-and-drop: a collapsed category still *accepts* a dropped feed (its header is its own drop target, appending to the end), but you cannot start a drag *out* of one, and precise positioning within one needs it expanded

---

### 4.3 Article Feed

**Layout**
- Card-based list: title, source favicon, source name, relative timestamp, reading time estimate, and a thumbnail
- Thumbnail priority: (1) `<media:content>` / `<media:thumbnail>`, (2) Open Graph `og:image`, (3) first `<img>` in body, (4) monogram placeholder
- Thumbnails fetched and cached locally — no re-fetching on scroll
- Thumbnail: 72×72dp square, cover crop, 8dp rounded corners, right-aligned
- Articles are grouped under **day dividers** and sorted newest-to-oldest by default; the order is configurable in the Filter bubble
- Unread articles have full visual weight; read articles are dimmed — by colour and opacity only. **The font weight is constant at `w600` and must stay that way.** It used to drop to `w400` when read, and lighter glyphs are narrower: a title sitting near a wrap boundary reflowed from three lines to two the moment mark-read-on-scroll fired, the card lost a line of height, and every card below it slid up under the reader's eyes mid-scroll with no gesture to explain it. Read state is carried by colour, opacity and the greyscale matrix, none of which can change layout

**Day Dividers**
- The list is broken up by day headers: **Today**, **Yesterday**, the weekday name within the last seven days, and a day-and-month label beyond that. All localised, and the weekday/date labels come from `DateFormat` in the active locale
- Grouping is by **calendar day, not elapsed hours** — an article published at 23:50 last night is filed under Yesterday at 14:30 today, even though that is under 24 hours ago
- Headers are emitted whenever the day changes from the previous article, so the same code is correct for both sort orders without being told which is in use: newest-first yields Today, Yesterday, …; oldest-first yields the reverse
- A **future publish date is both grouped and labelled as today**. Doing only one of the two is a real bug that shipped briefly: the label was clamped to "Today" while the grouping key kept the raw calendar day, so a feed publishing an hour into tomorrow produced two headers both reading "Today", stacked
- Header height is a declared constant (`kDayHeaderHeight`) rather than an estimate, because the mark-as-read scroll pass walks the row list summing heights and can measure article cards but not headers. The constant and the rendered `SizedBox` must stay in step or the read cutoff drifts further down the list

**Auto-Refresh on Open**
- Cold open order is: purge stale articles (read, unsaved, older than the configured cleanup window) → **show the cached list immediately** → fetch all feeds in the background. The network is never in the way of reading what's already on disk
- While that background fetch runs, a small animated lightning-bolt glyph appears in the app bar. It does **not** cover the content and the FABs stay available. (Previously a full-screen bolt pulse replaced the whole content area until the fetch finished, so a slow connection meant staring at an animation with a perfectly good cached list sitting unread underneath.)
- The brief moment before the cached list arrives — a local DB read — shows the standard shimmer skeleton, not a takeover
- This ensures the list is always up to date within seconds of opening the app, and readable instantly

**Auto-Refresh on Resume**
- Returning to Flash from the background after being away **≥30 seconds**, with no fetch in the last 5 minutes, triggers a silent network fetch (`ResumeRefreshPolicy`, both thresholds configurable)
- Unlike cold open, this fetch runs with **no cleanup** — deleting read articles mid-session would pull rows out of a list the reader is holding their place in — and shows the same small app-bar bolt as cold start, since the user is already looking at their list
- **The list resets to the top after any network refresh**, resume included. Preserving the offset was actively harmful rather than merely imperfect: with newest-first ordering new articles insert *above* the viewport, so the same offset then pointed at different content and everything above it — including everything just fetched — counted as "already scrolled past" and was marked read within a second of arriving
- The jump itself cannot mark anything read. A `ScrollController` listener cannot tell a `jumpTo` from a finger, so a `MarkReadGate` closes before every programmatic scroll and reopens only on a real `UserScrollNotification` with a non-idle direction — which `jumpTo` never produces, because it goes idle first
- A brief excursion (e.g. popping out to the browser and back) never triggers a fetch; only DB state is reloaded

**What the feed shows — read visibility**

Read is not a state an article rests in. It is a step on the way out.

**One verb: retire.** An article is retired when the user is finished with it.
Retiring deletes the row and writes a tombstone so the next fetch cannot bring
it back. **Show read** no longer decides whether a read article survives — every
read article is eventually retired — it decides only *when*:

- **Show read off** — retired as it scrolls past, two article-cards above the
  top of the viewport. The buffer matters: zero would retire an article the
  instant its last pixel left the screen, and a small overscroll or bounce
  would then feel like the list eating itself.
- **Show read on** — marked read, kept visible and dimmed, retired at the next
  refresh or cold start.

Both end in the same place. **Saved articles are the only exception**: marked
read, never retired, visible under either setting until un-bookmarked. That is
why the visibility query keeps them even with Show read off — hiding a
bookmark from the feed while it still sits in Bookmarks would be a lie about
where the user's data is.

**Recovering from retirement.** Settings → *Recover recently removed
articles* clears the tombstone table, so anything the feeds still carry is
re-inserted by the next fetch. It is the only route back, and it is
deliberately manual and confirmed rather than automatic. It cannot resurrect
an article the feed has stopped offering — nothing outside the seven-day fetch
window comes back — and it touches nothing else: feeds, folders, keywords,
bookmarks and surviving articles are all left alone. It exists because a user
who scrolls faster than they meant to otherwise has no recourse at all.

Retirement is **permanent and has no undo** without that action. It is not the cleanup window
(§4.8), which is age-based and only touches read, unsaved articles; the two
rules never consult each other.

**The invariant this is all built around**

> The article list must never move by a single pixel while the user is looking
> at it. Not one frame, not a flicker, not a settle.

This outranks everything else here. Retirement deletes rows, rows have height,
so every retirement is a candidate for violating it. Two rules make it
tractable, and every retirement call site must fall into one of them:

1. Retirement against a list that is **about to be rebuilt from scratch** is
   free — before a fetch, or inside an action that already resets the list.
2. Retirement that removes rows from a list **currently on screen** may only
   happen when the scroll is **idle**, and must correct the scroll offset by
   exactly the removed height *in the same synchronous turn* as the removal.

Rule 2 is why scroll retirement runs on `ScrollEndNotification` and not during
the gesture. `jumpTo` calls `goIdle()` first, which cancels the active scroll
activity: mid-drag it kills the user's gesture, mid-fling it destroys the
ballistic simulation. At scroll end the position is already idle, so the
correction is free. And because `setState` only marks the element dirty —
layout and paint happen at the end of the frame — a removal and a correction
issued in the same turn produce exactly one frame with both applied. There is
no intermediate state to render.

The frontier is recomputed at idle rather than reused from mid-scroll: if the
user flung down and dragged back up, rows that were eligible are no longer
above the viewport, and removing them would move content they are looking at.
A saved article above the frontier blocks the whole block from being removed,
because the offset arithmetic assumes one contiguous run at the top.

**What does not retire.** Marking read and retiring are separate concerns: the
dim is what the user sees while the card is still on screen; retirement is what
happens after it leaves. So tapping an article, swiping it, the radial menu and
the end-of-feed dwell timer all mark read and stop there. The dwell timer is
the clearest case — the user is parked at the bottom with the whole feed above
them, and retiring there would collapse the list while they watch.

**How a read article looks**
- Reduced opacity on the text at a **constant font weight** (see the Layout note above — a weight change moves the layout and shifts every card below); the thumbnail and favicon are desaturated to greyscale and dimmed
- The change **animates over ~180ms** rather than cutting hard, so a card visibly greys out instead of snapping
- Desaturation uses a `ColorFilter.matrix` interpolated between identity and greyscale, with the image instance reused across every animation frame. This is load-bearing: a `BlendMode.saturation` filter mixes with the backdrop and was the cause of a dark-mode scroll flicker (bright grey blocks flashing on unloaded thumbnails), and swapping the image widget to animate would force a redecode and reintroduce it

**Mark as Read — On Scroll**
- Articles are automatically marked as read as they scroll past the midpoint of the viewport
- DB write is immediate; the visual dim is debounced 150ms so a fast scroll doesn't thrash `setState`
- Can be disabled in Settings

**Mark as Read — End of Feed**
- Reaching the bottom of a feed marks every article in the current tab as read, propagating to that folder's badge and to All
- Configurable in Settings: a toggle, plus a delay of **Immediately, or 5–30 seconds in 5-second steps**. Default is on at 5 seconds
- The wait is cancelled by scrolling back up, switching tabs, navigating away, or backgrounding the app — a bulk mark-read the user didn't witness never lands
- It fires at most once per visit to the bottom; returning to the bottom later arms it again

**Mark as Read — Swipe**
- Swipe in either direction (left or right): marks as read. Nothing is removed — the card dims in place under the finger that swiped it
- Article dims in-place — it is never removed from the list under the finger that swiped it

**Mark as Unread — Swipe**
- Long-press → radial menu (see below), or dedicated swipe gesture: marks as unread
- Article restores full opacity and counts as unread again everywhere

**Mark All as Read — Confirmed, Then Permanent**

A confirmation dialog is shown first, from either entry point (the FAB and the folder tab bar both route through the same guard). The action cannot be undone and it runs a cleanup pass that deletes rows, so it asks before doing either.

Behaviour then differs by tab:

- **All tab:** marks every article read in the DB → runs age-based cleanup → refreshes all feeds behind the app-bar bolt → reloads. Result: only newly fetched unread articles are shown.
- **Category tab:** marks every article in that folder read → runs cleanup for that folder only → **refreshes that folder's feeds** → reloads → shows a `NotificationBanner` confirmation.

Both branches mark read and then **retire** — the rows are deleted and
tombstoned, so no setting brings them back. Pressing this button means "clear
these out". Retiring here is safe under rule 1: the All branch flips `_booting`
and rebuilds from scratch, and the category branch re-queries and resets.

This is deliberately *not* what the end-of-feed dwell timer does — it marks
read and stops, because reaching the bottom of a feed is passive reading rather
than dismissal, and the user is looking at a stationary list.

**The confirmation is skippable.** The dialog carries a "Don't show again"
checkbox, written only on **confirm** — ticking it and then backing out must
not disable the warning. It is turned back on from the **Confirm mark all as
read** switch in the Quick Settings bubble; a setting that can only ever be
disabled is a trap.

Scroll position for the affected tab resets to top after reload.

**Scroll position**
- Returning from the system browser restores the **exact** position — an article read and come back from should land where it was left
- Switching to a different category tab resets that tab's scroll to the top (correct behaviour); the previous tab's position is saved and restored when switching back
- **A network refresh is conditional.** Nothing arrived → nothing moves: scroll untouched, no rows removed, the user pulled to check and is not relocated. Something arrived → read articles are retired, the new ones load on top, and the list jumps to the top. "Arrived" means *visible*, not *inserted* — an article can be inserted and then hidden by the age filter, the per-feed cap or a blocklist match, and triggering on inserts would jump the user to the top to see nothing new. The decision is made **before** retiring, because retiring first would delete read rows even in the case where the user is meant to see no change, and they would then vanish at the next unrelated rebuild as an apparently random glitch
- Every one of these jumps is programmatic, so each closes the `MarkReadGate` first; restoring a saved tab offset must not mark everything above it read in a tab the user has only just arrived at
- Scroll and restore behaviour has no user toggle. **Read visibility does** — Show read, in the Filter bubble

**Long-Press Radial Menu**
- Long-press any article card to open a radial context menu centred on the card
- Three action buttons, arranged in a row above a close button:
  - **Bookmark** — toggles saved state; label and icon reflect whether the article is already saved
  - **Share** — triggers Android native share sheet
  - **✦ Summary** — opens AI article summary sheet
- Central × button and tapping outside both dismiss the menu
- Background dims while the menu is open
- Menu animates in with radial expand: the buttons travel outward from the × anchor on an `easeOutBack` overshoot while scaling and fading in (~220ms), and pull cleanly back to the anchor on reverse

**Pull-to-Refresh**
- Swipe down from the top of the feed list triggers an immediate refresh of all feeds in the current tab
- Uses Material 3 `RefreshIndicator`

**FAB Cluster (bottom-right)**
Three mini FABs, visible only when at least one feed exists:
- **Refresh** — refreshes the current tab's feeds; shows a spinner while active. It used to additionally drop already-read rows from the list, because there was no way to say *never show me read articles*. There is now, it is persistent, and it is one tap away, so the button and pull-to-refresh are the same operation again with two gestures — which is what a user would assume they already were
- **Search** — opens the Search screen
- **Mark all read** — executes the mark-all-read sequence above

**Open Article**
- Tap a card to open the article; the card dims in-place immediately (marks as read, never retired here); exact scroll position is restored on return — no reload
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

**Blocked articles are hidden, not deleted — and this is deliberate**

Making a blocked article *retire* (delete the row, write a tombstone) was
specified during pass 05, investigated, and not shipped. `is_blocked` already
excludes the article from every feed view under either show-read setting, so
deleting would buy nothing, and it would cost three things:

- `unblockByKeyword` becomes a no-op. Today, removing or editing a keyword
  restores what it hid. With the rows deleted there is nothing to restore, and
  the tombstone would block a re-fetch for another eight days on top.
- The **Blocked Articles** audit view — `getBlocked()`, live at
  `keyword_blocklist_screen.dart:33` — would be permanently empty. The whole
  point of that screen is showing the user what a keyword swallowed.
- A broad keyword becomes catastrophic. Adding "the" would irreversibly
  destroy essentially the entire library, with no confirmation dialog and no
  recovery path. Retroactive blocking is applied the moment a keyword is
  saved, so there is no moment at which the user is asked.

The rule: hiding is reversible, deletion is not, and a keyword is far too easy
to mistype for its blast radius to be permanent.

**Performance**
- Runs locally at parse time — zero latency, zero API calls

---

### 4.7 Keyword Alerts

- User can add keywords to an alert list, each optionally whole-word
- When a **newly fetched, unblocked** article matches an alert keyword, the app posts a system notification naming the matched term(s) — "New articles matching …". This fires from the background refresh path as well as foreground fetches, and is the only notification Flash produces
- Matching runs against the article title and description, after keyword *blocking* has been applied, so a blocked article never triggers an alert
- Managed via Settings → Keyword Alerts screen

---

### 4.8 Article Auto-Cleanup

- **Age-based:** read, unsaved articles whose `published_at` is older than the configured cleanup window are deleted automatically
- The cleanup window defaults to **7 days**. It shares the `cleanup_age_days` key with the Filter bubble's **Article age** slider, which offers 2–15 days; `runCleanup` itself clamps to 5–20, so a value below 5 leaves rows in the database a few days longer than the label implies. The user-visible list is unaffected — the display filter honours the real value
- Unread articles are never deleted, regardless of age
- Bookmarked (saved) articles are never deleted, regardless of read state or age
- Cleanup runs on every cold open and every background refresh, **before** new articles are fetched
- Neither refresh path — pull-to-refresh nor the refresh FAB — runs DB cleanup. Nothing is deleted by refreshing; what a refresh changes is only which rows match the visibility rule
- The FAB used to additionally drop read rows from the list while pull-to-refresh did not, which made two gestures for the same operation behave differently. Whether read articles show is now the **Show read** toggle's job (§4.3), so both gestures do the same thing and the answer is persistent rather than implied by which control you happened to touch
- Per-folder cleanup is also supported (used by "Mark all as read" on a category tab)
- **Tombstone pruning rides along here.** `runCleanup` drops `deleted_articles` rows older than `kTombstoneDayLimit` (`kFetchDayLimit + 1`, so eight days). Fetch thresholds already discard anything older than seven days by publish date, so a feed stops offering an article shortly after that; the extra day covers clock skew and lazily back-dated feeds. Beyond that a tombstone can only cost space. Pruning lives inside `runCleanup` rather than at its call sites so a new cleanup caller cannot forget it — and past the window a guid *can* insert again, which is intended: the fetch window has moved on, so a feed re-offering it means it genuinely republished

---

### 4.9 Fetch Thresholds

Applied to every feed fetch before articles are written to the database:

- Articles are sorted newest-to-oldest by `published_at`
- Articles with `published_at` older than 7 days are discarded — they would be cleaned up immediately anyway
- Articles with no `published_at` are always discarded
- At most **"Max articles per feed"** articles per feed per fetch are accepted (the newest N within the 7-day window), defaulting to `kFetchArticleLimit` (100). The setting is consulted by the fetch path and, separately, caps what the feed *displays* per feed — the display cap is what makes moving the slider visibly do something, since a fetch cap alone changes nothing already stored
- GUID resolution: feed-level guid is preferred; if absent, the article URL is used as the GUID; if neither exists, the article is skipped (no random or timestamp-based GUIDs)
- Duplicate (feed\_id + guid) articles are silently ignored on insert — re-fetching never resets the read state of existing articles
- **Dedup is two mechanisms, and both are load-bearing.** `INSERT OR IGNORE` against the unique `(feed_id, guid)` index stops duplicates *within* a fetch. That alone used to be enough, because a read article kept its row and therefore kept its guid to collide with. Retirement deletes the row, taking the guid with it — and the article is still in the feed's XML and still inside the seven-day fetch window, so on its own the next refresh would re-insert everything the user just cleared, as unread. The `NOT EXISTS` check against `deleted_articles` in `insertArticles` is what prevents that. **Anyone touching `insertArticles` needs to know this before they touch it:** the index guards within a fetch, the tombstone guards across one, and removing either brings the resurrection bug back

### 4.10 Background Refresh

- Configurable interval: 15 min, 30 min, 1h, 3h, 6h, Manual only
- Default: 30 minutes
- Respects Android battery optimisation (Doze mode)
- On refresh: articles fetched, parsed, keyword-filtered, and written to the database
- Silent by default — no "you have new articles" notification is ever posted
- **Exception:** keyword *alerts* (§4.7) do post a notification from this path when a newly fetched, unblocked article matches an alert term. That is the entire point of the feature, and it is the only notification the app produces

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
- Content scrolls only when it exceeds the sheet — `ClampingScrollPhysics`, not a fixed one-page assumption. A full-budget summary (one focal line plus five bullets) does exceed one page at the body density used here (16px / 1.8 line height), so scrolling is the normal case rather than the exception; readability of the text was chosen over fitting it above the fold
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

Top Bar:
├── App name "Flash" (or the Newspaper masthead when that mode is on)
└── Background-fetch indicator (small animated bolt, right-aligned, only while fetching)

Content area:
└── Article cards (scrollable)
```

**Wide layouts.** At ≥600dp width, or on Android TV, the bottom navigation bar is
replaced by a Material `NavigationRail` down the left edge and the content fills
the remainder. On TV the rail is extended (icon + label always visible) and all
text is scaled up 1.4× for couch legibility; the article card also drops its
swipe and long-press gestures there, since there is no touchscreen — D-pad OK
opens the article, and share/bookmark remain reachable inside the summary sheet.

---

## 7. Settings

Settings live in three places. The **Settings screen** keeps what is configured once and forgotten, grouped as **Reading**, **Refresh**, **Filters**, **Backup**, **About**. What is adjusted while reading was moved onto the feed screen itself, into two bubble panels opened from the top button cluster — controls duplicated in both places were removed from Settings rather than left to drift apart.

| Setting | Default | Lives in | Options |
|---|---|---|---|
| Theme | System | Quick Settings bubble | Light, Dark, System |
| Newspaper mode | Off | Quick Settings bubble | On/Off — overrides the theme choice and greys out the selector while on |
| Mark as read on scroll | On | Quick Settings bubble | On, Off |
| Confirm mark all as read | On | Quick Settings bubble | On/Off — also turned off by the dialog's own "Don't show again" |
| **Show read** | **On** | **Filter bubble** | **On/Off — off retires read articles as they scroll past, on defers retirement to the next refresh** |
| Max articles per feed | 100 | Filter bubble | 20–150 in tens (slider) |
| Article age | 7 days | Filter bubble | 2–15 days (slider) |
| Article order | Newest first | Filter bubble | Newest, Oldest |
| Mark all read at end of feed | On | Settings screen | On/Off |
| └ Wait before marking | 5 seconds | Settings screen | Immediately, 5s, 10s, 15s, 20s, 25s, 30s (shown only while the toggle is on) |
| Background refresh interval | 30 min | Settings screen | 15m, 30m, 1h, 3h, 6h, Manual only |
| Keyword blocklist | — | Settings screen | Manage list |
| Keyword alerts | — | Settings screen | Manage list |
| Google Drive backup | — | Settings screen | Sign in / Sign out, Backup now, Restore |
| Local backup | — | Settings screen | Export, Import |
| OPML | — | Settings screen | Import, Export |

The Filter bubble's four controls are staged behind an **Apply** button rather than written on release: dragging a slider is exploratory, and persisting each intermediate value re-queried the feed several times on the way to the one the user actually wanted. Apply is disabled until something differs, so it doubles as an indicator of whether anything is pending.

There is **no language setting** — the app follows the device locale (§3.10).

---

## 8. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Cold start to feed visible | < 1 second — the cached list is shown before any network call; measured at ~0.9s on a Pixel 9 Pro |
| Feed refresh (20 feeds, Wi-Fi) | < 8 seconds |
| Scroll performance | 60 fps minimum, 120 fps on capable devices |
| Offline readability | All cached headlines available with no network |
| Database size (typical use) | < 50 MB for 20 feeds × 100 articles |
| Crash-free sessions | > 99.5% |
| Min Android version | Android 8.0 (SDK 26) |
| Target Android version | SDK 36 (follows the Flutter SDK default) |

---

## 9. Build & Distribution

- **Framework:** Flutter + Android SDK
- **Package ID:** `io.getflash.app`
- **Dev environment:** VS Code + Claude Code
- **Builds:** `flutter build apk --release`, then `flutter install --release -d <device>` over USB to a physical Pixel 9 Pro. Note that `flutter install` uninstalls first; Android Auto Backup (`backup_rules.xml`) has so far restored the database afterwards, but that is the platform's behaviour rather than a guarantee
- **Signing:** release builds are still signed with the **debug key** (the Flutter template default in `android/app/build.gradle.kts`). Fine for sideloading, but the debug keystore is machine-local — an update signed with a different key cannot install over an existing copy, so testers would have to uninstall and lose their data. A real release keystore is needed before wider distribution
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
- Pull-to-refresh and a manual refresh FAB — the same operation with two gestures; both reset the list to the top
- Non-blocking cold open: cleanup → cached list shown immediately → background fetch behind a small animated app-bar bolt. Resume uses the same indicator
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
- Read retirement: read articles are deleted and tombstoned rather than hidden, immediately on scroll or deferred to the next refresh depending on **Show read**; saved articles exempt
- Newspaper mode: opt-in serif theme (bundled PT Serif / Playfair Display OFL fonts), masthead nameplate on the feed screen, DB-persisted toggle in Settings
- Folder tab bar: 60dp height, 48×48dp minimum tap targets, ripple feedback, auto-scroll to selected tab, fixed-width unread badges that never shift the layout as counts change
- Global loading indicator: a top-edge progress bar backed by a reference-counted `LoadingController`, covering every user-initiated async operation app-wide
- Resume refresh: returning from background after ≥30s triggers a silent, cleanup-free network fetch (5-minute minimum interval)
- Long-press drag-and-drop to reorder feeds within a category and move them between categories, with edge auto-scroll and drop-target highlighting
- Configurable end-of-feed auto mark-as-read (off, immediate, or 5–30s)
- Animated read-state dim (~180ms) on card text, thumbnail and favicon
- Wide-layout `NavigationRail` at ≥600dp and full Android TV support (extended rail, 1.4× text, D-pad-only interaction)
- Theme correctness: System mode tracks the live OS theme across cold start, resume and foreground changes; the native window background follows the *app's* theme rather than the OS, so a dark app on a light system no longer flashes white
- Faster Material motion: 220ms page transitions on all theme variants (subclassing `PredictiveBackPageTransitionsBuilder`, so predictive back is retained), 150ms swipe snap-back
- Scroll-driven FAB fade, plus Filter and Quick Settings bubble panels anchored to the buttons that open them
- **Show read** toggle deciding *when* a read article is retired (schema v13)
- Tombstones (`deleted_articles`) so a re-fetch cannot resurrect a retired article
- Conditional refresh: nothing moves when nothing arrived
- Reaching the bottom of a feed zeroes that tab's badge
- Skippable mark-all-read confirmation, re-enabled from Quick Settings
- **Day dividers** in the article list — Today / Yesterday / weekday / date, localised, grouped by calendar day
- List stability: every network refresh resets to the top, a `MarkReadGate` stops programmatic scrolls marking anything read, and the card's title weight no longer changes with read state (a weight change reflowed the title and shifted every card below it mid-scroll)
- Feed and category changes reach the article list on return to the Flash tab, via `FeedsChangedNotifier` pinged from the repository writes
- Categories collapsed by default on the Categories screen
- Mark-all-read confirmation dialog (the strings existed, translated, in all five locales; nothing ever showed them)

### Regressions Worth Remembering
- **Retirement-on-scroll deleted articles that were still on screen** (shipped in pass 05, disabled in pass 07). Three compounding causes: row heights were guessed at a hardcoded 120px for every row `ListView.builder` had disposed — real cards measure **96.8dp and 121.9dp** on a Pixel 11 Pro, so the guess was wrong in both directions and the error accumulated down the list; `jumpTo` dispatches `ScrollEndNotification`, so every programmatic scroll ran retirement; and retirement re-entered itself through its own offset correction. Fixed by caching measured heights, gating on `MarkReadGate`, a re-entrancy flag, and — the part that matters — a hard ceiling that confines retirement to rows the ListView has **disposed**, so no future arithmetic error can delete something visible.

### Tried and Removed
- **Retirement on keyword block** was specified into pass 05 and deliberately not shipped. `is_blocked` already hides the article everywhere, so deletion would add nothing except making `unblockByKeyword` a no-op, emptying the Blocked Articles audit view, and turning one mistyped keyword into irreversible library loss with no confirmation. See §4.6.
- **The 48-hour show-read window** shipped in schema v11 and was removed in v13. It kept a `read_at` timestamp per article so that switching Show read back on restored anything read recently. It worked, but it made "read" a state an article rested in indefinitely, which meant the table only ever grew and the user had no way to actually finish with anything. Retirement replaced it: one verb, two timings, and the row leaves. Do not repropose the window without also solving what it was hiding — that the database had no exit path.

### Deliberately Removed
- **In-app reader view.** Articles open in the system browser. A reader mode existed and was removed (schema v8 purges its settings and per-domain compatibility cache); it was never reliable enough across sites to be worth maintaining. This is the most likely gap a reviewer would name if the app were distributed publicly

### Not Yet Built
- iOS support
- Home screen widget
- Per-feed custom refresh intervals
- Multi-account Google Drive
- Live sync across devices — the single biggest reason a user would stay on Feedly or Inoreader instead
- Release signing key (see §9)

### Known Gaps in Test Coverage
- No widget tests for any screen. `testWidgets()` cannot be combined with real `sqflite_common_ffi` I/O — the FFI future never resolves inside flutter_test's FakeAsync zone and the test hangs. Closing this means extending the seam pattern already used in `app.dart` (`initialSettingsForTesting`, `homeOverrideForTesting`) to the screens worth covering
- No tests for `ArticleExtractor`, the Drive/local backup services, or the settings/folder/keyword repositories

---

## 11. Open Questions

- **Opinion filter:** Planned but not yet implemented — the dedicated Opinions folder and Claude Haiku classification pipeline are not shipped
- **Restore merge vs replace:** Current behaviour is replace (wipe then re-insert); merge with duplicate-URL detection is a future improvement
- **Play Store:** Under consideration. Blockers if pursued: a real signing key, an AAB build rather than APK, and a decision on free-vs-paid. Gemini Nano only runs on AICore-capable devices (Pixel 8+/Galaxy S24+ class), so the headline AI feature is unavailable to most of the market — which argues for a free download with a one-time unlock rather than a paid-upfront listing
- **Feedly API terms:** Feed discovery search goes through Feedly's API. Worth reviewing their terms before any paid distribution
