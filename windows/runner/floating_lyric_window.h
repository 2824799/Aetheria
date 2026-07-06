#ifndef RUNNER_FLOATING_LYRIC_WINDOW_H_
#define RUNNER_FLOATING_LYRIC_WINDOW_H_

#include <flutter/encodable_value.h>
#include <windows.h>

#include <functional>
#include <string>
#include <vector>

class FloatingLyricWindow {
 public:
  static FloatingLyricWindow& GetInstance();

  void Show();
  void Hide();
  void UpdateStyle(const flutter::EncodableMap& payload);
  void UpdateLyrics(const flutter::EncodableMap& payload);
  void SetBoundsCallback(std::function<void(int, int, int, int)> callback);

 private:
  FloatingLyricWindow();
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
    unsigned int unplayed_color = 0xFFFFFFFF;
    unsigned int played_color = 0xFF22C55E;
    unsigned int shadow_color = 0x99000000;
    double window_x = -1.0;
    double window_y = -1.0;
    double window_width = 760.0;
    double window_height = 150.0;
  };

  struct Frame {
    std::wstring line = L"暂无歌词";
    std::wstring translation;
    std::wstring next_line;
    std::vector<std::wstring> context_lines;
    double progress = 0.0;
    bool is_playing = false;
    bool fade = false;
  };

  void EnsureWindow();
  void DestroyWindowHandle();
  void ApplyWindowStyle();
  void Draw();
  void NotifyBoundsChanged();
  RECT DefaultBounds() const;

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept;

  HWND hwnd_ = nullptr;
  Style style_;
  Frame frame_;
  bool is_interacting_ = false;
  std::function<void(int, int, int, int)> bounds_callback_;
};

#endif  // RUNNER_FLOATING_LYRIC_WINDOW_H_
