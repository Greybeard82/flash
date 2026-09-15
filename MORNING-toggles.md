# Morning list — 0.9.6+31

Four commits, in the order you asked for them. Two of the four were bugs you
reported and **neither reproduced on 0.9.5+30** — read the notes on those
before you spend time on them.

The switch is the one that can be backed out on its own. It is the last
commit, it touches five files, and reverting it takes the call sites with it.

---

## 1. The disappearing category — on a phone AND on the tablet

The one that mattered. Do it first and do it twice.

1. Article list open. Menu → Categories.
2. Add a category. Add a feed to it.
3. Back to the article list.
4. **The new category should be in the folder bar before you touch anything.**
   No pull to refresh.

Then the same on the Lenovo, where the three-column layout can show you the
Categories column and the article list at the same time — that is the case a
"reload on pop" fix would have missed entirely, and why the fix is a broadcast
instead.

Also worth one try: do it while a background refresh is running (pull to
refresh, then immediately go add a category). The change used to be queued and
dropped; it should now land when the fetch finishes.

**I could not reproduce your original report.** Tapping in from the phone, the
tablet, and the back gesture all updated on 0.9.5+30. The fix is real — the
feed screen genuinely had the pull half of the notifier and not the push half
— but I cannot tell you it fixes the thing you saw, because I never saw it. If
it happens again, tell me what was on screen when the category was made.

## 2. Every Settings row, in three themes — and **drag one, do not tap it**

The switches are custom now. Stock Material could not make a square-shouldered
toggle: `SwitchThemeData` has no shape property and the track radius is
hardcoded to half the height. So this is a new widget, and new widgets are
where the small things break.

Eight rows changed:

- **Settings** — three rows
- **Quick Settings** (the bubble) — four rows
- **Filter bubble** — one row

In **Quiet Ink light, Quiet Ink dark, and Newspaper**. What to look at:

- the shape, which is the point — square shoulders, not a capsule. If the
  curve is wrong, it is **one number**: `kFlashSwitchCornerRatio` at the top
  of `lib/widgets/flash_switch.dart`, currently 0.32. 0.5 is the Material
  stadium, 0.0 is a hard rectangle. Say a number and I will set it.
- **drag the thumb across, do not tap it.** Tap is the easy path and it works.
  Drag is the one I rebuilt: it commits on distance — a quarter of the track —
  rather than on release velocity, so a slow push has to work too. Try a slow
  one and a flick.
- drag a switch that is already on, to the right. Nothing should happen.
- the off track is a deliberate dark grey, not the pale Material one. The pale
  track measures about 1.1:1 against white and only exists because of its
  outline; this one clears 3:1 on its own in all three themes.

## 3. The segmented buttons — **not reproduced, and I changed nothing**

You said they still look like capsules. On 0.9.5+30, on your device, they do
not: theme picker and sort order both render a rounded rectangle at radius ~9
with square dividers between the segments, which is what the design asks for.

If they still look wrong to you, **the disagreement is about the value, not
about whether the theme applies** — send me a screenshot and a number.

One thing I found that is worth your knowing: the segments themselves are
square *by construction*. Flutter hardcodes their shape and throws away
whatever the theme says. The outer corner is the theme's, the inner dividers
never can be. Nobody should spend an afternoon trying to round them.

## 4. Capitalisation — three fields

New category, new feed, rename. All three now capitalise the way a name does
rather than the way a sentence does. Type "travel" and the keyboard should
offer "Travel".

---

## Still open from earlier lists

- **The home screen widget** and **boot-completed refresh** — still untested by
  me, still on your list. Both need a device state I am not allowed to create.
- **"999+"** — closed as unverifiable. It needs a real unread count over 999.
