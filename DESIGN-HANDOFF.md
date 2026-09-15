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

> **Both halves of 5.1, recorded together because either alone misleads.**
>
> 1. `flutter.minSdkVersion` resolves to **24**, so the API<=30 window
>    where `Notification.color` also tints the app name **is live**. The
>    app installs on Android 7.0 through 11.
> 2. **Nothing sets `Notification.color` anywhere.** Neither
>    `AndroidNotificationDetails` passes a `color:`, and `#15868E` appears
>    in no file under `lib/` or `android/`. The constant is orphaned, not
>    at risk.
>
> Reading (1) alone says there is a contrast problem on old shades; reading
> (2) alone says the question is closed. Together: the question is real and
> unarrived. **Pass 9 is where it gets a consumer**, and that is the moment
> the 4.5:1 on a ~12sp app name stops being hypothetical. The answer then
> is that old shades get a slightly quiet app name, not that the token
> moves.

### 1.4 Newspaper's ink levels, authored

| role | value | was |
|---|---|---|
| `onSurfaceMuted` | `#A1A09E` | `lerp(ink, paper, 0.62)` |
| `onSurfaceRead` | `#92928F` | `lerp(ink, paper, 0.55)` |
| `illustration` | `#C3C2BF` | `lerp(ink, paper, 0.78)` |

> **SUPERSEDED for the two ink levels.** The table above is kept as the record
> of what was decided and why it was wrong.
>
> `onSurfaceMuted` and `onSurfaceRead` are now **`#686765` (lerp 0.35, 5.00:1)**
> and **`#5D5D5A` (lerp 0.30, 5.85:1)**. `illustration` is unchanged at 0.78 —
> it is decoration, not text.
>
> The 0.62 / 0.55 pair was chosen to correct an inverted hierarchy, checked
> against each other and never against paper. It put body text at **2.31:1 and
> 2.76:1**, where 4.5 is the bar. For scale, the value it replaced — `onSurface`
> at 0.6 alpha, before Quiet Ink — was lerp 0.40 and **4.27:1**, so the pair
> was a regression against what already shipped, and the correction lands
> slightly above it rather than merely back at it. The 0.62 pair never shipped;
> it existed only on this branch.
>
> **The "changes no pixel" guarantee is deleted from the comment, and that is
> the lesson rather than the footnote.** It was true. It was also the reason
> nobody looked: a promise that nothing moved is a promise that nothing was
> examined, and it is exactly the kind of reassurance that ends a review.
> `flash_colors_resolution_test.dart` now asserts every ink role that carries
> text clears 4.5:1 against its own theme's surface — a ratio against a
> surface, not a comparison between two roles, because comparing the two roles
> is what produced this. Mutation-tested: restoring the old pair fails with
> 2.31 and 2.76 named.
>
> **It flags two Quiet Ink light roles as known exceptions**, not one:
> `onSurfaceMuted` at **3.15:1** and `onSurfaceRead` at **3.99:1**. Both are
> Design's authored values and both are deliberate — a timestamp and a read
> headline are meant to recede. They are pinned to their measured ratios rather
> than excluded, so drift in either direction fails.

Approved as values so a future edit to `_npPaper` cannot silently move
newsprint's ink hierarchy. Keep the lerp expressions if you prefer them
readable; the point is that the hexes are now specified. Nothing else in
Newspaper changes.

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

> **SUPERSEDED for the action rail’s saved state.** The two meanings
> above stand; the rail is no longer painted the way this row describes.
> The row is kept as the record of what was decided.
>
> **The rail’s lower half no longer fills.** It is
> `primaryContainer` in both states, and the saved signal is the glyph:
> `bookmark_border_rounded` in `onSurfaceVariant` unsaved,
> `bookmark_rounded` in **`secondary`** saved. `savedFill` and
> `onSavedFill` are consequently unpainted — see below.
>
> Design 2a justified the fill by feed-scannability: a saved article
> should be findable down the column. That is the Bookmarks
> destination’s entire job, one tap from every screen, so the feed was
> carrying a solid orange block on every saved row to duplicate a screen
> that already exists — on the quietest surface in the app, and against
> both of the rules 1.6 sets out.
>
> **The shape swap is load-bearing now and must not be tidied away.**
> Outline-to-solid was decoration on top of a colour change while the
> fill existed. With the fill gone it is one of exactly two things
> separating the states; removing it would leave a colour-only
> distinction.
>
> **Contrast.** A glyph is a graphical object, so the bar is WCAG
> 1.4.11’s 3:1, not the 4.5:1 `summary_button_contrast_test.dart`
> holds the summary glyph to — the two halves of one control now
> answer to different bars, which is deliberate: the summary glyph’s
> colour is the whole of its identity, and this one also changes shape.
> Measured, `secondary` on `primaryContainer`:
>
>   | theme | ratio | headroom over 3:1 |
>   |---|---|---|
>   | Quiet Ink light | **3.36:1** | 0.36 |
>   | Quiet Ink dark | **6.88:1** | 3.88 |
>   | Newspaper | **5.97:1** | 2.97 |
>
> Light is the near thing and is pinned to its measured value, not just
> to the threshold. It replaced a pair that measured **4.12:1 against a
> 4.5 bar** — white `onSecondary` on the orange — which was a
> recorded shortfall, so the treatment moved from under one bar to over
> a lower one. Both facts belong in the record.
>
> **Newspaper is red, and it had to be.** `secondary` there is `_npRed`
> at 5.97:1. The alternative considered was `_npInk`, which is not
> viable rather than merely worse: Newspaper’s `onSurfaceVariant` —
> the unsaved glyph — is `#1D1D1B`, and `_npInk` is the same
> `#1D1D1B`. An ink saved glyph would be pixel-identical to an unsaved
> one, leaving the shape swap as the sole signal. Red is the only
> colour Newspaper has to carry a state with, and a small glyph shown
> only when saved is a different proposition from the solid red block
> that was rejected.
>
> **Transition unchanged.** The glyph colour already cross-faded over
> `kReadDimDuration` through the same `TweenAnimationBuilder` the fill
> used, so the tempo carried over with no edit.
>
> **Two roles are now unpainted:** `savedFill` and `onSavedFill` have no
> call site in `lib/` — the same condition 7.7 found `alertsFilterAll`
> in. They are still declared, still lerped, still compared in
> `FlashColors`, and three tests still assert their values. Reported,
> not deleted: the judgement about whether a role is worth keeping for a
> future consumer is not one to make inside a correction pass.

**Neither meaning is faults.** Invalid-URL text and the stale-feed glyph are
`error`. Error's ramp is unchanged (`#BA1A1A` / `#FFB4AB`) and its scope is
inline validation, the stale-feed glyph, and the radial menu's Delete — never a
confirmation button.

### 1.7 One new theme entry: `segmentedButtonTheme`

Three SegmentedButtons ship (sort order in the filter bubble; theme and summary
length in Quick Settings), all stock M3 capsules at radius 20 — the only
capsules left beside r9 chips and **r14** nav pills.

> **Corrected from the code.** This said "r9 nav pills". The pill is r14
> (`flash_bottom_nav.dart`, `pillRadius = 14`), which is the value the mock's
> own markup gave and what ships. The chip half is right: `folder_tab_bar.dart`
> is r9. Documentation error only — no code change.

Height **40**, radius **9** outer / **0** between, 1dp `outlineVariant` border
and divider, selected `primaryContainer` under `onPrimaryContainer` at 13/w600,
unselected `onSurfaceVariant` at 13/w500, `showSelectedIcon: false`. One theme
entry, three surfaces fixed, no widget changes.

