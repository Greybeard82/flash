# Quiet Ink — design handoff

Consolidated decisions from mock batches 4–8. This is the decisions document:
frames live in the canvas files, but nothing here depends on opening them.

Section 6 answers `HANDOFF-quiet-ink.md`'s seven open questions and says which
ones stay open.

Two invariants everything below obeys:

- **The list never moves under the reader.** No element changes weight, size,
  line count or laid-out position on read — colour and layout-neutral filters
  only.
- **Teal is what you press; orange is a state of the article.** Every
  interactive mark is `primary` or `primaryContainer`. Red means broken.

---

## 1. New colour values and roles

Four new values in total, one new `FlashColors` role, one new theme entry. The
fourteen tokens and six category hues shipped as specified and are untouched.

### 1.1 `illustration` — new role

| brightness | value | note |
|---|---|---|
| light | `#C3CAC9` | new value |
| dark | `#3A4241` | new value |
| Newspaper | `#C3C2BF` | authored; see 6.6 |

Add alongside `placeholder`, with the same `copyWith` / `lerp` / `==` /
`hashCode` treatment and a `_fallbackFlashColors` entry (`mix(0.78)`).

Replaces five `onSurface.withValues(alpha: …)` sites that no ink level
describes, because an illustration is not text.

**Sites:** Categories empty-state glyph 64dp · Bookmarks empty-state glyph 48dp
· both keyword panels' empty glyph 48dp · the feed's "caught up" `done_all`
glyph · the ad row's AdChoices box border.

**Not** the missing-thumbnail letter (26dp) — that is a character, not a
drawing: `onSurfaceMuted`. **Not** `ArticleDetailPlaceholder`'s 44dp glyph,
which stays `onSurfaceMuted` with the sentence beside it; they read as one
object and splitting them across two roles is a distinction nobody can see.
**Not** sheet grabbers or the keyword row marker — see 6.1 and 6.4.

### 1.2 `inert` — dark value authored

| brightness | value | note |
|---|---|---|
| light | `#C3CAC9` | as already specified |
| dark | `#464E4D` | **new value, this document** |

Keep `inert` and `illustration` as separate roles even though they agree on one
hex in light. See 6.2.

### 1.3 Notification accent — one constant, no theme pair

```
#15868E
```

4.35:1 on `#FFFFFF` · 3.96:1 on `#1B1B1B` · 3.69:1 on the `#1F2223` shade card.

`Notification.color` is a single ARGB read in the system's process; there is no
light/dark pair to give it. `primary` light is 2.7:1 on a dark shade and dark is
1.8:1 on a light one, so a third value is required.

**Do not re-derive `#12787F`.** It measured 5.2:1 / 3.30:1 / **3.07:1** and was
rejected by David: a 0.07 margin against a surface we do not control — OEM
skins, One UI and Material You each draw the shade card differently — is not a
real margin, and since neither value is a palette token there was never a
fidelity case for the riskier one.

Tints the small icon only (`ic_stat_flash.xml`, shipped, unchanged). On Android
12+ the shade's app-name label takes the system's ink, not this constant, which
is why 3:1 is the applicable bar. See task 5.1.

### 1.4 Newspaper's ink levels, authored

| role | value | was |
|---|---|---|
| `onSurfaceMuted` | `#A1A09E` | `lerp(ink, paper, 0.62)` |
| `onSurfaceRead` | `#92928F` | `lerp(ink, paper, 0.55)` |
| `illustration` | `#C3C2BF` | `lerp(ink, paper, 0.78)` |

Exactly what the shipped lerps produce, so **this changes no pixel**. Approved
as values so a future edit to `_npPaper` cannot silently move newsprint's ink
hierarchy. Keep the lerp expressions if you prefer them readable; the point is
that the hexes are now specified. Nothing else in Newspaper changes.

### 1.5 Android res — four widget colours

| resource | from | to | token |
|---|---|---|---|
| `values/widget_unread_bg` | `#F2F1EE` | `#FFFFFF` | surface |
| `values/widget_unread_text` | `#E07A1F` | `#0F1413` | onSurface |
| `values-night/widget_unread_bg` | `#1D1D1B` | `#161D1C` | surfaceContainer |
| `values-night/widget_unread_text` | `#F2E9DC` | `#E7EBEA` | onSurface |

