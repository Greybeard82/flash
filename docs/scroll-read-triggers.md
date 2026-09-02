# Scroll offset and read-state triggers

Line numbers are as of Pass 10 Phase 0 (after instrumentation was added).

## Table 1 — everything that can change the scroll offset

| Call site | Triggered by | User-initiated | Synchronous with layout | Emits a notification the read-marker can see |
|---|---|---|---|---|
| `feed_screen.dart:639` `_resetScrollToTop` → `jumpTo(0)` | Visibility/filter change (`:272`), pull-to-refresh (`:337`), boot/first load (`:483`), fetch-and-apply (`:712`), mark-all-read (`:1269`) | No | No — `addPostFrameCallback` | `ScrollStart` + `ScrollEnd` only. No `UserScrollNotification` (`jumpTo` calls `goIdle()` first) |
| `feed_screen.dart:653` `_restoreScrollOffset` → `jumpTo(saved)` | Resume from background via `_reloadArticles` (`:584`), return from browser via `_openArticle` (`:1084`) | No | No — `addPostFrameCallback` | Same as above |
| `feed_screen.dart:758` / `:761` tab-switch restore → `jumpTo(saved \| 0)` | Folder tab change | No | No — `addPostFrameCallback` | Same as above |
| `feed_screen.dart:869` retirement compensation → `jumpTo(offset - removedHeight)` | `_retireScrolledPast` from `ScrollEndNotification` | No | Yes — same synchronous turn as its `setState` | Same as above |
| `ListView` physics (drag / ballistic fling) | Finger, wheel, trackpad | Yes | Yes | `UserScrollNotification` with non-idle direction, plus `ScrollStart`/`Update`/`End` with `dragDetails` |
| `ScrollPosition.applyContentDimensions` / `correctPixels` (Flutter-internal) | Row extents changing after first layout: thumbnail resolving, text laying out, `maxScrollExtent` growing | No | Yes | **Nothing.** No scroll notification is dispatched. `_onScroll` fires from the `ScrollController` listener with no way to attribute it |
| `RefreshIndicator` drag/retract | Pull-to-refresh gesture and its release | Partly — the drag is, the retract is not | No | `ScrollStart`/`Update`/`End`; the retract carries no `dragDetails` |

## Table 2 — everything that can set `is_read = 1`

| Call site | Trigger | Gated on today | Can fire while backgrounded or mid-lifecycle-transition |
|---|---|---|---|
| `article_repository.dart:216` `markAsRead` ← `feed_screen.dart:1063` | Tapping an article open | `wasUnread` only | No — requires a tap |
| `article_repository.dart:216` `markAsRead` ← `feed_screen.dart:1094` | Swipe-to-mark-read on a card | `isRead` check only | No — requires a swipe |
| `article_repository.dart:216` `markAsRead` ← `bookmarks_screen.dart:71`, `:106` | Opening/marking from Bookmarks | None | No |
| `article_repository.dart:216` `markAsRead` ← `search_screen.dart:60` | Opening from Search | None | No |
| `article_repository.dart:239` `markManyRead` ← `feed_screen.dart:987` (`_onScroll`) | Any offset change past an article's midpoint | `_markReadOnScroll` setting, `MarkReadGate.isOpen`, midpoint arithmetic | Yes — `_onScroll` is a `ScrollController` listener; it fires for layout-induced offset changes and for every programmatic `jumpTo`. The gate is the only thing standing in front of it |
| `article_repository.dart:251` `markAllAsRead` ← `feed_screen.dart:1038` (`_onBottomDwellComplete`) | Dwelling `autoMarkReadAtBottomSeconds` at the list bottom | `settings.autoMarkReadAtBottom` **only** — **not** `MarkReadGate`, **not** `_markReadOnScroll` | **Yes.** Armed from `_updateBottomDwellTimer` (`:1013`), called at the top of `_onScroll` *before* both guards. A programmatic jump landing at the bottom arms it; it then fires from a `Timer` |
| `article_repository.dart:261` `markAllAsReadByFolder` ← `feed_screen.dart:1040` | Same as above, on a category tab | Same as above | Same as above |
| `article_repository.dart:251` `markAllAsRead` ← `feed_screen.dart:1220` | "Mark all as read" button, All tab | Explicit user action + confirm dialog | No |
| `article_repository.dart:261` `markAllAsReadByFolder` ← `feed_screen.dart:1244` | "Mark all as read" button, category tab | Explicit user action + confirm dialog | No |
| `article_repository.dart:308` `_retireChunk` (`SET is_read = 1 ... WHERE is_saved = 1`) | Retirement, for saved rows that are exempt from deletion | Reached only via `_retireScrolledPast`, which requires `kEnableScrollRetirement`, `_markReadOnScroll`, `!_showRead`, `MarkReadGate.isOpen` | Only as far as retirement itself can |

## Paths not covered by the Phase 3 fixes

- **`BottomDwellTimer` → `markAllAsRead`** is not a scroll-driven per-article write, so a `ReadGate` in front of `_onScroll`'s `markManyRead` does not cover it. It is armed from `_onScroll` ahead of every existing guard and marks the *entire* feed, not the rows above the viewport.
- **Layout-induced offset changes** (Table 1, row 6) dispatch no scroll notification at all, so `userInitiated` cannot be derived from the notification stream alone for that row — it must default to false and be positively set by a real drag.
