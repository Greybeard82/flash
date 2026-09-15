# Flash — pre-launch QA triage

**Spine: `MANUAL_QA.md`** (30 sections, what to exercise). This is the triage
table it never had.

**Organised by failure class, not by screen.** Screens have been walked
repeatedly across ten passes. These paths have not.

Status: 2026-09-15. Five pre-launch changes banked first (§1 below), then the
QA. **Nothing in the QA section was fixed** except where noted.

---

## The table — worst first

| # | finding | class | one line |
|---|---|---|---|
| 1 | **Emulators cannot render Flash on this machine** | **FIX BEFORE LAUNCH** *(investigate)* | System UI renders, Flash does not; 2400 `bad color buffer handle`. Blocks all disposable-data testing. |
| 2 | Backup does not contain bookmarks or read state | **DECISION NEEDED** | By design and asserted in tests, but a tester who restores loses both. |
| 3 | An XML comment broke the release build | **FIXED** | `--` is illegal in an XML comment. Caught only by building. |
| 4 | Impeller opt-out is deprecated upstream | **POST-LAUNCH** | Flutter warns it is being removed; likely related to #1. |
| 5 | Widget "999+" never rendered on a device | **VERIFY ON DEVICE** | No widget placed on any of the three; Samsung's 2153 unread is the case. |
| 6 | `article_detail_pane_clean_mode_test` is flaky | **POST-LAUNCH** | Fails under full-suite parallelism, passes alone. Test-only. |
| 7 | Newspaper inherits Material's `surfaceContainer` | **SHIPS AS IS** | Unauthored, now only reachable in the hued path. Loose end, not a defect. |
| 8 | Upgrade keeps everything | **SHIPS AS IS** | Verified — see §A. |
| 9 | Flash's own code has no R8 by-name exposure | **SHIPS AS IS** | Verified — see §B. |
| 10 | Flash has no incoming deep-link surface | **SHIPS AS IS** | No `VIEW` filter declared. Nothing to test. |
| 11 | Foldables | **WON'T FIX for launch** | Parked. Nobody in the closed test has one. |

---

## 1. The five changes

| item | result |
|---|---|
| 1.1 WorkManager keep | Explicit `-keep` added; manifest `<service>` kept and commented. Both asserted. Verified in R8 output: `BackgroundWorker -> BackgroundWorker`, unrenamed. |
| 1.2 Contrast | `onSurfaceMuted` `#8A9391` 3.15:1 → **`#717877` 4.51:1**. `onSurfaceRead` `#79817F` 3.99:1 → **`#6A7270` 4.94:1**. Exception list emptied; tripwire inverted. |
| 1.3 Newspaper chips | Unselected paper tint + ink text (13.62:1); selected ink fill + paper text (14.95:1). 6.8 closed. |
| 1.4 Mark all read | One-shot suppression + serialised updates + badge failure caught. Three groups, all mutation-verified. |
| 1.5 Banner | New role `FlashColors.bannerSurface`. `#F1F5F5` / `#161D1C` / `#E7E7E3`, text 16.92 / 14.24 / 13.62:1. |

**On 1.2's minimum.** `onSurfaceMuted` is the true minimum — one step lighter,
`#727978`, measures 4.45 and fails. `onSurfaceRead` could **not** stop at its
own minimum: scaled to the bar it lands on `#717877`, the same colour as muted,
which collapses the two roles and reintroduces the inverted hierarchy
`app_theme.dart:381` exists to prevent. It goes one visible step further —
7 units of separation where the original was 17.

**On 1.5's role and value.** Chosen: each theme's own `surfaceContainer`
(`_npSurface2` in Newspaper). No new hex. It is deliberately quiet, ~1.10:1
against the page, because the banner announces itself by sliding in and motion
does not need contrast shock with it; the `outlineVariant` hairline is what
makes the edge legible and is load-bearing at that weight.

---

## A. Upgrade and data integrity

**This is the section that decides whether the testers keep their data.**

### The answer: yes, and it is now proven rather than assumed

`upgrade_whole_database_test.dart` seeds a **v18 database that looks like a real
library** — feeds in folders, articles in all four read/saved combinations, a
keyword alert with a match behind it, settings — runs v18 → v19, and asserts
nothing is lost. 10 tests, all passing.

It matters more than the existing per-step migration tests because migrations
run in **one transaction**: a failure anywhere aborts the open, so the blast
radius is the whole library, not the changed table.

| checked | result |
|---|---|
| folders, feeds, articles, alerts, settings row counts | all intact |
| read state, bookmarks, and the **read-AND-bookmarked** combination | 16 / 16 / 8, exact |
| feeds still attached to the right category | yes |
| alert matches still resolve to a real article | yes |
| empty database | upgrades cleanly, ends on the new schema |
| 20 categories / 40 feeds / 160 articles | upgrades, all six hues used |

### Category names, order and colour — specifically

- **Names: untouched.** v19 is an `ALTER TABLE ADD COLUMN`, not a rebuild.
- **Order: untouched.** `position` is read, never written.
- **ids: untouched.** Pinned, because ids move only in a rebuild.
- **Colour: a FIRST assignment, not a shuffle.** v18 had no colour to lose.

**Which of shuffle-or-instability happens: neither.** The backfill is
`position % 6`, and it is pinned as **deterministic** (two identical libraries
upgrade to identical hues, `[0,1,2,3,4,5,0]`) and **stable** — a hand-set
colour survives the migration being handed to the device a second time, which
is what an interrupted upgrade does. If that ever regresses, every deliberate
colour choice would be erased on every launch, so it is asserted directly.

