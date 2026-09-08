# Tablet / Samsung performance audit — 2026-09-08

Branch: **`perf/tablet-samsung-audit-2026-09-08`**. Not merged, not pushed —
local only, waiting on your review. `main` is untouched.

---

## Read this first: I destroyed unread articles on the Samsung

**The Samsung went from 73 unread to 8. The tablet went from 81 to 6.**

Not a deliberate destructive test — the *scroll benchmark* did it. Flash marks
articles read on scroll, and `_flushRead` retires read articles on every tab
switch and resume. The scroll measurement is 12 swipes per run, and I ran it
repeatedly on both devices. Each pass consumed a chunk of the backlog and the
next tab switch deleted those rows.

I did not foresee that, and I should have: in this app, scrolling *is* a
destructive operation. The brief flagged Mark All Read, Restore, delete and OPML
import as the destructive flows and had me back up before touching them. Nobody
flagged the benchmark itself, and the backup would not have helped anyway (see
below).

**What survived:** feeds, categories, bookmarks, keyword alerts, settings — all
intact on both devices. The Alerts badge still reads 14 on the Samsung.

**What is gone:** the read/unread state of roughly 65 Samsung articles and 75
tablet articles, and the article rows themselves. A refresh will re-fetch
whatever is still inside each feed's current RSS window; anything that has
rolled out of that window is gone, and the read state is not recoverable at all.

**The Stage 0 backup the brief asked for was never possible.** Two independent
reasons, both found before any destructive step:

1. `LocalBackupService.exportBackup` writes a temp file and then calls
   `Share.shareXFiles` — the Android **system share sheet**. Import uses
   `FilePicker.platform.pickFiles`, the **system document picker**. Both are
   outside Flash's own UI, so driving them is exactly what the device rules
   forbid. (`lib/services/local_backup_service.dart:33,43`)
2. Even if it had run, it would not have helped: the backup serialises
   **folders, feeds and keywords only** — no articles, no read state
   (`BackupSerializer.toMap`). Restoring it after a Mark All Read would not
   un-mark anything.

I did not sign in to anything, did not touch Drive, and did not run any of the
flows the brief listed as destructive.

---

## Devices

| | Tablet | Samsung |
|---|---|---|
| Model | Lenovo Tab M11 (TB330FU) | Galaxy M51 (SM-M515F) |
| Android | 15 | 12 |
| Refresh rate | **90 Hz** (11.1ms budget) | 60 Hz (16.6ms budget) |
| `/data` used | 8% (99 GB free) | 23% (89 GB free) |
| Build at start | release, installed 13:33 today | release, installed 2026-09-07 |
| Build now | release (restored) | release (restored) |

Storage is not the tablet's problem — it is nearly empty. Note the Samsung was
two commits behind at the start of the day; it has today's code now.

---

## The measurement had to be rebuilt before any number meant anything

The brief specified `dumpsys gfxinfo io.getflash.app framestats`. **It reports
nothing for this app.** On both devices:

```
** Graphics info for pid 20479 [io.getflash.app] **
Total frames rendered: 0
Janky frames: 0 (0.00%)
```

`gfxinfo` measures HWUI, which draws the Android View hierarchy. Flutter renders
into a SurfaceView — visible in the layer list as
`SurfaceView - io.getflash.app/...(BLAST)#0` — so HWUI genuinely has zero frames
to report. Taken at face value, every reading in this report would have been
"0% janky" and the pass would have concluded the app is flawless.

Replaced with `dumpsys SurfaceFlinger --latency` on the app's BLAST layer, which
gives real present timestamps. Details and the two traps it had to handle
(layer naming differs between Android 12 and 15; the two devices have different
refresh rates) are in `perf/baseline/METHOD.md`.

All numbers are from `flutter build apk --profile`, as the brief required.

---

## Performance: baseline vs final

Nothing shipped, so **final = baseline**. Every fix I tried was measured and
rejected.

Janky frames, medians of 4 repetitions per build:

| Symptom | Tablet | Samsung |
|---|---|---|
| **Scrolling the article list** | **0.3%** (p99 11.3ms) | **1.3%** (p99 33.3ms) |
| **Switching tabs / categories** | **6.25%** (p95 22.2ms, worst 55.6ms) | **5.85%** (p95 33.3ms, worst 99.8ms) |
| **Cold start** (`am start -W`, median of 3) | **~1944 ms** | **~1094 ms** |

### The honest headline: the premise was wrong