All four are existing Quiet Ink tokens — no new value. The shipped tile is
newsprint cream on a warm orange from the palette era, sitting beside a teal
app. **Radius stays 16dp and the count stays 28sp bold**; no layout edit is
needed for the colour change.

### 1.6 Orange, as meaning — canonical wording

The token table's old line ("unread dot only, nothing else") needed amending
twice after audits, because it was a list. State it as meaning, and as **two**
meanings rather than one strained metaphor:

- **Unread state** — the unread dot on a feed row; the Alerts `Badge.count` in
  the tablet sections column; the swipe-to-unread reveal (`secondary` @15%
  behind a `secondary` glyph, Bookmarks only).
- **Saved state** — the lower half of the action rail (`savedFill` under
  `onSavedFill`); the reader's bookmark glyph, filled, in `secondary`.

A saved article is *kept*, not pending, so "in your queue" never covered both.
Any future site is judged against these two meanings instead of amending a list.

**Neither meaning is faults.** Invalid-URL text and the stale-feed glyph are
`error`. Error's ramp is unchanged (`#BA1A1A` / `#FFB4AB`) and its scope is
inline validation, the stale-feed glyph, and the radial menu's Delete — never a
confirmation button.

### 1.7 One new theme entry: `segmentedButtonTheme`

Three SegmentedButtons ship (sort order in the filter bubble; theme and summary
length in Quick Settings), all stock M3 capsules at radius 20 — the only
capsules left beside r9 chips and r9 nav pills.

Height **40**, radius **9** outer / **0** between, 1dp `outlineVariant` border
and divider, selected `primaryContainer` under `onPrimaryContainer` at 13/w600,
unselected `onSurfaceVariant` at 13/w500, `showSelectedIcon: false`. One theme
entry, three surfaces fixed, no widget changes.

---

## 2. ARB changes

Three new keys, four changed values, two description-only fixes. **Every new or
changed value needs de, es, fr, it or the parity test fails.**

### 2.1 New keys

**`bookmarkRemoved`**

```
"bookmarkRemoved": "Bookmark removed"
```

Banner after unsaving in Bookmarks, where the row then leaves the list. Pairs
with the existing `alertsRemovedBanner`. No undo — it would need the row's index
and saved timestamp held after deletion, and re-saving from the reader is one
tap.

**`alertNotificationSummary`**

```
"alertNotificationSummary": "{count, plural, one{1 keyword alert} other{{count} keyword alerts}}"
```

The group summary's `setContentText` for the collapsed stack.
`alertNotificationTitle` cannot be reused there: it says one keyword matched
when several did.

**`adSponsored`**

```
"adSponsored": "Sponsored"
```

The in-feed ad's disclosure label. Rendered uppercase by style, not by string,
so locales with different casing rules are unaffected.

### 2.2 Changed values

| key | from | to |
|---|---|---|
| `noBookmarks` | `No bookmarks yet.\nLong-press any article to save it.` | `No bookmarks yet.\nTap the bookmark on any article to save it.` |
| `saved` | `Saved` | `Bookmarks` |
| `markAllRead` | `Mark all as read` | `Mark all read` |
| `keywordBlocklist` | `Keyword Blocklist` | `Keyword blocklist` |

- **`noBookmarks`** — saving has been one tap on the action rail since the rail
  split. Long-press still works; it is no longer the way in.
- **`saved`** — the saved place is "Bookmarks" everywhere: the icon is a
  bookmark and the nav label already says it in five locales, so this is the
  fewest changes and the only option where word and glyph agree. **One site to
  sanity-check on device:** this key is also the action rail's tooltip when an
  article *is* saved, where a place-noun reads slightly oddly against a state.
  If it grates, the fix is a separate tooltip key, not a retreat to "Saved" for
  the destination.
- **`markAllRead`** — matches `markAllReadConfirm`, whose value is unchanged.
  **Keep both keys** with identical text: different widgets read them, and the
  dialog's confirm button must not depend on the FAB's tooltip key. On the
  tablet both are visible at once in the sections column, which is what made the
  one-word difference worth fixing.
