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
| Open an article in Reader mode, then drag the back edge slowly | Predictive back peek animation plays (partial screen reveal of the previous screen) |
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

## 9. Real Claude Haiku Summary (Anthropic API)

| Step | Expected |
|------|----------|
| Go to Settings → Anthropic API key → enter a valid key | Key saved and masked |
| Long-press an article → ✦ Summary | Bottom sheet loads; summary arrives as 4 bullet points |
| Tap "Open article" in the sheet | Launches article URL externally or in Reader |
| Remove the API key then trigger summary | "No API key — add one in Settings" message shown |
| Enter an invalid key | "Couldn't load summary. Tap to retry." shown; no crash |

---

## 10. Google Drive Backup / Restore Round-Trip

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

## 11. Folder Tabs Position (Thumb-Zone Hard Requirement)

| Step | Expected |
|------|----------|
| Create two or more folders | Tab bar appears |
| Observe tab bar position | Tabs are **at the bottom** of the content area, directly above the navigation bar — NOT at the top |
| Tap each tab | Article list switches; scroll resets to top for a tab not previously visited |
| Revisit a tab after scrolling it partway | Scroll position is restored to where you left it |

---

## 12. Minimum Tap Target Size

| Step | Expected |
|------|----------|
| Enable Settings → Developer options → Show tap highlights | — |
| Tap every interactive element (nav bar items, FABs, folder tabs, swipe actions, settings rows) | Highlight covers ≥ 48×48 dp in all cases; no tiny hit areas |

---

## 13. Swipe Mark-as-Read (Dims In-Place)

| Step | Expected |
|------|----------|
| Swipe an article to the LEFT | Article dims in-place (reduced opacity); stays in list; no removal animation |
| Swipe an article to the RIGHT | Same result — article dims in-place |
| Scroll away and back | Dimmed article is still present at its original position |

---

## 14. Onboarding (First-Launch Only)

| Step | Expected |
|------|----------|
| Clear app data (`adb shell pm clear io.getflash.app`) and relaunch | Onboarding flow appears |
| Complete the flow | Flag persisted; relaunching the app goes directly to the feed |
| Repeat launch | Onboarding never shown again |

---

## 15. Cross-Tab Unread Counts (Live)

| Step | Expected |
|------|----------|
| Note the "All" tab's badge and the "Gaming" tab's badge | — |
| Stay on the All tab and scroll past several Gaming articles (mark-read-on-scroll on) | Both badges decrement together, live, without switching tabs |
| Switch to the Gaming tab | The badge shown there already matches what the tab bar displayed before switching |
| Open an unread article directly, then go back | Both the opened article's folder badge and All badge decrement immediately |
| Wait ~1 second after a scroll-read burst | Counts still match the DB (reconciliation query self-heals any drift) |

---

## 16. Folder Tab Size

| Step | Expected |
|------|----------|
| Open the folder tab bar with 2+ folders | Tabs are visibly taller than before (60dp bar vs the old 48dp) |
| Tap a tab with a light, imprecise thumb tap near its edge | Registers reliably — no need to aim precisely |
| Tap a tab | A visible ripple plays from the tap point |
| Switch tabs repeatedly | Selected tab auto-scrolls into view within the horizontal tab strip |

---

## 17. Global Loading Indicator

| Step | Expected |
|------|----------|
| Add a feed, delete a folder, run an OPML import, open an AI summary, restore from Drive | Each operation shows a thin progress bar at the top of the content area |
| Trigger a fast, near-instant operation (e.g. toggling a settings switch) | No flash of the indicator — it only appears after ~150ms |
| Force an error (enable airplane mode, then add a feed) | The indicator disappears once the operation fails — it never hangs visible |
| Trigger two operations back to back | Indicator stays visible continuously across both, only disappearing once the last one finishes |

---

## 18. Resume Refresh

| Step | Expected |
|------|----------|
| Open an article in the external browser, then return to Flash within ~10 seconds | No network fetch runs; scroll position is untouched |
| Background the app for at least 2 minutes, then return | A network fetch runs automatically; new articles appear at the top |
| After that fetch | Previously-read articles remain dimmed in their original position — they are NOT purged from the list |
| Return to the app again immediately after the above fetch | No second fetch fires (5-minute minimum interval) |

---

## 19. AI Summary Reads the Full Article

| Step | Expected |
|------|----------|
| Pick an article whose RSS description is a one- or two-sentence teaser | — |
| Long-press → ✦ Summary | Sheet shows "Reading the article…" first, then "Writing the summary…" once generation starts |
| Wait for the summary | The summary contains information NOT present in the teaser (i.e. it summarised the full article, not the RSS blurb) |
| Trigger a summary on an article that is a single-topic piece (no distinct sub-points) | Summary renders as flowing prose with no bullet points |
| Trigger a summary on an article covering several distinct points | Summary renders as an opening sentence followed by short bullets |
| Trigger a summary on an article whose extraction fails (e.g. a URL that 404s) | Summary still generates from the RSS description, with a small "Based on the article preview only." note under the disclaimer |
