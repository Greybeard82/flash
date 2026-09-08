# Pre-release pass — 2026-09-08

Branch: **`perf/tablet-samsung-audit-2026-09-08`** (main merged in, so it carries
today's refresh-settings and clean-mode work). Not merged to `main`.

**This brief was not completed.** Stages 1, 2a, 2d and 4 are done, Stage 5 is
this document, and Stages 2b, 2c and 3 are not done. What
follows says which is which rather than blurring them. Two of the gaps are
hard blockers, not pacing:

- **The Samsung was not connected at any point today.** Only the tablet
  (`HVA74XA0`) and the Pixel were. Every instruction saying "both devices"
  could only be half-answered, and the audit's Samsung baseline has nothing to
  compare against.
- **Stage 3 is 516 rows × 2 devices.** That is over a thousand executions, most
  needing visual confirmation. It is not a one-session task at any pace.

---

## Stage 1 — Extraction quality: done

Ten real pages from six publishers, saved as fixtures (gzipped, 1.3MB; the raw
HTML is 6.6MB and does not belong in a repo). Every symptom was reproduced on a
real page before being fixed, and re-measured on the same page after.

### Which publisher exposed which symptom

| Symptom | Exposed by | Not present on |
|---|---|---|
| Duplicate image | **The Verge** (both fixtures, one dupe src each) | TechRadar, BBC, IGN, Eurogamer, RPS |
| Author photo + bio | **TechRadar** (`author author__default-layout`, `slice-author-bio`) | — |
| Related-links rail | **TechRadar** (`popular-box`), **The Verge** ("Most Popular", "More in:"), **BBC** ("Related topics", "Get in touch", "More on this story") | — |

### Before → after, same pages

| fixture | blocks before | after | what went |
|---|---|---|---|
| techradar_a | 18 | **15** | author photo, author bio, related rail |
| techradar_b | 46 | **44** | author bio, related rail |
| verge_a | 15 (1 dupe) | **10** | dupe image, tag list, "More in:", "Most Popular" |
| verge_b | 12 (1 dupe) | **8** | same shape |
| bbc_a | 33 | **29** | "Get in touch", "Related topics", tag list |
| bbc_b | 30 | **27** | "Related topics", tag list, "More on this story" |
| eurogamer_a | 19 | **19** | unchanged — control |
| rps_a | 6 | **6** | unchanged — control |

The two unchanged fixtures are the point of the exercise, and their block counts
are now pinned by tests. These heuristics have deleted whole pages twice before.

### Judgement calls I made, for your review

**Two proposed terms were not added.** `\bprofile\b` occurs in none of the ten
fixtures, so there was nothing to validate it against, and it is the term most
likely to collide with an article that *is* a profile. `\bmeta\b` matched only
IGN's `meta-items`. Both are recorded in the source with the reasoning.

**The trailing trim takes the earliest match in the last 40%, not the latest.**
The proposal searched backwards and cut at the last recirculation heading. On
the BBC that is wrong: the page ends "Get in touch" → "Related topics" → tag
list → "Related internet links", and cutting at the last one strips a single
heading and leaves the other three. Earliest-in-window cuts all four.

**No fix helped one page and hurt another.** The controls are byte-identical
before and after.

### Found, not fixed

**Both IGN fixtures extract to null — and did before this change too.** IGN
ships an empty shell and hydrates client-side, the same shape as the Kotaku case
already documented in `extractFromHtml`. Clean mode's "not available" banner is
correct behaviour for those pages, not a bug. Pinned by a test so that if it
ever starts working, someone notices.

---

## Stage 2 — Performance

### 2a. Impeller: measured, and NOT shipped

**The approval rested on numbers that do not reproduce.** Re-measured with the
Stage 0 methodology at four repetitions instead of the audit's single run:

| tablet | baseline | Impeller |
|---|---|---|
| tab-switch jank | **6.25%** | **10.7%** |
| tab p99 | 33.3ms | **66.7ms** |
| scroll jank, warm | 0.3% | ~1.1% (no gain) |
| scroll, first launch after install | 0.3% | **24.3%** |
| cold start | 1944ms | **2139ms** (+195ms, not the +113 predicted) |

All three metrics are worse or unchanged on the tablet — the device the original
complaint was about. Tab jank nearly doubles.

The audit read tablet scroll as 0.5% from one capture. Repeating it four times
shows why that was unreliable: **the first launch after an install runs on a
cold Impeller pipeline cache and measures 24.3% janky**, settling to ~1.1% once
warm. The audit sampled near that transient.

That first-launch number is not only an artifact to discount. Every install and
every update pays it, and a visibly janky first scroll after an update is
something a user sees.

The Samsung half of the approval — scroll p99 33.3 → 17.0ms — is **unverified**,
because that device was not connected. Manifest left at `EnableImpeller=false`.
**This needs your call with the Samsung attached**; I was not willing to ship a
measured regression on all three tablet metrics into a release on the strength
of one unreproduced number.

### 2b. Baseline profile: not done, and the premise needs correcting

**A baseline profile is already shipped.** The release APK contains
`assets/dexopt/baseline.prof` (2267 bytes), `baseline.profm`, and the
`androidx.profileinstaller` marker. The audit's "`base.dm` is missing" came from
a logcat line about dex metadata delivered at *install* time, which is a
different mechanism from the runtime profile installer — so the conclusion
"nothing to install" was wrong.

What is true is that 2.2KB is essentially the default that arrives transitively,
not a profile generated from Flash's own startup path. Producing a useful one
needs an `androidx.benchmark` macrobenchmark module driving real user journeys
on a device, and `android/` contains only `app` — there is no benchmark module.
That is real setup work, not a flag flip, and I did not start it.

### 2c. `main.dart` init sequence: not done

Untouched. The brief's own instruction is instrument first, and I did not get to
the instrumentation, so there is nothing to report beyond what the audit already
said.

### 2d. Per-tap DB work: done, and it does not help

Implemented exactly as the brief specified — less work, not later work,
`retireAllRead` untouched, only how often the tab-tap path calls it.
`ArticleRepository.hasRetirableRead` is an indexed existence probe sharing
`retireAllRead`'s exact WHERE clause; `_flushRead` skips the transaction when it
returns false. Skipping a delete that would match nothing is unobservable, which
is what makes it safe.

**It did not move the numbers.** Tablet, four repetitions, same build except the
guard:

| | reps | median |
|---|---|---|
| control, no guard | 7.4 / 7.6 / 7.9 / 7.8 | **7.7%** |
| with guard | 8.2 / 7.6 / 7.3 / 6.9 | **7.45%** |

Overlapping ranges. Reported as a no-op, not a win.

**Why, and what would help.** The audit's 4.55%-vs-6.25% upper bound came from
skipping *all three* per-tap operations. This removes only the DELETE — and a
DELETE matching no rows is already nearly free. The remaining cost is
`_refreshCountsFromDb`'s two COUNTs and `_articlesForTab`'s SELECT, and neither
can be skipped without changing what the screen shows. That is where any further
work has to go.

**Verification the brief asked for, all covered by 12 tests:** read articles
still retire, unread articles are never deleted, bookmarked read articles
survive, tombstones are still written, `alert_matches` survives its article being
retired, and the probe agrees with the delete in every state including folder
scope.

Two of those corrected assumptions rather than confirming them. `alert_matches`
has no `article_id` and no foreign key to `articles` — it keeps its own
`feed_id`/`guid`/`title`/`url` copy, which is what lets an alert stay readable
after the article is gone. And a bookmarked article survives retirement *in the
table* while still being filtered out of `getAllArticles`, so that assertion had
to move to the table; asserting through the feed list would have passed for the
wrong reason.

**Keeping it is your call.** Strictly less work per tap and fully covered, but
not the fix for tab-switch jank.

### Methodology note: cross-session comparisons on this tablet are unreliable

The same-code control measured **7.7%** where the audit's stored baseline on the
same device measured **6.25%**. Nothing between them touches the tab path. The
tablet's article count swung between 81 and 6 and back across the day, and
article volume changes query cost. Only same-session, same-build controls are
trustworthy here — which is why 2d was re-measured against a fresh control
rather than against the stored baseline, and why the first Impeller comparison
in this pass had to be redone.

---

## Stage 3 — Full regression: not done

`perf/regression-checklist.md` still holds its 516 rows, and it is still
**out of date** — it predates the refresh-settings move and Stage 1's extraction
changes. Re-validating it was the brief's own first instruction for this stage
and has not happened.

Nothing from the checklist was walked today. What was verified on-device today
was the refresh-settings work in the previous session (five checks, all passing,
including `dumpsys jobscheduler` confirming both the interval and the
`NOT_METERED` constraint reaching the live registration).

**The mark-as-read-on-scroll instruction is important and stands unused.** In
this app scrolling is destructive; any future scrolling row must run with that
setting off. That is written down here so the next pass does not repeat the data
loss.

---

## Stage 4 — Housekeeping: done

**4a.** The duplicated `"reading"` key is gone from all five ARB files. Values
were identical in every locale. Kept the later occurrence, because in
`app_en.arb` that is the one carrying the `@reading` description, and keeping
the same position across all five keeps the files aligned.

**4b.** `fab-bubbles` and `palabre-parity` deleted from origin, and locally.
The gate ran first and passed cleanly:

```
origin/fab-bubbles      sha ddc84b8   unique commits vs main: 0   merged: YES
origin/palabre-parity   sha 062eead   unique commits vs main: 0   merged: YES
```

Both were fully reachable from `main`, so nothing was lost. SHAs recorded above
in case you ever want to recreate the refs.

---

## Commits on this branch

| Commit | What |
|---|---|
| `0e2810f` | Merge `main` so the branch carries the refresh-settings and clean-mode work |
| `b3e8274` | Stage 1 — image dedupe, `<picture>` recursion, recirculation vocabulary, trailing trim, 10 real fixtures, 34 tests |
| `c4d5b70` | Stage 4a — duplicate ARB key |
| `9add01e` | Stage 2a — Impeller measured and rejected, data kept, manifest unchanged |
| `01c33c0` | Stage 5 — first version of this report |
| `e233d1b` | Stage 2d — retire guard, 12 tests, measured as a no-op and reported as one |

Earlier audit commits (`35c3cc2`, `adad003`, `9863256`, `5d0e290`) are unchanged
beneath these.

**985 tests, `flutter analyze lib test` clean.**

---

## Needs your judgement

1. **Impeller.** Measured worse on every tablet metric. Approved on numbers that
   did not reproduce. Reconnect the Samsung and decide.
2. **`\bprofile\b` and `\bmeta\b`.** Left out for lack of a page to validate
   them against. If you have a profile-piece article in your feeds, that is the
   test case.
3. **Whether to keep the 2d guard at all.** It is correct and tested but buys nothing measurable. The remaining tab-switch cost is the two COUNTs and the SELECT.
4. **Whether the fixtures belong in the repo at all.** 1.3MB gzipped, and they
   go stale as publishers re-template. The alternative is fetching them in CI,
   which trades reproducibility for freshness.

## Ready to merge

Stages 1 and 4 are self-contained and green: extraction fixes with real-page
tests, and two pieces of housekeeping. Stage 2a changes no production code — it
adds measurement data and a commit message explaining why the approved change
was not taken.
