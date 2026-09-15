# Morning list — pass 8

**0.7.2+22 on the Lenovo and the Pixel.** Clean launch, zero errors in logcat on
both. Pushed through `da13bf6`. **1569 passing, 1 skipped, analyzer clean.**

**The Samsung M51 dropped off USB part-way through the session** and never came
back — `adb` stopped seeing it entirely, mid-command. Nothing was done to it; it
had 0.7.1 installed and launching cleanly before it went. Plug it back in and
it needs one `adb install -r`. I did not touch any device setting to try to
recover it.

---

## 1. The clean view. This is the whole pass, and a test cannot judge it.

**Open an article. Tap the FAB to switch to clean mode. Then read a few
paragraphs properly — not scan them.**

What changed: the body is Literata now at 17px with a 1.62 line height. It was
Instrument Sans at 16 with 1.5. Sub-headings inside an article (h3) were sans
and are now the same serif, bold, at the body size.

**What I want to know, and only you can answer it:**

- Does a long paragraph hold together, or does 1.62 feel loose?
- Does 17 feel right, or large? It is one step up from everything else in the
  app, deliberately — this is the one surface whose job is sustained reading.
- Do the bold serif sub-headings read as headings, or as bold paragraphs? They
  sit at the same size as the body now. That is the part I am least sure of.

Try it on the **Pixel and the tablet** — the tablet caps the measure at 720dp
and the phone does not, so the line lengths are quite different.

In **Newspaper mode** the clean view stays PT Serif and only the size and line
height move. Worth one look to confirm it did not inherit Literata.

## 2. Alerts finally has an empty state

**Alerts tab.** If you have no alert keywords, there is now a bell above the
text instead of a line of grey floating in the middle of the screen.

It is the same bell the nav destination uses, at the same 48dp/12dp every other
empty state uses. **It is also the same bell the keyword alerts panel's empty
state uses** — both are about alerts, so I left it, but if seeing them together
looks like a duplicate, say so.

## 3. Three empty states got slightly darker copy

**Bookmarks** (empty), **Alerts** (empty), and **Filter → Keyword alerts**
(empty, first line only).

They were using the most recessive grey in the palette. The rule now is: when a
screen is empty, that copy is the only content on it, so it takes the ordinary
secondary ink — the recessive one is for a *second* line under a first.

Nothing moved; only the grey. If Bookmarks-empty now looks heavier than you
want, that is the change.

---

## Two things worth knowing that are not visual

### A test caught me reverting something correct

I swept the tablet's **idle reading pane** — the "Select an article to read it
here" column — into the empty-state rule. `ink_roles_test.dart` failed in both
brightnesses and was right to: nothing is empty there. The middle column is
full of articles and the right one is waiting to be told which. Pass 2 decided
that deliberately.

Reverted. The exclusion is now *asserted* rather than just absent, so the next
person who sweeps it gets the same failure with the reason attached.

### Literata cannot render every language, and a feed can feed it any

The font is subset to Latin — no Cyrillic, Greek, CJK, Arabic, Hebrew or emoji.
The clean view renders article bodies from **whatever feed you add**, and
nothing restricts a feed's language.

It will not draw tofu; Flutter falls back to the system font. The consequence is
that a Russian or Japanese feed's articles silently stop being Literata, with a
line height tuned for one face applied to another.

**Ten-second check if you feel like it:** add any Russian-language feed, open an
article, switch to clean mode. If the body looks like the rest of the app rather
than like the serif, that is the fallback. I could not test this — the host
suite substitutes its own font and cannot see font fallback at all.

---

## Answers you asked for

**Notification channels, for pass 9.** There are two, and **they are already
separate** — `flash_keyword_alerts` at importance 3, `flash_unread_count` at
importance 2. **B8 is already done; there is nothing to migrate.** Verified live
on the Lenovo.

The part that matters for the 25 testers: channels are created *lazily*, on the
first notification of that kind. The Lenovo has the unread channel and **not**
the keyword one, because no keyword alert has ever fired on it. So testers do
not have a uniform set — each has whatever their own usage triggered. Full
detail in handoff 11.6, including what a migration would cost if one were ever
needed.

**The reader action bar.** Not started, not threaded, as ruled. My
recommendation in one line: **take the overflow.** Open-in-browser is the escape
hatch for pages that do not render — a considered act, not a reflex — while
bookmark, share and close are all reflexes, and 160dp of title is about twenty
characters on the one screen where knowing which article you are in matters
most. Full paragraph, with the counter-argument, in handoff 11.7.

**`#15868E`.** The API≤30 window is live *and* nothing sets
`Notification.color` anywhere, so the token is orphaned rather than at risk.
Both halves recorded under 1.3 — either one alone is misleading.

---

## One correction on myself, recorded in the handoff as a standing rule

Last night's "showSelectedIcon gap" was not a gap. All three call sites already
passed the flag; my test had built its own SegmentedButton and asserted against
that, so it was true of the test and false of every button in the app.

That is now handoff 10.2, next to "assert the mutation landed": **a test that
constructs its own subject proves a fact about the test.** It is the fifth
harness-blindness incident in this project and the first of that exact shape,
and the handoff says plainly that a screenshot caught it and the suite did not.