> **SUPERSEDED for the height. It stays at 48.** The rest of the row is
> shipped as written; the line is kept as the record of what was asked
> for.
>
> **A decision reversed on the spec, not a miss.** 1.7 names a visual
> height and does not address touch targets, and on this widget the two
> are the same number: the segment paints at 48 rather than wearing a
> 40dp body inside a tap halo, because `_SegmentedButtonRenderObject`
> lays every segment out at a uniform tight height and Material’s tap
> padding ends up inside the paint. Reaching 40 means `tapTargetSize:
> shrinkWrap` or a negative `visualDensity`, and both take the target
> down with the paint.
>
> This app has gone under 48 exactly twice — the 36dp folder chip and
> the 36dp rail halves — each with an explicit sign-off and each time
> because the shape itself was the design. Here the 40 is a number on a
> low-frequency control in Settings and a bubble. It does not earn a
> third exception.
>
> Pinned at the real 48 in `segmented_button_theme_test.dart` so the gap
> is visible rather than implied, and so applying it later has to be a
> deliberate edit there.

---

## 2. ARB changes

Three new keys, four changed values, two description-only fixes. **Every new or
changed value needs de, es, fr, it** — but see the limitation below, because
the test does not enforce the second half.

> **KNOWN LIMITATION, not fixed before launch.** `arb_parity_test.dart`
> enforces **key** parity, not **value** freshness. A key missing from a locale
> fails (`:78-88`). But the only value-level check (`:90-102`) fails when the
> English and translated strings are *identical* — so changing an English value
> while leaving the four translations stale passes silently, and changing it
> makes that collision **less** likely, never more.
>
> So for the four changed values in 2.2, no de/es/fr/it edit is required for
> the suite to stay green. Re-translating them is still right; the test just is
> not what will catch it. David writes all five languages himself and will
> catch it there. Recorded rather than fixed.

### 2.1 New keys

**`bookmarkRemoved`**

```
"bookmarkRemoved": "Bookmark removed"
```

Banner after unsaving in Bookmarks, where the row then leaves the list. Pairs
with the existing `alertsRemovedBanner`. No undo — it would need the row's index
and saved timestamp held after deletion, and re-saving from the reader is one
tap.

> **SUPERSEDED for the English value.** The block above is kept as the
> record of what was specified.
>
> English is **"Removed from Bookmarks"**, not "Bookmark removed". The
> four other locales were written first and independently converged on
> "Removed from &lt;place&gt;" — `Aus Gespeichert entfernt`,
> `Eliminado de Guardados`, `Retiré des enregistrés`,
> `Rimosso dai salvati` — because **none of them has a bookmark noun**
> to build a state out of, only the verb *save* (see 7.10). English does
> have the place noun, in its own nav label, so writing it as a state
> would have made English the only locale describing a condition where
> the other four describe a location. The row leaves the list; the
> string says so. The four locale values are unchanged.

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

> **SUPERSEDED. `saved` stays "Saved" in all five locales.** The row and
> the reasoning above are kept as the record of what was decided and why
> it was wrong.
>
> **The premise is false.** This row justifies the change by saying the
> nav label already uses this key in five locales. It does not. The nav
> label is `bookmarks` — `app.dart:354`, `:1329`, `:1566` and
> `bookmarks_screen.dart:200` — a different key, which has read
> "Bookmarks" in English all along. So the change achieves nothing for
> the destination it was argued for.
>
> What it would have done instead is put a place-noun on two **state**
> labels. `l10n.saved` has exactly two call sites and both describe one
> article’s condition: the action rail’s tooltip
> (`article_card.dart:871`), which this row flags, and the radial
> menu’s **visible label** (`radial_menu.dart:244`), which it misses
> entirely — a rendered label rather than a tooltip, and
> unconditionally visible on long-press.
>
> And in the four other locales it would have been a grammar error. They
> have no bookmark noun (7.10), so the only "same direction" edit
> available is singular → plural — "Guardados" against a single
> saved article — at two sites that each describe exactly one.
>
> The tooltip was confirmed reachable on device before the revert (7.11),
> so the concern the row raises was real. It was the fix that was wrong.
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
read-marking walk — see task 5.2, **which is a prerequisite: `FeedRow` is
sealed and four unguarded casts throw on a third subtype. Those come first,
before any ad widget exists.**

**B7 · Grouped alert notifications get a summary.** Shared `groupKey` plus a
summary notification carrying `alertNotificationSummary`. The per-notification
ids stay minted from the sorted keyword set, so no two sets can collapse into
each other — that is the fix this must not undo.

**B8 · The unread notification is silent**, in its own `IMPORTANCE_LOW`
channel — never sharing a channel with keyword alerts. One is a number that
changes constantly; the other is the thing the user asked to be interrupted
for.

> **Not ongoing. `ongoing: false` stays, and this note exists so it is not
> re-proposed.** B8 asked for "silent and ongoing"; the channel half was right
> and the ongoing half reverses a considered decision that predates this
> document. `unread_badge_service.dart` already says why, quoted in full so the
> reasoning travels with the ruling:
>
> > ```
> > // Not ongoing. An un-dismissible notification for a count the user
> > // may not care about right now is worse than one they can swipe
> > // away; it comes back on the next count change either way.
> > ongoing: false,
> > ```
>
> An unread count the user cannot dismiss is hostile, and it returns on the
> next count change regardless, so the un-dismissible version buys nothing.

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

  > **Resolved, and it was not the no-op it looked like.** Both were already
  > identical at `indent: 16, endIndent: 16`, so "becomes the feed's" changed
  > nothing — but the feed's own hairline was specified full-bleed two batches
  > earlier, and had drifted. **Bookmarks was matching a feed that was itself
  > wrong.** Five dividers moved, not one: the feed's two, Bookmarks, search
  > and Alerts, all of which separate article rows. The three panel dividers
  > stay inset. `divider_scope_test.dart` guards both directions, because a
  > later sweep making every divider full-bleed would satisfy the first half
  > and break the second.
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

  > **Clarified, because that sentence reads two ways.** "Delete, in Alerts
  > only, keeps `error`" is about **the radial menu's Delete** — the
  > subject of the bullet it sits in, and the only Delete `app_theme.dart`
  > blesses by name among error's three jobs. "In Alerts only" describes
  > when that button exists, not a scope being introduced.
  >
  > It does **not** reach an `IconButton` in a panel. Pass 7 moved the
  > keyword alerts and blocklist bins to `onSurfaceVariant` on that reading,
  > matching the Categories header restyle in section 3, and
  > `pass7_sweep_test.dart` guards it with the radial menu as the one named
  > exemption. Recorded so the next person does not re-red a bin.
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

> **ANSWERED, and the question closes for a reason neither branch
> anticipated.**
>
> `flutter.minSdkVersion` resolves to **24** — Flutter 3.41.6,
> `FlutterExtension.kt:26`. `build.gradle.kts` no longer inherits it: the
> SDK pinning commit wrote `minSdk = 24` out explicitly, so the value is
> unchanged and is now visible in review. **The API≤ 30 window is
> therefore live** — the app installs on Android 7.0 through 11.
>
> But it is moot anyway, and not because of an API level: **nothing sets
> `Notification.color` at all.** Neither `AndroidNotificationDetails` —
> `refresh_service.dart:176` for keyword alerts, `unread_badge_service
> .dart:215` for the count — passes a `color:`, and `#15868E` appears
> nowhere in `lib/` or `android/`. The constant has no consumer yet, so
> the system draws both the small icon and the app name in its own ink on
> every API level.
>
> So the conclusion stands as 1.3 wrote it, just further off: when the
> constant IS wired, old shades get a slightly quiet app name at ~12sp,
> and that is the cost of the value rather than a reason to move it. It
> is a fact about Android 7–11, not a fact about `#15868E`.
>
> **This question is closed.** The open item it leaves behind is a
> different one and belongs to whoever wires the accent: there is no
> notification colour in the app today.

