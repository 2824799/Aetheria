#include "floating_lyric_window.h"
#include "lyric_renderer.h"

using namespace aetheria;

#include <cairo.h>
#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
#include <pango/pango.h>
#include <pango/pangocairo.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <algorithm>
#include <cmath>

namespace {

constexpr int kMinWindowWidth = 120;
constexpr int kMaxWindowWidth = 1800;
constexpr int kMinWindowHeight = 36;
constexpr int kMaxWindowHeight = 420;
constexpr double kMargin = 22.0;

bool GetBool(FlValue* map, const gchar* key, bool fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

double GetDouble(FlValue* map, const gchar* key, double fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) return fallback;
  double result = fallback;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) result = fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) result = fl_value_get_int(value);
  return std::isfinite(result) ? result : fallback;
}

uint32_t GetColor(FlValue* map, const gchar* key, uint32_t fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return static_cast<uint32_t>(fl_value_get_int(value));
}

std::string GetString(FlValue* map, const gchar* key,
                      const std::string& fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return fallback;
  }
  return fl_value_get_string(value);
}

std::vector<std::string> GetStringList(FlValue* map, const gchar* key) {
  std::vector<std::string> result;
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return result;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) {
    return result;
  }
  for (size_t i = 0; i < fl_value_get_length(value); ++i) {
    FlValue* item = fl_value_get_list_value(value, i);
    if (item != nullptr && fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      result.emplace_back(fl_value_get_string(item));
    }
  }
  return result;
}


}  // namespace

FloatingLyricWindow& FloatingLyricWindow::GetInstance() {
  static FloatingLyricWindow instance;
  return instance;
}

FloatingLyricWindow::~FloatingLyricWindow() {
  DestroyWindowHandle();
}

void FloatingLyricWindow::Show() {
  EnsureWindow();
  if (window_ == nullptr) {
    return;
  }
  ApplyWindowGeometry();
  if (!gtk_widget_get_visible(window_)) {
    gtk_widget_show_all(window_);
  }
  ApplyStacking();
}

void FloatingLyricWindow::Hide() {
  if (window_ != nullptr) {
    EndDrag();
    gtk_widget_hide(window_);
  }
}

void FloatingLyricWindow::UpdateStyle(FlValue* payload) {
  const double previous_x = style_.window_x, previous_y = style_.window_y;
  const double previous_width = style_.window_width, previous_height = style_.window_height;
  style_.locked = GetBool(payload, "locked", style_.locked);
  style_.always_on_top = GetBool(payload, "alwaysOnTop", style_.always_on_top);
  style_.show_translation =
      GetBool(payload, "showTranslation", style_.show_translation);
  style_.show_next_line = GetBool(payload, "showNextLine", style_.show_next_line);
  style_.bold_current_line =
      GetBool(payload, "boldCurrentLine", style_.bold_current_line);
  style_.zoom_current_line =
      GetBool(payload, "zoomCurrentLine", style_.zoom_current_line);
  style_.compact_multiline =
      GetBool(payload, "compactMultiline", style_.compact_multiline);
  style_.text_shadow_enabled =
      GetBool(payload, "textShadowEnabled", style_.text_shadow_enabled);
  style_.align = GetString(payload, "align", style_.align);
  style_.font_size = std::clamp(GetDouble(payload, "fontSize", style_.font_size), 8.0, 72.0);
  style_.line_gap = std::clamp(GetDouble(payload, "lineGap", style_.line_gap), 0.0, 32.0);
  style_.opacity = std::clamp(GetDouble(payload, "opacity", style_.opacity), 0.0, 1.0);
  style_.unplayed_color = GetColor(payload, "unplayedColor", style_.unplayed_color);
  style_.played_color = GetColor(payload, "playedColor", style_.played_color);
  style_.shadow_color = GetColor(payload, "shadowColor", style_.shadow_color);
  style_.window_x = std::clamp(GetDouble(payload, "windowX", style_.window_x), -1000000.0, 1000000.0);
  style_.window_y = std::clamp(GetDouble(payload, "windowY", style_.window_y), -1000000.0, 1000000.0);
  style_.window_width = std::clamp(GetDouble(payload, "windowWidth", style_.window_width), 120.0, 1800.0);
  style_.window_height = std::clamp(GetDouble(payload, "windowHeight", style_.window_height), 36.0, 420.0);

  if (window_ == nullptr) {
    return;
  }
  if (style_.window_x != previous_x || style_.window_y != previous_y ||
      style_.window_width != previous_width || style_.window_height != previous_height) {
    ApplyWindowGeometry();
  }
  if (style_.locked) EndDrag();
  ApplyStacking();
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
  gtk_widget_set_app_paintable(window_, TRUE);
  ApplyInputPassthrough();
  QueueDraw();
}

