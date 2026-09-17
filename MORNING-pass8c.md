# Device list — pass 8c

**0.8.1+24 on all three.** The Pixel is back on wireless debugging; clean launch
and zero logcat errors on all of them. Pushed through `9933fc2`.
**1620 passing, 1 skipped, analyzer clean.**

---

## 1. The bar, which is the whole pass

Open any article. It should now read:

```
×   Sky Sports                   [open]  [bookmark]  [share]
    Sep 15, 2026 12:30 PM
```

Both lines complete, nothing ellipsised. Confirmed on the M51 before writing
this — that is the actual render, not a mock-up.

**What to check:**

- Does the second line read as the date belonging to the source above it, or as
  two unrelated things stacked?
- The date is `labelSmall` in the muted grey, deliberately quieter than the
  source. Is it too quiet to be useful, or correctly out of the way?
- **Open something from The New York Times (World)** — the longest source in the
  starter pack at 26 characters. It *will* truncate on line 1. The masthead
  survives and the "(World)" is what goes. Does that read as intentional?

The bar is still 56dp. It was 56 with a title and a date, 56 with a source
alone, and it is 56 now — pinned in all three themes plus the two edge layouts.

## 2. Everything from 8b still applies

- **Bookmark** follows changes made elsewhere. Save from the feed's action rail,
  then open the article — the glyph should already be filled and orange.
- **Share a summary to a chat** and read what arrives. Copy now produces the
  identical bytes, which is a change to shipped behaviour.
- **The Literata fallback**, still carried over and still needing a person: add
  a Cyrillic or Greek feed, open clean mode, and see what the substituted font
  looks like at 17 / 1.62. The host suite cannot see font fallback at all.

---

## Two things I found and did not fix

### An Alerts article can be bookmarked from the radial menu, and cannot from
### the reader

You were right to ask. They disagree, and the reader is the poorer of the two.

The radial menu **can**: `alerts_screen._toggleSaved` never touches the
snapshot's id — it looks the real row up by (feed, guid), writes against that,
and shows "That article is no longer in your feed" when the row has gone.

The reader **cannot**: it checks `article.id == null` directly and hides the
button. That is the snapshot's id, and an Alerts snapshot never has one.

The fix is the one Alerts already uses, but it is a behaviour change with a
database read in it, so it is logged rather than slipped into a layout pass.

**And a second thing inside it:** `AlertEntry.toArticle()` never sets `isSaved`
at all, so it defaults to false. The radial menu takes its glyph from that —
which means an already-saved article opened from Alerts shows an *unsaved*
bookmark. The write is still correct, because `_toggleSaved` reads the real
row. So the glyph lies while the action behaves. Same class of problem as the
reader bookmark this whole pass was built around.

### For Design: two timestamp formats, neither chosen

The feed shows relative timestamps ("2h ago"). The reader now shows an absolute
date on its own line.

Both defensible — a list is scanned, a reader is committed — but nobody picked
it. The relative format arrived with the feed row, the absolute one with the
reader's Play-policy attribution, and they have never been looked at together.

Worth knowing before anyone changes either: the relative format is load-bearing
for the feed's layout stability (tabular mono, so the meta line does not shift
as it ticks), and the absolute one is what satisfies "show a publication date".

Logged in handoff 13.5.

---

## One small correction to the brief, since it affects a test

The brief said to assert the date fits using the longest format any locale
produces, "not the English one — German dates are longer."

**German is not longer.** English is, at 21 characters against German's 20:
German has the longer month names and gives it all back on a 24-hour clock,
where English pays for " PM". The test scans all five locales rather than
hardcoding a winner, so the next locale added cannot quietly become the longest.
