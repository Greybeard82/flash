#!/usr/bin/env python3
"""Turn SurfaceFlinger --latency dumps into frame-timing stats.

Each dump is: one line with the display refresh period in ns, then up to 128
lines of `desiredPresentTime actualPresentTime frameReadyTime`. Successive
dumps overlap heavily, so frames are deduplicated by actualPresentTime.

Jank definition used throughout: a gap between consecutive presented frames
that exceeds 1.5x the device's own refresh period. Anchoring to the device's
period rather than a fixed 16.6ms matters here — the tablet runs at 90Hz and
the Samsung at 60Hz, so a fixed budget would flatter the tablet.
"""
import sys
import statistics

SENTINEL = 9223372036854775807  # SurfaceFlinger's "not yet presented" marker


def parse(path):
    period = None
    presents = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = line.strip().split()
        if len(parts) == 1 and parts[0].isdigit():
            v = int(parts[0])
            if v > 1_000_000:           # a refresh period, not a stray number
                period = period or v
            continue
        if len(parts) != 3:
            continue
        try:
            _, actual, _ = (int(p) for p in parts)
        except ValueError:
            continue
        if actual <= 0 or actual >= SENTINEL:
            continue
        presents.add(actual)
    return period, sorted(presents)


def stats(path):
    period, presents = parse(path)
    if not period or len(presents) < 10:
        return None
    period_ms = period / 1e6

    # Gaps between consecutive presented frames. Drop gaps larger than 500ms:
    # those are the idle stretches between interaction bursts, not jank.
    gaps = []
    for a, b in zip(presents, presents[1:]):
        g = (b - a) / 1e6
        if g <= 500:
            gaps.append(g)
    if not gaps:
        return None

    budget = period_ms * 1.5
    janky = [g for g in gaps if g > budget]
    ordered = sorted(gaps)

    def pct(p):
        return ordered[min(len(ordered) - 1, int(len(ordered) * p / 100))]

    return {
        "refresh_hz": round(1000 / period_ms, 1),
        "frames": len(gaps) + 1,
        "janky": len(janky),
        "janky_pct": 100.0 * len(janky) / len(gaps),
        "mean": statistics.fmean(gaps),
        "p50": pct(50),
        "p90": pct(90),
        "p95": pct(95),
        "p99": pct(99),
        "worst": ordered[-1],
    }


if __name__ == "__main__":
    print(f"{'file':<44} {'Hz':>5} {'frames':>7} {'jank%':>7} "
          f"{'p50':>7} {'p90':>7} {'p95':>7} {'p99':>8} {'worst':>8}")
    for path in sys.argv[1:]:
        s = stats(path)
        name = path.replace("\\", "/").split("/")[-1]
        if not s:
            print(f"{name:<44} {'-- not enough frames --':>50}")
            continue
        print(f"{name:<44} {s['refresh_hz']:>5} {s['frames']:>7} "
              f"{s['janky_pct']:>6.1f}% {s['p50']:>6.1f}m {s['p90']:>6.1f}m "
              f"{s['p95']:>6.1f}m {s['p99']:>7.1f}m {s['worst']:>7.1f}m")
