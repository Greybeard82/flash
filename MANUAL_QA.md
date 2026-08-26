# Flash — Manual QA Checklist

Items that cannot be reliably verified in an automated test suite. Run on a physical Android device (Pixel 9 Pro recommended) against the current release build.

---

## 1. Dynamic Colour Theming (Android 12+)

| Step | Expected |
|------|----------|
| Open Settings → Wallpaper & Style and change your wallpaper | System generates a new Material You colour scheme |
| Relaunch Flash | App accent colours (FAB, tabs, selected state, chip backgrounds) update to match the new wallpaper palette |
| Set a neutral (grey/white) wallpaper | App falls back to a safe neutral palette; no garish colours |

---

## 2. Edge-to-Edge Layout & Window Insets

| Step | Expected |
|------|----------|
| Open Flash on a device with gesture navigation | Article list scrolls fully behind the bottom nav bar with proper padding; no content clipped behind the system bar |
| Open Flash on a device with three-button navigation | Same — nav bar background does not cover content |
| Rotate to landscape | Layout adjusts; no overflow; FABs remain reachable |
| Check status bar area | App content does not overlap the status bar icons |

---

## 3. Predictive Back Gesture (Android 14+)

| Step | Expected |
|------|----------|
| Open Settings, then drag the back edge slowly | Predictive back peek animation plays (partial screen reveal of the previous screen) |
| Complete the gesture | Returns to feed; scroll position is restored |
| Trigger predictive back from Search screen | Returns to main feed smoothly |
| Trigger predictive back from Settings | Returns to previous nav destination |

---

## 4. Haptic Feedback

| Step | Expected |
|------|----------|
| Swipe an article left or right | Light haptic tap fires at gesture completion |
| Tap "Mark all as read" FAB | Medium haptic tap fires |
| Long-press an article card | A brief haptic pulse fires as the radial menu opens |
| Toggle any swipe gesture rapidly | Each gesture produces exactly one haptic event (no stacking) |

---

## 5. Scroll Performance

| Step | Expected |
|------|----------|
| Load a feed with 50+ articles | Fling the list; scroll is smooth, no dropped frames visible |
| On a 120 Hz device (Pixel 8 Pro, Pixel 9 Pro): enable developer option "Show refresh rate" | Counter reads ≥ 90 Hz during active scroll |
| On a 60 Hz device | Counter reads 60 Hz; no jank |
| Scroll while thumbnails are loading | Thumbnails load in without causing scroll stutter |

---

## 6. Cold-Start Performance

| Step | Expected |
|------|----------|
| Force-stop Flash (recent apps → swipe away, or `adb shell am force-stop io.getflash.app`) | — |
| Tap the Flash icon and start a stopwatch | Lightning bolt animation visible within 1.5 seconds of tap |
| Wait for animation to complete | Feed list populated with fresh articles |
| Repeat 3× to get a representative average | All runs < 1.5 s to first meaningful paint (cached list visible) |

---

## 7. Background Refresh Speed (20 feeds, Wi-Fi)

| Step | Expected |
|------|----------|
| Add at least 20 feeds across multiple folders | — |
| Tap the Refresh FAB and start a stopwatch | Spinner appears immediately |
| Stop when spinner disappears | All 20 feeds refreshed in < 8 seconds on a good Wi-Fi connection |

---

## 8. Real Gemini Nano Summary

| Step | Expected |
|------|----------|
| Ensure device supports Gemini Nano (Pixel 8 Pro / 9 Pro, Android 14+) | — |
| Long-press an article → tap ✦ Summary | Bottom sheet slides up with loading skeleton |
| Wait for on-device inference | Summary appears as 4 concise bullet points, no API key required |
| Trigger from an article with a paywall / redirect | "Couldn't retrieve" error state shown gracefully |

---

## 9. Google Drive Backup / Restore Round-Trip

| Step | Expected |
|------|----------|
| Settings → Google Drive → Sign in | OAuth consent screen shown; sign-in completes |
| Tap "Backup now" | "Backup saved" confirmation shown |
| Open Google Drive (any device) → Storage → app data | `flash_backup.json` is NOT visible (private appdata, correct) |
| Add a new feed and folder | New items appear in Flash |
| Tap "Restore from Drive" | Shows feed/folder/keyword counts before confirming |
| Confirm restore | App wipes existing data, re-inserts backup contents; new feed/folder gone |
| Articles re-fetched on next refresh | ✓ |

---

## 10. Folder Tabs Position (Thumb-Zone Hard Requirement)

| Step | Expected |
|------|----------|
| Create two or more folders | Tab bar appears |
| Observe tab bar position | Tabs are **at the bottom** of the content area, directly above the navigation bar — NOT at the top |
| Tap each tab | Article list switches; scroll resets to top for a tab not previously visited |
| Revisit a tab after scrolling it partway | Scroll position is restored to where you left it |

---

## 11. Minimum Tap Target Size

| Step | Expected |
|------|----------|
| Enable Settings → Developer options → Show tap highlights | — |
| Tap every interactive element (nav bar items, FABs, folder tabs, swipe actions, settings rows) | Highlight covers ≥ 48×48 dp in all cases; no tiny hit areas |