### OPML and backup: already covered, verified by reading

Not re-tested, because the coverage is specific rather than nominal.

- **OPML** — malformed XML, empty string, XML that is not OPML, valid-but-empty,
  re-import is idempotent, export → import into a fresh database reproduces the
  library, export → import into the **same** database adds nothing.
- **Backup** — valid, wrong version, missing `folders`, missing `feeds`,
  round-trip of folders/feeds/keywords, and the real reported bug where folders
  and feeds arrive as maps rather than lists.

### ⚠ Finding 2: backup does not contain bookmarks or read state

`backup_serializer_test.dart` asserts it: *"does NOT include read/unread state,
API keys, or bookmarks"*. Deliberate, and defensible — a backup is the feed
list, not the reading history.

**But it is not what "backup and restore" implies to a tester**, and this is the
same audience the upgrade work is protecting. Someone who backs up, reinstalls
and restores gets their feeds and loses every bookmark. **Decision, not a bug** —
either widen the backup or say so in the UI.

### Not done, and why

**Fresh install, onboarding, starter pack, first refresh** and **uninstall /
reinstall** need a device whose data is disposable. All three physical devices
hold David's real library, and the emulator route is blocked by finding 1.

---

## B. Release-only paths

### Flash's own code, audited the way the fifteen plugins were

**Clean.** R8 only touches the Kotlin/Java side, which in Flash is three small
files.

| surface | verdict |
|---|---|
| `Class.forName`, `getDeclared*`, `newInstance`, Gson, `TypeToken` | **none** |
| `MainActivity::class.java` in `UnreadWidgetProvider` | compile-time literal, not reflection; also manifest-kept |
| `R.layout.*` / `R.id.*` | compile-time constants, shrinker-visible |
| `KEY_COUNT = "unread_count"` | a SharedPreferences **data** key; R8 does not touch string literals |
| resources resolved by name (`ic_stat_flash`) | already covered by `res/raw/keep.xml` |
| Dart entry points | two, `refresh_service.dart:47` and `alert_navigation_intent.dart:21`, **both already `@pragma('vm:entry-point')`** — Dart tree-shaking, not R8 |

### Finding 10: there is no deep-link surface

`MainActivity` declares only `MAIN/LAUNCHER` and `MAIN/LEANBACK_LAUNCHER`. **No
`VIEW` filter, no custom scheme, no App Links.** The only ways in are the
launcher, a notification tap, and the widget's `PendingIntent`. Nothing to
test, and worth knowing before someone goes looking.

### Finding 3: the release build was broken by a comment

The comment added in 1.1 explaining why the `<service>` line is load-bearing
used `--` as punctuation. **`--` is illegal inside an XML comment**, the
manifest merger failed, and the release build died.

**Fixed.** Worth recording because of *what caught it*: not the analyzer, not
1717 passing tests — only running the build. That is handoff 10.5's release-only
blind spot, hit twice in one day, once in R8 and once in the manifest merger.

### Not done

**Mark all read on a device** (blocked, finding 1 — the fix is covered by three
mutation-verified test groups but not by hardware), **the widget on a home
screen** (finding 5), and **boot-completed** (needs a reboot, which is
forbidden on these devices).

---

## Finding 1: emulators cannot render Flash on this machine

**The most consequential thing found, because it blocks a whole class of QA.**

Two different AVDs — the 1848×2448 @404dpi foldable and a stock 1200×1920
@320dpi tablet — behave identically: the app process starts, the Flutter engine
initialises, and **no frame ever reaches the screen**. The emulator log fills
with `bad color buffer handle` (2400 of them on the tablet), under `-gpu host`,
`-gpu swiftshader_indirect` and `-gpu swangle_indirect` alike.

**It is not a Flash crash.** No crash-buffer entry, no `FATAL`, no ANR, process
alive throughout, engine logging from inside itself.

**And the system UI renders fine on the same emulator** — status bar, launcher,
the permission dialog. Only Flash is blank.

**That correlation is the lead.** Flash is the one app on that emulator opting
out of Impeller (`AndroidManifest.xml:105`), so it renders through the legacy
Skia GL path — which is exactly the path that leans on the colour buffers being
mishandled. **Untested hypothesis**, stated as one: flipping
`EnableImpeller` to `true` and seeing whether the emulator renders would confirm
or kill it in one build. Not done here, because the QA brief says fix nothing
but crashes and data loss, and this is not either.

**Why it is FIX BEFORE LAUNCH anyway:** not because users hit it, but because
it removes the only safe way to test destructive paths. Every "needs disposable
data" item below is blocked on it, and those are the items most likely to lose
a tester's library.

It also connects to finding 4: the opt-out is deprecated upstream and will be
removed, so the renderer is going to change whether or not anyone chooses it.

---

## C, D, E — what was and was not reached

**Scope call, per the brief's instruction to prefer depth on A and B.** A and B
are complete to the limit of what this machine allows. C, D and E were not
started, and saying so is better than a thin pass over them.

The one item from those sections already answered: **E's "Samsung on first
launch after updating"** — done earlier today, 0.8.1 → 0.9.2 came through clean,
no stale blob, no throw on the package-replaced receiver.

Still open: C's dead-URL matrix, D's combination states, and E's Literata
Cyrillic/Greek fallback.

**A sixth category worth having, named and stopped at as instructed:**
**"things only the build can see"**. Findings 3 and the ProGuard bug are both in
it, neither is visible to the analyzer or the suite, and both were found by
running a release build rather than by testing behaviour. It is a different
class from B: B is *release-only runtime*, this is *release-only build*.
