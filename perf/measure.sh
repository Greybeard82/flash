#!/usr/bin/env bash
# Stage 0 / Stage 4 measurement harness.
#
# Deliberately identical between baseline and post-fix runs: same swipe count,
# same durations, same tab sequence. A perf comparison is only meaningful if the
# input is byte-for-byte the same, so this script is the single source of both.
#
# Read-only with respect to the device: force-stop / start / input on Flash
# itself, plus dumpsys reads. Nothing here touches a system setting.
set -u

ADB="/c/Users/david/AppData/Local/Android/Sdk/platform-tools/adb.exe"
PKG=io.getflash.app
DEV="$1"       # adb serial
NAME="$2"      # short label used in filenames
OUT="$3"       # output directory
LABEL="$4"     # baseline | postfix

# Per-device geometry. Tablet is landscape 1920x1200; Samsung portrait 1080x2400.
case "$NAME" in
  tablet)
    SW_X=400;  SW_Y1=950;  SW_Y2=350
    TAB_ALL="251 185"; TAB_2="403 185"; TAB_3="564 185"
    ;;
  samsung)
    SW_X=540;  SW_Y1=1850; SW_Y2=700
    TAB_ALL="143 311"; TAB_2="407 311"; TAB_3="979 311"
    ;;
  *) echo "unknown device name $NAME"; exit 1;;
esac

mkdir -p "$OUT"

settle() { "$ADB" -s "$DEV" shell "sleep $1"; }

echo "### $NAME / $LABEL"

# ---------- 1. Cold start ----------
# Three runs; the report uses the median. force-stop between runs is what makes
# it cold-ish (process death, not a cache-cold device, which we cannot force
# without touching system state).
: > "$OUT/${NAME}_${LABEL}_startup.txt"
for i in 1 2 3; do
  "$ADB" -s "$DEV" shell am force-stop $PKG
  settle 2
  "$ADB" -s "$DEV" shell am start -W -n $PKG/.MainActivity 2>&1 \
    | grep -E "TotalTime|WaitTime|LaunchState" >> "$OUT/${NAME}_${LABEL}_startup.txt"
  settle 3
done
echo "  startup captured"

# ---------- 2. Scroll the article list ----------
"$ADB" -s "$DEV" shell am force-stop $PKG
settle 2
"$ADB" -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null 2>&1
settle 8                                   # let the boot fetch + first paint finish
"$ADB" -s "$DEV" shell dumpsys gfxinfo $PKG reset >/dev/null 2>&1

# ~10s of steady downward scrolling: 12 swipes, 600ms each, 250ms between.
for i in $(seq 1 12); do
  "$ADB" -s "$DEV" shell input swipe $SW_X $SW_Y1 $SW_X $SW_Y2 600
  "$ADB" -s "$DEV" shell "sleep 0.25"
done

"$ADB" -s "$DEV" shell dumpsys gfxinfo $PKG > "$OUT/${NAME}_${LABEL}_scroll_summary.txt" 2>&1
"$ADB" -s "$DEV" shell dumpsys gfxinfo $PKG framestats > "$OUT/${NAME}_${LABEL}_scroll_framestats.txt" 2>&1
echo "  scroll captured"

# ---------- 3. Tab / category switching ----------
"$ADB" -s "$DEV" shell am force-stop $PKG
settle 2
"$ADB" -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null 2>&1
settle 8
"$ADB" -s "$DEV" shell dumpsys gfxinfo $PKG reset >/dev/null 2>&1

# All -> 2nd -> 3rd -> All -> 2nd, three times round.
for round in 1 2 3; do
  for T in "$TAB_2" "$TAB_3" "$TAB_ALL" "$TAB_2" "$TAB_ALL"; do
    "$ADB" -s "$DEV" shell input tap $T
    "$ADB" -s "$DEV" shell "sleep 0.9"
  done
done

"$ADB" -s "$DEV" shell dumpsys gfxinfo $PKG > "$OUT/${NAME}_${LABEL}_tabs_summary.txt" 2>&1
"$ADB" -s "$DEV" shell dumpsys gfxinfo $PKG framestats > "$OUT/${NAME}_${LABEL}_tabs_framestats.txt" 2>&1
echo "  tabs captured"
