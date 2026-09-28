#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 VERSION [BUNDLE_DIRECTORY] [OUTPUT_DIRECTORY]" >&2
  exit 2
fi

version="${1#v}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Invalid release version: $1" >&2
  exit 2
fi

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_dir="${2:-$repository_dir/build/linux/x64/release/bundle}"
output_dir="${3:-$repository_dir/dist}"
for required in aetheria lib data share/icons/hicolor/scalable/apps/aetheria.svg; do
  if [[ ! -e "$bundle_dir/$required" ]]; then
    echo "Incomplete Linux bundle: $bundle_dir/$required" >&2
    exit 1
  fi
done
if [[ ! -x "$bundle_dir/aetheria" ]]; then
  echo "The Linux executable is not executable." >&2
  exit 1
fi

mkdir -p -- "$output_dir"
staging_dir="$(mktemp -d)"
trap 'rm -rf -- "$staging_dir"' EXIT
package_name="Aetheria-v$version-linux-x64"
package_dir="$staging_dir/$package_name"
mkdir -- "$package_dir"
cp -a -- "$bundle_dir/." "$package_dir/"
# Development desktop entries contain the build machine's absolute path.
# The installer recreates them at the user's actual installation location.
rm -f -- "$package_dir/aetheria.desktop" "$package_dir/share/applications/aetheria.desktop"
cp -- "$repository_dir/scripts/install_linux.sh" "$package_dir/install.sh"
chmod +x -- "$package_dir/install.sh"
cp -- "$repository_dir/LICENSE" "$package_dir/LICENSE"
cat > "$package_dir/README.txt" <<'README'
Aetheria for Linux x64

Run ./aetheria from this directory, or run ./install.sh to install the complete
bundle in ~/.local/opt/aetheria and register a desktop launcher and application icon.
An optional absolute installation path can be passed to ./install.sh.
Keep aetheria, lib/, data/ and share/ together.

Requires a Linux x64 desktop with glibc 2.35 or later, GTK 3 and ALSA.
On Ubuntu/Debian: sudo apt install libgtk-3-0 libasound2
On distributions using time64 packages, the package names may end in t64.
README

archive="$output_dir/$package_name.tar.gz"
tar -czf "$archive" -C "$staging_dir" "$package_name"
echo "Created $archive"
