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

## 9. Folder Tabs Position (Thumb-Zone Hard Requirement)

| Step | Expected |
|------|----------|
| Create two or more folders | Tab bar appears |
| Observe tab bar position | Tabs are **at the bottom** of the content area, directly above the navigation bar — NOT at the top |
| Tap each tab | Article list switches; scroll resets to top for a tab not previously visited |
| Revisit a tab after scrolling it partway | Scroll position is restored to where you left it |

---

## 10. Minimum Tap Target Size

| Step | Expected |
|------|----------|
| Enable Settings → Developer options → Show tap highlights | — |
| Tap every interactive element (nav bar items, FABs, folder tabs, swipe actions, settings rows) | Highlight covers ≥ 48×48 dp in all cases; no tiny hit areas |

---

## 11. Swipe Mark-as-Read (Dims In-Place)

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
| Immediately after the swipe, check the list length | **Nothing has been removed.** A swipe marks read; it never retires. The row dims where it is |
| Scroll away and back, with **Show read** on | Dimmed article is still present at its original position |
| Same, with **Show read** off | The article is gone once it passes the retirement frontier, or at the next refresh — see §18 |

---

## 12. Onboarding (First-Launch Only)

| Step | Expected |
|------|----------|
| Clear app data (`adb shell pm clear io.getflash.app`) and relaunch | Onboarding flow appears |
| Complete the flow | Flag persisted; relaunching the app goes directly to the feed |
| Repeat launch | Onboarding never shown again |

---

## 13. Cross-Tab Unread Counts (Live)

| Step | Expected |
|------|----------|
| Note the "All" tab's badge and the "Gaming" tab's badge | — |
| Stay on the All tab and scroll past several Gaming articles (mark-read-on-scroll on) | Both badges decrement together, live, without switching tabs |
| Switch to the Gaming tab | The badge shown there already matches what the tab bar displayed before switching |
| Open an unread article directly, then go back | Both the opened article's folder badge and All badge decrement immediately |
| Wait ~1 second after a scroll-read burst | Counts still match the DB (reconciliation query self-heals any drift) |

---

## 14. Folder Tab Size

| Step | Expected |
|------|----------|
| Open the folder tab bar with 2+ folders | Tabs are visibly taller than before (60dp bar vs the old 48dp) |
| Tap a tab with a light, imprecise thumb tap near its edge | Registers reliably — no need to aim precisely |
| Tap a tab | A visible ripple plays from the tap point |
| Switch tabs repeatedly | Selected tab auto-scrolls into view within the horizontal tab strip |

---

## 15. Global Loading Indicator

| Step | Expected |
|------|----------|
| Add a feed, delete a folder, run an OPML import, open an AI summary, import a local backup | Each operation shows a thin progress bar at the top of the content area |
| Trigger a fast, near-instant operation (e.g. toggling a settings switch) | No flash of the indicator — it only appears after ~150ms |
| Force an error (enable airplane mode, then add a feed) | The indicator disappears once the operation fails — it never hangs visible |
| Trigger two operations back to back | Indicator stays visible continuously across both, only disappearing once the last one finishes |

---

## 16. Resume Refresh

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

## 17. AI Summary Reads the Full Article

| Step | Expected |
|------|----------|
| Pick an article whose RSS description is a one- or two-sentence teaser | — |
| Long-press → ✦ Summary | Sheet shows "Reading the article…" first, then "Writing the summary…" once generation starts |
| Wait for the summary | The summary contains information NOT present in the teaser (i.e. it summarised the full article, not the RSS blurb) |
| Trigger a summary on an article that is a single-topic piece (no distinct sub-points) | Summary renders as flowing prose with no bullet points |
| Trigger a summary on an article covering several distinct points | Summary renders as an opening sentence followed by short bullets |
| Trigger a summary on an article whose extraction fails (e.g. a URL that 404s) | Summary still generates from the RSS description, with a small "Based on the article preview only." note under the disclaimer |

---

## 18. Retirement and the Show Read Toggle

Read is not a state an article rests in — it is a step on the way out. An
article is **retired** when the user is finished with it: the row is deleted
and a tombstone written so a re-fetch cannot bring it back. **Show read**
decides only *when*.

**Retirement is permanent. There is no undo.** Do this on a device whose
library you are willing to lose.

