#!/usr/bin/env python3
"""Build Aetheria's pinned Flutter Linux engine in a prepared engine checkout."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

REVISION = "5f77625673248ee5846fbcaf5d3e1a3878386fd7"
ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "linux/engine"
PATCHED = ["BUILD.gn", "fl_engine.cc", "fl_compositor_opengl.cc", "fl_view_renderer.cc"]
RELATIVE = Path("engine/src/flutter/shell/platform/linux")


def run(args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate_protocol(target):
    header = target / "presentation-time-client-protocol.h"
    run(["wayland-scanner", "client-header", ENGINE / "presentation-time.xml", header])
    run(["wayland-scanner", "private-code", ENGINE / "presentation-time.xml",
         target / "presentation-time-protocol.c"])
    # The engine's Debian Bullseye sysroot has Wayland 1.18. Keep generated
    # request wrappers compatible when the host scanner is 1.20 or newer.
    text = header.read_text()
    text = text.replace(
        "wl_proxy_marshal_flags((struct wl_proxy *) wp_presentation,\n"
        "\t\t\t WP_PRESENTATION_DESTROY, NULL, wl_proxy_get_version((struct wl_proxy *) wp_presentation), WL_MARSHAL_FLAG_DESTROY);",
        "wl_proxy_marshal((struct wl_proxy *) wp_presentation, WP_PRESENTATION_DESTROY);\n"
        "\twl_proxy_destroy((struct wl_proxy *) wp_presentation);")
    text = text.replace(
        "wl_proxy_marshal_flags((struct wl_proxy *) wp_presentation,\n"
        "\t\t\t WP_PRESENTATION_FEEDBACK, &wp_presentation_feedback_interface, wl_proxy_get_version((struct wl_proxy *) wp_presentation), 0, surface, NULL);",
        "wl_proxy_marshal_constructor_versioned((struct wl_proxy *) wp_presentation,\n"
        "\t\t\t WP_PRESENTATION_FEEDBACK, &wp_presentation_feedback_interface, wl_proxy_get_version((struct wl_proxy *) wp_presentation), surface, NULL);")
    if "wl_proxy_marshal_flags" in text:
        raise RuntimeError("Unsupported wayland-scanner output; request wrappers need updating")
    header.write_text(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-source", type=Path, required=True,
                        help="Flutter git checkout with engine dependencies already synced")
    parser.add_argument("--mode", choices=["debug", "profile", "release"], default="release")
    parser.add_argument("--output", type=Path, default=ROOT / "build/linux_engine")
    parser.add_argument("--out-dir", type=Path, help="Existing GN build directory; default out/host_<mode>")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 6))
    args = parser.parse_args()
    checkout = args.flutter_source.resolve()
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION:
        parser.error(f"Expected engine checkout {REVISION}, got {revision}")
    source = checkout / "engine/src"
    target = checkout / RELATIVE
    manifest = checkout / ".aetheria-linux-engine.json"
    previous = json.loads(manifest.read_text()) if manifest.exists() else {}
    originals = {name: subprocess.check_output([
        "git", "-C", str(checkout), "show", f"{REVISION}:{RELATIVE / name}"])
        for name in PATCHED}
    with tempfile.TemporaryDirectory(prefix="aetheria-engine-") as temporary:
        stage = Path(temporary)
        staged = stage / RELATIVE
        staged.mkdir(parents=True)
        for name, original in originals.items():
            (staged / name).write_bytes(original)
        run(["patch", "--batch", "-p1", "-i", ENGINE / "flutter-gtk.patch"], cwd=stage)
        for name, original in originals.items():
            path = target / name
            if path.read_bytes() not in (original, (staged / name).read_bytes()) and digest(path) != previous.get(name):
                parser.error(f"Unrelated local engine changes in {path}; use a clean prepared checkout")
        for name in PATCHED:
            shutil.copy2(staged / name, target / name)
    for path in ENGINE.glob("aetheria_*"):
        shutil.copy2(path, target / path.name)
    generate_protocol(target)
    manifest.write_text(json.dumps({name: digest(target / name) for name in PATCHED}, indent=2))
    out = args.out_dir.resolve() if args.out_dir else source / "out" / f"host_{args.mode}"
    if not (out / "args.gn").exists():
        if args.out_dir:
            parser.error("--out-dir must already contain a configured GN build")
        run([source / "flutter/tools/gn", "--runtime-mode", args.mode,
             "--enable-fontconfig"], cwd=source)
    gn_args = (out / "args.gn").read_text()
    if f'flutter_runtime_mode = "{args.mode}"' not in gn_args:
        parser.error(f"Build directory does not match --mode {args.mode}: {out}")
    # Generic engine GN defaults omit system font discovery. Desktop builds
    # need Fontconfig so CJK and other system fallback fonts render correctly.
    desktop_args = gn_args
    for name in ("skia_use_fontconfig", "flutter_use_fontconfig"):
        pattern = rf"(?m)^{name}\s*=\s*(true|false)\s*$"
        if re.search(pattern, desktop_args):
            desktop_args = re.sub(pattern, f"{name} = true", desktop_args)
        else:
            desktop_args += f"\n{name} = true\n"
    if desktop_args != gn_args:
        (out / "args.gn").write_text(desktop_args)
    run(["ninja", "-C", out, "-j", args.jobs, "flutter/shell/platform/linux:flutter_linux_gtk"])
    output = args.output.resolve() / args.mode
    output.mkdir(parents=True, exist_ok=True)
    library = output / "libflutter_linux_gtk.so"
    # Atomic replacement also permits rebuilding while an older bundle runs.
    shutil.copy2(out / library.name, library.with_suffix(".so.new"))
    library.with_suffix(".so.new").replace(library)
    shutil.copy2(checkout / "LICENSE", output / "LICENSE.flutter")
    (output / "engine.version").write_text(REVISION + "\n")
    print(f"Built {output}")
    print(f"AETHERIA_LINUX_ENGINE_DIR={output.parent} flutter build linux --{args.mode}")


if __name__ == "__main__":
    main()
