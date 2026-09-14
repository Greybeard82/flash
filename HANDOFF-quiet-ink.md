# Quiet Ink — handoff

## Design questions: all closed

The seven open questions this file used to carry were answered in Design
section 6. Recorded here rather than deleted, because the reasoning is worth
more than the answer once someone is looking at the code and wondering why.

| | Question | Answer | Where it landed |
|---|---|---|---|
| 6.1 | Sheet grabbers had no role | `onSurfaceMuted`. Drag affordances take it, matching the resize grip that already did | 3 sites: summary sheet, feeds sheet, starter-pack picker |
| 6.2 | `inert` had no authored dark value | `#464E4D` — one step lighter than `illustration`, so the two differ visibly. ~2.2:1 is intended; WCAG exempts disabled controls | `app_theme.dart` |
| 6.3 | A read search result had no rule | Follows the card, elementwise | `search_screen.dart` |
| 6.4 | The keyword row tick was ornament | `onSurfaceMuted`. Batch 6's illustration line is superseded | `keyword_group_panel.dart` |
| 6.5 | Disabled vs inert | One role. The 8% wash goes away entirely rather than changing value | `radial_menu.dart` |
| 6.6 | Newspaper's derived values | Authored, no pixel moves. `_fallbackFlashColors` stays computed — authoring it would imply a fourth theme exists | `app_theme.dart` |

**The ink allowlist is empty.** `onSurface` at an alpha is no longer how this
app expresses ink, anywhere. `ink_roles_guard_test.dart` now polices a list
with nothing on it, which means the next entry is an argument rather than a
line.

The one thing still dimming by opacity is `_DimTransition` — a greyscale
matrix plus 0.4 opacity on the thumbnail and favicon. It never appeared on the
allowlist because it does not touch `onSurface`: it acts on imagery, and no ink
role describes a photograph.

### Two things inferred while applying section 6

- **The radial menu's enabled label.** 6.5 ruled on the disabled half of an
  enabled/disabled pair. The enabled half was ink at 80%, which is not a level
  the scale has, so it took `onSurfaceVariant` — it is a caption under an icon
  button. If that is wrong it is one line.
- **The search result's font weight.** 6.3 says "elementwise", and the card's
  rule is that a read title changes colour and *not* weight. So the search
  title now holds `w600` either way; it was dropping to `w400` when read, and
  lighter glyphs are narrower, so a title near the two-line wrap boundary
  reflowed the instant it was marked read. That is the bug
  `article_card_read_colour_test.dart` exists for, in a second list.

---

## Repo questions

Answered from the summary in David's message rather than the verbatim
questions: **`DESIGN-HANDOFF.md` is not in this repo** — the only handoff file
present is this one, which has no sections 5 or 6. If the wording differed,
these may answer slightly beside the point.

### 1. What `flutter.minSdkVersion` actually resolves to

**24** — Android 7.0 Nougat.

`android/app/build.gradle.kts:48` sets `minSdk = flutter.minSdkVersion`, which
is not defined in this repo. It comes from the Flutter SDK:
`flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:26`,
`val minSdkVersion: Int = 24`. The same file supplies `compileSdkVersion = 36`
(line 23) and `targetSdkVersion = 36` (line 34).

Confirmed on the device: `dumpsys package io.getflash.app` reports
`minSdk=24 targetSdk=36`.

**The part worth knowing:** none of these three are pinned in the repo. They
are Flutter SDK defaults, so upgrading Flutter can move the app's minSdk,
compileSdk and targetSdk without a single line changing here and without
anything in review showing it. If any of them matters — and targetSdk shortly
will, see question 4 — it should be a literal in `build.gradle.kts`, not an
inherited default.

### 2. The day-header sum versus the 306dp ad row

**There is no ad row.** `FeedRow` is a sealed class in
`lib/utils/day_grouping.dart` with exactly two subtypes, `DayHeaderRow` and
`ArticleRow`, and nothing in `lib/` mentions ads, AdMob or 306. The only trace
of ads anywhere is the untracked `app-ads.txt` at the repo root, which carries
a real AdMob publisher ID — so this is a question about what *will* happen, not
what does.

**What will happen is worse than a bad sum.** The read walk does not just
measure rows, it type-casts them. There are four unguarded casts:

| | |
|---|---|
| `feed_screen.dart:872` | `_rowHeight` — used by the read walk *and* the retirement planner |
| `feed_screen.dart:1117` | `_onScroll`'s accumulate loop |
| `feed_screen.dart:1685` | the three-column list builder |
| `feed_screen.dart:1830` | the phone list builder |

Each reads `if (row is DayHeaderRow) … ; final x = (row as ArticleRow)…`. A
third subtype does not produce a wrong offset — it throws a `TypeError`, in the
scroll listener, on every frame of a scroll.

So inserting a 306dp ad row is not a tuning problem. Before one can exist:

