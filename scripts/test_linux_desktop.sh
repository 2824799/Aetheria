#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
test_dir="$(mktemp -d -t aetheria-desktop-tests.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT

# Pixel tests need no window server. Uses the production Cairo/Pango renderer.
${CXX:-c++} -std=c++17 -Wall -Wextra \
  linux/tests/lyric_renderer_test.cc linux/runner/lyric_renderer.cc \
  $(pkg-config --cflags --libs pangocairo) -o "$test_dir/renderer"
"$test_dir/renderer"

if [[ "${1:-}" != "--windows" && "${1:-}" != "--kwin-fullscreen" ]]; then
  echo 'Pass --windows for GTK windows, or --kwin-fullscreen to also test fullscreen stacking on KWin.'
  exit 0
fi
if [[ ! -f linux/flutter/ephemeral/libflutter_linux_gtk.so ]]; then
  echo 'Build the Linux app first to prepare the Flutter Linux embedding library.' >&2
  exit 1
fi
cmake -S linux/third_party/gtk-layer-shell -B "$test_dir/layer-shell" -DCMAKE_BUILD_TYPE=Release >"$test_dir/cmake.log"
cmake --build "$test_dir/layer-shell" -j 4 >>"$test_dir/cmake.log"
${CXX:-c++} -std=c++17 -Wall -Wextra \
  linux/tests/desktop_window_test.cc linux/runner/window_state.cc \
  linux/runner/floating_lyric_window.cpp linux/runner/lyric_renderer.cc \
  -Ilinux/third_party/gtk-layer-shell/include -L"$test_dir/layer-shell" \
  -Wl,-rpath,"$test_dir/layer-shell" -lgtk-layer-shell \
  -Ilinux/flutter/ephemeral -Llinux/flutter/ephemeral \
  -Wl,-rpath,"$repo_dir/linux/flutter/ephemeral" -lflutter_linux_gtk \
  $(pkg-config --cflags --libs gtk+-3.0 x11 xext) -o "$test_dir/windows"
for backend in x11 wayland; do
  if [[ "$backend" == x11 && -z "${DISPLAY:-}" ]] ||
     [[ "$backend" == wayland && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "Skipping $backend: no display available."
    continue
  fi
  mkdir -p "$test_dir/$backend"
  XDG_CONFIG_HOME="$test_dir/$backend" GDK_BACKEND="$backend" "$test_dir/windows" write
  XDG_CONFIG_HOME="$test_dir/$backend" GDK_BACKEND="$backend" "$test_dir/windows" read
done
if [[ "${1:-}" == "--kwin-fullscreen" ]]; then
  python3 scripts/test_kwin_stacking.py "$test_dir/windows"
fi
