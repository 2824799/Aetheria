#include "floating_lyric_window.h"

#include <cairo.h>
#include <gtk/gtk.h>
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
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_FLOAT) {
    return fallback;
  }
  return fl_value_get_float(value);
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

struct Rgba {
  double r;
  double g;
  double b;
  double a;
};

Rgba ToRgba(uint32_t argb, double opacity) {
  return Rgba{
      ((argb >> 16) & 0xFF) / 255.0,
      ((argb >> 8) & 0xFF) / 255.0,
      (argb & 0xFF) / 255.0,
      (((argb >> 24) & 0xFF) / 255.0) * opacity,
  };
}

PangoAlignment ResolveAlignment(const std::string& align) {
  if (align == "left") {
    return PANGO_ALIGN_LEFT;
  }
  if (align == "right") {
    return PANGO_ALIGN_RIGHT;
  }
  return PANGO_ALIGN_CENTER;
}

struct LineLayout {
  PangoLayout* layout;
  double height;
};

LineLayout CreateLineLayout(cairo_t* cr, const std::string& text,
                            double font_size, bool bold,
                            const std::string& align, double max_width) {
  PangoLayout* layout = pango_cairo_create_layout(cr);
  PangoFontDescription* desc = pango_font_description_new();
  pango_font_description_set_family(
      desc, "Noto Sans CJK SC, WenQuanYi Micro Hei, Microsoft YaHei, sans-serif");
  pango_font_description_set_absolute_size(desc, font_size * PANGO_SCALE);
  pango_font_description_set_weight(
      desc, bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL);
  pango_layout_set_font_description(layout, desc);
  pango_font_description_free(desc);
  pango_layout_set_alignment(layout, ResolveAlignment(align));
  pango_layout_set_width(layout, static_cast<int>(max_width * PANGO_SCALE));
  pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR);
  pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
  pango_layout_set_text(layout, text.c_str(), -1);

  int width = 0;
  int height = 0;
  pango_layout_get_pixel_size(layout, &width, &height);
  return LineLayout{layout, static_cast<double>(std::max(1, height))};
}

void DrawLineWithShadow(cairo_t* cr, PangoLayout* layout, double x, double y,
                        const Rgba& color, const Rgba& shadow,
                        bool shadow_enabled) {
  if (shadow_enabled && shadow.a > 0.01) {
    cairo_save(cr);
    cairo_move_to(cr, x + 1.5, y + 1.5);
    cairo_set_source_rgba(cr, shadow.r, shadow.g, shadow.b, shadow.a);
    pango_cairo_show_layout(cr, layout);
    cairo_restore(cr);
  }
  cairo_save(cr);
  cairo_move_to(cr, x, y);
  cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
  pango_cairo_show_layout(cr, layout);
  cairo_restore(cr);
}

// Fills the "played" portion of the active line by clipping to a horizontal
// percentage of the layout width.
void DrawProgressLine(cairo_t* cr, PangoLayout* layout, double x, double y,
                      double width, double progress, const Rgba& played,
                      const Rgba& unplayed, const Rgba& shadow,
                      bool shadow_enabled) {
  DrawLineWithShadow(cr, layout, x, y, unplayed, shadow, shadow_enabled);
  if (progress <= 0.0) {
    return;
  }
  cairo_save(cr);
  cairo_rectangle(cr, x, y - 4, width * std::clamp(progress, 0.0, 1.0),
                  100000);
  cairo_clip(cr);
  DrawLineWithShadow(cr, layout, x, y, played, shadow, shadow_enabled);
  cairo_restore(cr);
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
  if (style_.always_on_top) {
    gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  }
}

void FloatingLyricWindow::Hide() {
  if (window_ != nullptr) {
    gtk_widget_hide(window_);
  }
}

