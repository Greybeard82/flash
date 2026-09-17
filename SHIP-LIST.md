# Ship list — Flash 0.9.7 (build 32)

The build that goes to the 25 testers. This is a statement of what is going
out, not a checklist to work through.

**APK 64,552,860 bytes.** Net change since 0.9.2, the last version with a
recorded size: **+34,684 bytes**, or 0.05 percent.

---

## 1. Release notes — paste this

Written for the testers. Plain language, no internals, nothing they cannot
see for themselves.

> **Flash 0.9.7**
>
> **Categories**
> - Make a category and you land in it. Flash takes you straight there instead
>   of leaving you to find it.
> - A brand-new category now says "Nothing here yet" with a button to add a
>   feed, instead of telling you that you are all caught up.
> - Category and feed names capitalise like names. Type "travel" and the
>   keyboard offers "Travel".
> - Adding a feed or making a category on one screen updates the article list
>   straight away, without a pull to refresh.
>
> **Reading**
> - Russian and Greek articles now read in the same typeface as everything
>   else. They used to quietly fall back to a different font.
> - Notifications are fixed. Some of them silently failed to appear in
>   released builds.
>
> **Look and feel**
> - New switches throughout Settings, with square shoulders to match the rest
>   of the app. They respond to a swipe as well as a tap.
> - The confirmation and warning banners are readable now. They were very
>   nearly invisible against the page.
> - Text contrast has been brought up to standard everywhere.
> - Newspaper mode identifies its sections by name rather than by colour.
>
> **Backup**
> - Your bookmarks are included in a backup file now. Older backup files still
>   restore fine.
>
> **Under the hood**
> - Flash now draws using Android's current graphics engine. Animations should
>   feel smoother, especially the first time you see each one. **This is the
>   change most worth telling us about if anything looks wrong.**

---

## 2. Known broken, shipping anyway

Named rather than omitted. None of these is a surprise and none is a reason
to hold the build.

**The folder bar still gives no sign that it scrolls.** A newly created
category is now scrolled into view, which was the reported bug. Everything
past the third or fourth chip is still reachable only by a sideways swipe
nothing advertises. The fix for the class — an edge fade, or a scroll hint —
was not made. **This is the most likely thing a tester reports that we
already know about.**

**The home screen widget is untested by me, on any device.** Placing a widget
needs a home screen, which is not mine to change. Its "999+" overflow has
never been rendered at all. If a tester uses the widget, their report is the
first real evidence it works.

**Boot-completed refresh is untested** for the same reason: it needs a
reboot, and reboots are not mine to perform.

**Portrait tablets are not supported and this is deliberate.** Tablets are
landscape-locked. A tablet held upright does nothing, by design — the wide
layouts are built across, and the fallback is a worse version of the same
screens. Do not file it.

**`RssService` cannot be given a test client.** Its fetch calls a top-level
HTTP function, so the error paths around it are exercised only indirectly.
The behaviour is correct as far as it has been checked; the coverage is
thinner than the rest.

**The test suite flakes under full-run parallelism.** Two files, one of them
a clean-mode test that passes in isolation every time. It is a test-harness
problem, invisible to users, and it is on the post-launch list. It appeared
once during this pass's verification and passed on both re-runs.

**Google Play Billing is not integrated.** The free/paid split is specified
and not built. Everyone testing now keeps everything permanently, as promised
on the site.

---

## 3. The one real risk in this build

**The renderer changed.** Flash spent its whole life on Flutter's legacy
graphics backend because of an opt-out nobody documented, added in a commit
that does not mention it. That flag is deprecated upstream and is being
removed, so the choice was between changing it deliberately now or having it
change by itself later, in an unrelated build, with no way to connect any
resulting bug to the cause.

It is verified — Vulkan on all three devices, no errors, no visual difference
including the embedded browser in the reader, and the suite unchanged. But it
is the kind of change that shows up on hardware nobody in this room owns.

**That is exactly what 25 testers and two weeks are for.** If something looks
wrong in a way that is hard to describe — a flicker, a smear, a shadow in the
wrong place, text that renders oddly for a moment — that is the first thing
to suspect, and the report is valuable even without a reproduction.

---

## 4. Verified on device for this build

| Check | Samsung M51 | Pixel 11 Pro | Lenovo Tab M11 |
|---|---|---|---|
| Installs and launches | yes | yes | yes |
| Impeller Vulkan backend | yes | yes | yes |
| No Flutter errors at launch | yes | yes | yes |
| WebView in the reader | yes | **not checked** | yes, in the pane |
| New category selects and scrolls to | yes, with a feed | — | yes, empty |
| New empty-category state | — | — | yes |
| Cyrillic in the reading view | yes | — | — |

**The Pixel's WebView was not checked visually.** The device was in a personal
video call when its turn came, and driving it would have meant interrupting
that. Its renderer was confirmed from the log, and the WebView is the same
component on all three; it is the one line in this table taken on inference
rather than on sight. Worth one look before the build goes out.

---

## 5. What to watch in the first 48 hours

Not measurements — things to feel.

- **First-run animation smoothness.** The read fade, the radial menu, the
  banner sliding in, the summary sheet. Impeller compiles its shaders ahead
  of time, so the benefit is specifically the *first* time each effect plays.
  That is also where a regression would show.
- **Anyone who subscribes to a non-Latin feed.** Russian and Greek are in.
  Chinese, Japanese, Korean, Arabic and Hebrew still fall back to the system
  font — deliberately, on size — and emoji in headlines always did.
- **Anyone who creates a category in a library that already has several.**
  That path changed twice in two builds.
