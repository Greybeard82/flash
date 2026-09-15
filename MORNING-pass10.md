# Device list — the whole redesign

**0.9.1+26 on the Lenovo and the Pixel.** Pushed through `eca7bcd`.
**1672 passing, 1 skipped, analyzer clean.**

**The Samsung M51 is still off USB.** It has been coming and going since pass 8;
nothing was done to it. One `adb install -r` when it reconnects.

This is the last list. It is not pass 10's list — pass 10 changed one thing —
it is a walkthrough of **Quiet Ink end to end**, because nobody has yet sat
down and used the whole thing in one go.

---

## Read this first

**One live bug, found on the Pixel while installing this build, and I did not
fix it.** It is release-only and it predates the redesign.

The unread-count notification **cannot dismiss itself**. Read everything and
the last count stays in the shade ("2 unread articles" on your Pixel as I write
this) instead of clearing. Turning the notification setting off does not remove
it either. Both need a manual swipe.

`plugin.cancel()` throws `Missing type parameter.` — R8 is on for release
builds, the app has no ProGuard configuration, `flutter_local_notifications`
ships none of its own, and its cancel path runs through Gson.

**It is not a regression from any of the ten passes** — the call dates to
`f95bb51`, and pass 9 only touched the posting side, which works fine.

I left it because it is build configuration rather than design: the likely fix
changes how the entire app is shrunk and wants verifying across every
notification path, not slipping in at the end of a pass. **No fix has been
tried.** It is written up in the handoff at 15.2. Your call.

---

## 1. Open it cold, on the phone

Force-stop first, then launch.

**What the redesign changed here:** teal is what you press, orange is a state
of the article. Every interactive mark in the app is teal now; orange means
unread or saved and nothing else. Red means broken.

**The one invariant worth actively trying to break:** scroll the feed and let
articles mark themselves read under you. **Nothing should move.** No headline
should reflow, no card should shift, no row should change height. Colour
changes, position does not. If you see the list twitch as something goes read,
that is the single most important bug you can report.

## 2. Read something

Tap an article. The bar at the top is **two lines** — source, then date
underneath — and four 48dp actions. No article title up there: four buttons
leave about 26 characters at phone width, which is a stub rather than a title,
and the page underneath already carries the real headline.

**Switch to clean view** (the FAB). Body text is Literata at 17 / 1.62.

> **Still unchecked after three passes, and the host suite structurally cannot
> see it:** add a **Cyrillic or Greek** feed and open clean view. Literata's
> subset is Latin only, so the text will silently fall back to another face
> with a line height tuned for Literata. I do not know what that looks like.
> This is the last thing on the list that has never been looked at.

## 3. Save it, then share it

Bookmark from the reader, then find the same article in **Alerts** if you have
a keyword that matches it. The bookmark there should already be **filled and
orange**.

That was a live data-loss bug until pass 9: the glyph in Alerts always drew
unsaved, so tapping what looked like "save this" ran a toggle that found the
row saved and **unsaved it**. Silently.

**Share a summary** to a chat and read what arrives: title, blank line,
summary, blank line, disclaimer, then the URL on its own line.

## 4. The tablet — this is pass 10's actual change

Open the three-column layout and tap an article in the middle column.

**The row you are reading now has a background.** A quiet `surfaceContainer`
wash, so the list and the reading pane agree about what you are looking at.
Deliberately not teal: the teal tint is already inside that row on the action
rail, and a teal row makes the rail vanish into it and reads as *pressed*
rather than as *current*.

**Then swap the sides while an article is open.** I tested this on your Lenovo
and the page does **not** reload — same Guardian consent dialog, same scroll
offset, same headline position before and after. That was the risk worth
checking, and it came out clean. If you ever see a swap throw you back to the
top of an article, the shell's layout order has been changed and that is why.

**The phone is unchanged by all of this.** The current-row highlight can only
turn on under the three-column shell, and Bookmarks, Alerts and search do not
set it at all.

## 5. The widget

Put the 1x1 widget on a home screen and **look at it next to the app icon** —
that is the whole point of the change and the only way to judge it.

- **Light OS:** white tile, near-black number
- **Dark OS:** dark tile one step up from the app's own surface, pale number

**Not a bug:** Flash in Dark on a Light OS gives you a **light** tile. The tile
lives on the launcher and should match the launcher — same reason Newspaper
mode does not put newsprint on your wallpaper.

**Still the one I most want eyes on:** force the count over 999 if you can.
"999+" should fit at around 20sp; one to three digits stay at the full 28sp.
The suite can prove the attributes and the threshold; it cannot measure a
TextView the launcher draws in another process.

## 6. The notification shade

Fire **two** keyword alerts on different keywords, then refresh. They should
collapse under **one heading** that counts them.

One alert on its own produces no summary at all — that is deliberate, since one
alert plus "1 keyword alert" is two notifications for one event.

The small icon should be **teal in both OS themes**. Confirmed live on both
devices: `color=0xff15868e`.

---

## What the suite still cannot see

Stated so it is not assumed. All of these are device-only, and all are above:

- Whether "999+" fits, and at what size it settles.
- Whether the widget reads correctly beside the app icon.
- Whether `values-night/` resolves the way the handoff describes.
- **Literata's fallback for non-Latin text.**
- Whether the feed genuinely never moves under the reader over a long scroll.

---

## Where the rest of it is written down

**`DESIGN-HANDOFF.md` section 15 is the exit inventory** — what is still open
at the end of the redesign and why each thing was left. A pointer at the top of
the document sends a new reader there first.

- **15.1** parked deliberately, with who decided
- **15.2** found and not fixed, including the notification bug above
- **15.3** decided against, carrying the argument and not just the verdict
- **15.4** the constants that look arbitrary and are load-bearing
- **15.5** the four harness rules

15.3 is the one that matters most six months from now. A decision without its
reasoning gets overturned by the next person who has the same idea.

**One gap I could not fill:** the pass 10 brief refers to "David's November
framing" of the two light-mode contrast exceptions. I could not find that note
anywhere in the work this document records, so 15.1 carries the framing as it
was actually recorded during the passes and says so. If the November note
exists, it belongs there.