| Step | Expected |
|------|----------|
| Open the Filter bubble (funnel button) and turn **Show read off**. Apply | The list re-queries and resets to the top |
| Scroll down slowly past six or seven articles, then stop | Articles behind you are removed once they are two cards above the viewport. **The list does not move under you** — see §24 |
| Scroll back up to the top | The retired articles are gone. The ones still on screen are the ones you had not passed |
| Now turn **Show read on** and Apply | Nothing you retired comes back. Retirement is not hiding |
| With Show read **on**, scroll past several articles | They dim in place and stay. Nothing is removed while you scroll |
| Pull to refresh | *Now* the dimmed ones disappear — retirement was deferred to the refresh, not skipped |
| Bookmark an article, mark it read, with Show read **off** | It stays in the feed. Saved articles are exempt from retirement under either setting |
| Refresh again with that bookmark still saved | Still there, still in Bookmarks |
| Un-bookmark it, then refresh | Now it retires like anything else |
| Force-close and relaunch | Retired articles are still gone; nothing is restored by a restart |

---

## 19. Day Dividers

| Step | Expected |
|------|----------|
| Open the feed with articles spanning several days | Headers break the list up: **TODAY**, **YESTERDAY**, then a weekday name within the last week, then a day-and-month label beyond that |
| Check the label language on a non-English device | Headers are localised, weekday and date included |
| Find an article published late last night (e.g. 23:50) and check it in the morning | Filed under **YESTERDAY**, not TODAY — grouping is by calendar day, not elapsed hours, even though it is under 24 hours ago |
| Count the headers at the top of the list | **Exactly one TODAY header.** A feed publishing an hour into tomorrow must group *and* label as today; clamping only the label produced two "Today" headers stacked, which shipped briefly |
| Switch Article order to Oldest first in the Filter bubble | Headers appear in reverse order and still bracket the right articles |
| Scroll slowly with mark-read-on-scroll on, past a header | Articles mark read at the same point they would without a header in the way — headers contribute height to the calculation but never trigger a read |

---

## 20. Refresh Is Conditional

A refresh either leaves the list completely alone or rebuilds it and jumps to
the top. Which one depends on whether anything *visible* actually arrived —
not whether anything was inserted, since an article can be inserted and then
hidden by the age filter, the per-feed cap or a blocklist match.

**Nothing arrived**

| Step | Expected |
|------|----------|
| Scroll well down the list and note exactly where you are | — |
| Pull to refresh at a quiet moment, when the feeds have nothing new | **The scroll position does not move at all.** You pulled to check, not to be relocated |
| Check the read articles that were on screen | Still there, still dimmed. Nothing is retired when nothing arrived |
| Repeat with the refresh FAB | Identical behaviour — the button and the pull are the same operation |

**Something arrived**

| Step | Expected |
|------|----------|
| Scroll down, then refresh when a feed genuinely has new items | Read articles are retired, the new ones load, and the list jumps to offset 0 |
| Immediately look at the articles now at the top | **Still unread.** The jump must not be mistaken for you scrolling past them — anything newly fetched showing up dimmed is a `MarkReadGate` regression |
| Wait ten seconds without touching the screen | Still unread |
| Scroll down yourself | *Now* articles mark read as they pass the midpoint |
| Open an article in the browser and come back | Scroll position restored **exactly**. Only refresh paths reset to top |

---

## 21. Feed Add / Remove Reaches the Article List

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

## 22. Categories Collapsed by Default

| Step | Expected |
|------|----------|
| Open the Categories tab | **All categories render collapsed** — a tidy list of headers, chevrons pointing right |
| Expand one, leave the tab, come back | Collapsed again. Expansion is per-visit and deliberately not remembered |
| Long-press a feed in an expanded category and drag it onto a *collapsed* category's header | Accepted — the feed is appended to the end of that category |
| Try to start a drag from inside a collapsed category | Not possible; the rows are not rendered. Expand it first |
| Drop a feed at a specific position inside a collapsed category | Not possible — positioning needs the category expanded. Append-to-end is the only option while collapsed |

---

## 23. Filter Bubble — Article Age

| Step | Expected |
|------|----------|
| Open the Filter bubble and move **Article age** down | The label tracks the slider; nothing changes in the list yet |
| Press Apply | The list re-queries immediately and articles older than the window are gone |
| Move it back up and Apply | They return, provided they are still in the database |
| Set a value below 5 days | The visible list is correct. Note that `runCleanup` clamps to 5–20, so rows linger in the database a few days longer than the label implies — storage lags, the list does not |

---

## 24. Tombstones — Retired Articles Stay Gone

