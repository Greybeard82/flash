# Stage 3 — progress log

Per-session, because Stage 3 is explicitly a multi-session job. Newest session
at the top. Rows refer to `perf/regression-checklist.md`.

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
