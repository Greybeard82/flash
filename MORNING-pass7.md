# Morning list — pass 7

**0.7.1+21 on all three devices.** Clean launch, zero errors in logcat on each.
Pushed through `13cfe97`.

You have not seen most of these screens since the redesign started, so this is
ordered by how much it would cost to have got wrong, not by how interesting it
is. Fifteen minutes end to end.

---

## 1. Categories — the one change you can actually see (Samsung)

Open **Categories**. Look at the right-hand end of a category header row.

Three controls sit there: pencil, bin, chevron. What you should see is **one
teal thing and two neutral ones** — the pencil teal, the bin and the chevron
grey.

It used to be pencil teal, bin grey, chevron *teal at 70% opacity*. Three
different teals in one row, one of them a strength that exists nowhere else in
the app.

**What would be wrong:** the chevron looking teal-ish, or looking lighter than
the bin beside it. They should be the same grey.

## 2. Filter bubble — the last capsules are gone (Samsung)

Feed → funnel icon, top right. Look at **Newest / Oldest**.

Corners should be **slightly rounded, not a lozenge**. Same corner as the
category chips behind the sheet. There should be a hairline border all the way
round and a hairline between the two halves — one line, not two different
weights.

While you are here: **Keyword blocklist** and **Keyword alerts** should match in
case. That landed in pass 6 but you may not have seen it.

**What would be wrong:** a pill shape, a missing divider, or the selected half
sitting flush against the border with no gap.

## 3. Quick Settings — the same control, twice (Samsung)

Quick Settings → **Theme** and **Summary length**. Both are the same segmented
button as above, three segments instead of two.

**What would be wrong:** these looking different from the filter bubble's. They
share one theme entry now, so any difference is a bug.

## 4. Keyword panels — the red is gone (Samsung)

Filter → **Keyword alerts**. If you have keywords, look at the bin at the end of
a row: **grey, not red.**

Then tap a bin. The confirmation block that appears should be a **neutral raised
grey**, not a pink wash. The sentence inside it still names how many cards
disappear — that is where the consequence lives now.

Same in **Keyword blocklist**.

**This is the one I would most like a second opinion on.** Removing the pink
tint takes away the only thing that made that block look different from the rows
around it. It now separates by tone alone. If it reads as "just another row",
say so — the fix is an outline or a left rule, and that is a design decision I
deliberately did not make. It is logged in handoff 9.2.

## 5. Settings — a row with nothing behind it

Quick Settings → **More settings** → scroll to **About**.

Under *Privacy policy* there is a new greyed-out row: **Ad privacy choices /
Available when ads are introduced**. It does nothing and cannot be tapped.

It is there because EEA and UK ad rules need a permanent way to withdraw
consent, Settings is where that lives, and Settings was open tonight. The copy
is an English-only constant, **not** a translated string — the real wording
ships with the ads pass and five locales twice is waste.

**What I want from you:** is that the right place for it? Position is the whole
of what shipped.

Also in Settings: **Import backup**. Tap it and look at the confirm button —
**teal, not red.** Cancel out; do not actually restore.

## 6. Onboarding — only if you are willing to lose your data

**Skip this unless you feel like it.** Seeing it means clearing app data, which
wipes your feeds.

The Start-reading button's corners changed from the card radius to the button
radius, so it matches every other primary button. It is a small thing and not
worth your library.

## 7. Tablet — one look

Open Flash on the **Lenovo**. Categories, then the filter bubble.

Nothing is tablet-specific in this pass; this is just confirming the sweep did
not disturb the three-column layout. If the columns are there and the sections
list on the left is intact, it is fine.

---

## Two things I decided not to do, which need your ruling

**1. The segmented buttons are 48dp tall, and 1.7 asked for 40.**

Not an oversight. The segment *paints* at 48 — that is fill, not a tap halo
around a 40dp body, because Flutter lays every segment out at a uniform tight
height and the tap padding ends up inside the paint. Getting to 40 takes the
**touch target** to 40 with it, 8dp under the floor this app holds itself to.

The two places we already go under 48 — the 36dp folder chip and the 36dp rail
halves — each got an explicit decision from you and a test saying why. This
would be the third, and 1.7 does not mention touch targets at all. So: reported,
with the number, the way the FAB gap was.

**Say the word and it is one line.**

**2. The app bar's white band is not a bug, and there is a question behind it.**

Measured: the status bar inset is consumed exactly once. The band is the status
bar drawn over the same white as the app bar, plus 14dp of title centring.

| device | status bar | above the title |
|---|---|---|
| Lenovo Tab M11 | 39.3dp | 53.3dp |
| Samsung M51 | 34.7dp | 48.7dp |
| **Pixel 11 Pro** | **65.5dp** | **79.5dp** |

The Pixel's is nearly twice the Samsung's and it is the system's number, not
ours. The design question — should the app bar carry a different tint so the
band stops reading as empty — is logged for Design in handoff 9.5 and not
actioned.

---

## What I did not build, and listed instead

Eight items in **handoff 9.2**. Each would have meant inventing a value or a
component rather than swapping to a role that exists. The two worth your eye:

- **Empty states are split 2–2** across the app between two legal muted roles.
  Nobody has picked one.
- **Alerts' empty state is text-only**, where every other empty state pairs a
  large glyph with muted copy. That is a missing component, not a wrong colour.

---

## One correction from tonight, since it is the kind you would want to know

I wrote a test asserting the segmented buttons still show a selected checkmark,
and a handoff entry calling it an open gap. Then the filter bubble rendered
without one, which sent me to the call sites: **all three already pass
`showSelectedIcon: false`.** The item had been closed before the theme entry
existed.

The test was true of the bare widget it built itself and false of every
segmented button in the app — coverage-shaped, covering nothing. It is now a
guard on the call sites, which is the only place the flag can be got wrong, plus
a tripwire that deletes itself if Material ever changes the default.

Caught by looking at a screenshot. Worth saying out loud.
