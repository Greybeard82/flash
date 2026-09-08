# Flash — working rules

## NEVER change anything on a connected device. Ever.

No resolution. No DPI or display scaling. No rotation or orientation. No
Wi-Fi, mobile data, airplane mode, DNS or proxy. No system settings, no
permissions, no accounts. No reboots, no resets, no clearing app data.

**Not for testing. Not "just to check". Not "I will put it back
afterwards".** That last one is not a mitigation and never was — it is the
sentence that made every one of these changes feel free. They were not free.

This is not "ask first". It is **never**. If a task appears to require it,
the task is wrong: say so, and say what you would need David to do himself.
He may choose to change something on his own device. You may not.

### What is allowed on a connected device

Installing and launching the app, driving the app's own UI, reading state
(`dumpsys`, `logcat`, `screencap`, `am get-config`). That is the whole list.
Everything is read-only or inside Flash itself.

### Test the state, do not create it

Offline behaviour, a rotated screen, a different width — build these where
they cost nothing: an emulator, an injected fake client, a widget test, a
unit test. A real device is for confirming the app works on real hardware,
in the state the owner keeps it in.

### Why this is written this way

Every clause above exists because it was actually done. Density and rotation
overrides on the Pixel and the Samsung scrambled home screen layouts David
had to rebuild by hand. Disabling Wi-Fi on the Lenovo to exercise an offline
code path cost him an entire evening and ended in a factory reset. Each time,
the check afterwards was shallow enough to report success — "Wi-Fi is
enabled" proved the radio had power and nothing else — so the damage was
found by him, not by me.

## Commands that are never to be run against any device

Named because each one has already caused damage. The list is illustrative,
not exhaustive — the rule above is the rule, and it covers anything not
listed here.

- `adb shell wm size` / `wm density` — setting **or** resetting. A reset does
  not restore the home screen the override scrambled.
- `adb shell settings put system user_rotation` / `accelerometer_rotation`,
  or any other forced rotation.
- `adb shell svc wifi disable` / `svc data disable`, or anything else that
  takes a device off the network.
- `adb shell settings put ...` of any kind, `adb shell reboot`, `pm clear`.

This applies to the Samsung Galaxy M51, the Pixel 11 Pro, the Lenovo Tab M11,
and any device connected in future. Emulators are the place for all of it.

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