void FloatingLyricWindow::UpdateLyrics(FlValue* payload) {
  frame_.line = GetString(payload, "line", frame_.line);
  frame_.translation = GetString(payload, "translation", frame_.translation);
  frame_.next_line = GetString(payload, "nextLine", frame_.next_line);
  frame_.context_lines = GetStringList(payload, "contextLines");
  frame_.progress =
      std::clamp(GetDouble(payload, "progress", frame_.progress), 0.0, 1.0);
  frame_.is_playing = GetBool(payload, "isPlaying", frame_.is_playing);
  frame_.fade = GetBool(payload, "fade", frame_.fade);
  QueueDraw();
}

void FloatingLyricWindow::SetBoundsCallback(
    std::function<void(int, int, int, int)> callback) {
  bounds_callback_ = std::move(callback);
}

void FloatingLyricWindow::EnsureWindow() {
  if (window_ != nullptr) {
    return;
  }

  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  layer_shell_ = gtk_layer_is_supported();
  if (layer_shell_) {
    gtk_layer_init_for_window(GTK_WINDOW(window_));
    gtk_layer_set_namespace(GTK_WINDOW(window_), "aetheria-lyrics");
    gtk_layer_set_keyboard_mode(GTK_WINDOW(window_), GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    gtk_layer_set_anchor(GTK_WINDOW(window_), GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(window_), GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    // No panel reservation. Margins use the output's full logical geometry.
    gtk_layer_set_exclusive_zone(GTK_WINDOW(window_), -1);
    ApplyStacking();
  }
  gtk_window_set_title(GTK_WINDOW(window_), "Aetheria Lyrics");
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_type_hint(GTK_WINDOW(window_), GDK_WINDOW_TYPE_HINT_UTILITY);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
  gtk_widget_set_app_paintable(window_, TRUE);
  gtk_window_set_focus_on_map(GTK_WINDOW(window_), FALSE);
  gtk_widget_set_name(window_, "aetheria-lyrics");
  // Remove theme-provided CSD shadows/borders as well as the window-manager frame.
  g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css,
      "#aetheria-lyrics, #aetheria-lyrics decoration { background: transparent;"
      " border: none; box-shadow: none; margin: 0; padding: 0; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(window_),
      GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  gtk_widget_add_events(window_, GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
                                     GDK_POINTER_MOTION_MASK);
  gtk_widget_set_size_request(window_, kMinWindowWidth, kMinWindowHeight);

  GdkScreen* screen = gtk_widget_get_screen(window_);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(window_, visual);
  }

  g_signal_connect(window_, "draw", G_CALLBACK(OnDraw), this);
  g_signal_connect(window_, "button-press-event", G_CALLBACK(OnButtonPress), this);
  g_signal_connect(window_, "motion-notify-event", G_CALLBACK(OnMotion), this);
  g_signal_connect(window_, "button-release-event", G_CALLBACK(OnButtonRelease),
                   this);
  g_signal_connect(window_, "configure-event", G_CALLBACK(OnConfigure), this);
  g_signal_connect(window_, "destroy", G_CALLBACK(OnWindowDestroy), this);

  g_signal_connect(window_, "realize", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    static_cast<FloatingLyricWindow*>(data)->ApplyInputPassthrough();
  }), this);
  g_signal_connect_after(window_, "size-allocate", G_CALLBACK(+[](GtkWidget*, GtkAllocation*, gpointer data) {
    static_cast<FloatingLyricWindow*>(data)->ApplyInputPassthrough();
  }), this);
  ApplyWindowGeometry();
}