> **The single most important manual check in this sheet.** Dedup used to work
> because a read article kept its row, and therefore its guid, to collide with.
> Retirement deletes the row. The article is still in the feed's XML and still
> inside the seven-day fetch window, so without the tombstone table a refresh
> re-inserts everything you just cleared, as unread.

| Step | Expected |
|------|----------|
| Show read **off**. Note the titles of five or six articles at the top | — |
| Scroll past all of them and let the list settle | They are retired and gone |
| Pull to refresh | **None of those titles return.** If any comes back unread, the `NOT EXISTS` guard in `insertArticles` is broken and nothing else in this area can be trusted |
| Force-close, relaunch, refresh again | Still gone |
| Leave the app for eight days, then refresh | They *may* return — tombstones prune past `kTombstoneDayLimit`, and by then a feed still offering the guid has genuinely republished. This is intended, not a leak |

---

## 25. The List Never Moves

The invariant the whole retirement design is built around: the article list
must never move by a single pixel while you are looking at it.

| Step | Expected |
|------|----------|
| Show read **off**. Scroll down slowly, in small drags, pausing after each | Rows are removed behind you at each pause. **Nothing on screen shifts** — no jump, no flicker, no settle |
| Pick a headline in the middle of the screen and keep your eye on it through a pause | It does not move a pixel when rows above it are removed |
| Now fling hard and let it come to rest | Same — the removal happens at rest, and the correction lands in the same frame |
| Fling down, then immediately drag back up before it settles | Nothing is removed from what you scrolled back to. The frontier is recomputed at rest, not reused from mid-scroll |
| Scroll to the very top and overscroll-bounce repeatedly | **No rows are eaten.** A bounce is not a scroll past the frontier |
| Bookmark an article, then scroll past it | Nothing above it is removed either — a saved article blocks the whole block, so the list stays put rather than resequencing around a survivor |

---

## 26. Retiring Across a Day Boundary

| Step | Expected |
|------|----------|
| Find a list with at least two day groups (**TODAY** and **YESTERDAY**) | — |
| Show read **off**. Scroll so the frontier lands in the *middle* of the first group | The header stays. The surviving articles still have a date above them |
| Keep scrolling until the whole first group is retired | **TODAY** goes with its last article; **YESTERDAY** becomes the top header |
| Watch the moment the header is removed | Nothing jumps — the header's height is inside the correction |
| Scroll to the top | The list opens on a header, never on a bare article |

---

## 27. Reaching the Bottom Zeroes the Badge

| Step | Expected |
|------|----------|
| Pick a category tab with a visible unread count | — |
| Scroll to the very bottom of that tab and stop | Its badge drops to **0** immediately, even though articles down there are still unread |
| Check the other category tabs | Unchanged |
| Check the **All** badge | It is now the sum over the categories that were *not* zeroed — clearing one category must not claim the whole app is caught up |
| Switch away and back | Still zero |
| Refresh so that new articles genuinely arrive for that tab | The badge shows the true count again — the suppression is display-only and clears when there is something new to show |
| Force-close and relaunch | True counts everywhere; nothing was written to the database |

---

## 28. "Don't Show Again" on Mark All as Read

| Step | Expected |
|------|----------|
| Tap **Mark all as read** | Confirmation dialog, now with a **Don't show again** checkbox |
| Tick the box, then tap **Cancel** | Nothing is marked. **The setting is unchanged** — open Quick Settings and confirm *Confirm mark all as read* is still on |
| Tap Mark all as read again, tick the box, tap **Mark all read** | It runs, and the setting is now off |
| Tap Mark all as read again | It runs immediately, no dialog |
| Open Quick Settings and turn **Confirm mark all as read** back on | — |
| Tap Mark all as read once more | The dialog is back |

---

---

## 29. Recovering Recently Removed Articles

Retirement is irreversible by design, so this is the only way back for a user
who scrolled faster than they meant to. It cannot recover anything the feeds
have stopped offering.

| Step | Expected |
|------|----------|
| Show read **off**. Note six article titles, then scroll past them | They are retired and gone |
| Pull to refresh | They stay gone — tombstones are doing their job |
| Settings → **Recover recently removed articles** | A confirmation explaining that removed articles may reappear, and that older ones cannot be recovered |
| Tap **Cancel** | Nothing changes; the articles are still gone |
| Tap it again and confirm | A refresh runs |
| Check the list | The articles the feeds still carry are back, as **unread** |
| Check your bookmarks, categories, feeds and keyword blocklist | All completely unchanged — recovery clears tombstones and nothing else |
| Scroll past an article older than seven days, then recover | It does **not** come back. Outside the fetch window there is nothing to re-insert |

