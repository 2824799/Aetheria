#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="${1:-$root/build/linux/x64/profile/bundle}"
output="$root/build/high_refresh_lifecycle"
mkdir -p "$output"
c++ -std=c++17 -Wall -Wextra "$root/linux/tests/high_refresh_window_test.cc" \
  -I"$root/linux/flutter/ephemeral" -L"$bundle/lib" -lflutter_linux_gtk \
  -Wl,-rpath,"$bundle/lib" $(pkg-config --cflags --libs gtk+-3.0) \
  -o "$output/window_test"
# A trace is append-only so a remapped surface cannot erase earlier feedback.
: > "$output/presentations.csv"
capture_dir="$(mktemp -d "$output/pixels-XXXXXX")"
GDK_BACKEND=wayland AETHERIA_PRESENTATION_TRACE="$output/presentations.csv" \
  AETHERIA_FRAME_CAPTURE="$capture_dir/frame" \
  "$output/window_test" "$bundle" > "$output/window.log" 2>&1
python3 - "$output" "$capture_dir" <<'PY'
import csv
from pathlib import Path
import re
import sys
from PIL import Image
root = Path(sys.argv[1])
matched = 0
for path in Path(sys.argv[2]).glob('frame-*-source.png'):
    with Image.open(path) as source, Image.open(str(path).replace('-source.png', '-window.png')) as window:
        if source.size != window.size:
            continue  # A resize can leave one old-sized EGL back buffer.
        if sum(high - low for low, high in source.getextrema()[:3]) < 50:
            continue  # Startup frames may have no animated content yet.
        assert source.tobytes() == window.tobytes(), f'{path.name}: window pixels differ from Flutter pixels'
        matched += 1
assert matched >= 1, 'No nonempty Flutter frame was verified in the EGL window'
print(f'{matched} nonempty Flutter frames match the actual EGL back buffer byte for byte.')
log = (root / 'window.log').read_text()
with (root / 'presentations.csv').open() as source:
    times = [int(row[1]) for row in csv.reader(source) if row[0] == 'presented']
steps = {int(step): int(time) * 1000 for step, time in
         re.findall(r'step=(\d+) time_us=(\d+)', log)}
assert len(steps) == 8, log
# This fixture uses CLOCK_MONOTONIC timestamps, as does KWin's presentation
# feedback. Each resize/restore must actually put new frames on the screen.
for step in (1, 2, 3, 5, 6, 8):
    start = steps[step]
    frames = sum(start < time < start + 1_000_000_000 for time in times)
    assert frames >= 30, f'Step {step}: presentation stopped ({frames} frames)'
    print(f'Step {step}: {frames} frames presented in the following second')
for step in (4, 7):
    start = steps[step]
    assert sum(start + 200_000_000 < time < start + 1_000_000_000 for time in times) == 0
assert 'error in client communication' not in log, log
assert 'Aetheria window lifecycle completed' in log, log
print('Resize, maximize, hide/restore twice, and teardown completed.')
PY
