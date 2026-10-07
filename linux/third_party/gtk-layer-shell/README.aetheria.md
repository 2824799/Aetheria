# Bundled gtk-layer-shell

Unmodified C sources, public/private headers and layer-shell protocol from
https://github.com/wmww/gtk-layer-shell, v0.10.1,
commit fd88ba666c18ff65ea786bf7b2e270d840030817.
xdg-shell.xml and ext-session-lock-v1.xml come from wayland-protocols 1.45:
https://gitlab.freedesktop.org/wayland/wayland-protocols.

The CMake adapter is maintained by Aetheria. The library is dynamically linked
and shipped alongside the application so installations need no additional
gtk-layer-shell package. Source and license files are distributed with the bundle
under share/aetheria/gtk-layer-shell; it can be rebuilt with
`cmake -S . -B build && cmake --build build` and the shared library replaced.
Requires GTK 3 and Wayland development libraries, CMake and wayland-scanner.

Upstream code retains its license notices (MIT and LGPL); see LICENSE_MIT.txt,
LICENSE_LGPL.txt and LICENSE_GPL.txt. Protocol licensing is included in each XML.
