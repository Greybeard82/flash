# Device list — pass 9

**0.9.0+25 on the Lenovo and the Pixel.** Clean launch, zero logcat errors.
Pushed through `b8c4cf2`. **1647 passing, 1 skipped, analyzer clean.**

**The Samsung M51 is off USB again.** It has been coming and going all session;
nothing was done to it. One `adb install -r` when it reconnects.

**This list matters more than usual.** Two of the three sections are native and
barely testable in the host suite. One thing I *was* able to confirm on the
tablet, read-only: the live notification now carries `color=0xff15868e`.

---

## 1. Fire two keyword alerts on different keywords

Filter → Keyword alerts → add two keywords that will both hit on the next
refresh. Then refresh.

**What you should see:** the two alerts collapse under **one heading** that
counts them — "2 keyword alerts" — rather than two loose cards.

**What would be wrong:** two separate cards with no heading (the summary did not
post), or a heading plus only one alert (the group key drifted), or a third card
saying "1 keyword alert" (the below-two guard failed).

**One alert on its own should produce no summary at all.** That is deliberate —
one alert plus "1 keyword alert" is two notifications for one event.

## 2. The small icon's tint, light and dark

Pull the shade down with any Flash notification in it and look at the small
icon. It should be teal, not grey.

Then look in the other OS theme. Same teal — it is a single constant, because
`Notification.color` is one ARGB read in the system's process with no theme to
resolve against.

**Measured, and it agrees with the handoff to the digit:** 4.35:1 on a light
shade, 3.96:1 on a dark one, 3.69:1 on the shade card. All clear the 3:1 a
tinted icon is held to.

## 3. The widget, both OS themes

Put the 1x1 widget on a home screen. It was **newsprint cream under a warm
orange** — palette-era leftovers sitting next to a teal app. It should now be:

- **Light OS:** white tile, near-black number
- **Dark OS:** dark tile one step up from the app's own surface, pale number

**Check it against the app icon beside it.** That is the whole point of the
change and the only way to judge it.

**B10, so nobody reports it as a bug:** if you run Flash in Dark on a Light OS,
the tile is **light**. That is correct and deliberate — the tile lives on the
launcher and should match the launcher, which is also why Newspaper mode does
not put newsprint on your wallpaper. It is recorded in the `values-night` file
itself so the next person to wonder finds it there.

## 4. Force a count over 999 if you can

The clamp moved from 99 to 999, and the TextView now autosizes between 18sp and
28sp.

**What to look for:** "999+" fitting, not "99" or an ellipsis. One to three
digits should still be the full 28sp; only the four-character case shrinks, to
around 20sp.

**This is the one I most want eyes on.** The host suite can prove the attributes
exist and the threshold is 999; it cannot measure a TextView the launcher draws
in another process. If "999+" is clipped, the autosize bounds are wrong and it
is a one-line fix.

## 5. The Alerts bookmark bug — worth confirming by hand

This was a live data-loss bug on 25 testers' phones.

1. Save an article from the feed.
2. Find the same article in the **Alerts** tab.
3. **The bookmark there should already be filled and orange.**

Before this pass it showed empty, and tapping it — which looks like "save this"
— *unsaved* the article. The bookmark was gone and nothing said so.

Then **open that article from Alerts**. The reader's bookmark should be there
and filled. Before this pass the reader had no bookmark button at all for
anything opened from Alerts, while the list behind it bookmarked the same
article perfectly well.

---

## Carried over, still unlooked-at

- **The Literata fallback** (pass 8). Add a Cyrillic or Greek feed, open clean
  mode, and see what the substituted font looks like at 17 / 1.62. The host
  suite substitutes its own font and is structurally unable to see this.
- **The reader bar's two lines** (pass 8c), if you have not seen them.
- **The summary share payload** (pass 8b) — share one to a chat and read what
  arrives.

---

## What the suite proves about the widget, and what it does not

Stated because it would otherwise be assumed.

**Real:** the four colour values in both directories, the autosize attributes
and bounds, the clamp threshold and its "+" form, that the layout reads
resources rather than literals, that the radius is untouched.

**Device only:** whether "999+" actually fits and at what size, whether the tile
reads correctly beside the app, and whether `values-night` resolves the way B10
describes.

`widget_resources_test.dart` carries a test asserting it contains no
`testWidgets`, so a future rendering assertion has to argue with that first.
