#!/usr/bin/env bash
# Frame-timing capture for a Flutter app, via SurfaceFlinger present times.
#
# WHY NOT gfxinfo: Flutter renders into a SurfaceView (BLAST layer), not the
# Android View hierarchy, so `dumpsys gfxinfo <pkg> framestats` reports
# "Total frames rendered: 0" for this app on both devices. Verified on the
# Samsung (Android 12) and the tablet (Android 15) before switching methods.
# SurfaceFlinger --latency reports the actual present timestamps of the layer
# the user is looking at, which is what "is it janky" actually means.
#
# --latency holds only the last 128 frames (~2.1s at 60Hz, ~1.4s at 90Hz), so
# this polls once per interaction cycle and the analyser dedupes by timestamp.
#
# Device-safe: force-stop / start / input on Flash itself plus dumpsys reads.
# Nothing here touches a system setting.
set -u

ADB="/c/Users/david/AppData/Local/Android/Sdk/platform-tools/adb.exe"
PKG=io.getflash.app
DEV="$1"; NAME="$2"; OUT="$3"; LABEL="$4"

case "$NAME" in
  tablet)  SW_X=400; SW_Y1=950;  SW_Y2=350; TAB_ALL="251 185"; TAB_2="403 185"; TAB_3="564 185";;
  samsung) SW_X=540; SW_Y1=1850; SW_Y2=700; TAB_ALL="143 311"; TAB_2="407 311"; TAB_3="979 311";;
  *) echo "unknown device $NAME"; exit 1;;
esac

mkdir -p "$OUT"
settle() { "$ADB" -s "$DEV" shell "sleep $1"; }

# Two formats in the wild: Android 12 prints the bare layer name, Android 15
# wraps it as RequestedLayerState{<name> parentId=...}. Passing the wrapped
# form to --latency yields a header and no frames, which reads as "the app
# rendered nothing" rather than as an error — so unwrap it.
layer() {
  "$ADB" -s "$DEV" shell dumpsys SurfaceFlinger --list 2>/dev/null \
    | grep BLAST | grep getflash | head -1 | tr -d '\r' \
    | sed -e 's/^RequestedLayerState{//' -e 's/ parentId=.*$//' -e 's/}$//'
}

restart_app() {
  "$ADB" -s "$DEV" shell am force-stop $PKG
  settle 2
  "$ADB" -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null 2>&1
  settle 8
}

echo "### $NAME / $LABEL"

# ---------- scroll ----------
restart_app
L=$(layer)
: > "$OUT/${NAME}_${LABEL}_scroll.latency"
for i in $(seq 1 12); do
  "$ADB" -s "$DEV" shell input swipe $SW_X $SW_Y1 $SW_X $SW_Y2 600
  "$ADB" -s "$DEV" shell "dumpsys SurfaceFlinger --latency '$L'" >> "$OUT/${NAME}_${LABEL}_scroll.latency" 2>&1
  "$ADB" -s "$DEV" shell "sleep 0.2"
done
echo "  scroll captured"

# ---------- tab / category switching ----------
restart_app
L=$(layer)
: > "$OUT/${NAME}_${LABEL}_tabs.latency"
for round in 1 2 3; do
  for T in "$TAB_2" "$TAB_3" "$TAB_ALL" "$TAB_2" "$TAB_ALL"; do
    "$ADB" -s "$DEV" shell input tap $T
    "$ADB" -s "$DEV" shell "dumpsys SurfaceFlinger --latency '$L'" >> "$OUT/${NAME}_${LABEL}_tabs.latency" 2>&1
    "$ADB" -s "$DEV" shell "sleep 0.55"
  done
done
echo "  tabs captured"

# ---------- cold start ----------
: > "$OUT/${NAME}_${LABEL}_startup.txt"
for i in 1 2 3; do
  "$ADB" -s "$DEV" shell am force-stop $PKG
  settle 2
  "$ADB" -s "$DEV" shell am start -W -n $PKG/.MainActivity 2>&1 \
    | grep -E "TotalTime|LaunchState" >> "$OUT/${NAME}_${LABEL}_startup.txt"
  settle 3
done
echo "  startup captured"