**5.2 · Confirm the day-header sum still balances once the ad row exists.**
`kDayHeaderHeight` is load-bearing because `FeedScreen._onScroll` walks row
heights to decide what has passed the viewport midpoint. A 306dp row the walk
does not know about puts every mark-read below it at the wrong offset,
compounding down the list.

> **ANSWERED, and it is a prerequisite rather than a caveat.**
>
> Two corrections to the question first. The walk uses the viewport **top**,
> not the midpoint — `final offset = _scrollController.offset` at
> `feed_screen.dart:1102`, with the code's own comment at `:1106` reading "a
> guessed row puts the viewport top at the wrong article". The consequence is
> as described; the threshold is not.
>
> And the sum does not go out of balance, because **the walk never runs.**
> `FeedRow` is a `sealed class` with exactly two subtypes, `DayHeaderRow` and
> `ArticleRow` (`lib/utils/day_grouping.dart:17-35`). Every consumer branches
> on the header and then *casts* everything else:
>
> | | |
> |---|---|
> | `feed_screen.dart:872` | `_rowHeight` — used by the read walk **and** the retirement planner |
> | `feed_screen.dart:1117` | `_onScroll`'s accumulate loop |
> | `feed_screen.dart:1685` | the three-column list builder |
> | `feed_screen.dart:1830` | the phone list builder |
>
> Each reads `if (row is DayHeaderRow) … ; final x = (row as ArticleRow)…`. A
> third subtype does not mis-measure — it throws a `TypeError`, in the scroll
> listener, on every frame of a scroll, and at paint in both list builders.
>
> **So B6 has three prerequisites before any ad widget exists:**
>
> 1. **Open the sealed type.** Add `AdRow` to `day_grouping.dart`. Being
>    `sealed`, this turns all four sites into non-exhaustive-switch problems
>    the analyser can point at, which is the good version of this — do it
>    first so the compiler enumerates the work rather than a scroll gesture.
> 2. **Give `_rowHeight` a branch** returning the ad's height as a constant,
>    exactly as it returns `kDayHeaderHeight`. An ad is not measurable from a
>    `_cardKeys` entry, because it has no article id.
> 3. **`continue` past it in `_onScroll`**, as headers already do. An ad is
>    not something a reader can have read, so it must contribute height
>    without ever deciding the cutoff.
>
> The header is the working precedent for all three. Note the scale difference
> though: a header is 36dp and the ad is 306, roughly eight and a half headers,
> so an off-by-one in the accumulate loop that is invisible today becomes a
> third of a screen.
>
> The scroll and retirement code has a documented regression history, which is
> why this is listed as a prerequisite: the ad row is a change to the read
> walk that happens to have a widget attached, not a widget that happens to
> sit in a list.

**5.3 · Check `folder_tab_bar_test.dart` and `action_rail_test.dart` against
this document.** Both pin geometry the redesign has now settled. The rail
numbers here match what ships; the chip test pinned the old round pill and
should be updated to the 36dp / radius 9 / separate-numeral form rather than
deleted.

> **ANSWERED — both were already done, in earlier passes.**
>
> `folder_tab_bar_test.dart` was rewritten for the chip redesign, not
> deleted: `kChipHeight = 36`, `kChipRadius = 9`, a whole group named
> "the count is its own numeral now", and a per-theme test reading
> "corners are 9dp, not a full pill". The r999 pill it warns about is
> gone from the file and from the widget.
>
> `action_rail_test.dart` was updated twice since — once when the
> saved fill was removed, once when its tooltip finders stopped carrying
> English literals.
>
> Pass 7 added six tests to the chip file for B3 rather than changing
> any geometry. Nothing in 5.3 was outstanding.

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

> **See the superseded block in 1.4.** The two ink levels moved again after
> this was written, because authoring them at 0.62 / 0.55 preserved a contrast
> regression rather than a correct value. They are 0.35 and 0.30 now.

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

---

## 6.8 Newspaper renders Quiet Ink's category hues — PARKED, awaiting values

**Known, reproduced, and deliberately not fixed.** Design is speccing a
monochrome treatment; this is recorded so it is not "fixed" into something
else in the meantime.

The mechanism: `_flashColorsNewspaper` declares `brightness: Brightness.light`,
and `FlashColors.category(int)` forwards that straight to
`categoryPalette(colorIndex, brightness)`. The hue table in
`category_colors.dart` has only light and dark columns, so Newspaper gets the
light column — Quiet Ink's six tinted chips, on newsprint.

Visible wherever a category hue is painted, which since the chip rewrite means
the folder chip bar on every screen with one.

Not fixed because the fix is a value decision, not a code one: a monochrome
Newspaper needs six values (or a rule that collapses all six to one), and
inventing them to close a visual bug would be exactly the kind of guess the
rest of this document exists to avoid.

---

## 7. Corrections from the code (added by implementation)

Findings from cross-checking every claim in this document against `lib/`. Each
is a place the document and the code disagree; none is blocking.

**Rulings applied.** 7.1 stands, arbitrated below. 7.2's `outlineVariant` and
7.4's badge colour are fixed in code. 7.5 is a documentation error, corrected
in 1.7. 7.6 and the `ongoing` half of 7.8 are recorded as limitations in place.
7.7's dead key is deleted.

### 7.1 Newspaper `illustration` is `#C3C2C0`, not `#C3C2BF`

Printed as `#C3C2BF` in 1.1, 1.4 and 6.6, under the guarantee that authoring
these values **changes no pixel**. Those two statements disagree by one unit of
blue, and the document settles it against itself.

On the blue channel, `lerp(_npInk, _npPaper, t)` gives:

| t | exact | rounded | truncated | document |
|---|---|---|---|---|
| 0.62 | 157.82 | `9E` | `9D` | `9E` — **rounded** |
| 0.55 | 143.05 | `8F` | `8F` | `8F` — rounded |
| 0.78 | 191.58 | `C0` | `BF` | `BF` — **truncated** |

Two of the three are rounded; only this one is not. One value converted the
other way from its neighbours, under a promise of no pixel change, reads as a
transcription slip rather than an override — so **the code keeps `#C3C2C0`**
and the document is the thing to correct. **Arbitrated.** The test now checks all three authored values against
`Color.lerp` at 8-bit, not only the disputed one. **All three pass**, which
settles it: Flutter's `lerp` rounds to the byte, so `9E` and `8F` are correct
and `#C3C2BF` is the only value the document got wrong. One slip, not two.

### 7.2 Two alpha ink sites survived the "allowlist is empty" claim

`_NewspaperMasthead` (`feed_screen.dart`) bound `final ink =
theme.colorScheme.onSurface` and then thinned that local twice — a 0.4 divider
and a 0.55 dateline. The guard looks for `onSurface` immediately followed by
`.withValues`, so a variable in between hid both for four passes.

Fixed: the rule takes `outline`, the dateline takes `onSurfaceMuted`, and the
guard now also bans binding `onSurface` to a local at all, since aliasing is
the mechanism rather than the symptom.

