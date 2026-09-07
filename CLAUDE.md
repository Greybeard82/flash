# Flash — working rules

## Never reconfigure the phones

**Never run any of the following against the Samsung Galaxy M51
(`RF8N82VYG2D`) or the Pixel 11 Pro, for any reason, under any
circumstance:**

- `adb shell wm size` (setting *or* resetting)
- `adb shell wm density` (setting *or* resetting)
- `adb shell settings put system user_rotation` /
  `accelerometer_rotation`, or any other forced-rotation command
- Any other command that changes resolution, DPI, display scaling, or
  orientation on either of these two specific devices

**Landscape testing and landscape implementation work are completely
off-limits on both phones, full stop.** Not temporarily, not "just to check
something quickly", not "reset afterward" — off-limits, permanently.

**Why.** Overriding density, resolution or rotation on a real phone does not
just change what Flash sees — it disrupts David's actual home screen. Icon
positions and widget layouts get scrambled and there is no automatic undo.
He has had to rebuild his home screen by hand after this happened, more than
once. Restoring the *setting* afterwards does not restore the layout, so
"I reset it after" is not a mitigation. Treat this with the same seriousness
as any other "don't touch David's real device state" boundary.

**If a task appears to need a phone in landscape, that is a sign to use a
different device — not a sign to make an exception.**

### What to do instead

- Expanded tier, Medium tier, landscape, or anything tablet-shaped → the
  **Lenovo Tab M11**. Real hardware, reaches both tablet tiers natively just
  by rotating it, no override needed.
- A width the Lenovo and the two AVDs do not cover → create or adjust an
  **AVD**. Never a real phone.
- The Samsung and the Pixel are for **portrait-only, phone-tier testing**
  from now on — nothing else.

## Phones do not have a landscape mode

This is a product rule, not only a testing one. Rotating a phone does
nothing: portrait is locked at the Activity level in `MainActivity.kt`,
keyed off `Configuration.smallestScreenWidthDp < 600`. Tablets are left
unlocked and rotate freely.

`smallestScreenWidthDp` is the device's shorter dimension and does not
change with rotation, which is what makes the lock immune to the original
problem — a rotated phone reporting a tablet-sized width to `MediaQuery`.

Do not "fix" this in Dart. `kThreeColumnBreakpoint` (840) and `useRail`
(600) are width-based and were always correct; they were simply being handed
a width a phone should never have produced. The 600 threshold in
`MainActivity.kt` deliberately mirrors `useRail`'s — keep them in step.
