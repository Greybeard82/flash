# Measurement method, and why it is not the one the brief asked for

The brief specified `adb shell dumpsys gfxinfo io.getflash.app framestats`.
**That instrument reports nothing for this app.** Verified on both devices
before switching:

```
** Graphics info for pid 20479 [io.getflash.app] **
Total frames rendered: 0
Janky frames: 0 (0.00%)
Pipeline=Skia (OpenGL)
```

`gfxinfo` measures HWUI, which draws the Android View hierarchy. Flutter does
not use it — it renders into a SurfaceView, confirmed from the layer list:

```
SurfaceView - io.getflash.app/io.getflash.app.MainActivity@8f8aa11@0(BLAST)#0
```

So HWUI genuinely has zero frames to report. Had the numbers been taken at face
value, every reading in this report would have been "0% janky" and the whole
pass would have concluded the app is flawless.

## What is used instead

`dumpsys SurfaceFlinger --latency '<layer>'` — the actual present timestamps of
the surface the user is looking at. Each dump carries the display refresh period
plus the last 128 frames as `desiredPresentTime actualPresentTime frameReadyTime`.
`perf/capture.sh` polls once per interaction so the 128-frame window never
overflows; `perf/analyze.py` dedupes by present time and derives the stats.

Two device-specific traps this had to handle:

- **Layer naming differs by OS version.** Android 12 prints the bare name;
  Android 15 wraps it as `RequestedLayerState{<name> parentId=...}`. Passing the
  wrapped form to `--latency` returns a header and no frames — indistinguishable
  from "the app rendered nothing" unless you check. The first tablet run failed
  exactly this way.
- **Refresh rates differ.** The tablet runs at **90Hz** (11.1ms budget), the
  Samsung at **60Hz** (16.6ms). Jank is therefore computed against each device's
  own period x1.5, not a fixed 16.6ms. A fixed budget would have flattered the
  tablet by giving it 50% more headroom than it actually has.

Gaps longer than 500ms are excluded as idle time between interaction bursts
rather than counted as jank.

## Build

All numbers come from `flutter build apk --profile` installed on both devices,
per the brief. Profile mode is AOT-compiled like release but keeps the
instrumentation; debug mode's JIT overhead would make the comparison meaningless.