- **`keywordBlocklist`** — sentence case, matching `keywordAlerts`. Same widget,
  adjacent rows in the filter bubble, and nothing else in the app uses title
  case. German capitalises both anyway, so it is really a four-locale change.

### 2.3 Description-only — no translation

- `@alertsTab` calls Alerts "the pill that switches the feed list" — it is a
  bottom-nav destination with its own screen.
- `@swapSides` says "button in the tablet navigation bar" — `app.dart`
  deliberately styles it as one more entry in the 72dp sections column.

### 2.4 Swept and left alone

`restoreSuccess`'s "Pull to refresh." is **correct** — `RefreshIndicator` still
wraps the feed and Alerts. `markReadOnScrollSubtitle`, `showReadSubtitle`,
`cleanModeSettingSubtitle`, `refreshOnWifiOnlySubtitle`, `wholeWordSubtitle` and
`opmlSubtitle` all describe rules or outcomes rather than controls, so no
restyle can make them stale.

Minor, non-blocking: `manualOnly` has the value "Never" (key/value drift, not
user-visible), and `allTab` / `alertsFilterAll` are both "All" for two chip bars
that now render identically — keep both keys, but they must not drift.

---

## 3. Behaviour changes, apart from restyles

A restyle changes what a widget paints. These change what it does, what it
takes, or what the app writes — each needs a test, and several need a call site
threaded.

**B1 · The unread dot, with reserved space.** 5dp circle in `secondary`, leading
the meta line, 7dp before the favicon. **The 12dp is laid out whether or not the
dot paints** — on read it fades to transparent over `kReadDimDuration` and keeps
its space. Removing it would shift the meta line left mid-scroll, the same class
of bug as the read font-weight change. Pin the reserved width in a test.

**B2 · `isCurrent` on ArticleCard.** New `bool isCurrent = false`, painting the
row `surfaceContainer`. Default off, so phone and Bookmarks are byte-for-byte
unchanged; the tablet shell already knows which article the pane holds. **Not
`primaryContainer`** — the teal tint is already inside the row on the rail, and a
teal row makes the rail vanish and reads as pressed. The rail itself is
unchanged inside a current row.

**B3 · Chip count gets a semantics label.** Nothing in the ARB ever carried the
inline "(12)", so the chip redesign needed no copy — but a bare mono numeral
beside a label reads to TalkBack as two nodes, "Tech" then "twelve". Wrap the
chip in `Semantics(label: '$name, ${l10n.articlesCount(n)}')` and exclude the
numeral. Existing key, five locales already. Follow-up, not part of the chip
pass — the chips have shipped.

**B4 · Unsave banners.** One `NotificationBanner` with `bookmarkRemoved` when
the orange half is tapped in Bookmarks — the only place where the row it removes
is the only visible record of that decision.

**B5 · mark-all-read's confirm button leaves `error`.** `FilledButton` becomes
`primary` under `onPrimary`. The danger is carried by "You won't be able to undo
this", which the string already says. Stays a dialog, not a sheet — it is shared
by three screens.

**B6 · The in-feed ad row.** New widget: `surfaceContainer` container at radius
14 with a 1dp `outlineVariant` border, 28dp label bar with `adSponsored` at
11/w700/0.8 tracking in `onSurfaceVariant`, a 15dp AdChoices box at the far end,
and a 300×250 media slot — total **306dp**. Insertion: first no earlier than
index 8, one per 10 after, never directly under a day header, never last, never
two in a viewport. **No fill renders nothing at all** and the slot is not
retried in the same list. The ad's height must be known to the scroll
read-marking walk — see task 5.2.

**B7 · Grouped alert notifications get a summary.** Shared `groupKey` plus a
summary notification carrying `alertNotificationSummary`. The per-notification
ids stay minted from the sorted keyword set, so no two sets can collapse into
each other — that is the fix this must not undo.

**B8 · The unread notification is silent and ongoing**, in its own
`IMPORTANCE_LOW` channel — never sharing a channel with keyword alerts. One is a
number that changes constantly; the other is the thing the user asked to be
interrupted for.