---

## 12. Swipe Mark-as-Read (Dims In-Place)

The height check below cannot be automated. `flutter_test` renders with a font
whose glyphs all share identical metrics, so a font-weight change produces no
measurable size difference in a widget test — a height-equality assertion there
passed just as happily before the fix as after it. A device is the only place
this regression is visible.

| Step | Expected |
|------|----------|
| Swipe an article to the LEFT | Article dims in-place (reduced opacity); stays in list; no removal animation |
| Swipe an article to the RIGHT | Same result — article dims in-place |
| Pick an article whose title wraps to three lines, and watch it closely as it dims | **The card's height does not change.** Nothing below it moves. Read state is carried by colour and opacity only; the title weight is constant at `w600` |
| Scroll away and back, with **Show read** on | Dimmed article is still present at its original position |
| Same, with **Show read** off | The article is gone once the list rebuilds — see §19 |

---

## 13. Onboarding (First-Launch Only)

| Step | Expected |
|------|----------|
| Clear app data (`adb shell pm clear io.getflash.app`) and relaunch | Onboarding flow appears |
| Complete the flow | Flag persisted; relaunching the app goes directly to the feed |
| Repeat launch | Onboarding never shown again |

---

## 14. Cross-Tab Unread Counts (Live)

| Step | Expected |
|------|----------|
| Note the "All" tab's badge and the "Gaming" tab's badge | — |
| Stay on the All tab and scroll past several Gaming articles (mark-read-on-scroll on) | Both badges decrement together, live, without switching tabs |
| Switch to the Gaming tab | The badge shown there already matches what the tab bar displayed before switching |
| Open an unread article directly, then go back | Both the opened article's folder badge and All badge decrement immediately |
| Wait ~1 second after a scroll-read burst | Counts still match the DB (reconciliation query self-heals any drift) |

---

## 15. Folder Tab Size

| Step | Expected |
|------|----------|
| Open the folder tab bar with 2+ folders | Tabs are visibly taller than before (60dp bar vs the old 48dp) |
| Tap a tab with a light, imprecise thumb tap near its edge | Registers reliably — no need to aim precisely |
| Tap a tab | A visible ripple plays from the tap point |
| Switch tabs repeatedly | Selected tab auto-scrolls into view within the horizontal tab strip |

---

## 16. Global Loading Indicator

| Step | Expected |
|------|----------|
| Add a feed, delete a folder, run an OPML import, open an AI summary, restore from Drive | Each operation shows a thin progress bar at the top of the content area |
| Trigger a fast, near-instant operation (e.g. toggling a settings switch) | No flash of the indicator — it only appears after ~150ms |
| Force an error (enable airplane mode, then add a feed) | The indicator disappears once the operation fails — it never hangs visible |
| Trigger two operations back to back | Indicator stays visible continuously across both, only disappearing once the last one finishes |

---

## 17. Resume Refresh

| Step | Expected |
|------|----------|
| Open an article in the external browser, then return to Flash within ~10 seconds | No network fetch runs; scroll position is untouched |
| Background the app for at least 2 minutes, then return | A network fetch runs automatically; new articles appear at the top |
| After that fetch, check where the list sits | **The list has reset to offset 0.** Preserving the old offset would point it at different content, since new articles insert *above* the viewport |
| Wait ten seconds, then look at the articles that just arrived | **They are still unread.** This is the point of the exercise: the jump to the top must not be mistaken for the user scrolling past them. Anything newly fetched showing up dimmed is a `MarkReadGate` regression |
| With **Show read** on, look for articles read earlier | Still present, dimmed. Nothing is purged by a refresh — a refresh never deletes |
| With **Show read** off, same check | Read articles are absent. Deletion is still not involved; they simply no longer match the visibility rule |
| Return to the app again immediately after the above fetch | No second fetch fires (5-minute minimum interval) |

---

## 18. AI Summary Reads the Full Article

| Step | Expected |
|------|----------|
| Pick an article whose RSS description is a one- or two-sentence teaser | — |
| Long-press → ✦ Summary | Sheet shows "Reading the article…" first, then "Writing the summary…" once generation starts |
| Wait for the summary | The summary contains information NOT present in the teaser (i.e. it summarised the full article, not the RSS blurb) |
| Trigger a summary on an article that is a single-topic piece (no distinct sub-points) | Summary renders as flowing prose with no bullet points |
| Trigger a summary on an article covering several distinct points | Summary renders as an opening sentence followed by short bullets |
| Trigger a summary on an article whose extraction fails (e.g. a URL that 404s) | Summary still generates from the RSS description, with a small "Based on the article preview only." note under the disclaimer |

---

## 19. Read Visibility and the Show Read Toggle

**Show read** lives in the Filter bubble (the funnel button, top right). Read
articles are never deleted by this setting — deletion is the cleanup window's
job, a separate rule this one never consults.

