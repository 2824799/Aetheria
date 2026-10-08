#include "aetheria_wayland.h"
#include <algorithm>
#include <cstring>
#include <vector>
#include <gdk/gdkwayland.h>
#include "presentation-time-client-protocol.h"
#include "flutter/shell/platform/linux/fl_engine_private.h"
#include "flutter/shell/platform/linux/fl_opengl_manager.h"

AetheriaWayland::AetheriaWayland(GtkWidget* widget, FlEngine* engine)
    : widget_(widget), engine_(engine) { g_mutex_init(&mutex_); }
AetheriaWayland::~AetheriaWayland() { Destroy(); g_mutex_clear(&mutex_); }
void AetheriaWayland::Global(void* data, wl_registry* registry, uint32_t name,
                            const char* interface, uint32_t version) {
  auto* self = static_cast<AetheriaWayland*>(data);
  if (!strcmp(interface, "wl_compositor"))
    self->compositor_ = static_cast<wl_compositor*>(wl_registry_bind(
        registry, name, &wl_compositor_interface, std::min(version, 4u)));
  else if (!strcmp(interface, "wl_subcompositor"))
    self->subcompositor_ = static_cast<wl_subcompositor*>(wl_registry_bind(
        registry, name, &wl_subcompositor_interface, 1));
  else if (!strcmp(interface, "wp_presentation")) {
    self->presentation_ = static_cast<wp_presentation*>(wl_registry_bind(
        registry, name, &wp_presentation_interface, 1));
    static const wp_presentation_listener listener = {ClockId};
    wp_presentation_add_listener(self->presentation_, &listener, self);
  }
}
void AetheriaWayland::GlobalRemoved(void*, wl_registry*, uint32_t) {}
void AetheriaWayland::ClockId(void*, wp_presentation*, uint32_t) {}
bool AetheriaWayland::Setup() {
  display_ = gdk_wayland_display_get_wl_display(gtk_widget_get_display(widget_));
  registry_ = wl_display_get_registry(display_);
  static const wl_registry_listener listener = {Global, GlobalRemoved};
  wl_registry_add_listener(registry_, &listener, this);
  if (wl_display_roundtrip(display_) < 0 || !compositor_ || !subcompositor_) return false;
  auto* top = gtk_widget_get_toplevel(widget_);
  auto* parent = gdk_wayland_window_get_wl_surface(gtk_widget_get_window(top));
  if (!parent) return false;
  parent_ = parent;
  parent_id_ = wl_proxy_get_id(reinterpret_cast<wl_proxy*>(parent));
  surface_ = wl_compositor_create_surface(compositor_);
  subsurface_ = wl_subcompositor_get_subsurface(subcompositor_, surface_, parent);
  wl_subsurface_set_desync(subsurface_);
  auto* region = wl_compositor_create_region(compositor_);
  wl_surface_set_input_region(surface_, region);
  wl_region_destroy(region);
  scale_ = gtk_widget_get_scale_factor(widget_);
  wl_surface_set_buffer_scale(surface_, scale_);
  width_ = std::max(1, gtk_widget_get_allocated_width(widget_)) * scale_;
  height_ = std::max(1, gtk_widget_get_allocated_height(widget_)) * scale_;
  window_ = wl_egl_window_create(surface_, width_, height_);
  auto* manager = fl_engine_get_opengl_manager(engine_);
  if (!fl_opengl_manager_make_platform_current(manager)) return false;
  egl_display_ = eglGetCurrentDisplay();
  EGLint config_id = 0, count = 0;
  eglQueryContext(egl_display_, eglGetCurrentContext(), EGL_CONFIG_ID, &config_id);
  const EGLint attributes[] = {EGL_CONFIG_ID, config_id, EGL_NONE};
  EGLConfig config;
  bool ok = eglChooseConfig(egl_display_, attributes, &config, 1, &count) && count;
  if (ok) egl_surface_ = eglCreateWindowSurface(egl_display_, config,
      reinterpret_cast<EGLNativeWindowType>(window_), nullptr);
  fl_opengl_manager_clear_current(manager);
  if (egl_surface_ == EGL_NO_SURFACE) return false;
  if (const char* path = g_getenv("AETHERIA_PRESENTATION_TRACE")) trace_ = fopen(path, "a");
  Resize();
  aetheria_engine_direct(engine_, true);
  // Bootstrap an empty surface; subsequent frames follow wl_surface.frame.
  aetheria_engine_frame(engine_);
  g_message("Aetheria renderer: direct Wayland EGL, presentation feedback=%s",
            presentation_ ? "available" : "unavailable");
  return true;
}
void AetheriaWayland::Map() {
  auto* top = gtk_widget_get_toplevel(widget_);
  auto* parent = gdk_wayland_window_get_wl_surface(gtk_widget_get_window(top));
  const auto id = parent ? wl_proxy_get_id(reinterpret_cast<wl_proxy*>(parent)) : 0;
  if (parent == parent_ && id == parent_id_) return;
  Destroy();
  aetheria_engine_direct(engine_, false);
  if (parent && Setup()) aetheria_engine_schedule(engine_);
}
void AetheriaWayland::Resize() {
  g_mutex_lock(&mutex_);
  if (subsurface_) {
    int x = 0, y = 0;
    gtk_widget_translate_coordinates(widget_, gtk_widget_get_toplevel(widget_), 0, 0, &x, &y);
    wl_subsurface_set_position(subsurface_, x, y);
    scale_ = gtk_widget_get_scale_factor(widget_);
    wl_surface_set_buffer_scale(surface_, scale_);
    width_ = std::max(1, gtk_widget_get_allocated_width(widget_)) * scale_;
    height_ = std::max(1, gtk_widget_get_allocated_height(widget_)) * scale_;
    wl_egl_window_resize(window_, width_, height_, 0, 0);
  }
  g_mutex_unlock(&mutex_);
}
void AetheriaWayland::FrameDone(void* data, wl_callback* callback, uint32_t) {
  auto* self = static_cast<AetheriaWayland*>(data);
  g_mutex_lock(&self->mutex_);
  wl_callback_destroy(callback);
  self->callback_ = nullptr;
  g_mutex_unlock(&self->mutex_);
  aetheria_engine_frame(self->engine_);
}
void AetheriaWayland::SyncOutput(void*, struct wp_presentation_feedback*, wl_output*) {}
void AetheriaWayland::Presented(void* data, struct wp_presentation_feedback* feedback,
    uint32_t hi, uint32_t lo, uint32_t ns, uint32_t refresh, uint32_t, uint32_t,
    uint32_t flags) {
  auto* self = static_cast<AetheriaWayland*>(data);
  g_mutex_lock(&self->mutex_);
  if (self->trace_) fprintf(self->trace_, "presented,%llu,%u,%u\n",
      static_cast<unsigned long long>(((uint64_t(hi) << 32) | lo) * 1000000000ULL + ns), refresh, flags);
  self->feedbacks_.erase(feedback);
  wp_presentation_feedback_destroy(feedback);
  g_mutex_unlock(&self->mutex_);
}
void AetheriaWayland::Discarded(void* data, struct wp_presentation_feedback* feedback) {
  auto* self = static_cast<AetheriaWayland*>(data);
  g_mutex_lock(&self->mutex_);
  if (self->trace_) fprintf(self->trace_, "discarded,0,0,0\n");
  self->feedbacks_.erase(feedback);
  wp_presentation_feedback_destroy(feedback);
  g_mutex_unlock(&self->mutex_);
}
bool AetheriaWayland::Present(GLuint framebuffer, int width, int height) {
  g_mutex_lock(&mutex_);
  if (!surface_ || egl_surface_ == EGL_NO_SURFACE) { g_mutex_unlock(&mutex_); return false; }
  const auto context = eglGetCurrentContext();
  const auto draw = eglGetCurrentSurface(EGL_DRAW), read = eglGetCurrentSurface(EGL_READ);
  if (!eglMakeCurrent(egl_display_, egl_surface_, egl_surface_, context)) {
    g_mutex_unlock(&mutex_); return false;
  }
  eglSwapInterval(egl_display_, 0);
  GLint saved_draw, saved_read;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &saved_draw);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &saved_read);
  const GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
  glDisable(GL_SCISSOR_TEST);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
  // The engine first makes this context current without a surface. Its
  // default framebuffer can therefore retain GL_NONE as the draw buffer,
  // even after binding an EGL window surface. Blitting to GL_NONE succeeds
  // without writing any pixels. Select the back buffer explicitly and restore
  // the engine's state afterwards.
  GLint previous_draw_buffer = GL_NONE;
  glGetIntegerv(GL_DRAW_BUFFER0, &previous_draw_buffer);
  const GLenum back_buffer = GL_BACK;
  glDrawBuffers(1, &back_buffer);
  const char* diagnostic_path = g_getenv("AETHERIA_FRAME_CAPTURE");
  const bool diagnose = diagnostic_path && diagnostic_frames_++ < 8;
  if (diagnose) {
    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
    GLint samples = 0;
    glGetIntegerv(GL_SAMPLES, &samples);
    g_message("Aetheria GL before blit: error=%x src=%u %dx%d dst=%dx%d read_status=%x draw_status=%x samples=%d previous_draw_buffer=%x",
        glGetError(), framebuffer, width, height, width_, height_,
        glCheckFramebufferStatus(GL_READ_FRAMEBUFFER), glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER), samples, previous_draw_buffer);
  }
  if (framebuffer) {
    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
    glBlitFramebuffer(0, 0, width, height, 0, 0, width_, height_, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  } else {
    // Flutter can submit no layers for a transparent frame. Clear the previous
    // contents instead of leaving the last animation frame on screen.
    GLfloat color[4];
    GLboolean mask[4];
    glGetFloatv(GL_COLOR_CLEAR_VALUE, color);
    glGetBooleanv(GL_COLOR_WRITEMASK, mask);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(color[0], color[1], color[2], color[3]);
    glColorMask(mask[0], mask[1], mask[2], mask[3]);
  }
  if (diagnose) {
    g_message("Aetheria GL after blit: error=%x", glGetError());
    for (int source = 0; source < 2; ++source) {
      int w = source ? width : width_, h = source ? height : height_;
      if (w <= 0 || h <= 0) continue;
      glBindFramebuffer(GL_READ_FRAMEBUFFER, source ? framebuffer : 0);
      std::vector<guchar> pixels(w * h * 4);
      glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
      g_message("Aetheria capture %s: error=%x", source ? "source" : "window", glGetError());
      auto* pixbuf = gdk_pixbuf_new_from_data(pixels.data(), GDK_COLORSPACE_RGB, TRUE,
                                             8, w, h, w * 4, nullptr, nullptr);
      g_autofree gchar* path = g_strdup_printf("%s-%u-%s.png", diagnostic_path,
          diagnostic_frames_, source ? "source" : "window");
      gdk_pixbuf_save(pixbuf, path, "png", nullptr, nullptr);
      g_object_unref(pixbuf);
    }
  }
  const GLenum restore_buffer = previous_draw_buffer;
  glDrawBuffers(1, &restore_buffer);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, saved_read);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, saved_draw);
  if (scissor) glEnable(GL_SCISSOR_TEST);
  if (!callback_) {
    callback_ = wl_surface_frame(surface_);
    static const wl_callback_listener listener = {FrameDone};
    wl_callback_add_listener(callback_, &listener, this);
  }
  if (presentation_ && trace_) {
    auto* feedback = wp_presentation_feedback(presentation_, surface_);
    feedbacks_.insert(feedback);
    static const wp_presentation_feedback_listener listener = {SyncOutput, Presented, Discarded};
    wp_presentation_feedback_add_listener(feedback, &listener, this);
  }
  const bool ok = eglSwapBuffers(egl_display_, egl_surface_) == EGL_TRUE;
  eglMakeCurrent(egl_display_, draw, read, context);
  wl_display_flush(display_);
  g_mutex_unlock(&mutex_);
  return ok;
}
void AetheriaWayland::Destroy() {
  g_mutex_lock(&mutex_);
  if (callback_) { wl_callback_destroy(callback_); callback_ = nullptr; }
  for (auto* feedback : feedbacks_) wp_presentation_feedback_destroy(feedback);
  feedbacks_.clear();
  if (egl_surface_ != EGL_NO_SURFACE) {
    eglDestroySurface(egl_display_, egl_surface_); egl_surface_ = EGL_NO_SURFACE;
  }
  if (window_) { wl_egl_window_destroy(window_); window_ = nullptr; }
  if (subsurface_) { wl_subsurface_destroy(subsurface_); subsurface_ = nullptr; }
  if (surface_) { wl_surface_destroy(surface_); surface_ = nullptr; }
  parent_ = nullptr;
  parent_id_ = 0;
  if (presentation_) { wp_presentation_destroy(presentation_); presentation_ = nullptr; }
  if (compositor_) { wl_compositor_destroy(compositor_); compositor_ = nullptr; }
  if (subcompositor_) { wl_subcompositor_destroy(subcompositor_); subcompositor_ = nullptr; }
  if (registry_) { wl_registry_destroy(registry_); registry_ = nullptr; }
  if (trace_) { fclose(trace_); trace_ = nullptr; }
  g_mutex_unlock(&mutex_);
}