void FloatingLyricWindow::DestroyWindowHandle() {
  if (window_ != nullptr) {
    EndDrag();
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

void FloatingLyricWindow::ApplyWindowGeometry() {
  if (window_ == nullptr) {
    return;
  }
  int width = std::clamp(static_cast<int>(std::lround(style_.window_width)), kMinWindowWidth, kMaxWindowWidth);
  int height = std::clamp(static_cast<int>(std::lround(style_.window_height)), kMinWindowHeight, kMaxWindowHeight);
  const bool saved = style_.window_x > -9000.0 && style_.window_y > -9000.0 &&
      !(style_.window_x == -1.0 && style_.window_y == -1.0);
  GdkDisplay* display = gtk_widget_get_display(window_);
  GdkMonitor* monitor = saved ? gdk_display_get_monitor_at_point(display,
      static_cast<int>(style_.window_x), static_cast<int>(style_.window_y)) :
      gdk_display_get_primary_monitor(display);
  if (!monitor) monitor = gdk_display_get_monitor(display, 0);
  GdkRectangle area{0, 0, 1920, 1080};
  if (monitor) gdk_monitor_get_workarea(monitor, &area);
  width = std::min(width, std::max(kMinWindowWidth, area.width));
  height = std::min(height, std::max(kMinWindowHeight, area.height));
  const int requested_x = saved ? static_cast<int>(std::lround(style_.window_x)) : area.x + (area.width - width) / 2;
  const int requested_y = saved ? static_cast<int>(std::lround(style_.window_y)) : area.y + area.height - height - 120;
  const int x = std::clamp(requested_x, area.x, area.x + std::max(0, area.width - width));
  const int y = std::clamp(requested_y, area.y, area.y + std::max(0, area.height - height));
  if (layer_shell_) {
    GdkRectangle output = area;
    if (monitor) {
      gdk_monitor_get_geometry(monitor, &output);
      gtk_layer_set_monitor(GTK_WINDOW(window_), monitor);
    }
    style_.window_x = x;
    style_.window_y = y;
    style_.window_width = width;
    style_.window_height = height;
    gtk_layer_set_margin(GTK_WINDOW(window_), GTK_LAYER_SHELL_EDGE_LEFT, x - output.x);
    gtk_layer_set_margin(GTK_WINDOW(window_), GTK_LAYER_SHELL_EDGE_TOP, y - output.y);
    gtk_widget_set_size_request(window_, width, height);
    gtk_window_resize(GTK_WINDOW(window_), 1, 1);
    return;
  }
  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_window_resize(GTK_WINDOW(window_), width, height);
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    gtk_window_move(GTK_WINDOW(window_), x, y);
  }
#endif
  // xdg-shell does not offer absolute positioning. Do not send ignored moves or
  // overwrite a saved X11 position with fabricated Wayland root coordinates.
}

void FloatingLyricWindow::ApplyStacking() {
  if (!window_) return;
  if (layer_shell_) {
    // TOP is above ordinary windows but below active fullscreen windows in
    // KWin. OVERLAY keeps lyrics visible over games without taking focus.
    gtk_layer_set_layer(GTK_WINDOW(window_), style_.always_on_top ?
        GTK_LAYER_SHELL_LAYER_OVERLAY : GTK_LAYER_SHELL_LAYER_BOTTOM);
  } else {
    gtk_window_set_keep_above(GTK_WINDOW(window_), style_.always_on_top);
  }
}

void FloatingLyricWindow::EndDrag() {
  if (!dragging_) return;
  dragging_ = false;
  if (window_ && gtk_widget_has_grab(window_)) gtk_grab_remove(window_);
  NotifyBoundsChanged();
  QueueDraw();
}

void FloatingLyricWindow::QueueDraw() {
  if (window_ != nullptr) {
    gtk_widget_queue_draw(window_);
  }
}

void FloatingLyricWindow::ApplyInputPassthrough() {
  if (window_ == nullptr) return;
  GdkWindow* native = gtk_widget_get_window(window_);
  if (native == nullptr) return;
  cairo_region_t* region = style_.locked ? cairo_region_create() : nullptr;
  // GDK translates the input region on both X11 and Wayland. Apply after realize
  // as well, otherwise an initially locked window still intercepts clicks.
  gtk_widget_input_shape_combine_region(window_, region);
  if (region) cairo_region_destroy(region);
}

void FloatingLyricWindow::NotifyBoundsChanged() {
  if (window_ == nullptr || bounds_callback_ == nullptr || dragging_) {
    return;
  }
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  x = static_cast<int>(style_.window_x);
  y = static_cast<int>(style_.window_y);
  if (layer_shell_) {
    // Persist the final request even if the compositor has not acknowledged it.
    width = static_cast<int>(style_.window_width);
    height = static_cast<int>(style_.window_height);
  } else {
    gtk_window_get_size(GTK_WINDOW(window_), &width, &height);
  }
  bounds_callback_(x, y, width, height);
}

gboolean FloatingLyricWindow::OnDraw(GtkWidget* /*widget*/, cairo_t* cr,
                                     gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  self->Draw(cr);
  return TRUE;
}

gboolean FloatingLyricWindow::OnButtonPress(GtkWidget* widget,
                                            GdkEventButton* event,
                                            gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  if (self->style_.locked || event->button != 1 ||
      event->type != GDK_BUTTON_PRESS) {
    return FALSE;
  }
  // Compositor-managed move/resize works without global coordinates on Wayland.
  const int width = gtk_widget_get_allocated_width(widget);
  const int height = gtk_widget_get_allocated_height(widget);
  const bool left = event->x < 8, right = event->x > width - 8;
  const bool top = event->y < 8, bottom = event->y > height - 8;
  if (self->layer_shell_) {
    // Layer surfaces have no xdg_toplevel move/resize operation. The pointer's
    // local position plus our output margins supplies the drag coordinates.
    self->dragging_ = true;
    self->resize_x_ = left ? -1 : right ? 1 : 0;
    self->resize_y_ = top ? -1 : bottom ? 1 : 0;
    self->drag_x_ = event->x;
    self->drag_y_ = event->y;
    self->resize_padding_x_ = width - event->x;
    self->resize_padding_y_ = height - event->y;
    gtk_grab_add(widget);
    self->QueueDraw();
    return TRUE;
  }
  if (left || right || top || bottom) {
    GdkWindowEdge edge = top ? (left ? GDK_WINDOW_EDGE_NORTH_WEST :
        right ? GDK_WINDOW_EDGE_NORTH_EAST : GDK_WINDOW_EDGE_NORTH) :
        bottom ? (left ? GDK_WINDOW_EDGE_SOUTH_WEST :
        right ? GDK_WINDOW_EDGE_SOUTH_EAST : GDK_WINDOW_EDGE_SOUTH) :
        left ? GDK_WINDOW_EDGE_WEST : GDK_WINDOW_EDGE_EAST;
    gtk_window_begin_resize_drag(GTK_WINDOW(widget), edge, event->button,
        event->x_root, event->y_root, event->time);
  } else {
    gtk_window_begin_move_drag(GTK_WINDOW(widget), event->button,
        event->x_root, event->y_root, event->time);
  }
  return TRUE;
}

gboolean FloatingLyricWindow::OnMotion(GtkWidget*, GdkEventMotion* event, gpointer data) {
  auto* self = static_cast<FloatingLyricWindow*>(data);
  if (!self->dragging_ || self->style_.locked) return FALSE;
  auto& s = self->style_;
  if (!self->resize_x_ && !self->resize_y_) {
    s.window_x += event->x - self->drag_x_;
    s.window_y += event->y - self->drag_y_;
  } else {
    if (self->resize_x_ < 0) {
      const double width = std::clamp(s.window_width - event->x + self->drag_x_,
          double(kMinWindowWidth), double(kMaxWindowWidth));
      s.window_x += s.window_width - width;
      s.window_width = width;
    } else if (self->resize_x_ > 0) {
      s.window_width = event->x + self->resize_padding_x_;
    }
    if (self->resize_y_ < 0) {
      const double height = std::clamp(s.window_height - event->y + self->drag_y_,
          double(kMinWindowHeight), double(kMaxWindowHeight));
      s.window_y += s.window_height - height;
      s.window_height = height;
    } else if (self->resize_y_ > 0) {
      s.window_height = event->y + self->resize_padding_y_;
    }
  }
  self->ApplyWindowGeometry();
  return TRUE;
}

gboolean FloatingLyricWindow::OnButtonRelease(GtkWidget*, GdkEventButton* event, gpointer data) {
  auto* self = static_cast<FloatingLyricWindow*>(data);
  if (!self->dragging_ || event->button != 1) return FALSE;
  self->EndDrag();
  return TRUE;
}

gboolean FloatingLyricWindow::OnConfigure(GtkWidget* widget,
                                      GdkEventConfigure* event,
                                      gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  int x = static_cast<int>(self->style_.window_x);
  int y = static_cast<int>(self->style_.window_y);
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(gtk_widget_get_display(widget))) {
    gtk_window_get_position(GTK_WINDOW(widget), &x, &y);
  }
#endif
  const bool changed = event->width != self->style_.window_width ||
      event->height != self->style_.window_height || x != self->style_.window_x ||
      y != self->style_.window_y;
  // Layer configure events may acknowledge an earlier resize. The requested
  // geometry remains authoritative while requests are in flight.
  if (!self->layer_shell_) {
    self->style_.window_width = event->width;
    self->style_.window_height = event->height;
  }
  self->style_.window_x = x;
  self->style_.window_y = y;
  if (changed) {
    if (self->bounds_notify_timer_) g_source_remove(self->bounds_notify_timer_);
    self->bounds_notify_timer_ = g_timeout_add(150, [](gpointer data) -> gboolean {
      auto* self = static_cast<FloatingLyricWindow*>(data);
      self->bounds_notify_timer_ = 0;
      self->NotifyBoundsChanged();
      return G_SOURCE_REMOVE;
    }, self);
  }
  return FALSE;
}