void FloatingLyricWindow::UpdateStyle(FlValue* payload) {
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
  style_.font_size = GetDouble(payload, "fontSize", style_.font_size);
  style_.line_gap = GetDouble(payload, "lineGap", style_.line_gap);
  style_.opacity = GetDouble(payload, "opacity", style_.opacity);
  style_.unplayed_color = GetColor(payload, "unplayedColor", style_.unplayed_color);
  style_.played_color = GetColor(payload, "playedColor", style_.played_color);
  style_.shadow_color = GetColor(payload, "shadowColor", style_.shadow_color);
  style_.window_x = GetDouble(payload, "windowX", style_.window_x);
  style_.window_y = GetDouble(payload, "windowY", style_.window_y);
  style_.window_width = GetDouble(payload, "windowWidth", style_.window_width);
  style_.window_height = GetDouble(payload, "windowHeight", style_.window_height);

  if (window_ == nullptr) {
    return;
  }
  // Prevent configure-event feedback when we programmatically resize.
  g_signal_handlers_block_by_func(window_, reinterpret_cast<gpointer>(OnConfigure), this);
  ApplyWindowGeometry();
  gtk_window_set_keep_above(GTK_WINDOW(window_), style_.always_on_top ? TRUE : FALSE);
  gtk_window_set_accept_focus(GTK_WINDOW(window_), style_.locked ? FALSE : TRUE);
  gtk_widget_set_app_paintable(window_, TRUE);
  ApplyInputPassthrough();
  g_signal_handlers_unblock_by_func(window_, reinterpret_cast<gpointer>(OnConfigure), this);
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
  gtk_window_set_title(GTK_WINDOW(window_), "Aetheria Lyrics");
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_type_hint(GTK_WINDOW(window_), GDK_WINDOW_TYPE_HINT_UTILITY);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
  gtk_widget_set_app_paintable(window_, TRUE);
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

  ApplyInputPassthrough();
  // Set the position before the window is first shown; KWin Wayland ignores
  // gtk_window_move() after the surface exists.
  ApplyWindowGeometry();
}

void FloatingLyricWindow::DestroyWindowHandle() {
  if (window_ != nullptr) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

void FloatingLyricWindow::ApplyWindowGeometry() {
  if (window_ == nullptr) {
    return;
  }
  const int width = std::clamp(static_cast<int>(std::lround(style_.window_width)),
                               kMinWindowWidth, kMaxWindowWidth);
  const int height = std::clamp(
      static_cast<int>(std::lround(style_.window_height)), kMinWindowHeight,
      kMaxWindowHeight);
  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_window_resize(GTK_WINDOW(window_), width, height);

  if (style_.window_x > -9000.0 && style_.window_y > -9000.0 &&
      !(style_.window_x == -1.0 && style_.window_y == -1.0)) {
    gtk_window_move(GTK_WINDOW(window_),
                    static_cast<int>(std::lround(style_.window_x)),
                    static_cast<int>(std::lround(style_.window_y)));
    return;
  }

  // Default: horizontally centered near the bottom of the primary monitor.
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) {
    return;
  }
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor == nullptr) {
    return;
  }
  GdkRectangle workarea{};
  gdk_monitor_get_workarea(monitor, &workarea);
  const int x = workarea.x + (workarea.width - width) / 2;
  const int y = workarea.y + workarea.height - height - 120;
  gtk_window_move(GTK_WINDOW(window_), x, y);
}

void FloatingLyricWindow::QueueDraw() {
  if (window_ != nullptr) {
    gtk_widget_queue_draw(window_);
  }
}

void FloatingLyricWindow::ApplyInputPassthrough() {
#ifdef GDK_WINDOWING_X11
  if (window_ == nullptr) {
    return;
  }
  GdkWindow* gdk_window = gtk_widget_get_window(window_);
  if (gdk_window == nullptr || !GDK_IS_X11_WINDOW(gdk_window)) {
    return;
  }
  GdkDisplay* display = gdk_window_get_display(gdk_window);
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) {
    return;
  }
  if (style_.locked) {
    cairo_region_t* empty = cairo_region_create();
    gdk_window_input_shape_combine_region(gdk_window, empty, 0, 0);
    cairo_region_destroy(empty);
  } else {
    gdk_window_input_shape_combine_region(gdk_window, nullptr, 0, 0);
  }