**Related: Newspaper's `outlineVariant` resolves to pure black** (`#000000`).
It is never declared and does not fall back to anything sensible. Nothing in
`lib/` reads it today, so nothing is broken — but the next widget that reaches
for the standard hairline role will draw a hard black line on newsprint.
Newspaper should declare it.

### 7.3 The threshold is the row's midpoint against the viewport top

An earlier version of this note said "the viewport top, not the midpoint",
which over-corrected. Both terms are in play and they belong to different
things:

```dart
final offset = _scrollController.offset;   // the viewport TOP
...
if (cumulative + h / 2 < offset) {          // the ROW's midpoint
```

So a row is marked read once **its own midpoint** passes the **top of the
viewport**. 5.2 put the midpoint on the viewport; the correction put it
nowhere. This is the accurate statement.

### 7.3b What `_onScroll` actually assumes about row heights — 5.2 downgraded

Asked in pass 5 section 4, reported without changing anything.

**It measures. It does not calculate.** Article rows go through a three-tier
source, and `_rowHeight` uses the same one so the read walk, the retirement
planner and the height cache agree by construction:

| tier | source | when |
|---|---|---|
| 1 | `_cardKeys[id]` → `RenderBox.size.height` | the row is laid out; the result is cached |
| 2 | `_measuredHeights[id]` | the row has scrolled out and has no live context |
| 3 | the constant `120.0` | never measured — and this sets `extentsStable = false` |

Day headers are the exception: they are **calculated**, `kDayHeaderHeight`, and
`continue`d past so they contribute height without deciding the cutoff.

**So the ad row's height is a non-problem, and 5.2 can be closed on its own
terms.** A variable-height row participates honestly the moment it is
measurable — give it a key, let tier 1 read its box, and the walk is correct
without knowing what the row contains. It does not need 306 hard-coded
anywhere, and it would not need re-tuning if a creative came back a different
size.

What survives from 5.2 is **not** the arithmetic. It is the type system: the
four unguarded `as ArticleRow` casts throw before any of this machinery runs.
The prerequisite block above stands; the height-walk warning does not.

**5.2 is closed. What replaces it is a two-line prerequisite:**

1. **Give the ad row a key**, so tier 1 measures it like any card. It does not
   need `306` written down anywhere, and a creative that comes back a different
   size needs no re-tuning. The height machinery already does this correctly;
   the ad just has to opt in.
2. **Handle the four casts** — `feed_screen.dart` 872, 1117, 1685 and 1830 —
   which throw before any of that machinery runs. This is the whole remaining
   blocker, and it is a type problem rather than an arithmetic one.

**The tier-3 caveat stays visible, because it is harmless today and will not
be.** The `120.0` fallback is roughly a card, so an unmeasured card is
understated by ~30dp. An unmeasured ad row would be understated by **~186dp**,
six times the error. `extentsStable` already goes false in that case and is the
existing safety valve — but a valve sized for a 30dp mistake is being asked to
absorb a 186dp one. Worth deciding whether the ad gets its own fallback
constant at the point it gets its key, rather than after the first report of
articles being marked read that nobody saw.

### 7.4 1.6's site lists do not match the code

- **The unread dot does not exist.** `colorScheme.secondary` has exactly two
  consumers in `lib/`, both the swipe reveal on the article card. B1 builds
  the dot; until then, one of the three named unread sites is real.
- **The Alerts `Badge.count` is `error` red, not orange.** `app.dart:319` and
  `:1294` pass no `backgroundColor`, and there is no `badgeTheme`, so it takes
  Material's default — which is `error`. That quietly contradicts 1.6's own
  "neither meaning is faults", since a fault colour is painting an unread
  count. Needs either a `badgeTheme` entry or an explicit colour at both call
  sites; neither is mentioned in 1.6 or 1.7.
- **The reader's filled bookmark glyph does not exist.** There is no bookmark
  control in `article_detail_pane.dart` or the clean view; the proposal in
  section 4 is what would add it.
- **`error`'s scope is wider than the three named items.** Also
  `keyword_alerts_panel.dart:557`, `keyword_group_panel.dart:388` (delete icon
  buttons) and `settings_screen.dart:160` (a red `backgroundColor`). The last
  is a button background and worth a look against "never a confirmation
  button".

> **Three of these four are closed. Marked rather than deleted, so the list
> stays readable as a record of what 1.6 claimed against what shipped.**
>
> - The unread dot **exists** — B1 shipped in pass 5, with
>   `unread_dot_geometry_test.dart` pinning the reserved 12dp.
> - The Alerts badge **is the orange** — a `badgeTheme` entry landed in batch 4.
> - `error`'s scope **is now the three named items** — pass 7 moved both delete
>   bins to `onSurfaceVariant` and took the red off the restore-backup confirm.
>   `pass7_sweep_test.dart` guards all three.
> - **The reader's filled bookmark glyph still does not exist**, and pass 8
>   confirmed it: `article_detail_pane.dart` carries a close button and an
>   open-in-browser button and nothing else. Section 4's proposal is what would
>   add it, and it is deliberately still out — see 11.7 for the recommendation
>   it is waiting on.

### 7.5 1.7's "only capsules left beside r9 chips and r9 nav pills"

The chip half is right (`folder_tab_bar.dart`, `_radius = 9`). **The nav pill
is r14**, not r9 — `flash_bottom_nav.dart`, `pillRadius = 14`, which is the
value 1.7's own sibling sections specify. There is no `BorderRadius.circular(9)`
anywhere in `lib/` outside the chip constant.

### 7.6 The ARB parity test does not do what 2.1 assumes

2.1 says "every new or changed value needs de, es, fr, it or the parity test
fails". True for **new keys** — `arb_parity_test.dart:78-88` fails on a key
missing from a locale. Not true for **changed values**: the only value-level
check (`:90-102`) fails when the English and translated strings are *identical*,
so changing an English value makes that collision less likely, never more.
Re-translating the four changed values may still be editorially right; the
stated enforcement mechanism just is not there.

### 7.7 `alertsFilterAll` is a dead key

2.4 describes it as one of "two chip bars that now render identically". There is
only one chip bar. `alertsFilterAll` has no call site in `lib/` — only the
generated accessors — and `alerts_screen.dart` contains no `Chip` at all. Its
description documents a filter control that was never built.

**Deleted** from all five locales, and the generated accessors regenerated.

Pass 6 section 4 then asked for a test pinning `allTab` == `alertsFilterAll`
in every locale. There is nothing left to compare. `pass6_strings_test.dart`
guards the deletion instead — the key is absent from all five .arb files and
unreferenced in `lib/` — so it cannot come back by someone reading 2.4 at face
value. If the second chip bar is ever built, that test goes in the same commit
as the call site.

### 7.8 Three B-items already disagree with shipped code

- **B8 "silent and ongoing"** — `unread_badge_service.dart:236` sets
  `ongoing: false` deliberately, with a comment explaining why an
  un-dismissible notification was wrong. B8 would reverse a considered
  decision; worth confirming that is intended.
- **B9 "clamp to 999+"** — a clamp exists in `UnreadWidgetProvider.kt:39` but
  at a different threshold. The autosize half is genuinely missing.
- **Bookmarks' separator** — already identical to the feed's, and neither is
  full-bleed. Nothing to adopt.

### 7.9 `saved` is never the destination — both its call sites are states