1. `_rowHeight` needs a branch returning the ad's height, the way it returns
   `kDayHeaderHeight` for a header.
2. `_onScroll` needs to `continue` past it, as it already does for headers —
   an ad is not something you can have read.
3. Both list builders need a case, or they throw at paint.

The header precedent is the model: a constant height, summed rather than
measured, and excluded from deciding the read cutoff. Note that a header is
36dp and an ad is 306 — roughly eight and a half headers — so an off-by-one in
the accumulate loop that is currently invisible would become a third of a
screen.

### 3. The two geometry tests

`action_rail_test.dart:38-39`:

```dart
const Size _cardSizeBefore = Size(1080, 92);
const Size _railSizeBefore = Size(40, 72);
```

**They are not the same kind of assertion, and only one of them is sound.**

`_railSizeBefore` is a genuine invariant. The rail is literally
`SizedBox(width: 40, height: 72)` in `article_card.dart`, and the test asserts
the two halves still sum to it. It will only fail if someone changes the rail,
which is exactly when it should.

`_cardSizeBefore` is a **snapshot, and it will go stale.** The card's height is
not declared anywhere — it falls out of the title's font, line height, the
`maxLines: 3` cap, and the row padding. 92 was measured on the pre-pass-3 card
under `flutter_test`'s substitute font, where every glyph is a square of the
font size. It is not the height the card has on a phone.

That makes it a tripwire with a misleading label: it fires on any typography
change, reporting "the card's outer geometry changed" when what changed was a
font. It did its job for pass 3, whose whole claim was that the card did not
move — but as a standing assertion it is a future false positive, and the
honest fix is either to delete it now that pass 3 has landed, or to compare two
cards against each other in one run rather than against a number from a
previous one.

Recommend the latter: assert `saved` and `unsaved` cards are the same size,
which is the real claim and survives a font change.

### 4. The API 37 date on portrait tablet

**August 2027**, and it is the same release that forces the issue.

Android 17 is API 37 and shipped 16 June 2026 — your Pixel is already running
it. Google's official Play target-API page carried no API 37 deadline as of
15 July 2026, but Miguel Montemayor (Developer Relations Engineer, Android)
stated in February 2026 that new apps and updates will be required to target
API 37 for Play distribution in **August 2027**.

That is roughly eleven months out.

**Why it lands on portrait tablet specifically.** `CLAUDE.md` records that the
tablet landscape lock survives on Android 16 only because of
`PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`, and that the property stops
working at API 37. The Android 17 change list confirms the mechanism: adaptive
UI enforcement on large screens becomes mandatory, and tablets and foldables
can no longer opt out of resizability.

So the sequence is forced:

- **Now → Aug 2027.** `targetSdk = 36` keeps the lock. Nothing breaks.
- **At `targetSdk = 37`.** The Lenovo Tab M11 can be rotated into portrait and
  the app must render something. Today that falls back to the rail tier, which
  the PRD calls "decided, not built".
- **From Aug 2027.** Play will not accept updates at `targetSdk = 36`.

A portrait tablet layout therefore has to exist before the app can ship an
update after August 2027. It is not urgent this month, but it is the one
deadline in this list that cannot be renegotiated, and it is a layout job
rather than a colour one.

Related to question 1: `targetSdk` is currently an inherited Flutter default.
When Flutter's default moves to 37, this app will target 37 **without anyone
editing this repo** — and the tablet lock will break in a build nobody
associated with a layout change. Pinning `targetSdk = 36` explicitly in
`build.gradle.kts` would turn that into a deliberate act.

Sources: [Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) ·
[Meet Google Play's target API level requirement](https://developer.android.com/google/play/requirements/target-sdk) ·
[Android 17 API 37 behaviour changes](https://ecorpit.com/android-17-api-37-behavior-changes-migration-guide-2026/)

---

## Verify on device

Changes with no widget test, by decision: single-use, and living inside screens
that need a database on a real isolate before they render a row. Extracting
them purely to make a harness happy would shape the codebase around the tests
rather than the design. The real fix is a test seam for those screens, which is
a post-launch job.

- **Feed, no feeds added** — filter and quick-settings icons present and greyed
  at `inert`, not absent.
- **Feed, caught up** — `done_all` glyph above "No new articles. You're all
  caught up.", in the `illustration` grey.
- **Categories, a category header** — delete icon neutral `onSurfaceVariant`;
  the rename icon beside it still teal.
- **Any bottom sheet** — the grabber at the top should be a visible mid-grey
  (`onSurfaceMuted`), noticeably darker than it was at 20% ink.
- **Search, a read result** — title greys but does **not** get thinner, and the
  row must not reflow when an article is marked read.
- **Radial menu, a disabled action** — the faint disc behind the glyph is gone;
  the glyph alone carries the disabled state.
- **Bottom nav** — at your normal font size, and again with Android's font size
  turned up. The label should get bigger, not stay put.