---

## 30. The Alerts tab

An alert match is now a row of its own in `alert_matches`, not a column on the
article. That is the whole point: the article can be read, retired, cleaned up
and tombstoned, and the alert card stays. Most of this list is really one
question asked from several directions — *did the snapshot survive?*

The single most important invariant: `runCleanup`, `retireAllRead`, the
tombstone system, the display-age filter and the per-feed article cap must all
leave `alert_matches` completely untouched.

### 30.1 The pill and the badges

| Step | Expected |
|------|----------|
| Fresh install, add two feeds, add alert keyword `the` (guaranteed hits) | The **Alerts** pill appears at the far right of the pill row with a non-zero count. Scroll the row right if it is off screen |
| Add a second keyword overlapping the first on at least one article | That card shows **two** badges |
| Read the filter strip | Counts are correct, and **All** is *lower* than the sum of the two keyword counts — that difference is de-duplication working |
| Add a keyword long enough to truncate ("Nintendo Switch 2 Pro") | The badge ellipsises, stays centred, nothing overflows the card |
| Find an article matching four keywords | Three chips plus `+1` |
| Compare a read card with an unread one | Badge height is identical. Read state changes colour and opacity only — never layout |

### 30.2 Notifications

| Step | Expected |
|------|----------|
| Refresh with a new matching article | A notification arrives |
| Refresh again with nothing new | **No** notification |
| Two different keywords hit in one refresh | **Two separate** notifications side by side in the shade. Neither replaces the other |
| Tap a notification from a cold start | The app opens on the Alerts tab |
| Post an alert, then tap a *second* notification without restarting | Still opens the Alerts tab. Posting an alert used to silently de-register the tap handler |
| Switch the phone to German and trigger an alert | The notification body is German, matching the rest of the app |

### 30.3 Read state

| Step | Expected |
|------|----------|
| Open an alert article from the Alerts tab | It dims but **stays**. Back out; still there, scroll position preserved |
| Scroll the Alerts tab top to bottom without tapping anything | **Nothing dims.** Mark-read-on-scroll is deliberately off here — it is the only list where "seen" and "not yet seen" is the whole point |
| Mark all read on the Alerts tab | All dim, **none disappear**, the pill count is unchanged |
| Mark the same article read from the All tab, switch tabs to flush, return to Alerts | Entry still present, now dimmed |
| Open an alert-matched article from **Bookmarks**, return to Alerts | Dimmed there too |
| Open one from **Search**, return to Alerts | Dimmed there too |

### 30.4 Survival — the invariant

| Step | Expected |
|------|----------|
| Mark a whole folder read so its articles retire | Every alert card from that folder is still on the Alerts tab, dimmed, count unchanged |
| Set the display age filter to its minimum and cold-restart | Old alert entries are still present |
| Delete the feed an alert came from | The card stays, still naming that feed and showing its icon — the snapshot does not join back to `feeds` |
| Delete **every** feed | The Alerts pill is still there and the tab still opens. The history must not become unreachable |
| Long-press an Alerts card whose article has been retired and tap **Bookmark** | A banner: *That article is no longer in your feed*. No crash, the card stays |
| Restore a backup, then refresh | Alert cards are **not** duplicated and no notification re-fires for articles already alerted |

### 30.5 The radial menu

| Step | Expected |
|------|----------|
| Long-press a card in the Alerts tab | **Four** buttons — Bookmark, Share, Summary, Remove — all fully on screen, nothing clipped, labels legible |
| Repeat in German | Still four, still nothing clipped. German's *Zusammenfassung* is what used to push Remove off the edge |
| Tap **Remove** | The card goes, a banner shows, counts update. The **article itself stays** in its category tab and no tombstone is written |
| Long-press a card in the All tab | **Three** buttons, visually identical to before this change |

### 30.6 Managing keywords