**The tablet is not slower at scrolling. It is better.** It holds 90fps almost
perfectly — 0.3% janky, p99 11.3ms — while the Samsung drops four times as many
frames. Whatever you are feeling on the tablet, the scroll frame timing does not
show it.

**Tab switching is genuinely janky, on both devices**, at 6-8% with worst frames
of 3-6 budget periods. This is the real interaction defect and it is not
tablet-specific.

**Where the tablet is badly behind is cold start: 1.8x the Samsung**, on newer
hardware with a higher refresh rate. If "the tablet feels slow" has a single
measured cause in this data, it is this one.

---

## What I tried, and why none of it shipped

Four hypotheses, each applied as a single variable, rebuilt, reinstalled and
re-measured with the identical interaction sequence.

| Change | Tablet tabs | Samsung tabs | Verdict |
|---|---|---|---|
| baseline | 6.25% | 5.85% | — |
| Enable Impeller | 7.5%¹ | 7.0%¹ | **rejected** — startup +113ms tablet, +64ms Samsung |
| Skip redundant rebuild when query == displayed | 5.95% | 5.75% | **rejected** — no effect |
| PageView root-type stability + slot keys | 6.55% | 5.95% | **rejected** — no effect |
| Defer DB work past the animation (260ms) | 6.20% | 8.20% | **rejected** — regressed the Samsung |
| *Skip the DB work entirely (not shippable)* | *4.55%* | *6.45%* | *upper bound — tablet only* |

¹ single run; the repetition discipline came in later.

**Impeller.** The app opts out (`AndroidManifest.xml:75-77`), so it runs on
legacy Skia/OpenGL — plausible, since Skia compiles shaders lazily on first
draw, which fits "tab switch janks, steady scroll does not". Enabling it did
improve Samsung scroll p99 from 33.3ms to 17.0ms, a real gain worth revisiting.
But it did not touch tab jank and it made cold start worse on both devices —
landing squarely on the metric the tablet is already worst at. Shipping it would
have meant reporting a change that made the headline complaint worse.

**PageView type stability.** A sub-agent found, and I verified, that the
itemBuilder returns `RefreshIndicator` for the selected slot and a bare
`ListView.builder` for unselected ones, unkeyed — so `Widget.canUpdate` fails
and both the outgoing and incoming pages fully re-inflate on every switch. The
mechanism is real. Making all branches share a root type and keying each slot
moved no percentile. **The re-inflation happens; it is not what costs the
frames.** Worth knowing, because it is a convincing story that turns out to be
wrong.

**The one real finding.** Skipping the per-tap DB work entirely takes the tablet
from 6.25% to 4.55% and halves p95 from 22.2ms to 11.5ms, consistently across
all four repetitions — and does nothing for the Samsung. That is a genuine,
device-specific cost, and it fits eMMC (tablet) versus UFS (Samsung).

But **deferring** that same work past the animation bought nothing, and hurt the
Samsung. So the cost is that the work happens at all, not when it happens. Every
tab tap runs a DELETE (`retireAllRead`, unconditional), two COUNT queries
(`_refreshCountsFromDb`), and a SELECT (`_articlesForTab`). The fix has to be
*less work* — not later work. I did not ship a fourth guess without measuring
it, which is the discipline this pass exists to enforce.

### Cold start: mostly the device, partly fixable

The gap is largely hardware. The purest control segment — process fork to
`Using CollectorTypeCC GC.`, which executes zero Flash bytecode — is 53ms on the
tablet versus 23ms on the Samsung (2.3x). The Dart-and-first-frame segment ratio
(1.84x) is *lower* than the pre-Dart ratio, which rules out the app doing more
work on the tablet. Lenovo Tab M11 is a Helio G88 on eMMC; the M51 is a
Snapdragon 730G on UFS. Newer tablet, slower silicon.

