#!/usr/bin/env python3
"""Join desktop stress phases with actual Wayland presentation timestamps."""
import argparse
from bisect import bisect_left, bisect_right
import csv
import json
from pathlib import Path
from statistics import mean, median, pstdev


def time_stats(values):
    values = sorted(values)
    if not values:
        return {'samples': 0}
    return {
        'samples': len(values),
        'p50_ms': median(values) / 1000,
        'p95_ms': values[int((len(values) - 1) * .95)] / 1000,
        'p99_ms': values[int((len(values) - 1) * .99)] / 1000,
        'max_ms': max(values) / 1000,
    }


def matched_presentations(report, trace):
    submits = {int(row[1]): list(map(int, row[2:]))
               for row in trace if len(row) == 7 and row[0] == 'submit'}
    shown = {int(row[1]): int(row[2]) / 1000
             for row in trace if len(row) == 5 and row[0] == 'presented_frame'}
    ordered = sorted((times[0], serial) for serial, times in submits.items())
    starts = [time for time, _ in ordered]
    frames = {}
    for frame in report.get('frame_timings', []):
        index = bisect_left(starts, frame[4])
        if index < len(ordered) and starts[index] <= frame[5]:
            serial = ordered[index][1]
            if serial in shown:
                frames[frame[0]] = (frame, shown[serial])
    return frames, submits, shown


def input_latency(report, trace):
    frames, submits, shown = matched_presentations(report, trace)
    inputs = {row[0]: row for row in report.get('thumb_inputs', [])}
    handled = [row[2] for row in report.get('thumb_inputs', [])]
    for name, phase in report['phases'].items():
        phase_submits = [times for times in submits.values()
                         if phase['start_us'] <= times[0] <= phase['end_us']]
        phase['native_submit'] = {
            'lock_wait': time_stats([s[1] - s[0] for s in phase_submits]),
            'gl_before_swap': time_stats([s[2] - s[1] for s in phase_submits]),
            'egl_swap': time_stats([s[3] - s[2] for s in phase_submits]),
            'submit_to_present': time_stats([shown[serial] - times[-1]
                for serial, times in submits.items() if serial in shown
                and phase['start_us'] <= times[0] <= phase['end_us']]),
        }
        if not name.startswith('thumb'):
            continue
        samples = []
        seen = set()
        for frame_number, seq, _, offset in report.get('thumb_frames', []):
            if frame_number not in frames or seq not in inputs or seq in seen:
                continue
            frame, presentation = frames[frame_number]
            if not phase['start_us'] <= frame[2] <= phase['end_us']:
                continue
            event = inputs[seq]
            if abs(offset - event[3]) > .01:
                continue
            samples.append((presentation - event[1],
                            bisect_right(handled, presentation) - seq - 1))
            seen.add(seq)
        if samples:
            phase['input_to_present'] = time_stats([s[0] for s in samples])
            phase['newer_inputs_already_handled'] = {
                'p50': median(s[1] for s in samples),
                'max': max(s[1] for s in samples),
            }
        if name == 'thumb_step_latency' and (not samples or not submits):
            raise ValueError('Missing matched input / UI / raster / presentation samples')


def wheel_motion(report, trace):
    frames, _, _ = matched_presentations(report, trace)
    for name, phase in report['phases'].items():
        if not name.startswith('wheel_cadence_'):
            continue
        inputs = [row for row in report.get('wheel_inputs', [])
                  if phase['start_us'] <= row[0] <= phase['end_us']]
        if len(inputs) < 2:
            raise ValueError(f'{name}: missing wheel input samples')
        periods = [b[0] - a[0] for a, b in zip(inputs, inputs[1:])]
        steady_start = inputs[0][0] + 800000
        steady_end = inputs[-1][0] + median(periods)
        samples = sorted((frames[number][1], offset)
                         for number, sample, offset in report.get('wheel_frames', [])
                         if number in frames and steady_start <= sample <= steady_end)
        if len(samples) < 20:
            raise ValueError(f'{name}: missing actual presented wheel frames')
        speeds = [(b[1] - a[1]) * 1e6 / (b[0] - a[0])
                  for a, b in zip(samples, samples[1:]) if b[0] > a[0]]
        average = mean(speeds)
        phase['wheel_motion'] = {
            'presented_samples': len(samples),
            'input_period_p50_ms': median(periods) / 1000,
            'steady_presented_fps': (len(samples) - 1) * 1e6 /
                (samples[-1][0] - samples[0][0]),
            'mean_speed_px_s': average,
            'speed_cv': pstdev(speeds) / abs(average),
            'speed_min_ratio': min(speeds) / average,
            'speed_max_ratio': max(speeds) / average,
            'input_jump_max_px': max(abs(row[4] - row[3]) for row in inputs),
        }


