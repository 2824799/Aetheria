#!/usr/bin/env python3
"""Summarize wp_presentation feedback, not Flutter animation timestamps."""
import argparse
import csv
import json
from pathlib import Path
from statistics import median


def summarize(path, warmup=3.0, duration=9.0):
    with Path(path).open() as source:
        rows = list(csv.reader(source))
    presented = [(int(row[1]), int(row[2])) for row in rows
                 if len(row) == 4 and row[0] == "presented"]
    if len(presented) < 2:
        raise ValueError("Insufficient presentation feedback; actual FPS is unverified")
    start = presented[0][0] + int(warmup * 1e9)
    end = start + int(duration * 1e9)
    sample = [(time, refresh) for time, refresh in presented if start <= time <= end]
    if len(sample) < 2:
        raise ValueError("Insufficient frames inside the requested measurement window")
    intervals = [b[0] - a[0] for a, b in zip(sample, sample[1:])]
    if any(interval <= 0 for interval in intervals):
        raise ValueError("Presentation timestamps are not strictly increasing")
    elapsed = (sample[-1][0] - sample[0][0]) / 1e9
    if elapsed < duration * .9:
        raise ValueError(f"Incomplete measurement: {elapsed:.3f}s of {duration:.3f}s requested")
    ordered = sorted(intervals)
    refreshes = [refresh for _, refresh in sample if refresh > 0]
    nominal = median(refreshes) if refreshes else None
    return {
        "source": "Wayland wp_presentation.presented",
        "presented_frames": len(sample),
        "duration_seconds": elapsed,
        "presented_fps": (len(sample) - 1) / elapsed,
        "nominal_hz": 1e9 / nominal if nominal else None,
        "interval_p50_ms": median(intervals) / 1e6,
        "interval_p95_ms": ordered[int(len(ordered) * .95)] / 1e6,
        "interval_p99_ms": ordered[int(len(ordered) * .99)] / 1e6,
        "interval_max_ms": max(intervals) / 1e6,
        "intervals_over_1_5_refresh": sum(i > nominal * 1.5 for i in intervals) if nominal else None,
        "discarded_total_in_trace": sum(row[0] == "discarded" for row in rows if row),
        "warmup_seconds": warmup,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--warmup", type=float, default=3)
    parser.add_argument("--duration", type=float, default=9)
    parser.add_argument("--min-refresh-ratio", type=float, default=0)
    args = parser.parse_args()
    report = summarize(args.trace, args.warmup, args.duration)
    print(json.dumps(report, indent=2))
    if args.min_refresh_ratio:
        if report["nominal_hz"] is None:
            parser.exit(1, "Compositor did not report a nominal refresh interval\n")
        if report["presented_fps"] < report["nominal_hz"] * args.min_refresh_ratio:
            parser.exit(1, "Actual presentation cadence missed the requested refresh ratio\n")


if __name__ == "__main__":
    main()