2.2 changes `saved` from "Saved" to "Bookmarks" because "the nav label already
says it in five locales". **The nav label is a different key.** `l10n.bookmarks`
is the destination — `app.dart:354`, `:1329`, `:1566` and
`bookmarks_screen.dart:200` — and it has read "Bookmarks" in English all along.

`l10n.saved` has exactly two call sites, and both describe the state of one
article rather than a place:

- `article_card.dart:871` — the action rail's tooltip when the article is saved
- `radial_menu.dart:244` — the radial menu's **visible label** when it is saved

2.2 flags the first and asks it be checked on device. It does not mention the
second, which is a rendered label rather than a tooltip, is unconditionally
visible on long-press, and will read "Bookmarks" beside a bookmark glyph as the
name of the state the article is in.

**Reverted.** `saved` is "Saved" in all five locales again, and the 2.2
row is marked superseded rather than edited. The change was applied in
English for one commit (21c8975) and taken back in the next; it never
reached a release outside this branch.

### 7.10 Four locales have no bookmark noun, and never had one

The lookup rule assumes each locale already has a word for the bookmark. None of
de/es/fr/it does — all four are built on the verb *save*:

| key | de | es | fr | it |
|---|---|---|---|---|
| `bookmarks` (destination) | Gespeichert | Guardados | Enregistrés | Salvati |
| `saved` (state) | Gespeichert | Guardado | Enregistré | Salvato |
| `bookmark` (action) | Speichern | Guardar | Enregistrer | Salva |
| `noBookmarks` | …gespeichert | …guardado | …enregistré | …salvato |

They do not disagree with each other, so there is **no pre-existing drift to
report** — but the noun the lookup was meant to find is not there.

The English edit aligns two different words. In the other four they are already
the same word, separated only by grammatical number, which is the state/place
distinction English does not mark. The only "same direction" edit available is
singular → plural at two sites that each describe a single article: a grammar
error in four languages, three of which would then be wrong in a way David can
see and one in a way nobody here can.