| Step | Expected |
|------|----------|
| Alerts tab → **Manage keywords** | A flat list: one row per keyword with its match count and a bin. No expanding, no article lists — that is the tab's job |
| Delete a keyword that has matches | A confirmation appears **inline in the panel**, states the correct count, and its buttons actually work. A dialog here renders under the bubble's own scrim and cannot be tapped |
| Confirm | Those entries go. Entries also matched by a surviving keyword remain, one badge lighter |
| Delete a keyword **while its chip is the selected filter** | The tab falls back to All rather than rendering an empty list under a chip that no longer exists |
| Delete the last keyword | The Alerts pill disappears and the view falls back to All without a crash |
| Long-press a keyword and rename it to a keyword that **already exists** | A banner says it already exists. Nothing is deleted — the old behaviour destroyed the snapshots and then threw silently |
| Add a keyword that already exists | Same banner. No silent re-backfill with the wrong whole-word setting |
| Repeat the delete confirmation in German | Longest strings; the dialog still fits and reads correctly |

---

## 31. Local Backup — Export and Import

Export used to write a temp file and open the **share sheet**, which cannot save
to the device: `ACTION_SEND` targets apps that accept a file, and the phone's
own storage is not an app. The sheet offered Gmail, WhatsApp, Drive and Quick
Share, and no way to simply keep the file. Export now goes through the Storage
Access Framework — the system file picker in *create* mode — so the destination
is the user's choice and Downloads is one of them.

| Step | Expected |
|------|----------|
| Settings → Local backup file → **Export backup** | The **system file picker** opens in save mode — a folder tree with a filename field. **Not** the share sheet, and no app icons |
| Note the proposed filename | `flash_backup_YYYYMMDD_HHmm.json` — date **and** time. Two exports in one day must not propose the same name |
| Save it to Downloads | The picker closes and a **"Backup saved"** banner appears |
| Open the phone's Files app → Downloads | The file is there, and opening it shows complete, valid JSON — feeds, folders and keywords, no truncated tail |
| Export again and **dismiss** the picker (back gesture or Cancel) | **No banner and no error.** A cancel is deliberate, not a failure |
| Export twice in the same minute-boundary crossing, then compare | Two distinct files. Overwriting a larger backup with a smaller one is what leaves garbage after the JSON |
| **Import backup** → pick the saved file | The confirm dialog reads **"Restore from backup?"** — not "from Drive" — and restoring succeeds |
| Repeat the export in Spanish or French | The banner is localised, with no missing-key placeholder. **Note:** the picker's own title is supplied by Android, not by Flash — `file_picker` 8.0.7 drops `dialogTitle` on Android, so the system wording is expected there |

---

## 32. Cloud Summaries via Firebase AI Logic + App Check

Cloud summaries no longer carry an API key. Requests go to the Firebase AI
Logic gateway, which holds the key server-side and verifies an **App Check**
token — Play Integrity, attesting a genuine untampered build — before the
request reaches Gemini. Nano is untouched and still wins wherever it exists.

### The quickest check: read the footer

Every summary sheet says where it came from. This is the signal to trust, and
it beats reading logs:

- **"Generated on-device by Gemini Nano."** — Nano ran. Expected on the Pixel.
- **"Generated by Gemini in the cloud."** — Firebase AI Logic ran, and App
  Check attested. Expected on the Samsung and the Lenovo.

A Nano-capable device showing the *cloud* footer is a `shouldUseCloud`
precedence regression, not an improvement.

### ⚠ Read this before filing a bug: sideloaded builds need a debug token

Play Integrity attests that the app is a build **Google Play distributed**. A
locally-built APK is not, so it fails attestation, App Check refuses to issue a
token, and **every cloud summary fails**. That is the system working, not a
defect.

So local builds must be made with the debug provider:

```
flutter build apk --release --dart-define=APP_CHECK_DEBUG=true
```

Install, launch once, then read the token out of logcat. **Do not** filter by
tag: release builds are R8-minified, so the provider's tag is obfuscated (it
was `Z2.d`, and that will change with any rebuild of the SDK). Match the
message instead:

```
adb -s <serial> logcat -d | grep -i "debug token"
```

Register it — either in the Firebase console (App Check → Apps → ⋮ → **Manage
debug tokens**) or, faster, with the CLI:

```
firebase appcheck:debugtokens:create <token>   --app <androidAppId> --display-name "<device> (dev)" --project <projectId>
```

Until it is registered, cloud summaries fail on that device and that is
expected. The AAB uploaded to Play is built **without** the flag, so it uses
Play Integrity.

A registered debug token bypasses attestation entirely — treat it like a key.
It is per device, read from logcat, and must never be committed. Delete tokens
when testing finishes.

#### If the token never appears in logcat

Some OEM builds suppress DEBUG-level logs from app processes, and the token is
only ever written at `D/`. The Lenovo Tab M11 does this. Check with:

```
adb -s <serial> shell getprop log.tag        # 'I' means DEBUG is suppressed
```

If it reports `I`, the token is being generated but never printed. Raising the
level is a **device change and therefore the owner's call, not the agent's**:

```
adb -s <serial> shell setprop log.tag.<obfuscatedTag> DEBUG   # or: log.tag D
```

Set it *before* launching, since the level is read when the provider
initialises, and note it resets on reboot. The alternative, if that is
unwelcome, is to stop scraping altogether: `AndroidDebugProvider` accepts an
explicit `debugToken`, so a UUID can be generated, registered, and passed in by
`--dart-define` instead.

| Step | Expected |
|------|----------|
| **Samsung Galaxy M51** (no Nano) — tap ✦ on a real article | A summary streams in and completes, footer **"Generated by Gemini in the cloud."** This is the point of the migration: this device had no working cloud path that did not depend on a baked-in key |
| **Pixel 11 Pro** (Nano-capable) — tap ✦ | Footer says **"Generated on-device by Gemini Nano."** Confirm with `adb logcat \| grep -i aicore` that on-device inference ran, and that **no** Firebase AI or App Check traffic appears. If this device reaches the cloud, `shouldUseCloud` precedence is broken |
| **Lenovo Tab M11** (no Nano) — tap ✦ | Cloud summary, and the three-column layout still renders the sheet correctly |
| Tap ✦ twice on the same article | The second is served from `SummaryCache` — no second cloud call. To force a real generation, use an article not yet summarised |
| Aeroplane mode on a non-Nano device, then tap ✦ | The existing failure state appears — not a hang and not a crash. The 15-second deadline still applies |
| Feed refresh, favicons and the embedded reader, after all of the above | No regression. Firebase initialisation now runs before them in `main()` |
| Settings, end to end | **No API key field anywhere**, and no backend choice. The device decides, and the user is asked for nothing |

---

## 33. Privacy Policy Link (Play requirement)

Google Play requires the privacy policy to be reachable from **inside** the app,
not only from the store listing.

| Step | Expected |
|------|----------|
| Settings → scroll to the bottom | An **ABOUT** section exists below Local backup file |
| Tap **Privacy policy** | The system browser opens `https://flashrssapp.github.io/privacy.html`. It deliberately does **not** open in the built-in reader: that pane is built around an `Article` and runs Clean-mode extraction, which is the wrong treatment for a legal document, and the user should see the real domain |
| Repeat in German, Spanish, French and Italian | The section header and the tile label are localised, with no missing-key placeholder |
| Airplane mode, then tap it | No crash. The URL is shown in the banner so the policy is still reachable by hand |

---

## 34. Starter Pack and First Run (Play requirement)

Google Play made the app unavailable under the **News and Magazines** policy on
11 Sep 2026. The reviewer's account: a fresh install, onboarding's only button
("Add a feed") landed them on Categories with an empty add sheet, the Flash tab
read "Nothing here yet", and Bookmarks and Alerts were empty. Verdict — news
section empty / static content.

Everything below is the fix, so it is the section to run first on a release
candidate.

**Use an emulator for every fresh-install row.** These steps need a device with
no database, and wiping one is not something to do to a real phone. On a
physical device, install over the top with `adb install -r <apk>` — never
`flutter install`, which uninstalls first and takes the library with it.

