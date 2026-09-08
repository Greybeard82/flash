# Stage 3 — progress log

Per-session, because Stage 3 is explicitly a multi-session job. Newest session
at the top. Rows refer to `perf/regression-checklist.md`.

---

## Session 4 — 2026-09-08 (night)

### Counts by tier — MANUAL listed separately, never as unwalked

| Tier | Walked | Pass | Fail | MANUAL (David) | Remaining for me |
|---|---|---|---|---|---|
| 1 — today's changes | 11 | **11** | 0 | 5 (rows 1-5) | rows 6-9, 12-17, 19-26, 29-30, 487-513 |
| 2 — core flows | 0 | 0 | 0 | — | all |
| 3 — everything else | 0 | 0 | 0 | — | all |

Across the whole checklist, **50 rows** now carry `MANUAL`.

### Row 382 — regression found, fixed, tested, verified

Confirmed the mechanism in the code rather than inferring it:
`dismissTopBubblePanel()` has exactly three callers, all in `lib/app.dart`, and
`registerBackDismiss` feeds nothing else. `SettingsScreen` is a pushed route, so
its own pop answers back and the shell handler never runs — the interval menu's
registered handler was unreachable, and the first back press popped Settings with
the menu still open. A regression from the refresh-settings move: the widget was
relocated without accounting for a dismiss mechanism that only works inside the
app shell.

**Fix.** `RefreshIntervalField` now carries its own `PopScope`, in whatever
route hosts it, so it intercepts that route's pop while its menu is open.
`registerBackDismiss` is kept as well, so the widget still behaves correctly if
it is ever put back inside a bubble; the two are idempotent because `_closeMenu`
no-ops on an already-removed entry. `_menu` is now assigned through `setState`
because it drives `canPop`.

**Test** — `test/refresh_interval_back_test.dart`, 5 cases. The route is the
point: pumping the field as `home:` would pass against the broken build, because
there is no route to pop. Verified it discriminates by stashing the fix and
re-running: **2 of 5 fail on the pre-fix build**, both being the "must not pop
the hosting route" assertions. All 5 pass with the fix.

**On device, both:** open Settings → REFRESH → tap the interval row → one back
press. Menu closes, Settings stays. Second back returns to Flash, so the fix does
not trap anyone on the screen.

| | Tablet | Samsung |
|---|---|---|
| Back closes the menu, Settings stays open | **pass** | **pass** |
| Second back leaves Settings normally | **pass** | **pass** |

978 tests, analyze clean.

### Blocked rows retagged MANUAL

The 50 rows that need a surface outside Flash's own UI are now tagged `MANUAL`
rather than `BLOCKED (system UI)`, with the legend rewritten to say David walks
them and that they must be counted separately rather than read as unwalked. Rows
1-5 carry an explicit "Press:" note — Home, recents, or nothing in row 4's case,
which only inherits row 3's manual step.

### Standing items

- Mark-as-read-on-scroll is **still OFF on both devices**. Restore to ON when
  Stage 3 finishes. **Not yet done.**
- All four devices attached this session: tablet, Samsung, Pixel, emulator. The
  tablet dropped off adb briefly during the test run and came back on
  `adb reconnect`; no row was run while it was missing.

---

## Session 3 — 2026-09-08 (late)

### Counts by tier

| Tier | Walked | Pass | Fail | Blocked | Remaining |
|---|---|---|---|---|---|
| 1 — today's changes | 9 | **9** | 0 | 5 | rows 6-9, 12-17, 19-26, 29-30, 487-513 |
| 2 — core flows | 0 | 0 | 0 | 0 | all |
| 3 — everything else | 0 | 0 | 0 | 0 | all |

Both devices attached throughout; no row was run on only one.

### Checklist re-validation: LANDED and applied

The merge completed on the resumed run — only the trailing critic agent was cut
off, so this was not resumed a fourth time. The delta was taken from the workflow
journal and applied by hand.

7 rows rewritten in place (3, 18, 22, 24, 27, 290, 322), 7 relocated out of
"Quick Settings contents" and rewritten for the Settings screen (379-385), 27 new
rows added (487-513). **486 rows before, 513 after.**

### Rows walked this session

| Row | What | Tablet | Samsung |
|---|---|---|---|
| 10 | Add Feed: field disabled and no keyboard before a category is picked | **pass** | **pass** |
| 11 | Add Feed: chip selection enables the field, keyboard opens on tap | **pass** | **pass** |

Both were verified objectively rather than by eye: `dumpsys input_method` reports
`mInputShown=false` on opening the sheet and `mInputShown=true` after selecting a
chip and tapping the field, on each device. That is the autofocus removal in
`cf05ee1` doing exactly what it was meant to.

### Blocked, not skipped

Rows **1, 2, 3, 5** are tagged BLOCKED (system UI) — every one needs Home or
recents to background the app, which is outside Flash's own UI and therefore
outside what this session may drive. Row **4** reads the unread count
"immediately after row 3's resume", so it inherits the block.

That is the whole `NewContentCheck` resume block. It is the one part of tier 1
that cannot be walked from here at all and needs a human with the device in hand.

### Suspected regression, from the re-validation rather than a device

