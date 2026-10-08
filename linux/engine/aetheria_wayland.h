#pragma once

#include <epoxy/egl.h>
#include <gtk/gtk.h>
#include <cstdio>
#include <set>
#include <wayland-client.h>
#include <wayland-egl.h>
#include "flutter/shell/platform/linux/public/flutter_linux/fl_engine.h"

struct wp_presentation;
struct wp_presentation_feedback;
void aetheria_engine_frame(FlEngine* engine);
void aetheria_engine_direct(FlEngine* engine, bool enabled);
void aetheria_engine_schedule(FlEngine* engine);

class AetheriaWayland {
 public:
  AetheriaWayland(GtkWidget* widget, FlEngine* engine);
  ~AetheriaWayland();
  bool Setup();
  void Map();
  void Resize();
  void Destroy();
  bool Present(GLuint framebuffer, int width, int height);
 private:
  static void Global(void*, wl_registry*, uint32_t, const char*, uint32_t);
  static void GlobalRemoved(void*, wl_registry*, uint32_t);
  static void FrameDone(void*, wl_callback*, uint32_t);
  static void ClockId(void*, wp_presentation*, uint32_t);
  static void SyncOutput(void*, wp_presentation_feedback*, wl_output*);
  static void Presented(void*, wp_presentation_feedback*, uint32_t, uint32_t,
                        uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
  static void Discarded(void*, wp_presentation_feedback*);
  GtkWidget* widget_;
  FlEngine* engine_;
  GMutex mutex_;
  wl_display* display_ = nullptr;
  wl_registry* registry_ = nullptr;
  wl_compositor* compositor_ = nullptr;
  wl_subcompositor* subcompositor_ = nullptr;
  wl_surface* surface_ = nullptr;
  wl_surface* parent_ = nullptr;
  uint32_t parent_id_ = 0;
  wl_subsurface* subsurface_ = nullptr;
  wl_callback* callback_ = nullptr;
  wl_egl_window* window_ = nullptr;
  wp_presentation* presentation_ = nullptr;
  std::set<struct wp_presentation_feedback*> feedbacks_;
  EGLDisplay egl_display_ = EGL_NO_DISPLAY;
  EGLSurface egl_surface_ = EGL_NO_SURFACE;
  int scale_ = 1;
  int width_ = 1;
  int height_ = 1;
  FILE* trace_ = nullptr;
  unsigned diagnostic_frames_ = 0;
};
