# Quiet Ink — open questions for Design

Things the redesign hit that no mock or memo answers. Each one is a live
decision, not a bug: the code does something reasonable today and says so in a
comment, but the value or the rule behind it was inferred rather than given.

Kept here rather than in commit messages so it can be read in one go.

---

## 1. Sheet grabbers have no role

**Three sites.** `article_summary_sheet.dart`, `feeds_screen.dart`,
`starter_pack_picker.dart` — the 40×4 rounded bar at the top of a bottom sheet.
All three paint `onSurface` at 20%.

They have the same problem every other alpha-over-ink site had, and it is the
reason the ink roles exist at all: **alpha cannot express a tinted surface.**
20% ink over white and 20% ink over the near-black dark surface are two
different greys, and neither is a chosen one. In Newspaper, over warm paper,
it is a third.

Batch 4's `illustration` role was offered for these, but a grabber is furniture,
not a picture — it stands in for nothing and carries no meaning. Giving it a
role named `illustration` would make the role mean two unrelated things, which
is the same mistake as merging `inert` and `illustration` (see below).

**Needed:** one value per brightness for a sheet grabber, or a ruling that they
should take an existing role.

---

## 2. `inert` has no authored dark value

`FlashColors.inert` exists and is used — the feed's filter and quick-settings
icons take it when there are no feeds to act on.

Its values are **borrowed from `illustration`** and marked as such in
`app_theme.dart`. Design specified `#C3CAC9` for an inert control and `#C3CAC9`
for an empty-state glyph — the same hex — and gave a dark value for the glyph
only.

The two roles were kept separate deliberately. "Nothing to act on" and "a
picture standing in for missing content" are different statements that happen
to agree on one number in one brightness; one role meaning both would make the
next change to either silently move the other.

**Needed:** an authored dark value for `inert`. It lands in one place and
nothing else moves.

---

## 3. A read search result has no role

**One site.** `search_screen.dart` paints a result's title at
`onSurface` with `a.isRead ? 0.5 : 1.0`.

Batch 4 settled this shape on the article card — title to `onSurfaceRead`,
source to `onSurfaceMuted`, timestamp unmoved — and named only those two sites.
A search result is arguably the same object in a different list, but it was
left alone rather than assumed to follow, because the card's answer depends on
a three-level hierarchy that a search result may not share: it has no source
line and no timestamp beneath it to outrank.

**Needed:** either "search follows the card" or its own treatment.

---

## 4. The keyword row marker is ornament with no name

**One site.** `keyword_group_panel.dart`, a 20dp leading icon repeated beside
every matched article, at `onSurface` 30%.

It sits below all three ink levels. Its 48dp sibling in the same file — the
empty-state glyph — moved to `illustration`, but this is neither an
illustration nor text; it is a repeated tick marking rows in a list.

**Needed:** a ruling. It may simply be `onSurfaceMuted` and slightly louder
than today, which would close the site entirely.

---

## 5. Disabled is a different axis from quiet

**Four sites,** all in `radial_menu.dart`: a disabled button's circular wash at
8%, its glyph at 30%, and an enabled/disabled label pair at 80% and 30%.

These express *inactive*, not *quieter*. The ink scale runs from
`onSurfaceVariant` down through `onSurfaceMuted`; "you cannot press this" is a
different statement and the scale has no rung for it. Converting one half of an
enabled/disabled pair while leaving the other on an alpha reads worse than
leaving both.

`inert` (item 2) may be the answer here too — an inert control and a disabled
control are arguably the same statement — but that is a decision, and `inert`
does not have its own dark value yet.

**Needed:** a ruling on whether disabled and inert are one role.

---

## 6. Newspaper's derived values are nobody's choice

Three values in `flashNewspaperTheme()` are computed by lerping between
`_npInk` and `_npPaper` rather than authored:

| role | value |
|---|---|
| `onSurfaceMuted` | `lerp(ink, paper, 0.62)` |
| `onSurfaceRead` | `lerp(ink, paper, 0.55)` |
| `illustration` | `lerp(ink, paper, 0.78)` |

They are reasonable newsprint greys and they satisfy the hierarchy —
`flash_colors_resolution_test.dart` pins that a read title outranks a
timestamp — but no one picked them.

The same is true of `_fallbackFlashColors`, which only a theme carrying no
extension ever reaches; that one matters less, since in practice it is only hit
by widget tests.

**Needed:** nothing urgent. Worth authoring if Newspaper is ever treated as a
first-class theme rather than a mode.

---

## 7. Verify on device

Three Batch 4 changes have no widget test, by decision: they are single-use and
live inside screens that need a database on a real isolate before they render a
row, and extracting them purely to make a harness happy would shape the
codebase around the tests rather than the design. The real fix is a test seam
for those screens, which is a post-launch job.

Check these by eye:

- **Feed → filter and quick-settings icons, with no feeds added.** Should be
  present and greyed at `inert`, not absent. Previously they vanished entirely.
- **Feed → caught up.** Should show a `done_all` glyph above "No new articles.
  You're all caught up.", in the `illustration` grey.
- **Categories → a category header's delete icon.** Should be
  `onSurfaceVariant` — neutral, not teal and not red. The rename icon beside it
  stays teal.