#endif
}

void FloatingLyricWindow::NotifyBoundsChanged() {
  if (window_ == nullptr || bounds_callback_ == nullptr) {
    return;
  }
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
  gtk_window_get_position(GTK_WINDOW(window_), &x, &y);
  gtk_window_get_size(GTK_WINDOW(window_), &width, &height);
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
  self->dragging_ = true;
  int window_x = 0;
  int window_y = 0;
  gtk_window_get_position(GTK_WINDOW(widget), &window_x, &window_y);
  self->drag_offset_x_ = event->x_root - window_x;
  self->drag_offset_y_ = event->y_root - window_y;
  return TRUE;
}

gboolean FloatingLyricWindow::OnMotion(GtkWidget* widget, GdkEventMotion* event,
                                       gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  if (!self->dragging_ || self->style_.locked) {
    return FALSE;
  }
  const int target_x = static_cast<int>(std::lround(event->x_root - self->drag_offset_x_));
  const int target_y = static_cast<int>(std::lround(event->y_root - self->drag_offset_y_));
  gtk_window_move(GTK_WINDOW(widget), target_x, target_y);
  return TRUE;
}

gboolean FloatingLyricWindow::OnButtonRelease(GtkWidget* /*widget*/,
                                              GdkEventButton* event,
                                              gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  if (!self->dragging_ || event->button != 1) {
    return FALSE;
  }
  self->dragging_ = false;
  self->NotifyBoundsChanged();
  return TRUE;
}

void FloatingLyricWindow::OnConfigure(GtkWidget* widget,
                                      GdkEventConfigure* event,
                                      gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  const int width = std::clamp(event->width, kMinWindowWidth, kMaxWindowWidth);
  const int height = std::clamp(event->height, kMinWindowHeight, kMaxWindowHeight);
  // Only notify when the size actually changed to avoid Wayland configure
  // feedback loops.
  const int current_w = static_cast<int>(self->style_.window_width);
  const int current_h = static_cast<int>(self->style_.window_height);
  if (!self->dragging_ && (width != current_w || height != current_h)) {
    self->style_.window_width = width;
    self->style_.window_height = height;
    self->NotifyBoundsChanged();
  }
}

void FloatingLyricWindow::OnWindowDestroy(GtkWidget* /*widget*/,
                                          gpointer user_data) {
  auto* self = static_cast<FloatingLyricWindow*>(user_data);
  self->window_ = nullptr;
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

  double top = (height - total_height) / 2.0;
  double x = kMargin;
  if (style_.align == "left") {
    x = kMargin;
  } else if (style_.align == "right") {
    int text_width = 0;
    int text_height = 0;
    pango_layout_get_pixel_size(active.layout, &text_width, &text_height);
    x = std::max(kMargin, width - kMargin - text_width);
  }

  DrawProgressLine(cr, active.layout, x, top, max_width, frame_.progress,
                   played, unplayed, shadow, style_.text_shadow_enabled);
  top += active.height;

  if (translation.layout != nullptr) {
    top += gap * 0.55;
    DrawLineWithShadow(cr, translation.layout, x, top, translation_color, shadow,
                       style_.text_shadow_enabled);
    top += translation.height;
  }

  if (next.layout != nullptr) {
    top += gap;
    DrawLineWithShadow(cr, next.layout, x, top, next_color, shadow,
                       style_.text_shadow_enabled);
    top += next.height;
  }

  for (const auto& extra : extras) {
    top += gap * 0.28;
    DrawLineWithShadow(cr, extra.layout, x, top, compact_color, shadow,
                       style_.text_shadow_enabled);
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