Row **382** predicts that the interval menu's back-press handler broke when the
picker moved out of the Quick Settings bubble in `5b81aa4` — my own change.
`registerBackDismiss` is only consulted by the shell's `PopScope` in `app.dart`,
which sits *below* a pushed Settings route, so the first back press probably pops
Settings instead of closing the menu. It worked in the bubble because the bubble
sat over the shell, and no code in the widget itself changed. Written as an
observation row, to be walked with row 509.

Also surfaced: `backgroundRefreshInterval` is now an orphan ARB key with no call
site in `lib/`.

---

## Session 2 — 2026-09-08 (evening)

### Counts by tier

| Tier | Walked | Pass | Fail | Remaining |
|---|---|---|---|---|
| 1 — today's changes | 7 | **7** | 0 | most of rows 1-30 + the new refresh rows |
| 2 — core flows | 0 | 0 | 0 | all |
| 3 — everything else | 0 | 0 | 0 | all |

Both devices attached for every row below, so none was run half.

### Passed, both devices

| Check | Tablet | Samsung | Evidence |
|---|---|---|---|
| Clean-mode button appears after background extraction | pass | pass | TechRadar article, FAB arrives after the page has loaded |
| **No trailing author photo, author bio or related rail** (Stage 1 fix) | pass | pass | Clean view ends on "Follow TechRadar on Google News…" and stops |
| Clean view renders images with captions, theme-driven colours | pass | pass | "(Image credit: Future)" / "(Image credit: Shutterstock / …)"; correct in the Samsung's dark+teal and the tablet's light+orange |
| Last paragraph clears the floating button (96dp inset) | pass | pass | Visible gap under the final paragraph on both |
| Quick Settings has no refresh control at all | pass | pass | Panel shows Theme / Summary / Palette / Newspaper / Mark-read / Confirm / Badge / More settings |
| Mark-as-read-on-scroll toggles and persists | pass | pass | Turned OFF on both, verified visually |
| Text column caps at 720dp and centres | pass | n/a | Tablet only — wide right margin in the detail pane |

The Samsung's run used **the exact `techradar_a` fixture page** — the PS3-emulator
article was live in its Tech tab — so the on-device result and the pinned test
assertion are about the same bytes. Before Stage 1 that page ended
`IMG P L5`: author portrait, author bio, `popular-box` rail. It now ends on prose.

### Not yet walked

The bulk of tier 1: the `NewContentCheck` resume rows (1-5), the feeds-screen
rows (6-14), app-bar order (15-17), the rest of clean mode (19-26, 29-30), and
every new refresh-settings row — those last ones do not exist yet, pending the
re-validation.

### Still in flight

Checklist re-validation. Resumed this session after last session's run was cut
off mid-merge; the three analysis passes are cached and complete, the merge is
running.

### Environment notes

- Emulator `Flash_Medium_Tablet` booted and ready for the fresh-install rows.
  Neither physical device will be wiped.
- Tablet unread has fallen to All (12) — consumed by the audit's perf scrolls
  earlier today, already reported. Samsung is at All (37) and recovering.

---

## Session 1 — 2026-09-08

### Done

**2d reverted.** `hasRetirableRead`, its call site in `_flushRead`, and its 12
tests are gone (279 lines). The finding is preserved in `perf/REPORT.md` under a
"do not re-propose this" heading, with the reason it can never work: the guard
removed only the DELETE, and a DELETE matching no rows never opens a write page.
The remaining per-tap cost is `_refreshCountsFromDb`'s two COUNTs and
`_articlesForTab`'s SELECT. Measurement data kept under `perf/reps/`.

**Impeller closed** in the report. Not to be re-measured with the Samsung.

**Both devices staged, and this time all three are connected:**

| device | serial | state |
|---|---|---|
| Lenovo Tab M11 | `HVA74XA0` | branch release build, awake |
| Galaxy M51 | `RF8N82VYG2D` | branch release build, awake |
| Pixel 11 Pro | `adb-67181FDKX00285…` | connected, not used for Stage 3 |

**Mark-as-read-on-scroll turned OFF on both devices**, before anything scrolled
— the lesson from the audit's data loss, applied rather than just written down.
Verified visually on each: tablet knob pale/left, Samsung knob grey/left.

> **Restore before finishing Stage 3:** it was **ON** on both devices to begin
> with. It must go back on, and the rows that test it directly must run with it
> on.

**Samsung data intact** after staging: All (37), Gaming (11), My News (4),
Tech (22). It has partly recovered from the audit's loss via background fetches.

**Incidental confirmation** (formally row 379's subject): Quick Settings on
*both* devices now shows Theme / AI Summary length / Colour palette / Newspaper
mode / Mark as read on scroll / Confirm mark all as read / Icon badge / More
settings — and **no refresh interval control at all**. Gone, not hidden.

### In flight

Checklist re-validation against the branch (refresh-settings move, extraction
fixes, 2d revert). Not yet applied to the checklist.

### Not started

Walking the rows. Deliberately not begun before the checklist is re-validated,
which was the brief's own first instruction for this stage.

### Notes for next session

- The checklist has **486** numbered rows, not 516.
- Rows already known stale: **3** (specifies a 15-minute interval, which no
  longer exists) and **379** (taps the interval field inside Quick Settings,
  which has moved). The re-validation is looking for the rest.
- Rows 18-30 cover clean reading mode and will need assertions added for the
  Stage 1 extraction fixes — no duplicate images, no trailing author bio or
  related rail.
- The 3-hour default is only observable on a **fresh install**; both devices
  carry a stored value, so that row needs a clean install or an emulator.
