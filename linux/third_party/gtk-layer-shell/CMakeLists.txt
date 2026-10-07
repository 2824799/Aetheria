cmake_minimum_required(VERSION 3.13)
project(aetheria_layer_shell LANGUAGES C)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(protocol_sources)
foreach(protocol wlr-layer-shell-unstable-v1 xdg-shell ext-session-lock-v1)
  set(xml "${CMAKE_CURRENT_SOURCE_DIR}/protocol/${protocol}.xml")
  set(header "${CMAKE_CURRENT_BINARY_DIR}/${protocol}-client.h")
  set(code "${CMAKE_CURRENT_BINARY_DIR}/${protocol}.c")
  add_custom_command(OUTPUT "${header}" "${code}"
    COMMAND ${WAYLAND_SCANNER} -c client-header "${xml}" "${header}"
    COMMAND ${WAYLAND_SCANNER} -c private-code "${xml}" "${code}"
    DEPENDS "${xml}" VERBATIM)
  list(APPEND protocol_sources "${header}" "${code}")
endforeach()
add_library(aetheria-layer-shell SHARED
  src/api.c src/gtk-wayland.c src/custom-shell-surface.c src/layer-surface.c
  src/xdg-popup-surface.c src/xdg-toplevel-surface.c src/gtk-priv-access.c
  src/simple-conversions.c ${protocol_sources})
set_target_properties(aetheria-layer-shell PROPERTIES
  C_STANDARD 11 OUTPUT_NAME gtk-layer-shell VERSION 0.10.1 SOVERSION 0)
target_compile_definitions(aetheria-layer-shell PRIVATE
  GTK_LAYER_SHELL_MAJOR=0 GTK_LAYER_SHELL_MINOR=10 GTK_LAYER_SHELL_MICRO=1)
target_include_directories(aetheria-layer-shell PUBLIC include
  PRIVATE gtk-priv/h "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(aetheria-layer-shell PRIVATE PkgConfig::GTK PkgConfig::WAYLAND)
