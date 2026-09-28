#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [ABSOLUTE_INSTALL_DIRECTORY]" >&2
  exit 2
fi

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${1:-$HOME/.local/opt/aetheria}"
if [[ "$install_dir" != /* || "$install_dir" == *$'\n'* || "$install_dir" == *$'\r'* ]]; then
  echo "The installation directory must be an absolute path without line breaks." >&2
  exit 2
fi
for required in aetheria lib data share/icons/hicolor/scalable/apps/aetheria.svg; do
  if [[ ! -e "$source_dir/$required" ]]; then
    echo "Missing application file: $source_dir/$required" >&2
    exit 1
  fi
done

mkdir -p -- "$install_dir"
install_dir="$(cd -- "$install_dir" && pwd)"
if [[ "$source_dir" != "$install_dir" ]]; then
  cp -a -- "$source_dir/." "$install_dir/"
fi
chmod +x -- "$install_dir/aetheria"

desktop_command() {
  local char
  printf '"'
  for ((index = 0; index < ${#1}; index++)); do
    char="${1:index:1}"
    case "$char" in
      '\') printf '%s' '\\' ;;
      '"') printf '%s' '\"' ;;
      '$') printf '%s' '\$' ;;
      '`') printf '%s' '\`' ;;
      '%') printf '%s' '%%' ;;
      *) printf '%s' "$char" ;;
    esac
  done
  printf '"'
}

applications_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p -- "$applications_dir"
desktop_file="$applications_dir/aetheria.desktop"
{
  printf '[Desktop Entry]\nName=Aetheria\nComment=本地音乐库与播放器\n'
  printf 'Exec=%s\n' "$(desktop_command "$install_dir/aetheria")"
  printf 'Icon=%s\n' "$install_dir/share/icons/hicolor/scalable/apps/aetheria.svg"
  printf 'Terminal=false\nType=Application\nCategories=AudioVideo;Audio;Player;\n'
  printf 'StartupWMClass=com.aetheria.aetheria\n'
} > "$desktop_file"
chmod 644 -- "$desktop_file"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$applications_dir"
fi

echo "Installed Aetheria in $install_dir"
echo "Desktop launcher: $desktop_file"