**B9 · Widget count clamp and autosize.** Clamp to `999+` in the provider, and
add `android:autoSizeTextType="uniform"` with min 18sp / max 28sp to the
existing TextView: 64dp of usable width takes one to three digits at 28sp, and
"999+" settles near 20sp. Without the autosize the clamp alone ellipsises. **The
zero state stays as shipped** — `android:text="0"` is the widget-picker preview
and the pre-first-update value.

**B10 · The widget follows the OS theme, not the app's — accepted, not a bug.**
`RemoteViews` resolves `values-night/` against the system uiMode, so a
Dark-app / Light-OS user gets a light tile. It should match the launcher it sits
on, and someone in Newspaper mode should not get newsprint on their wallpaper.

### Restyles — same behaviour, new paint

- **Read-state ink:** title `onSurfaceRead`, source `onSurfaceVariant →
  onSurfaceMuted`, **timestamp unchanged** (already at the ink floor). The alpha
  allowlist is deleted; `_DimTransition` is untouched, because it acts on
  imagery and no ink role describes a photograph.
- **Timestamps** adopt the already-declared `kNumeralTimestampStyle` (12.5px
  mono, tabular).
- **Search results:** constant w600 with `onSurface → onSurfaceRead` and
  subtitle to `onSurfaceMuted` — removes the last weight-on-read and the last
  alpha ink in any list row.
- **Clean view** reads in Literata 17/1.62, with h3 moved off sans
  `titleMedium` to Literata 17/w700; captions stay sans.
- **Missing-thumbnail letter** to `onSurfaceMuted`.
- **Bookmarks' separator** becomes the feed's full-bleed hairline. Panel
  dividers stay inset — they are not article lists.
- **Categories' header delete icon** to `onSurfaceVariant`, so deleting a
  category does not rank equal to renaming it.
- **Four widget colours** (1.5).

---

## 4. Still a proposal, or still a guess

Nothing in sections 1–3 is in this list.

- **PROPOSAL · Reader bookmark + share.** Approved to draw; shipping as its own
  pass after the redesign. Bar becomes 4 × 48dp, leaving the title **160dp** at
  360dp; fallback is open-in-browser into an overflow, which buys it back to
  208dp — a device call. Needs both callbacks threaded from the phone route and
  the tablet pane, plus `SavedStateNotifier` so the glyph stays honest. **No new
  strings** — `bookmark`, `saved`, `share` exist and the tooltips must reuse
  those exact keys.
- **PROPOSAL · The radial menu's close button.** Its glyph is `error` today,
  painting "cancel this menu" in the same red as "delete this forever".
  Proposed: `onSurfaceVariant` on a neutral `surfaceContainerHighest` circle, no
  tint. Delete, in Alerts only, keeps `error`. Not in the locked set, but not
  ruled on either.
- **PROPOSAL · The ad's dark media well, `#1E2524` — a new value** I would
  rather not add. It exists only so a creative with a dark background still has
  a visible edge. To hold the line at zero new surface values, use `placeholder`
  `#262C2B` and accept a slightly brighter well.
- **DECLINED · The bolt in the widget tile** — on my own argument: an
  `ImageView` plus room taken from the count, to answer a question about the
  user's home screen rather than about this design. **DECLINED · Imageless feed
  rows** — post-launch idea only, not drawn: row height feeds the scroll
  read-marking walk, which is the code with the regression history.
- **STAND-IN · Every bolt glyph in every batch file is Material Symbols**
  standing in for the real mark. The app's mark is
  `assets/images/flash_bolt.svg` / `FlashBolt`, and natively
  `ic_stat_flash.xml`. Take the shape from those files, never from the frames.
  Same for thumbnails and hero images, which are flat gradients where a
  photograph goes.
- **NOT DRAWN · never mocked in any batch:** the onboarding screen and
  starter-pack picker, the add-feed / feed-search sheet, the Settings screen's
  four sections beyond Batch 3's treatment, the OPML and backup rows, the
  shimmer loading card, and the TV layout beyond the rail tier it shares. All
  inherit the theme and will look consistent, but none has been designed against
  its widget.