| Step | Expected |
|------|----------|
| Fresh install, launch | Onboarding shows the icon, name and tagline, then **"Start with a few feeds"**, the helper line, and five ticked categories: World News, Tech, Fitness / Health, Travelling, Sports. Each subtitle names that category's publishers. No feature bullets |
| Scroll the onboarding screen | The middle scrolls; **Start reading** and **Skip, I'll add my own** stay pinned at the bottom. Neither can be scrolled out of reach on a short screen |
| Untick every category | **Start reading** goes disabled. **Skip** stays enabled |
| Tick one category | The button label counts that category's feeds — "Add 3 feeds", or "Add 1 feed" for a single-feed category |
| Fresh install → keep all → **Start reading** | Lands on the **Flash** tab, not Categories. Articles appear and all five category tabs have articles within ~15s, with **no further taps** |
| `adb logcat` across the step above | **One** refresh cycle, not two. Two means the queued `needsFetch` was not cleared — see §4.14 |
| Fresh install → **Skip, I'll add my own** | Lands on **Categories**, empty, exactly as before this pass. No feeds created |
| From the skip path: Flash tab | Empty state shows **Add a feed** and, below it, **Add starter pack** |
| Tap **Add starter pack** on the Flash tab | The sheet opens, seeds on confirm, and articles appear **without leaving the tab**. This path consumes the queued change by hand — if the list stays empty until you switch tabs and come back, that is the bug |
| From the skip path: Categories empty state → **Add starter pack** | Banner reads "{n} feeds added", the categories and feeds are listed, and the Flash tab has articles on return |
| Re-open the sheet after adding | **There is no route to it.** The pack lives only on the two empty states, and neither is reachable once feeds exist — by design (§4.1: no Settings item, no menu). To reach it again you must remove every feed first. The idempotency it would test is covered by `starter_pack_service_test.dart` |
| Delete every category, then Categories empty state → **Add starter pack** | Everything is recreated. Note this is a *fresh* seed, not a re-add: deleting a category cascades its feeds, so nothing is left to skip |
| Delete the pack's feeds individually, leaving the categories in place, then Flash empty state → **Add starter pack** | This is the real re-add test. The five categories are **reused** — still five, not ten — and the feeds come back inside them |
| Before adding, rename a category to `world news` (lower case, with spaces around it), then add the pack | The existing category is reused — **your** spelling is kept — and the World News feeds land inside it. No second folder |
| Move one pack feed into a category of your own, then add the pack again | The feed **stays where you put it**, under the name you gave it. It is skipped, not moved and not renamed |
| Add the pack, then check Categories | Pack categories are appended **after** any categories you already had; within a reused category, pack feeds come **after** your existing ones |
| Repeat the first run in German, Spanish, French and Italian | Category names, both buttons, the sheet title and the banner are all localised, with no missing-key placeholder. Folder names are created in that language and **stay** in it after switching the device back to English |
| Feed favicons, a minute after seeding | Icons fill in progressively. A feed that never resolves one keeps its monogram — not a blank space, and never a blocked first run |

### Publisher and publication date

| Step | Expected |
|------|----------|
| Long-press a card → ✦ Summary | Under the dimmed article title, one line: **publisher · absolute date and time**, localised |
| Open an article in the reading pane (tablet / wide layout) | The top bar shows the title, and under it the same **publisher · date** line, ellipsised to one line |
| An article whose feed title is missing | The line shows the date alone, with no stray `·` separator |
| Switch the device to German and repeat both | Date order and the 12/24-hour clock follow the locale — not "Mar 14" with an AM/PM stamp |

### Contact and support

| Step | Expected |
|------|----------|
| Settings → **ABOUT** | **Contact & support** and **Email us** appear **above** Privacy policy. Contact & support shows `flashrssapp@gmail.com` as its subtitle |
| Tap **Contact & support** | The system browser opens `https://flashrssapp.github.io/support.html`. This URL must be **identical** to the contact URL in the Play Console News and Magazines declaration |
| Tap **Email us** | A mail app opens, composing to `flashrssapp@gmail.com`. If nothing opens, the manifest `<queries>` entry for `SENDTO`/`mailto` is missing |
| Airplane mode, then tap each | No crash. The URL or the address is shown in the banner, so both stay reachable by hand |
| Repeat in all four other locales | Both labels are localised, with no missing-key placeholder |

---

## 35. OPML Import and Export

Settings → OPML, beside the local backup file buttons.

The rule this section exists to protect is **merge, never replace**. Backup
restore wipes and re-inserts; an OPML import must only ever add. If any step
below leaves the tester with fewer feeds than they started with, stop.

