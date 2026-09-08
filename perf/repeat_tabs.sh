#!/usr/bin/env bash
# Tab-switch capture, repeated N times.
#
# Single runs turned out to be too noisy to support a claim: the tablet's
# scroll jank moved 0.3% -> 1.4% between builds whose diff cannot affect
# scrolling at all. Anything reported as an improvement has to survive
# repetition, so this runs the same sequence N times and the analyser is fed
# every repetition separately.
set -u

ADB="/c/Users/david/AppData/Local/Android/Sdk/platform-tools/adb.exe"
PKG=io.getflash.app
DEV="$1"; NAME="$2"; OUT="$3"; LABEL="$4"; REPS="${5:-3}"

case "$NAME" in
  tablet)  TAB_ALL="251 185"; TAB_2="403 185"; TAB_3="564 185";;
  samsung) TAB_ALL="143 311"; TAB_2="407 311"; TAB_3="979 311";;
  *) echo "unknown device $NAME"; exit 1;;
esac

mkdir -p "$OUT"

layer() {
  "$ADB" -s "$DEV" shell dumpsys SurfaceFlinger --list 2>/dev/null \
    | grep BLAST | grep getflash | head -1 | tr -d '\r' \
    | sed -e 's/^RequestedLayerState{//' -e 's/ parentId=.*$//' -e 's/}$//'
}

for rep in $(seq 1 "$REPS"); do
  "$ADB" -s "$DEV" shell am force-stop $PKG
  "$ADB" -s "$DEV" shell "sleep 2"
  "$ADB" -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null 2>&1
  "$ADB" -s "$DEV" shell "sleep 8"
  L=$(layer)
  F="$OUT/${NAME}_${LABEL}_r${rep}_tabs.latency"
  : > "$F"
  for round in 1 2 3; do
    for T in "$TAB_2" "$TAB_3" "$TAB_ALL" "$TAB_2" "$TAB_ALL"; do
      "$ADB" -s "$DEV" shell input tap $T
      "$ADB" -s "$DEV" shell "dumpsys SurfaceFlinger --latency '$L'" >> "$F" 2>&1
      "$ADB" -s "$DEV" shell "sleep 0.55"
    done
  done
  echo "  $NAME $LABEL rep$rep done"
done