- **CORRECTED · two wrong claims of mine**, in case either is repeated from an
  older file: the tablet shell **does** exist in `app.dart` (I searched it
  badly), and landscape-only **is** enforced, in Kotlin, by
  `MainActivity.applyOrientationLock()` off `smallestScreenWidthDp`. Also:
  "cardTheme serves bubbles and sheets" is inaccurate — `bubble_panel.dart`
  hardcodes its own radius 20, which stays. And the filter bubble has **no**
  article-count control; the sliders were deleted and `article_limit` /
  `cleanup_age_days` now have no UI anywhere.

---

## 5. Four things the repo has to answer

**5.1 · Report what `flutter.minSdkVersion` actually resolves to.**
`build.gradle.kts` inherits it rather than pinning one. On API 30 and earlier,
`Notification.color` also tinted the shade's app name at ~12sp, where the bar is
4.5:1 and `#15868E`'s 3.96 / 3.69 does not clear it. Either that window is live
or it is moot — it should not stay unknown. If live, the answer is that old
shades get a slightly quiet app name, not that the token changes.

**5.2 · Confirm the day-header sum still balances once the ad row exists.**
`kDayHeaderHeight` is load-bearing because `FeedScreen._onScroll` walks row
heights to decide what has passed the viewport midpoint. A 306dp row the walk
does not know about puts every mark-read below it at the wrong offset,
compounding down the list.

**5.3 · Check `folder_tab_bar_test.dart` and `action_rail_test.dart` against
this document.** Both pin geometry the redesign has now settled. The rail
numbers here match what ships; the chip test pinned the old round pill and
should be updated to the 36dp / radius 9 / separate-numeral form rather than
deleted.

**5.4 · Portrait tablet has a deadline, not just a decision.** `CLAUDE.md`
records that the orientation lock stops working at **API 37**. "Decided, not
built" is fine until then; after it, a portrait tablet layout is mandatory and
nothing in these eight batches covers one. Worth a dated line in the PRD rather
than a comment in a Kotlin file.

---

## 6. Answers to `HANDOFF-quiet-ink.md`

### 6.1 Sheet grabbers — take `onSurfaceMuted`. No new role.

You are right that `illustration` would be wrong: a grabber stands in for
nothing. But it does not need a role of its own either, because the app already
has a drag affordance with an authored answer — **the tablet resize handle's
grip dots, which are `onSurfaceMuted` and read correctly at 3dp.** A 40×4 bar is
the same kind of mark at a different size, so it takes the same role.

All three sites — `article_summary_sheet.dart`, `feeds_screen.dart`,
`starter_pack_picker.dart` — become `onSurfaceMuted`.

This is deliberately **one step louder** than today's `onSurface` at 20%
(`#8A9391` against roughly `#CCCFCF` in light). A grabber is the only thing
telling a reader the sheet can be dragged, and a handle you cannot see is worse
than one that is slightly more present than fashion suggests. Rule for the
future: **drag affordances are `onSurfaceMuted`.**

Supersedes Batch 5's line offering `illustration` for the summary sheet handle.

### 6.2 `inert` dark — `#464E4D`. Two roles stay two roles.

Authored: light `#C3CAC9` (unchanged), **dark `#464E4D`** (new value).

It sits one step lighter than `illustration`'s `#3A4241` on purpose. An inert
control is *present but not acting*; a picture is *standing in for absent
content*. The control should read as slightly more there than the drawing, and
in light they agree on one hex only because `#C3CAC9` happens to suit both. Your
reasoning for keeping them separate is correct and this value is what makes it
visible rather than theoretical.

Contrast is ~2.2:1 and that is intended: WCAG exempts disabled controls from the
text minimum, and an inert glyph that met 4.5:1 would not read as inert.

### 6.3 A read search result — search follows the card.

Already ruled and drawn (Batch 6): constant **w600**, `onSurface →
onSurfaceRead`, subtitle `onSurfaceVariant → onSurfaceMuted`. This removes the
`isRead ? 0.5 : 1.0` alpha and the w600/w400 weight change, which was the last
weight-on-read in the app.