void FloatingLyricWindow::OnWindowDestroy(GtkWidget* /*widget*/,
                                          gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  self->EndDrag();
  if (self->bounds_notify_timer_) {
    g_source_remove(self->bounds_notify_timer_);
    self->bounds_notify_timer_ = 0;
  }
  self->window_ = nullptr;
  self->layer_shell_ = false;
}

void FloatingLyricWindow::Draw(cairo_t* cr) {
  if (window_ == nullptr) {
    return;
  }
  int width = 0;
  int height = 0;
  gtk_window_get_size(GTK_WINDOW(window_), &width, &height);
  width = std::max(1, width);
  height = std::max(1, height);

  cairo_save(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0, 0, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

  const double opacity = frame_.fade ? style_.opacity * 0.22 : style_.opacity;
  const Rgba played = ToRgba(style_.played_color, opacity);
  const Rgba unplayed = ToRgba(style_.unplayed_color, opacity);
  const Rgba translation_color = ToRgba(style_.unplayed_color, opacity * 0.76);
  const Rgba next_color = ToRgba(style_.unplayed_color, opacity * 0.66);
  const Rgba compact_color = ToRgba(style_.unplayed_color, opacity * 0.52);
  const Rgba shadow = ToRgba(style_.shadow_color, opacity);

  if (dragging_ && !style_.locked) {
    cairo_set_source_rgba(cr, 0, 0, 0, 0.16);
    cairo_rectangle(cr, 0, 0, width, height);
    cairo_fill(cr);
  }

  const double max_width = std::max(1.0, width - kMargin * 2);
  const double current_size =
      style_.font_size * (style_.zoom_current_line ? 1.08 : 1.0);
  const double translation_size = current_size * 0.42;
  const double next_size = current_size * 0.55;
  const double compact_size = next_size * 0.88;
  const double gap = style_.line_gap;

  std::vector<std::string> compact_lines;
  if (style_.compact_multiline) {
    for (const auto& line : frame_.context_lines) {
      if (!line.empty() && compact_lines.size() < 3) {
        compact_lines.push_back(line);
      }
    }
  }

  const std::string active_text =
      frame_.line.empty() ? "暂无歌词" : frame_.line;
  const bool has_translation =
      style_.show_translation && !frame_.translation.empty();
  const bool has_next = style_.show_next_line &&
                        (!frame_.next_line.empty() || !compact_lines.empty());

  LineLayout active = CreateLineLayout(cr, active_text, current_size,
                                       style_.bold_current_line, style_.align,
                                       max_width);
  double total_height = active.height;

  LineLayout translation{nullptr, 0.0};
  if (has_translation) {
    translation = CreateLineLayout(cr, frame_.translation, translation_size,
                                   false, style_.align, max_width);
    total_height += gap * 0.55 + translation.height;
  }

  LineLayout next{nullptr, 0.0};
  if (has_next) {
    const std::string first_next = frame_.next_line.empty() && !compact_lines.empty()
                                       ? compact_lines.front()
                                       : frame_.next_line;
    next = CreateLineLayout(cr, first_next, next_size, false, style_.align,
                            max_width);
    total_height += gap + next.height;
  }

  std::vector<LineLayout> extras;
  if (!compact_lines.empty()) {
    const size_t start = frame_.next_line.empty() ? 1 : 0;
    for (size_t i = start; i < compact_lines.size(); ++i) {
      extras.push_back(CreateLineLayout(cr, compact_lines[i], compact_size,
                                        false, style_.align, max_width));
      total_height += gap * 0.28 + extras.back().height;
    }
  }

  double top = std::max(0.0, (height - total_height) / 2.0);
  // Pango handles alignment inside max_width. Moving x again double-aligns text.
  const double x = kMargin;

  DrawProgressLine(cr, active.layout, x, top, frame_.progress,
                   played, unplayed, shadow, active.font_size,
                   style_.text_shadow_enabled);
  top += active.height;

  if (translation.layout != nullptr) {
    top += gap * 0.55;
    DrawLineWithShadow(cr, translation.layout, x, top, translation_color, shadow,
                       translation.font_size, style_.text_shadow_enabled);
    top += translation.height;
  }

  if (next.layout != nullptr) {
    top += gap;
    DrawLineWithShadow(cr, next.layout, x, top, next_color, shadow,
                       next.font_size, style_.text_shadow_enabled);
    top += next.height;
  }

  for (const auto& extra : extras) {
    top += gap * 0.28;
    DrawLineWithShadow(cr, extra.layout, x, top, compact_color, shadow,
                       extra.font_size, style_.text_shadow_enabled);
    top += extra.height;
  }

  g_object_unref(active.layout);
  if (translation.layout != nullptr) {
    g_object_unref(translation.layout);
  }
  if (next.layout != nullptr) {
    g_object_unref(next.layout);
  }
  for (auto& extra : extras) {
    g_object_unref(extra.layout);
  }
}
