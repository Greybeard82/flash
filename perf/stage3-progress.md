# Stage 3 — progress log

Per-session, because Stage 3 is explicitly a multi-session job. Newest session
at the top. Rows refer to `perf/regression-checklist.md`.

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
