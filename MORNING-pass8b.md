# Morning list — pass 8b

**0.8.0+23 on the Lenovo and the Samsung.** Clean launch, zero errors in logcat
on both. Pushed through `be324d5`. **1611 passing, 1 skipped, analyzer clean.**

**The Pixel dropped off wireless debugging** part-way through, the way the
Samsung did last night (and the Samsung is back). Nothing was done to it. It
needs one `adb install -r` when it reconnects.

---

## 1. The bar, and the one thing I want you to look at first

Open any article. The bar is now:

`[×]  Sky Sports · Sep 15, 2026 9:44 …  [open]  [bookmark]  [share]`

**The date truncates.** Not the publisher — the publisher survives, because the
date is joined after it — but on a 360dp phone with four buttons, the text has
about 160dp and "Sky Sports · Sep 15, 2026 9:44 PM" does not fit. On the
article I opened it rendered as `Sky Sports · Sep 15, 2026 9:44 …`.

I did not anticipate this and it is the thing worth your judgement:

- Does it read as **intentional** — a source name with a timestamp trailing off —
  or as **broken**?
- Play policy wants a news app to show source and date. The date is in the
  string and is cut visually; the publisher's own page under the bar carries a
  full date too. I do not think this is a compliance problem, but it is your
  call and I would rather raise it than assume.

If it grates, the options are: drop the date from the bar and show the publisher
alone, shorten the date format, or go back to two lines and lose a button. I
have not done any of them.

**Try a long source too.** `The New York Times (World)` is the longest in the
starter pack at 26 characters — open something from there and see how much of
the date is left.

## 2. The three new buttons

- **Bookmark** — filled and orange when saved, outline when not, matching the
  card's action rail exactly. It follows changes made elsewhere: save an article
  from the feed list's rail, open it, and the glyph should already be filled.
- **Share** — the article title and link, same as the radial menu's share.
- **Open in browser** stays visible rather than going into an overflow. That
  reverses my recommendation and you were right to overrule it: the moment it is
  needed is the moment a page has failed to render.

**One thing to notice:** open an article **from the Alerts tab**. There is no
bookmark button there. That is deliberate — an alert-sourced article carries no
id, because its identity is (feed, guid), so nothing can be written. The button
is absent rather than present and doing nothing.

## 3. Share a summary to a chat, and read what arrives

Open an article, tap the sparkle on the card's rail, wait for the summary, then
tap **share** next to copy.

What arrives:

```
Microsoft proposes limits on its AI with code of conduct amid safety debate

Microsoft has published a voluntary code of conduct for its AI products,
setting out limits it says it will hold itself to while regulators are still
deciding what to require.
- The code covers model release, red-teaming and incident reporting
- It is not binding and carries no external audit
- Rivals have published similar documents in the past year

Generated on-device by Gemini Nano. May not be fully accurate.
https://www.theguardian.com/technology/2026/sep/15/microsoft-ai-code-of-conduct
```

**Copy now produces exactly the same bytes.** That is a change to shipped
behaviour: copy used to put the bare summary on the clipboard, with no title,
no link and no sign a machine wrote it. Paste it somewhere and check.

No new strings — both existing disclaimers survive the move into a message
because neither says "this" or "above". **One gap worth knowing:** neither names
Flash, so a recipient can tell an AI wrote it but not which app. Fixing that is
a new key in five locales; I did not.

## 4. Carried over from pass 8, because it needs a person

**The Literata fallback.** The reading font is subset to Latin. Add any Cyrillic
or Greek feed, open an article, switch to clean mode with the FAB.

The body should *not* draw boxes — Flutter falls back to the system font — so
what you are looking for is whether the fallback face at 17 / 1.62 looks
acceptable or obviously wrong. The line height was tuned for Literata and will
be applied to whatever the system substitutes.

The host test suite substitutes its own font and is structurally unable to see
this. It needs eyes.

---

## What I did not touch

The clean view toggle. I verified it rather than assuming: it is still a
floating extended FAB at bottom right with a text label, appearing only when a
clean version exists, and **not one line of it has changed since the day it was
written**. It is not in the bar and it keeps its label.

Two details that are not quite what the shorthand says, now recorded in handoff
12.5: the condition is `_cleanBlocks != null` rather than "a clean version
exists" — three different causes make it absent and look identical — and "does
not move" is true of its anchor, not its width, since an extended FAB sizes to
its label and the two labels differ in length.