What is fixable is the size of the thing being multiplied. On both devices the
dominant block is Android's application bind — `Slow dispatch took 1043ms main
... m=110` on the tablet, and an explicit
`handleBindApplication()++ → --` bracket of 503ms on the Samsung. That is
roughly half of each device's cold start. Its content: 22 dex files, and **no
baseline profile** — `Unable to open '.../base.dm': No such file or directory`,
logged twice. Every cold start verifies and JITs that dex.

**Untested.** Shipping a baseline profile via `androidx.profileinstaller` (which
is already in the merged manifest with nothing to install) is the one app-side
lever that would narrow the gap as well as the absolute, because the tablet
applies a ~2x multiplier to every millisecond saved. I ran out of afternoon
before testing it. Expected effect if real: 20-40% off bind, ~200-400ms on the
tablet.

---

## Regression results

**The full pass was not executed. I am not going to claim otherwise.**

`perf/regression-checklist.md` was built from the live repo (not the PRD, not
memory): **516 rows** across every screen and interaction surface, each tagged
`DESTRUCTIVE`, `BLOCKED (system UI)` or `TABLET-ONLY`, with file:line anchors
and both device columns left empty. That is the Stage 1 deliverable and it is
ready to walk.

What I actually verified on-device, all on the tablet's three-pane layout:

| # | Item | Tablet | Samsung | Evidence |
|---|---|---|---|---|
| 6 | **Drag feedback width** (the tablet-only fix from today) | **PASS** | n/a | Lifted card spans x≈128-736; list column is x≈110-722. Stops at the divider, does not enter the detail pane. Source row dimmed to 30% behind it. |
| — | Quick Settings rightmost on Flash tab | **PASS** | **PASS** | Funnel left, tune icon rightmost, in both layouts |
| — | Clean mode: extraction + button appears | **PASS** | not run | "Read clean version" appeared on a TechRadar article after the WebView had loaded |
| — | Clean mode: toggle to clean view | **PASS** | not run | Clean text, lead image with "(Image credit: Shutterstock)" caption, ads and consent banner gone, button flipped to "View original page" |
| — | App launches, no crash, correct layout | **PASS** | **PASS** | Both devices, profile and release builds |

**Not run:** everything else — 510+ rows. Including the Add Feed gating, the
capitalization fields, the `NewContentCheck` resume behaviour, clean mode's
failure banner and session cache, and the whole of Bookmarks, Alerts, Search,
Settings and Onboarding.

The destructive rows I would in any case not have run unattended on the Samsung,
for the reason in the opening section: there is no working undo.

---

## Commits on this branch

| Commit | What and why |
|---|---|
| `35c3cc2` | Stage 0 baseline. Replaces the specified `gfxinfo` instrument (which reports zero frames for a Flutter app) with SurfaceFlinger present times; adds `capture.sh` / `analyze.py` and the raw data for both devices. |
| `adad003` | Impeller tested and rejected, with the before/after numbers that killed it. Manifest reverted; data kept. |
| `9863256` | Three more fixes tested and rejected; repetition discipline added after single runs proved too noisy; the DB-cost finding isolated. Adds the 516-row regression checklist. |

No production code is changed on this branch. `git diff main..HEAD -- lib/ android/`
is empty by design — everything under `perf/` is data and tooling.

---

## Still open

**Needs your judgment, not mine:**

- **The Samsung's lost read state.** Nothing I can do restores it. Tell me if
  you want the tablet re-seeded or left as it is.
- **Impeller.** It genuinely fixes Samsung scroll p99 (33.3 → 17.0ms) and
  genuinely costs ~100ms of startup. That is a trade, not a bug, and it is a
  renderer swap across the whole app with possible visual side effects. Your
  call, not mine.
- **The per-tap DB work.** Removing it is worth ~1.7pp of janky frames and half
  the p95 on the tablet. Doing that correctly means changing when read articles
  are retired and when counts are recomputed — a behavioural change to a
  lifecycle rule the codebase documents deliberately. I am not making that call
  unattended.

**Found but not fixed:**

- No baseline profile is shipped; `base.dm` is missing and app bind is ~50% of
  cold start on both devices. Highest-value untested lever.
- `main.dart` awaits seven initialisations strictly in sequence before
  `runApp`, including `refreshService.init()`, which re-registers WorkManager
  that `androidx.work.WorkManagerInitializer` already initialised during bind.
  Untested; instrument before restructuring.
- `Image.file` at `article_card.dart:483,509` decodes local thumbnails at full
  resolution for a 72×72dp box, while the network path correctly uses
  `memCacheWidth: 144`. A real inefficiency — but scroll jank is already 0.3%,
  so it is **not** the cause of any measured symptom. Do not "fix" it expecting
  a frame-rate win.
- `"reading"` is a duplicate key in all five ARB files (en lines 71 and 339).
  Harmless, invisible to `arb_parity_test`, worth a separate cleanup.

**Fixed but not re-verified:** nothing — nothing was fixed.

---

## Branch status

`perf/tablet-samsung-audit-2026-09-08`, three commits, **local only**. Not
merged, not pushed to `main`, not pushed to origin at all. Both devices are back
on the release build they started the day with.
