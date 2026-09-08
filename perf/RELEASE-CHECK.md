# Pre-release check — 2026-09-08

Scope was cut deliberately: **101 rows RELEASE, 412 DEFERRED** out of 513. The
checklist stays as a reference document and for future releases. Walking all of
it before a 14-day closed test with 12 real users is enterprise-scale QA for a
solo-dev app, and the testers using it normally is what actually surfaces
ordinary bugs.

---

## What was walked, and what it found

### A — recent changes

| Check | Tablet | Samsung | Emulator |
|---|---|---|---|
| Clean mode: button appears after background extraction | pass | pass | — |
| **Clean mode: no trailing author photo / bio / related rail** | pass | pass | — |
| Clean mode: images with captions, theme-driven colours | pass | pass | — |
| Clean mode: last paragraph clears the floating button | pass | pass | — |
| Clean mode: 720dp measure cap and centring | pass | n/a | — |
| Quick Settings has no refresh control at all | pass | pass | — |
| Add Feed: field disabled, no keyboard, before a category is picked | pass | pass | — |
| Add Feed: chip enables the field, keyboard opens on tap | pass | pass | — |
| Row 382: back closes the menu, Settings stays open | pass | pass | — |
| Row 382: second back leaves Settings normally | pass | pass | — |
| Drag feedback matches the list column width | pass | n/a | — |
| Mark-as-read-on-scroll toggles and persists | pass | pass | — |

The Add Feed rows were verified with `dumpsys input_method` rather than by eye:
`mInputShown=false` on opening the sheet, `true` after selecting a chip and
tapping the field.

**Corroboration worth recording:** the Samsung's Tech tab was showing the live
TechRadar PS3-emulator article that is saved as the `techradar_a` fixture — so
the on-device result and the pinned test assertion cover the same bytes. Before
the extraction fix that page's clean view ended `IMG P L5` (author portrait,
author bio, `popular-box` rail); it now ends on prose.

### B — data-loss paths

Run on the **emulator**, which carries 360 articles and real feeds but none of
David's data. See the note below on why the destructive halves were not run on
the physical devices.

| Check | Result |
|---|---|
| Mark-all-read raises a confirmation naming the consequence | **pass** — "You won't be able to undo this" |
| Cancel leaves everything intact | **pass** — counts unchanged at All (360) |
| Confirm actually retires the feed | **pass** — 360 → 0 |
| **Bookmarks survive mark-all-read** | **pass** — both bookmarks present afterwards, and the newly-bookmarked one was not even marked read |

That last row is the one that matters for the closed test: a tester who marks
everything read does not lose what they deliberately saved.

### C — core loop

| Step | Result |
|---|---|
| Bookmark an article (radial menu → Bookmark) | **pass**, emulator |
| Bookmarked article appears in Bookmarks | **pass**, emulator |
| Read an article end to end (WebView and clean view) | **pass**, both devices |
| Add a feed | partially — the Add Feed sheet and its gating pass on both devices; a completed add was not walked |

---

## Not walked, and honest about it

Of the 101 RELEASE rows: **15 are MANUAL** (David's — they need Home, recents, a
share sheet or a file picker), **6 already passed**, and roughly **60 remain**.
What is left is mostly:

- **Delete feed and delete category** (rows 96-98, 121-123). Not run.
- **Local backup export/restore** (297-308) — most are MANUAL: export goes
  through the system share sheet, restore through the system file picker.
- **Drive restore** (317-320). Not run, and I would not run it unattended
  against a live Google account.
- **The refresh rows** (487-513), beyond the interval ladder and the back-press
  fix.
- **Search and Alerts** core-loop steps.

### Why the destructive rows did not run on the physical devices

Mark-all-read, delete feed and delete category destroy real data on the Samsung,
and the app's own backup cannot undo them: `LocalBackupService` serialises
**folders, feeds and keywords only** — no articles, no read state — and both its
export and import go through system UI that is outside what I drive. So there is
no undo available for the very rows that need one.

They were run in full on the emulator instead, where the same code path acts on
360 real articles. If you want them on the physical devices too, that is a
deliberate call to make with the data loss understood — say so and I will.

### OPML import does not exist

The brief listed it as a data-loss path. There is no OPML service, no UI and no
call site in `lib/`; the only occurrence of the word is inside a doc comment in
`feeds_changed_notifier.dart`. Nothing to walk.

---

## The regression this pass found and fixed

**Row 382 — the interval menu's back press on a pushed route.** A regression from
the refresh-settings move. `dismissTopBubblePanel()` has exactly three callers,
all in `lib/app.dart`, and `registerBackDismiss` feeds nothing else; a pushed
route's own pop answers back first, so the menu's handler was unreachable and the
first back press popped Settings with the menu still open.

Fixed with a `PopScope` inside the widget's own subtree, so it works in whatever
route hosts it. Five tests, written against a pushed route on purpose — pumping
the field as `home:` would pass against the broken build. Verified they
discriminate: **2 of 5 fail without the fix.** Verified on both devices.

---

## Device state

- **Mark-as-read-on-scroll restored to ON on both devices**, verified visually on
  each. This was the last blocking item.
- Both physical devices are on the branch release build. The emulator has been
  used destructively and is expendable.
- The Samsung's data: All (38) at last check, recovered from the audit's earlier
  loss via background fetches.

---

## What is left before this merges to main

1. **Your review.** That was the point of the branch.
2. **The 15 MANUAL rows** are yours to walk — rows 1-5 carry an explicit
   "Press:" note.
3. **A decision on the destructive rows** on physical devices: run them knowing
   the data goes, or accept the emulator coverage.
4. Nothing technical blocks the merge. 978 tests, `flutter analyze lib test`
   clean, branch is ahead of `main` with no conflicts.

Deferred work is recorded in the checklist as `DEFERRED`, not deleted — 412 rows,
kept for post-launch and future releases.