**Left unchanged, pending a ruling.** Note also that the four `noBookmarks`
values now name the control by what it does ("das Speichern-Symbol", "el icono
de guardar") rather than introducing Lesezeichen / marcador / marque-page /
segnalibro, so no new noun enters the app in this pass.

### 7.11 The action rail tooltip is reachable

Measured rather than reasoned. Long-press on the rail's bookmark half renders
the tooltip and does **not** open the radial menu; the same gesture on the card
body does open it, which is the control that makes the first result mean
something. The rail's `Tooltip` is the inner long-press recognizer and takes the
gesture arena from the card's `GestureDetector`.

So the concern 2.2 raises is real — confirmed on the M51, where the
tooltip rendered "Bookmarks" against the orange saved bookmark. It is the
fix that was wrong, not the worry: see the superseded block on 2.2. The
tooltip reads "Saved" again.

Worth keeping even though the string reverted, because it answers a
question that will come back the next time anything is put on the rail:
the rail's own long-press wins, and the card's radial menu does not fire
from there.

### 7.12 `onSurfaceRead` does not qualify for WCAG's large-text bar

Both sites render at **14.0 logical px, `FontWeight.w600`** — `article_card
.dart:357` and `search_screen.dart:160`, measured off the rendered
`RenderParagraph` in all three themes.

Worth knowing for any future measurement here: reading `flashQuietInkTheme(...)
.textTheme.bodyMedium.fontSize` reports **null**. Sizes arrive from the text
geometry that `Theme.of` merges in, not from the `ThemeData` object, so the
theme has to be measured through a widget tree or it reports nothing at all.

WCAG 1.4.3 sets the large-text floor at 18.66px bold or 24px regular. 14px
clears neither at any weight, so the 4.5:1 bar stands and the 3.99:1 entry in
`flash_colors_resolution_test.dart` stays exactly as it is. The question of
whether `w600` counts as "bold" never arises — the size fails first.

Separately, and answering a narrower question than it looks like: the large-text
exemption is a compliance floor, not a statement that the text is comfortable.
3.99:1 at 14px is a deliberate recession, not a comfortable read.

### 7.13 An unused ARB key breaks nothing

Checked for `adSponsored`, which ships with no call site. `arb_parity_test.dart`
is the only thing in the repo that reads the .arb files, and it compares locales
against the template in both directions — never against `lib/`. There is no
unused-key lint, and `flutter gen-l10n` emits a public getter, which the
analyzer does not report as unused. `flutter analyze` is clean with the key in.

### 7.14 `alertNotificationSummary` has no call site either

There is no group summary notification in the app. `groupKey` is set on the
children (`refresh_service.dart:182`, `unread_badge_service.dart:233`) but
nothing calls `setAsGroupSummary`, so the whole key is unreachable, not just its
`one` branch. Written correctly regardless — how Android treats a group with a
single child is version-dependent, and that is not worth betting a wrong string
on.

The French `one` branch takes `{count}`, not a literal 1, because CLDR routes
**0 and 1 both** through `one` in French. That is already the house style in
`alertNotificationCount` and `deleteAlertKeywordBody`.

It is **not** the style in `unreadCountNotification`, whose French `one` branch
hardcodes "1". Latent rather than live: `unread_badge_service.dart:149` clears
at `safe == 0` and never posts, so the only way to reach it is to call
`unreadBadgeText(0)` directly. Worth fixing when something else opens that file.

---

## 8. Pass 9 scope — recorded, not started

Two items found during the pass 6 strings work that are **behaviour, not
copy**, and were deliberately left alone.

### 8.1 The notification stack has no summary at all

`setAsGroupSummary` is never called. `kFlashNotificationGroupKey` is set on
every child — `refresh_service.dart:182` and `unread_badge_service.dart:233`
— but a group with no summary notification is only half the feature: Android
will auto-bundle children on its own terms, with its own heading, instead of
the one the app would write.

This is **why `alertNotificationSummary` is unreachable**, and the distinction
matters for whoever picks it up: the key is not waiting on a call site that was
forgotten, it is waiting on a notification that was never built. The string is
already written, in five locales, and is not the work.

Note also `notification_group.dart`, which is worth reading first: keyword
alerts and the unread count sit on channels of different importance, so Android
puts them in different sections of the shade and **will not group them with each
other whatever this key says**. A summary would cover the keyword alerts only.

### 8.2 `unreadCountNotification` fr carries the plural trap, and a guard is
holding it

French routes **0 and 1 both through the ICU `one` branch**. The French
`unreadCountNotification` hardcodes "1":

```
{count, plural, one{1 article non lu} other{{count} articles non lus}}
```

so it renders "1 article non lu" at a count of zero. The house style elsewhere
— `alertNotificationCount`, `deleteAlertKeywordBody`, and the new
`alertNotificationSummary` — uses `{count}` in the `one` branch for exactly
this reason.

**It cannot fire today, and the reason it cannot is load-bearing.**
`unread_badge_service.dart:149` reads:

```dart
if (safe == 0) {
  await _clear();
  return;
}
```

That early return exists to dismiss the badge, not to protect a translation,
and it is the only thing standing between the French build and "1 article non
lu" on an empty feed. The next person to simplify that branch — to post a
"you are all caught up" line, say — will ship the bug without touching the
ARB and with every test green, because no test renders `unreadBadgeText(0)`.

Fix the string, then the guard is free to change. Not the other way round.

---

## 9. Pass 7: the consistency sweep

Not a redesign. Section 4 lists most of these screens as NOT DRAWN, so the work
was finding the places where a screen had stopped inheriting the theme and
closing them. Every change below is a swap to a role that already existed.

### 9.1 What each surface turned out to be

| surface | verdict |
|---|---|
| Categories | role substitution — one chevron |
| Alerts | role substitution — two |
| Keyword alerts panel | role substitution (one auditor said "needs a mock"; see 9.3) |
| Keyword blocklist panel | role substitution — one |
| Quick Settings | role substitution — one scrim |
| Settings | role substitution — one confirm button |
| Onboarding + starter pack | role substitution — one radius override |
| Add-feed sheet | **already correct** |

**The eight changes, all one-liners:**

- `feeds_screen.dart` — the folder chevron was `primary` at **alpha 0.7**.
  Alpha-faked ink one role over from the one the guard watches, and it made the
  header read as three different teals. Now `onSurfaceVariant`, which is what
  the alerts and blocklist chevrons already use — and their comments cite
  *this* chevron as the original they match, so Categories was the drifted copy
  of its own precedent.
- `bubble_panel.dart` and `radial_menu.dart` — `Colors.black` at 0.28 and
  0.6 became `scrim`. Byte-identical today, since neither scheme declares a
  scrim and both take ColorScheme's black. That is the argument *for* it: it
  costs nothing and gives a theme that wants a warmer wash somewhere to say so.
  **The two opacities are left different on purpose** — one isolates a menu
  over the whole screen, the other blurs behind a panel that is still part of
  its screen. One number for both is a design call.
- `settings_screen.dart` — the restore-backup confirm was a `FilledButton`
  in `error` under `onError`. The same red on a question that B5 removed from
  mark-all-read and `confirm_sheet_no_red_test.dart` records for the two
  sheets. `restoreConfirmMessage` already says what restoring does.
- `keyword_alerts_panel.dart` — the inline "this destroys N cards" prompt
  was `errorContainer` at **35% alpha**. Both halves wrong: alpha over a role
  is a colour nobody authored, and error on a confirmation reads as though
  something had already gone wrong. Now `surfaceContainerHighest`.
- `keyword_alerts_panel.dart` and `keyword_group_panel.dart` — two delete
  bins in `error`, now `onSurfaceVariant`, matching the Categories header
  restyle in section 3. **On section 4's "Delete, in Alerts only, keeps
  `error`":** that sentence is inside the radial-menu bullet and is about the
  radial menu's Delete, which is also the only Delete `app_theme.dart` blesses
  by name. It does not reach an IconButton in a panel. Recorded because the
  sentence is easy to read the other way.
- `onboarding_screen.dart` — the Start-reading CTA carried its own
  `RoundedRectangleBorder` at radius **14**, the *card* radius applied to a
  button, making the first screen a new user sees the only one whose primary
  action is a different shape. Deleted; it inherits `filledButtonTheme` at r20.
  The full-width 52dp minimum stays — that is the button being a CTA.

### 9.2 What was NOT done, and is listed rather than built

Everything here would have meant inventing a value, a component or a decision.
None of it is a defect; it is the boundary of a sweep.

- **Two drop-target washes disagree** in `feeds_screen.dart`: `primary` at 0.08
  for the header hover, 0.12 for the drop slot, while `article_card.dart` and
  `radial_menu.dart` wash at 0.15. Picking one is a value decision and
  `FlashColors` has no wash role to swap to.
- **The empty-state caption is split 2–2** across the app between
  `onSurfaceVariant` and `onSurfaceMuted`. Both are legal roles. Choosing is a
  cross-surface call.
- **`EmptyState`'s brand mark is `primary`** at 80dp while every other
  empty-state glyph is `illustration`. Arguably correct — it is the app's
  mark, not a decorative glyph — and arguably the last unswept one.
- **The Alerts empty state is text-only**, where every other empty state in the
  app pairs a large `illustration` glyph with muted copy. That is a missing
  component, not a wrong colour.
- **Disabled states do not use `inert` anywhere.** The OPML and backup buttons,
  the add-feed search field and chips, and the starter-pack checkboxes all fall
  to Flutter's framework default when disabled. 6.5 says "one role, four sites
  close" — those four are closed; these are a different, larger set.
- **Quick Settings expresses a disabled block as `Opacity(0.4)`** around an
  `IgnorePointer` when Newspaper mode is on. That is a disabled state written
  as a filter rather than as `inert`, and unpicking it is a component change.
- **Two hardcoded `TextStyle`s survive**: `onboarding_screen.dart`'s CTA label
  (16/w600) and `feed_card.dart`'s monogram (16). Both are sizes, not colours,
  and both were out of a colour sweep's scope.
- **`feed_card.dart`'s unread count is `primary`.** Proposed as `secondary`
  and **rejected on measurement**: Quiet Ink light `secondary` is 4.12:1 on
  white for an 11px label where `primary` is 6.34:1 — a light-mode
  regression, and the only theme it would change.

### 9.3 1.7 asks for two things a theme cannot carry

`segmentedButtonTheme` ships. Radius **9** outer / 0 between, one 1dp
`outlineVariant` `side` serving as both border and divider, selected
`primaryContainer` under `onPrimaryContainer` at 13/w600, unselected
`onSurfaceVariant` at 13/w500. Shared by both themes so they cannot drift on
geometry, and derived from each theme's own `labelLarge` so Newspaper keeps PT
Serif.

Two things did not land, and neither is a slip:

1. **`showSelectedIcon: false` is not a theme property, and did not need to
   be.** `SegmentedButtonThemeData` has exactly two fields, `style` and
   `selectedIcon`; the flag is a `SegmentedButton` constructor argument. That
   reads like an unclosable item — until you open the call sites, where
   **all three already pass it**: `filter_bubble.dart` once and
   `quick_settings_bubble.dart` twice. The app was never wrong here; only the
   mechanism was missing.

   The guard is therefore on the **call sites**, not on a rendered widget. A
   widget test can only prove things about the SegmentedButton it built
   itself, and the risk is a fourth one added elsewhere inheriting a default
   of `true`. `segmented_button_theme_test.dart` asserts the count is three
   and that every one carries the flag, plus a tripwire confirming the
   framework default really is the checkmark — so if Material ever flips
   it, the guard is deleted rather than left reading as protection.

2. **"Height 40" costs 8dp of touch target.** Measured: the segment paints at
   **48**, and that is the painted fill, not a tap halo around a 40dp body —
   `_SegmentedButtonRenderObject` lays every segment out at a uniform tight
   height, so Material's tap padding ends up inside the paint. Reaching 40
   means `tapTargetSize: shrinkWrap` or a negative `visualDensity`, and both
   take the **touch target** to 40 with it. The two places this app already
   goes under 48 — the 36dp folder chip, the 36dp rail halves — each
   carry a written justification and a test. 1.7 does not mention touch targets
   at all, so the number is reported rather than applied. Pinned at the real 48
   so the gap is visible.

### 9.4 B3 landed; the chip reads as one node

`Semantics(label: "$name, ${l10n.articlesCount(n)}")` inside the `InkWell`,
with the painted text under `ExcludeSemantics`. Inside rather than around,
because wrapping the chip takes the button role and the tap action with it.

**At a count of zero the label is the name alone.** Nothing is painted at zero,
and "Tech, 0 articles" describes a numeral that is not on screen.

### 9.5 The app bar band — logged for Design, not a defect

Not a bug and nothing was changed. `height - toolbarHeight == inset` exactly at
insets of 0, 24 and 48, and the body reads `padding.top = 0`, so the status bar
inset is consumed once, by the `AppBar` at `primary: true`. The band is the
status bar drawn over the same white as the app bar, plus 14dp of title
centring — a 28dp text line inside a 56dp toolbar.

**The design question behind it**, which is Design's and is not actioned here:
should the app bar carry a different tint from the status bar so the band stops
reading as empty? The device numbers that motivate it, since the Pixel is the
case that makes it visible:

| device | status bar | density | dp | total above the title |
|---|---|---|---|---|
| Lenovo Tab M11 | 59px | 1.5 | 39.3 | 53.3 |
| Samsung M51 | 91px | 2.625 | 34.7 | 48.7 |
| Pixel 11 Pro | 172px | 2.625 | **65.5** | 79.5 |

The Pixel's band is nearly twice the Samsung's, and it is the system's number,
not the app's.

### 9.6 An ad-privacy row with nothing behind it

Serving ads in the EEA and the UK needs a Google-certified CMP, and consent
that can be given has to be withdrawable afterwards — a permanent entry
point, not a first-launch dialog.

The row ships now because **Settings was being touched tonight and will not be
touched again before the ads pass.** It sits directly under the privacy policy
and last in About: the policy says what is collected, this changes what the
reader agreed to, and nothing legal sits below it.

`enabled: false`, so it is reviewable in place and cannot reach a form that
does not exist. `_onAdPrivacy()` is an empty method carrying its own
explanation, because an empty method with no comment is indistinguishable from
an unfinished one.

**The copy is an English-only constant, not an ARB key**, and deliberately:
the real wording ships with the ads pass, and five locales now means paying for
the same row twice — with `arb_parity_test.dart` then holding four
translations of a sentence nobody has agreed to. `kAdPrivacyRowLabelEn` and
`kAdPrivacyRowSubtitleEn` are marked for deletion in that pass.

No UMP SDK, no ad code, no new strings. A test asserts all three absences.

### 9.7 `savedFill` and `onSavedFill` are deleted

Two roles with no call site in `lib/` — the same condition 7.7 found
`alertsFilterAll` in — left behind when the action rail’s saved fill
became a glyph.

**Why deleted rather than kept warm for a future consumer.** A role with no call
site is still lerped on every theme animation, compared in every `==` and
hashed in every `hashCode`. That is the cheap part. The expensive part is
that it reads as an available answer: the next person needing a saved treatment
would find two roles sitting in `FlashColors` and reasonably assume the
decision had been made. It had been, and it was reversed. Restoring the fill now
means restoring these two deliberately, which is the right amount of friction.

`_qiOnSavedFill` went with them. It was `#0D1211` and it existed only
because `onSecondary` gave 4.12:1 on the orange, under the 4.5:1 this app
holds a lone glyph to — an authored constant written to solve a contrast
problem the fill had created.

**The three tests that went, and what each asserted:**

| test | asserted | replaced by |
|---|---|---|
| `flash_colors_resolution` · *Newspaper does not fill it red* | `savedFill` was `_npInk`, not `_npRed` | **inverted** — the glyph IS `_npRed`, see below |
| `flash_colors_resolution` · *Quiet Ink fills it with the unread orange* | `savedFill == secondary` in both brightnesses | `batch4_ink_test.dart`, on the glyph |
| `flash_colors_resolution` · *every theme keeps a legible glyph on the saved fill* | `onSavedFill` on `savedFill` ≥ 4.5:1 | `summary_button_contrast_test.dart`, glyph on tint, 3:1 |

A fourth assertion went too, a line inside `batch4_ink_test.dart`’s "error
is not the orange" reading `expect(scheme.error, isNot(flashColors.savedFill))`.
It asked the same question as the line beside it, since `savedFill` resolved
to `secondary` in both Quiet Ink brightnesses.

**The first row is the one worth reading.** Its argument — `_npRed` is
already the nav selection, the FAB, the switch and the masthead, so a red saved
block competes with all of them — was correct about a BLOCK and was overturned
for a GLYPH by measurement, not by this deletion: Newspaper’s
`onSurfaceVariant` and its `_npInk` are the same `#1D1D1B`, so an
ink saved glyph would be pixel-identical to an unsaved one. The claim that test
made is now true in reverse, which is exactly the kind of thing that gets lost
when a test is deleted without a note.

---

## 10. Standing rules for tests in this repo

Both of these were bought with an incident. Neither is a style preference.

### 10.1 Assert the mutation landed before running the test

A mutation test is only evidence if the mutation happened. Change the code,
**assert the change is in the file**, and only then run the suite.

Bought by a mutation that silently did nothing: a `str.replace` targeting
`

` against text that Python had already normalised to `
`. It matched
zero times, the file was untouched, the test passed, and that was read as "the
parity gate does not catch a missing key— " a conclusion about a gate that was
in fact working perfectly. Every mutation in passes 6 to 8 prints a VERIFIED
line before the test runs.

### 10.2 A test that constructs its own subject proves a fact about the test

If the app never builds the widget that way, the coverage is shaped like
coverage and covers nothing. **Assert against the call sites, or assert that
the call sites pass what you think they pass.**

Bought by `showSelectedIcon`. Handoff 1.7 asks for `showSelectedIcon: false`,
`SegmentedButtonThemeData` has no such field, and that was written up as an
unclosable gap — with a test asserting the selected checkmark **is** shown, to
pin the gap. The test built its own `SegmentedButton`, which of course inherits
the framework default of `true`. Every SegmentedButton in the app already
passed `false`. The assertion was true of the widget in the test and false of
all three that ship.

**A screenshot caught it, not the suite.** The filter bubble rendered with no
checkmark, which is what sent me to the call sites. Worth recording plainly:
the suite was green, and green was wrong.

The replacement reads `lib/` — the count of SegmentedButtons is three, every
one carries the flag — plus a tripwire confirming the framework default really
is the checkmark, so the guard deletes itself rather than lingering as
protection if Material ever flips it.

This is the fifth harness-blindness incident in the project and the first of
this exact shape. The others, for pattern-matching: the alpha-ink allowlist
reported empty while two aliased sites sat in the file; a wrapped call chain
the guard's regex could not see; `find.byType(Image)` finding nothing on a card
that renders no Image, so the finder was empty exactly when it mattered; and
22 nav tests pumping into a `Scaffold` with no `body:`, which is how a total
render failure reached a device.

---

## 11. Pass 8: the reading surfaces

Deliberately small. Most of these took their ink roles in passes 2 and 4 and
Design never mocked them in detail, so this is one type change, verification,
and two consistency items.

### 11.1 The clean view reads in Literata now

Body, quotes, list items and list markers at **17 / 1.62**; h3 off the sans
`titleMedium` onto the reading face at 17 / w700; captions unchanged. h1 and h2
were already serif and did not move.

**The family is taken from `titleLarge`, not from `kSerifFamily`.** Both themes
put their reading serif there — Literata in Quiet Ink, PT Serif in Newspaper —
while `bodyLarge` is the *operating* face in Quiet Ink. Hardcoding the constant
would have put Literata into Newspaper, which has its own type system.

Worth knowing for anyone touching headings: **Newspaper has two serifs.**
Playfair Display for display and headline, PT Serif for title and body. A test
asserting h1 matches the reading face would demand Newspaper give that up; the
assertions are each against their own theme entry instead.

`kCleanBodySize` and `kCleanBodyHeight` live in `app_theme.dart`, and
`clean_view_type_test.dart` pins 1.62 with an explicit `isNot(1.6)` — it is a
value that looks like a rounding artefact and is not one.

### 11.2 Literata's subset, and what can fall outside it

The subset is documented in `pubspec.yaml`: **Latin-1, Latin Extended-A and
Extended-B, general punctuation, currency, plus U+2122 and U+2212**. No
Cyrillic, Greek, Vietnamese, CJK, Arabic, Hebrew, or emoji.

**Yes, content can reach it outside that range, and the path is the obvious
one:** the clean view renders article bodies from whatever RSS feed the user
adds, and nothing restricts a feed's language. Emoji in body text and headlines
are ordinary in feeds. This is not a hypothetical about an unusual locale — it
is any user who subscribes to a Russian, Greek or Japanese source.

What happens is fallback rather than tofu: Flutter consults the platform's
fallback fonts for a codepoint the family does not carry. So the failure is not
missing glyphs, it is **a reading view that silently stops being Literata** for
those feeds, with a line height tuned for one face applied to another. Smaller
than tofu, and real.

**Not verified on device in this pass.** The fallback claim is Flutter's
documented behaviour; confirming it needs a non-Latin article in a real feed,
and `flutter_test` substitutes its own font so the host suite cannot see it.
Worth ten seconds with a Russian feed before the ads pass.

### 11.3 Verification results

| surface / state | verdict |
|---|---|
| Reader app bar: `surface`, `titleSmall`, `onSurfaceVariant` attribution | **correct** |
| Reader action ink (close, open-in-browser) | **correct** — inherits, no overrides |
| Reader bookmark glyph, filled, in `secondary` | **does not exist**, see 7.4 |
| Summary: reading / writing status line | **correct**, `onSurfaceMuted` |
| Summary: the result | **correct** |
| Summary: unavailable | **correct**, muted glyph + variant message |
| Summary: show / hide details | **correct**, `onSurfaceVariant` |
| Summary: copy | **correct** |
| Summary: on-device disclaimer | **correct**, muted + italic |
| Summary: teaser-only | **correct** by reading; shares the disclaimer's style |
| Summary: failed (cloud) | **unreachable from a test** |
| Summary: cloud disclaimer | **unreachable from a test** |
| Clean view: offered / active / unavailable / extracting | **correct**, covered by `article_detail_pane_clean_mode_test.dart` |

The two unreachable states both hang off `useCloud`, which the sheet resolves
internally from the summary tier and exposes no seam for. Adding one would be a
production change made for a test's convenience, which this project has turned
down before. Both were verified by reading: each is the other half of a ternary
whose on-device branch is now pinned, so a drift would have to be written
deliberately into a line whose twin fails.

**One finding worth acting on eventually.**
`article_summary_sheet.dart:449` reads
`final secondary = theme.colorScheme.onSurfaceVariant;` — a local named
`secondary` that is **not** `colorScheme.secondary`, in an app where 1.6
reserves that role for unread and saved. The value is correct; the name is a
trap, and "fixing" it to `theme.colorScheme.secondary` would turn the control
orange while looking like a tidy-up. Not renamed, because this was a
verification pass — but the resolved colour is now pinned, so that edit fails
rather than ships.

### 11.4 Empty states: the structure, and the one exclusion

The split was not 2—2, it was three shapes:

| site | copy | was | now |
|---|---|---|---|
| Categories, no feeds | one piece | `onSurfaceVariant` | unchanged |
| Feed, caught up | one piece | `onSurfaceVariant` | unchanged |
| Bookmarks | one piece | `onSurfaceMuted` | **`onSurfaceVariant`** |
| Alerts | one piece, no glyph | `onSurfaceMuted` | **`onSurfaceVariant`** + glyph |
| Keyword alerts panel | two pieces | muted + muted | **variant** + muted |
| Keyword blocklist panel | two pieces | variant + muted | unchanged |

Note the newline trap: Bookmarks and Alerts each render **two lines** from one
string. The rule is about pieces of copy, not rendered lines — you cannot give
two roles to halves of one `Text` without splitting it, which would be a
structural change nobody asked for.

**`empty_state.dart` is exempt from the shape, not the rule.** It is the
first-run state: an 80dp brand mark, a `headlineSmall` w700 heading and a
button. Its one line of body copy is already `onSurfaceVariant`. Forcing the
rule onto it would demote its heading to a caption.

**The tablet's idle reading pane is exempt outright, and a test said so before
I did.** It was swept into the rule and reverted when `ink_roles_test.dart`
failed in both brightnesses. The rule rests on the copy being the only content
on the screen; nothing is empty there — the middle column is full of articles
and the right-hand one is waiting to be told which. Pass 2 gave it
`onSurfaceMuted` deliberately. The exclusion is now asserted in
`empty_state_roles_test.dart` rather than merely absent.

### 11.5 Alerts' glyph matched a pattern; it was not invented

Five of the six empty states already pair `flashColors.illustration` with their
copy, and three use the same three numbers: **48dp glyph, 12dp gap, then the
text**. Alerts takes the destination's own bell,
`Icons.notifications_none_rounded`, at exactly those numbers.

It is the same glyph the keyword alerts panel's empty state uses. Both are about
alerts and both are bells; flagged rather than treated as a collision.

### 11.6 Notification channels, for pass 9

**Two channels, and they are already separate.**

| id | name | importance | declared in |
|---|---|---|---|
| `flash_keyword_alerts` | Keyword alerts | `Importance.defaultImportance` (3) | `refresh_service.dart:21-22`, posted at `:177` |
| `flash_unread_count` | Unread count | `Importance.low` (2) | `unread_badge_service.dart:11-12`, posted at `:216` |

**They do not share one, and the unread count is already IMPORTANCE_LOW.** So
**B8 is already done** — there is nothing to migrate. Verified live on the
Lenovo: `NotificationChannel{mId='flash_unread_count', mName=Unread count,
mImportance=2, mOriginalImp=2, mUserLockedFields=0, mDeleted=false}`.

Three facts pass 9 should hold onto:

1. **Channels are created lazily, on the first `show()` for that id** — nothing
   calls `createNotificationChannel` explicitly. The Lenovo has
   `flash_unread_count` and **not** `flash_keyword_alerts`, because no keyword
   alert has ever fired on it. So the 25 testers do not have a uniform set:
   each has whichever channels their own usage has triggered.
2. **`mUserLockedFields=0`** on the one channel observed, meaning nothing had
   been customised there. That is one device and does not generalise.
3. **If a migration ever is needed**, it is a new id plus
   `deleteNotificationChannel` on the old one, and the user-visible cost is
   that anyone who had customised the old channel — sound, importance, dot,
   lock-screen visibility — silently loses all of it and gets the app's
   defaults, with no notice and nothing to restore from. That is the reason to
   avoid needing one, and the reason this was worth checking before writing the
   pass rather than after.

### 11.7 The reader action bar — a recommendation, not a change

Not started, not threaded. Handoff 4's proposal stays out.

**I would take the overflow.** Four 48dp actions leave the title 160dp at
360dp, roughly twenty characters of a headline — enough to read "Microsoft
proposes limits o" and stop, on the one surface where knowing which article you
are in matters most. Moving open-in-browser into an overflow buys back 48dp to
208dp, and it is the right action to demote on the evidence already in the app:
the reader opens in the embedded WebView by default, clean mode is one tap from
the FAB, and open-in-browser is the escape hatch for the minority of pages that
do not render — a considered act rather than a reflex, which is what an overflow
is for. The three that stay, bookmark, share and close, are all one-tap
reflexes. The counter-argument is real and worth holding a phone for: an
overflow is two taps and a menu for something some readers use constantly, and
160dp of title is only cramped if headlines are long, which on this feed list
they mostly are.