def cadence(intervals):
    ordered = sorted(intervals)
    return {
        'intervals': len(intervals),
        'cadence_fps': len(intervals) * 1e6 / sum(intervals),
        'interval_p50_ms': median(intervals) / 1000,
        'interval_p95_ms': ordered[int((len(ordered) - 1) * .95)] / 1000,
        'interval_max_ms': max(intervals) / 1000,
    }


def analyze(report_path, trace_path):
    data = json.loads(Path(report_path).read_text())
    report = data["desktop_stress"]
    with Path(trace_path).open() as source:
        trace = list(csv.reader(source))
    presented = [(int(row[1]) / 1000, int(row[2]) / 1000)
                 for row in trace if len(row) == 4 and row[0] == "presented"]
    for name, phase in report["phases"].items():
        samples = [(time, refresh) for time, refresh in presented
                   if phase["start_us"] <= time <= phase["end_us"]]
        if len(samples) < 2 or not phase["frames"]:
            raise ValueError(f"{name}: missing actual rendered frames")
        # Drawer phases deliberately include idle time between clicks; their
        # aggregate FPS would misrepresent their animation cadence.
        intervals = [b[0] - a[0] for a, b in zip(samples, samples[1:])]
        refresh = median(r for _, r in samples if r > 0)
        ordered = sorted(intervals)
        presentation = {
            "frames": len(samples),
            "interval_p50_ms": median(intervals) / 1000,
            "interval_p95_ms": ordered[int((len(ordered) - 1) * .95)] / 1000,
            "interval_max_ms": max(intervals) / 1000,
            "nominal_hz": 1e6 / refresh,
        }
        if name in ("thumb_scrub", "wheel_scroll"):
            presentation.update(
                presented_fps=(len(samples) - 1) * 1e6 / (samples[-1][0] - samples[0][0]),
                intervals_over_1_5_refresh=sum(i > refresh * 1.5 for i in intervals),
            )
        phase["presentation"] = presentation
    for window in report.get('thumb_passes', []):
        samples = [time for time, _ in presented
                   if window['start_us'] <= time <= window['end_us']]
        if len(samples) < 2:
            raise ValueError('thumb pass: missing actual rendered frames')
        window['presentation'] = cadence([b - a for a, b in zip(samples, samples[1:])])
    # Only count adjacent presentations within each active animation. The idle
    # pauses between repeated clicks must not be counted as animation drops.
    active = {}
    for window in report.get('animation_windows', []):
        samples = [time for time, _ in presented
                   if window['start_us'] <= time <= window['end_us']]
        key = window['phase'] + ':' + window['direction']
        active.setdefault(key, []).extend(b - a for a, b in zip(samples, samples[1:]))
    report['active_animation_presentation'] = {
        key: cadence(intervals) for key, intervals in active.items() if intervals
    }
    if report.get('thumb_inputs'):
        input_latency(report, trace)
    if report.get('wheel_inputs'):
        wheel_motion(report, trace)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.dumps(analyze(args.report, args.trace), indent=2, ensure_ascii=False)
    if args.output:
        args.output.write_text(result + "\n")
    print(result)


if __name__ == "__main__":
    main()