| Step | Expected |
|------|----------|
| Settings → scroll to **OPML** | Section sits between Local backup file and About, with **Export OPML** and **Import OPML**, and the line "Importing adds to your feeds, it never replaces them." |
| **Export OPML** with feeds present | The system save dialog opens proposing `flash_feeds_YYYYMMDD.opml`. Saving shows the success banner |
| **Export OPML** with no feeds at all | Banner: "There are no feeds to export yet." No file dialog, no empty file written |
| Cancel the save dialog | No banner. A cancel is a deliberate act, not a failure |
| Open the exported file in a text editor | OPML 2.0, one outline per category in Categories order, each feed carrying `type="rss" text title xmlUrl`, and `htmlUrl` where the feed has a site URL |
| **Import OPML** → pick the file you just exported | Banner: "Imported 0 feeds into 0 folders, N skipped". **Nothing duplicates** and no second copy of any category appears |
| Import an OPML with one new feed in a new folder | Banner counts 1 feed and 1 folder. The category appears on the Categories screen, and the Flash tab shows its articles on return — no manual refresh |
| Before importing, rename a category to lower case with spaces around it, then import a file using the normal spelling | The existing category is **reused** and keeps **your** spelling. No second folder |
| Move a feed into a category of your own, then re-import a file containing it | The feed **stays where you put it**, under the name you gave it. Counted as skipped |
| Import a file with three levels of nesting | Every feed lands in a category named after its **top-level** outline. Flash has one folder level; deeper nesting flattens rather than being dropped |
| Import a file with feeds at the root and no folders | They land in a category called **Imported** (localised) |
| Import a file containing `feed://` or `ftp://` URLs | Those are skipped. Only `http` and `https` feeds are added — anything else could never fetch |
| Import a `.txt`, a photo, or a malformed XML file | Banner: "That file is not a valid OPML file. Nothing was changed." Verify the feed count is **unchanged** |
| Import the same file twice in a row | The second import reports 0 added and everything skipped |
| Round trip: export, delete a category, import the export | The deleted category and its feeds come back. Categories you kept are untouched |
| Repeat the section in German, Spanish, French and Italian | Section header, both buttons, the subtitle, the banner and the **Imported** folder name are localised, with no missing-key placeholder |

**Known limitation, not a bug:** an *empty* category is not recreated by a
round trip. Import is feed-driven — a category exists because a feed lands in
it — so a category with no feeds has nothing to bring it back.

---

## 36. Swap sides (tablets)

Tablets only. Phones have no navigation bar to move, and TV never swaps.
Run every row **twice**: once normal, once swapped.

Two tiers, and they behave differently enough to be worth doing both:

| Tier | Width | Normal | Swapped |
|------|-------|--------|---------|
| Three-column | ≥840dp (M11 landscape) | bar, feed, web view | web view, feed, bar |
| Rail | 600–839dp (M11 portrait) | rail, content | content, rail |

| Step | Expected |
|------|----------|
| Find the button | **Swap sides** — a ↔ icon with its label under it — pinned to the **bottom** of the bar, below the entries. Scrolling the bar does not move it |
| Tap it | The columns **slide** to their new positions in about a fifth of a second. The bar ends flush against the opposite screen edge |
| Look at the chrome | The thin column rule is still between the bar and the content, on whichever side the bar is. Nav entries and section actions are still top-aligned |
| **The one that matters:** scroll the feed halfway, open an article, scroll inside the page, then tap Swap sides twice | The feed is still where you scrolled it, the article is still open, and the page has **not** reloaded or jumped to the top. If anything resets, the shell is remounting — stop and report it |
| Drag the divider right, normal | The article list gets **wider** |
| Drag the divider right, swapped | The article list gets **narrower**. The handle must follow the finger, not run from it |
| Drag the divider, then swap | The width you dragged to survives the swap |
| Double-tap the divider | Back to the automatic split, in both states |
| Force-stop Flash, relaunch | It comes back on the side you left it, with **no** slide on launch — that would be the app animating a state it was already in |
| Rotate the tablet while swapped (portrait ↔ landscape) | Still swapped, across the tier change |
| Visit Flash, Categories, Bookmarks and Alerts swapped | All four work. Section actions fire. Quick Settings and the Filter bubble open **fully on screen** and anchored to their buttons, not clipped by the edge the bar moved away from |
| Back, swapped | Closes an open article first, then returns to Flash, then exits — unchanged by the swap |
| Look at the bar's edges | Bar content is not under the status bar, the gesture bar or a display cutout, on **either** side |
| Large tablet, swapped | The bar is flush to the right edge and the content group stays centred. No wide gutter beside the bar — that was the original sidebar bug, and mirroring is where it would come back |
| German, at 1.3× font scale (emulator) | "Seiten tauschen" fits or wraps to two lines and ellipsises cleanly. No overflow stripes, and the bar does not get wider because of the label |
| Turn animations off (emulator: animator duration scale 0) | The swap is **instant**, not a 220ms slide |
| Fresh install, before finishing onboarding | No bar and no Swap sides button. After **Start reading**, both appear |
| Android TV | No Swap sides button at all. A TV has no way to put the layout back, so it is never offered |

**Emulator only** for anything that changes a device setting — font scale,
locale, animator scale, `wm size`. Never on the M11, the M51 or the Pixel; see
`CLAUDE.md`.
