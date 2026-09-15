# David's list — the things only you can do

Everything else in the pre-launch QA is either done or written down as a
decision. These five need you, and for four of them the reason is that they are
not app operations at all.

---

## 1. Place the widget on a home screen

**Why not me:** putting a widget on a home screen is a launcher interaction, not
something the app can do and not something `adb` can do honestly.

Long-press the home screen → Widgets → Flash → the 1×1 unread tile.

**What to look for:**

- **Next to the app icon.** That comparison is the entire point of the colour
  change and the only way to judge it.
- **Light OS:** white tile, near-black number. **Dark OS:** dark tile one step
  up from the app's own surface, pale number.
- **Not a bug:** Flash in Dark on a Light OS gives a **light** tile. The tile
  lives on the launcher and should match the launcher.

### The "999+" case, which is now closed as unverifiable

I cleared the Samsung with your approval and that cost the 2153-unread backlog
that made it the right device for this. Rebuilding it takes days of real feed
traffic, and seeding it artificially would not be a device test, so **do not
rebuild it for this.**

If a backlog ever crosses 999 naturally, look once: **"999+" should fit at
around 20sp**; one to three digits stay at the full 28sp. Worst case if it does
not fit is an ellipsis on the tile — wrong, not broken, and one line to fix.

## 2. Reboot a device, once, whenever it suits

**Why not me:** rebooting your phone is yours to do. The standing rules forbid
it and they are right to.

Nothing needs a reboot *for its own sake*. But `ScheduledNotificationBootReceiver`
runs on `BOOT_COMPLETED`, walks the same Gson path that the ProGuard bug broke,
and has never been exercised on a real boot with the fix in place.

**What to look for:** nothing at all. No crash, no notification appearing that
should not, Flash's unread count unchanged after the reboot. It is a
does-nothing-visible test; a silent pass is the pass.

The same path also runs on `ACTION_MY_PACKAGE_REPLACED`, which every
`adb install -r` triggers, and that has been clean on all three devices all
day. So this is confirmation, not discovery.

## 3. Check the three banner classifications I flagged

I classified all 18 banner messages and applied it. **Three are judgement
calls** and you will spot a wrong one faster than a round trip would:

| message | shows | I called it |
|---|---|---|
| `alertKeywordExists` | "…is already an alert keyword" | **failure** — you asked to add it and it was not added |
| `opmlExportEmpty` | "There are no feeds to export yet." | **failure** — a refusal, nothing was exported |
| `cleanModeUnavailable` | "Clean view not available for this page" | **failure** — though nothing malfunctioned |

All three are refusals rather than malfunctions. I read a warning glyph as the
honest answer for "what you asked for did not happen", but the opposite reading
is defensible and it is your call.

## 4. Decide on Impeller

Tested and reported; the decision is yours. Short version: it runs, it renders
correctly including the WebView, the suite passes unchanged, and **nobody ever
wrote down why it was turned off**. There is now a dated line in the PRD so the
deadline has an owner.

**My recommendation is to remove the opt-out**, because the only argument for
keeping it would be the original reason and there is no record of one.

## 5. Decide on read state in backups

Bookmarks are in the backup now, stored by value. **Read state is not**, and
the recommendation against it is arithmetic rather than taste:

- Retention is a rolling **7 days** (`kFetchDayLimit`). A restore refetches and
  discards anything older, so a backup **a week old matches zero articles**.
- Cost would be ~119 bytes per article: **150–250 KB** for a normal library,
  where everything else in the file is about **4 KB**.

You can overrule this, and now you would be overruling it with the number in
front of you, which is the point.

---

## Two smaller things, for information

**The Literata gap is now known rather than suspected.** A Cyrillic feed in
clean view renders with no tofu at all, but in a **grotesque sans, not
Literata** — the reading view's typographic identity is simply gone for
non-Latin articles. The 1.62 line height reads loose on it rather than wrong.
Not fixed: bundling Cyrillic and Greek subsets costs app size for a case most
readers never hit, and accepting the sans is defensible. Knowing is the win.

**The emulator is stopped and stays stopped.** No emulator will be started
again in this project.
