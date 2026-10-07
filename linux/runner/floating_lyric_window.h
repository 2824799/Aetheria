#ifndef RUNNER_FLOATING_LYRIC_WINDOW_H_
#define RUNNER_FLOATING_LYRIC_WINDOW_H_

#include <flutter_linux/flutter_linux.h>

#include <functional>
#include <string>
#include <vector>

// Always-on-top transparent overlay that renders the current lyric line for
// the Linux desktop. Mirrors windows/runner/floating_lyric_window.cpp.
class FloatingLyricWindow {
 public:
  static FloatingLyricWindow& GetInstance();

  void Show();
  void Hide();
  void UpdateStyle(FlValue* payload);
  void UpdateLyrics(FlValue* payload);
  void SetBoundsCallback(std::function<void(int, int, int, int)> callback);

 private:
  FloatingLyricWindow() = default;
  FloatingLyricWindow(const FloatingLyricWindow&) = delete;
  FloatingLyricWindow& operator=(const FloatingLyricWindow&) = delete;
  ~FloatingLyricWindow();

  struct Style {
    bool locked = false;
    bool always_on_top = true;
    bool show_translation = true;
    bool show_next_line = true;
    bool bold_current_line = true;
    bool zoom_current_line = true;
    bool compact_multiline = false;
    bool text_shadow_enabled = true;
    std::string align = "center";
    double font_size = 30.0;
    double line_gap = 8.0;
    double opacity = 0.95;
    uint32_t unplayed_color = 0xFFFFFFFF;
    uint32_t played_color = 0xFF22C55E;
    uint32_t shadow_color = 0x99000000;
    double window_x = -99999.0;
    double window_y = -99999.0;
    double window_width = 760.0;
    double window_height = 150.0;
  };

  struct Frame {
    std::string line;
    std::string translation;
    std::string next_line;
    std::vector<std::string> context_lines;
    double progress = 0.0;
    bool is_playing = false;
    bool fade = false;
  };

  void EnsureWindow();
  void DestroyWindowHandle();
  void ApplyWindowGeometry();
  void ApplyStacking();
  void EndDrag();
  void ApplyInputPassthrough();
  void QueueDraw();
  void NotifyBoundsChanged();

  static gboolean OnDraw(GtkWidget* widget, cairo_t* cr, gpointer user_data);
  static gboolean OnButtonPress(GtkWidget* widget, GdkEventButton* event,
                                gpointer user_data);
  static gboolean OnMotion(GtkWidget* widget, GdkEventMotion* event,
                           gpointer user_data);
  static gboolean OnButtonRelease(GtkWidget* widget, GdkEventButton* event,
                                  gpointer user_data);
  static gboolean OnConfigure(GtkWidget* widget, GdkEventConfigure* event,
                          gpointer user_data);
  static void OnWindowDestroy(GtkWidget* widget, gpointer user_data);

  void Draw(cairo_t* cr);

  GtkWidget* window_ = nullptr;
  Style style_;
  Frame frame_;
  bool dragging_ = false;
  bool layer_shell_ = false;
  int resize_x_ = 0;
  int resize_y_ = 0;
  double drag_x_ = 0;
  double drag_y_ = 0;
  double resize_padding_x_ = 0;
  double resize_padding_y_ = 0;
  guint bounds_notify_timer_ = 0;
  std::function<void(int, int, int, int)> bounds_callback_;
};

#endif  // RUNNER_FLOATING_LYRIC_WINDOW_H_