| Step | Expected |
|------|----------|
| Find a Gaming folder with at least two unread articles (call them 5 and 6). Turn **Show read on**. Start on the All tab | All shows 5 and 6; Gaming shows 5 and 6 |
| Scroll past article 5 in All (mark-read-on-scroll on) | Article 5 dims in place in All |
| Switch to Gaming | **Article 5 is still there, dimmed, in position.** Read state lives on the row, so it is the same answer in every tab |
| Switch back to All | Unchanged — 5 dimmed, 6 full weight |
| Now turn **Show read off** and Apply | The list re-queries and resets to the top. Article 5 is gone from All |
| Switch to Gaming | Article 5 is gone there too. **This is the headline check** — it is the behaviour the toggle exists for |
| Still with Show read off, scroll past article 6 in the tab you are looking at | **It greys in place and does not vanish under your thumb.** A row disappearing mid-scroll is the exact defect this design avoids |
| Switch tabs and come back (or refresh) | *Now* article 6 is gone. It leaves on the next rebuild, not under the finger that read it |
| Swipe article 5 unread | It returns at full weight in every tab, under either toggle setting — mark-unread clears the timestamp outright |
| Turn **Show read back on** and Apply | Articles read within the last 48 hours return, dimmed. This is what the persisted `read_at` buys |
| Force-close and relaunch with Show read on | **Articles read in the last 48 hours are still there, dimmed.** This is the opposite of the old session-scoped behaviour, where a relaunch showed unread-only |
| Press Mark all as read, confirm the dialog, then make sure Show read is on | Those articles do **not** come back. Mark-all-read stamps a dismissal sentinel that sits outside every window — pressing it means "clear these out" |
| Reach the bottom of a feed and wait for the auto-mark-read, then check with Show read on | These *do* come back, dimmed. Reaching the end of a feed is passive reading, not dismissal, so it stamps a real time |

---

## 20. Day Dividers

| Step | Expected |
|------|----------|
| Open the feed with articles spanning several days | Headers break the list up: **TODAY**, **YESTERDAY**, then a weekday name within the last week, then a day-and-month label beyond that |
| Check the label language on a non-English device | Headers are localised, weekday and date included |
| Find an article published late last night (e.g. 23:50) and check it in the morning | Filed under **YESTERDAY**, not TODAY — grouping is by calendar day, not elapsed hours, even though it is under 24 hours ago |
| Count the headers at the top of the list | **Exactly one TODAY header.** A feed publishing an hour into tomorrow must group *and* label as today; clamping only the label produced two "Today" headers stacked, which shipped briefly |
| Switch Article order to Oldest first in the Filter bubble | Headers appear in reverse order and still bracket the right articles |
| Scroll slowly with mark-read-on-scroll on, past a header | Articles mark read at the same point they would without a header in the way — headers contribute height to the calculation but never trigger a read |

---

## 21. Refresh Resets to Top

| Step | Expected |
|------|----------|
| Scroll well down the list and note where you are | — |
| Pull to refresh | The list returns to offset 0 |
| Repeat with the refresh FAB | Same — the button and the pull gesture are the same operation |
| Immediately after either, look at the articles now at the top | Still unread. They must not be marked read by the jump |
| Wait a few seconds without touching the screen, then look again | Still unread |
| Now scroll down yourself | *Now* articles mark read as they pass the midpoint — a real scroll re-arms it |
| Open an article in the browser and come back | Scroll position is restored **exactly**. Only refresh paths reset to top |

---

## 22. Feed Add / Remove Reaches the Article List

> ⚠️ **Not yet exercised on device.** The `needsFetch` branch below has been
> verified only by unit test and by its `structureOnly` sibling (a category
> rename, which did reach the feed screen on device). Run it.

| Step | Expected |
|------|----------|
| On Categories, add a real feed to a category | Feed appears with its article count |
| Return to the Flash tab **without touching refresh** | The new feed's articles are in the list |
| Remove that feed, then return to Flash again | Its articles are gone |
| Rename a category, then return to Flash | The tab label updates |
| Add several feeds in a row before returning | One refresh happens, not one per feed |

---

## 23. Categories Collapsed by Default

| Step | Expected |
|------|----------|
| Open the Categories tab | **All categories render collapsed** — a tidy list of headers, chevrons pointing right |
| Expand one, leave the tab, come back | Collapsed again. Expansion is per-visit and deliberately not remembered |
| Long-press a feed in an expanded category and drag it onto a *collapsed* category's header | Accepted — the feed is appended to the end of that category |
| Try to start a drag from inside a collapsed category | Not possible; the rows are not rendered. Expand it first |
| Drop a feed at a specific position inside a collapsed category | Not possible — positioning needs the category expanded. Append-to-end is the only option while collapsed |

---

## 24. Filter Bubble — Article Age

| Step | Expected |
|------|----------|
| Open the Filter bubble and move **Article age** down | The label tracks the slider; nothing changes in the list yet |
| Press Apply | The list re-queries immediately and articles older than the window are gone |
| Move it back up and Apply | They return, provided they are still in the database |
| Set a value below 5 days | The visible list is correct. Note that `runCleanup` clamps to 5–20, so rows linger in the database a few days longer than the label implies — storage lags, the list does not |