Your objection — that the card's answer depends on a three-level hierarchy a
search result does not have — is worth answering rather than waving off. **The
rule is elementwise, not a ranking.** Each element moves down its own scale, or
stays put; nothing depends on a timestamp existing beneath the title. A search
result has two of the three elements, so two of the three rules apply and the
third is simply unused.

### 6.4 The keyword row marker — `onSurfaceMuted`. Site closed.

Your suggestion, and it is better than mine. Batch 6 specified `illustration`
for that 20dp leading icon; **that line is superseded.** A repeated tick marking
rows in a list is furniture at list scale, not a picture, and at 20dp repeated
down a column `onSurfaceMuted` is right — slightly louder than today's 30%
alpha, which is the correct direction for a mark whose job is to be scannable.

Same role as 6.1, and the same rule behind it: repeated functional marks take
`onSurfaceMuted`; only things standing in for missing content take
`illustration`.

### 6.5 Disabled and inert — one role. Four sites close.

**They are the same statement.** "Nothing to act on" and "you cannot press this"
both mean *this control has no effect right now*, and a user cannot tell the
difference in the moment. Two roles here would be a distinction for the
codebase's benefit, not the reader's.

For `radial_menu.dart`:

| today | becomes |
|---|---|
| disabled circular wash, `accent` @8% | no wash — the circle's own `surfaceContainerHighest`, unmodified |
| disabled glyph, `onSurface` @30% | `inert` |
| disabled label, `onSurface` @30% | `inert` |
| enabled label, `onSurface` @80% | `onSurfaceVariant` |

The wash goes away rather than changing value: an 8% tint of an accent is a
surface treatment pretending to be a state, and with the glyph and label both on
`inert` it is carrying nothing. Dropping it also removes the one place a
*disabled* control still shows a trace of the interactive hue.

That closes all four alpha sites in that file, and with 6.1 and 6.4 it closes
every remaining alpha ink site outside `_DimTransition` — which is imagery and
stays.

### 6.6 Newspaper's derived values — authored, see 1.4.

`onSurfaceMuted` `#A1A09E`, `onSurfaceRead` `#92928F`, `illustration`
`#C3C2BF` — the values the 0.62 / 0.55 / 0.78 lerps already produce, so no
pixel moves. Authored so an edit to `_npPaper` cannot silently move the
hierarchy `flash_colors_resolution_test.dart` pins.

**`_fallbackFlashColors` stays computed.** I agree it matters less, and I would
go further: it *should* stay a computation. Its job is to be reasonable for a
theme nobody designed, and authoring values for it would imply a fourth theme
exists.

### 6.7 Verify on device — agreed, plus five more.

Your three, with the expected result restated so the check is unambiguous:

- **Feed → filter and quick-settings icons, no feeds added.** Present and greyed
  at `inert` — light `#C3CAC9`, dark `#464E4D` (6.2). Not absent.
- **Feed → caught up.** `done_all` glyph above "No new articles. You're all
  caught up.", in `illustration`.
- **Categories → a category header's delete icon.** `onSurfaceVariant` —
  neutral. The rename icon beside it stays teal.

Five more from batches 4–8, same reasoning — each is single-use, inside a screen
that needs a real database, or outside the app entirely:

- **Feed → mark-read-on-scroll across a wrapped title.** The unread dot must
  fade without the meta line shifting left, and no card below may jump (B1).
- **Feed → the ad row.** "SPONSORED" must not be mistakable for a source name,
  and the 300×250 slot must not push a day header into the wrong offset (5.2).
- **Notification shade, both OS themes.** Small icon tinted `#15868E`; the app
  name is the shade's own ink, not teal. Then collapse a group of four and check
  the summary reads "4 keyword alerts", not a single keyword's sentence.
- **Widget, both OS themes, and OS-theme-opposite-to-app.** Colours from 1.5;
  the light tile beside a dark app is expected, not a bug (B10).
- **Tablet → open an article.** The list row highlights `surfaceContainer`, the
  rail inside it is unchanged, and swapping sides mid-read does not reload the
  page (B2).
