#include "floating_lyric_window.h"

#include <gdiplus.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <memory>
#include <variant>
#include <vector>

#pragma comment(lib, "gdiplus.lib")

namespace {

constexpr wchar_t kFloatingLyricClassName[] = L"AetheriaFloatingLyricWindow";

class GdiplusSession {
 public:
  GdiplusSession() {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&token_, &input, nullptr);
  }

  ~GdiplusSession() {
    if (token_ != 0) {
      Gdiplus::GdiplusShutdown(token_);
    }
  }

 private:
  ULONG_PTR token_ = 0;
};

GdiplusSession& EnsureGdiplus() {
  static GdiplusSession session;
  return session;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return L"";
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) {
    return L"";
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size);
  return result;
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                         const char* key) {
  auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

bool GetBool(const flutter::EncodableMap& map, const char* key,
             bool fallback) {
  const auto* value = FindValue(map, key);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<bool>(value)) {
    return *typed;
  }
  return fallback;
}

double GetDouble(const flutter::EncodableMap& map, const char* key,
                 double fallback) {
  const auto* value = FindValue(map, key);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<double>(value)) {
    return *typed;
  }
  if (const auto* typed = std::get_if<int32_t>(value)) {
    return static_cast<double>(*typed);
  }
  if (const auto* typed = std::get_if<int64_t>(value)) {
    return static_cast<double>(*typed);
  }
  return fallback;
}

unsigned int GetUint(const flutter::EncodableMap& map, const char* key,
                     unsigned int fallback) {
  const auto* value = FindValue(map, key);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<int32_t>(value)) {
    return static_cast<unsigned int>(*typed);
  }
  if (const auto* typed = std::get_if<int64_t>(value)) {
    return static_cast<unsigned int>(*typed);
  }
  return fallback;
}

std::string GetString(const flutter::EncodableMap& map, const char* key,
                      const std::string& fallback) {
  const auto* value = FindValue(map, key);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<std::string>(value)) {
    return *typed;
  }
  return fallback;
}

std::wstring GetWideString(const flutter::EncodableMap& map, const char* key,
                           const std::wstring& fallback) {
  const auto* value = FindValue(map, key);
  if (!value) {
    return fallback;
  }
  if (const auto* typed = std::get_if<std::string>(value)) {
    return Utf8ToWide(*typed);
  }
  return fallback;
}

std::vector<std::wstring> GetWideStringList(const flutter::EncodableMap& map,
                                            const char* key) {
  std::vector<std::wstring> result;
  const auto* value = FindValue(map, key);
  if (!value) {
    return result;
  }
  const auto* list = std::get_if<flutter::EncodableList>(value);
  if (!list) {
    return result;
  }
  for (const auto& item : *list) {
    if (const auto* text = std::get_if<std::string>(&item)) {
      auto wide = Utf8ToWide(*text);
      if (!wide.empty()) {
        result.push_back(wide);
      }
    }
  }
  return result;
}

Gdiplus::Color ToGdiColor(unsigned int argb, double opacity = 1.0) {
  auto a = static_cast<BYTE>((argb >> 24) & 0xFF);
  auto r = static_cast<BYTE>((argb >> 16) & 0xFF);
  auto g = static_cast<BYTE>((argb >> 8) & 0xFF);
  auto b = static_cast<BYTE>(argb & 0xFF);
  a = static_cast<BYTE>(std::clamp(std::round(a * opacity), 0.0, 255.0));
  return Gdiplus::Color(a, r, g, b);
}

void AddRoundedRect(Gdiplus::GraphicsPath& path, const Gdiplus::RectF& rect,
                    float radius) {
  const float diameter = radius * 2.0f;
  path.AddArc(rect.X, rect.Y, diameter, diameter, 180.0f, 90.0f);
  path.AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter, 270.0f,
              90.0f);
  path.AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter,
              diameter, diameter, 0.0f, 90.0f);
  path.AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter, 90.0f,
              90.0f);
  path.CloseFigure();
}

float MeasureLineHeight(Gdiplus::Graphics& graphics, Gdiplus::Font& font) {
  return font.GetHeight(&graphics);
}

Gdiplus::StringAlignment AlignmentFor(const std::string& align) {
  if (align == "left") {
    return Gdiplus::StringAlignmentNear;
  }
  if (align == "right") {
    return Gdiplus::StringAlignmentFar;
  }
  return Gdiplus::StringAlignmentCenter;
}

void DrawLine(Gdiplus::Graphics& graphics, const std::wstring& text,
              const Gdiplus::RectF& rect, Gdiplus::Font& font,
              const std::string& align, const Gdiplus::Color& color,
              const Gdiplus::Color& shadow_color, bool draw_shadow) {
  Gdiplus::StringFormat format;
  format.SetAlignment(AlignmentFor(align));
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);

  if (draw_shadow) {
    Gdiplus::SolidBrush shadow(shadow_color);
    Gdiplus::RectF shadow_rect = rect;
    shadow_rect.Offset(0.0f, 1.4f);
    graphics.DrawString(text.c_str(), -1, &font, shadow_rect, &format, &shadow);
  }

  Gdiplus::SolidBrush brush(color);
  graphics.DrawString(text.c_str(), -1, &font, rect, &format, &brush);
}

void DrawProgressLine(Gdiplus::Graphics& graphics, const std::wstring& text,
                      const Gdiplus::RectF& rect, Gdiplus::Font& font,
                      const std::string& align, double progress,
                      const Gdiplus::Color& played,
                      const Gdiplus::Color& unplayed,
                      const Gdiplus::Color& shadow_color, bool draw_shadow) {
  DrawLine(graphics, text, rect, font, align, unplayed, shadow_color, draw_shadow);

  Gdiplus::StringFormat measure_format;
  measure_format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  measure_format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  Gdiplus::RectF measured;
  graphics.MeasureString(text.c_str(), -1, &font, rect, &measure_format,
                         &measured);
  const float drawn_width = std::min(measured.Width, rect.Width);
  float left = rect.X;
  if (align == "center") {
    left = rect.X + (rect.Width - drawn_width) / 2.0f;
  } else if (align == "right") {
    left = rect.GetRight() - drawn_width;
  }
  Gdiplus::RectF clip(left, rect.Y, drawn_width * static_cast<float>(progress),
                      rect.Height);
  Gdiplus::GraphicsState state = graphics.Save();
  graphics.SetClip(clip);
  DrawLine(graphics, text, rect, font, align, played, shadow_color, draw_shadow);
  graphics.Restore(state);
}

}  // namespace

FloatingLyricWindow& FloatingLyricWindow::GetInstance() {
  static FloatingLyricWindow instance;
  return instance;
}

FloatingLyricWindow::FloatingLyricWindow() {
  EnsureGdiplus();
}

FloatingLyricWindow::~FloatingLyricWindow() {
  DestroyWindowHandle();
}

void FloatingLyricWindow::Show() {
  EnsureWindow();
  if (!hwnd_) {
    return;
  }
  ApplyWindowStyle();
  Draw();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
}

void FloatingLyricWindow::Hide() {
  if (hwnd_) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

void FloatingLyricWindow::UpdateStyle(const flutter::EncodableMap& payload) {
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
  style_.unplayed_color =
      GetUint(payload, "unplayedColor", style_.unplayed_color);
  style_.played_color = GetUint(payload, "playedColor", style_.played_color);
  style_.shadow_color = GetUint(payload, "shadowColor", style_.shadow_color);
  style_.window_x = GetDouble(payload, "windowX", style_.window_x);
  style_.window_y = GetDouble(payload, "windowY", style_.window_y);
  style_.window_width = GetDouble(payload, "windowWidth", style_.window_width);
  style_.window_height =
      GetDouble(payload, "windowHeight", style_.window_height);

  EnsureWindow();
  if (!hwnd_) {
    return;
  }
  RECT bounds = DefaultBounds();
  SetWindowPos(hwnd_, style_.always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST,
               bounds.left, bounds.top, bounds.right - bounds.left,
               bounds.bottom - bounds.top,
               SWP_NOACTIVATE | SWP_NOOWNERZORDER);
  ApplyWindowStyle();
  Draw();
}

void FloatingLyricWindow::UpdateLyrics(const flutter::EncodableMap& payload) {
  frame_.line = GetWideString(payload, "line", frame_.line);
  frame_.translation = GetWideString(payload, "translation", frame_.translation);
  frame_.next_line = GetWideString(payload, "nextLine", frame_.next_line);
  frame_.context_lines = GetWideStringList(payload, "contextLines");
  frame_.progress =
      std::clamp(GetDouble(payload, "progress", frame_.progress), 0.0, 1.0);
  frame_.is_playing = GetBool(payload, "isPlaying", frame_.is_playing);
  frame_.fade = GetBool(payload, "fade", frame_.fade);

  EnsureWindow();
  Draw();
}

void FloatingLyricWindow::SetBoundsCallback(
    std::function<void(int, int, int, int)> callback) {
  bounds_callback_ = std::move(callback);
}

void FloatingLyricWindow::EnsureWindow() {
  if (hwnd_) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kFloatingLyricClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = FloatingLyricWindow::WndProc;
  RegisterClass(&window_class);

  RECT bounds = DefaultBounds();
  DWORD ex_style = WS_EX_LAYERED | WS_EX_TOOLWINDOW |
                   (style_.always_on_top ? WS_EX_TOPMOST : 0);
  if (style_.locked) {
    ex_style |= WS_EX_TRANSPARENT;
  }

  hwnd_ = CreateWindowEx(ex_style, kFloatingLyricClassName, L"Aetheria Lyrics",
                         WS_POPUP, bounds.left, bounds.top,
                         bounds.right - bounds.left, bounds.bottom - bounds.top,
                         nullptr, nullptr, GetModuleHandle(nullptr), this);
}

void FloatingLyricWindow::DestroyWindowHandle() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void FloatingLyricWindow::ApplyWindowStyle() {
  if (!hwnd_) {
    return;
  }
  LONG_PTR ex_style = GetWindowLongPtr(hwnd_, GWL_EXSTYLE);
  ex_style |= WS_EX_LAYERED | WS_EX_TOOLWINDOW;
  if (style_.locked) {
    ex_style |= WS_EX_TRANSPARENT;
  } else {
    ex_style &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLongPtr(hwnd_, GWL_EXSTYLE, ex_style);
  SetWindowPos(hwnd_, style_.always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0,
               0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void FloatingLyricWindow::Draw() {
  if (!hwnd_) {
    return;
  }

  RECT rect{};
  GetClientRect(hwnd_, &rect);
  int width = std::max(1L, rect.right - rect.left);
  int height = std::max(1L, rect.bottom - rect.top);

  Gdiplus::Bitmap bitmap(width, height, PixelFormat32bppPARGB);
  Gdiplus::Graphics graphics(&bitmap);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));

  double effective_opacity = frame_.fade ? style_.opacity * 0.22 : style_.opacity;
  if (is_interacting_ && !style_.locked) {
    Gdiplus::Color background(42, 0, 0, 0);
    Gdiplus::SolidBrush background_brush(background);
    Gdiplus::GraphicsPath path;
    AddRoundedRect(path,
                   Gdiplus::RectF(0, 0, static_cast<float>(width),
                                  static_cast<float>(height)),
                   14.0f);
    graphics.FillPath(&background_brush, &path);
  }

  auto font_family = std::make_unique<Gdiplus::FontFamily>(L"Microsoft YaHei UI");
  if (!font_family->IsAvailable()) {
    font_family = std::make_unique<Gdiplus::FontFamily>(L"Segoe UI");
  }
  const float current_size =
      static_cast<float>(style_.font_size * (style_.zoom_current_line ? 1.08 : 1.0));
  const float translation_size = current_size * 0.42f;
  const float next_size = current_size * 0.55f;
  Gdiplus::Font current_font(
      font_family.get(), current_size,
      style_.bold_current_line ? Gdiplus::FontStyleBold
                               : Gdiplus::FontStyleRegular,
      Gdiplus::UnitPixel);
  Gdiplus::Font translation_font(font_family.get(), translation_size,
                                 Gdiplus::FontStyleRegular,
                                 Gdiplus::UnitPixel);
  Gdiplus::Font next_font(font_family.get(), next_size,
                          Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);

  const bool has_translation =
      style_.show_translation && !frame_.translation.empty();
  std::vector<std::wstring> compact_lines;
  if (style_.compact_multiline) {
    for (const auto& line : frame_.context_lines) {
      if (!line.empty() && compact_lines.size() < 3) {
        compact_lines.push_back(line);
      }
    }
  }
  const bool has_next = style_.show_next_line &&
                        (!frame_.next_line.empty() || !compact_lines.empty());
  const float gap = static_cast<float>(style_.line_gap);
  const float current_height = MeasureLineHeight(graphics, current_font);
  const float translation_height =
      has_translation ? MeasureLineHeight(graphics, translation_font) : 0.0f;
  const float next_height = has_next ? MeasureLineHeight(graphics, next_font) : 0.0f;
  float total_height = current_height;
  if (has_translation) {
    total_height += gap * 0.55f + translation_height;
  }
  if (has_next) {
    total_height += gap + next_height;
  }
  if (!compact_lines.empty()) {
    const float compact_height = next_height * 0.88f;
    const size_t extra_count =
        frame_.next_line.empty() ? compact_lines.size() - 1 : compact_lines.size();
    total_height += static_cast<float>(extra_count) * (compact_height + gap * 0.28f);
  }
  const float margin = 22.0f;
  float top = (height - total_height) / 2.0f;
  Gdiplus::RectF line_rect(margin, top, width - margin * 2, current_height);
  DrawProgressLine(graphics, frame_.line.empty() ? L"暂无歌词" : frame_.line,
                   line_rect, current_font, style_.align, frame_.progress,
                   ToGdiColor(style_.played_color, effective_opacity),
                   ToGdiColor(style_.unplayed_color, effective_opacity),
                   ToGdiColor(style_.shadow_color, effective_opacity),
                   style_.text_shadow_enabled);
  top += current_height;

  if (has_translation) {
    top += gap * 0.55f;
    Gdiplus::RectF translation_rect(margin, top, width - margin * 2,
                                    translation_height);
    DrawLine(graphics, frame_.translation, translation_rect, translation_font,
             style_.align, ToGdiColor(style_.unplayed_color, effective_opacity * 0.76),
             ToGdiColor(style_.shadow_color, effective_opacity),
             style_.text_shadow_enabled);
    top += translation_height;
  }

  if (has_next) {
    top += gap;
    Gdiplus::RectF next_rect(margin, top, width - margin * 2, next_height);
    const std::wstring first_next =
        frame_.next_line.empty() && !compact_lines.empty() ? compact_lines.front()
                                                           : frame_.next_line;
    DrawLine(graphics, first_next, next_rect, next_font, style_.align,
             ToGdiColor(style_.unplayed_color, effective_opacity * 0.66),
             ToGdiColor(style_.shadow_color, effective_opacity),
             style_.text_shadow_enabled);
    top += next_height;

    const size_t start_index = frame_.next_line.empty() ? 1 : 0;
    if (compact_lines.size() > start_index) {
      Gdiplus::Font compact_font(font_family.get(), next_size * 0.88f,
                                 Gdiplus::FontStyleRegular,
                                 Gdiplus::UnitPixel);
      const float compact_height = MeasureLineHeight(graphics, compact_font);
      for (size_t i = start_index; i < compact_lines.size(); ++i) {
        top += gap * 0.28f;
        Gdiplus::RectF compact_rect(margin, top, width - margin * 2,
                                    compact_height);
        DrawLine(graphics, compact_lines[i], compact_rect, compact_font,
                 style_.align,
                 ToGdiColor(style_.unplayed_color, effective_opacity * 0.52),
                 ToGdiColor(style_.shadow_color, effective_opacity),
                 style_.text_shadow_enabled);
        top += compact_height;
      }
    }
  }

  HBITMAP hbitmap = nullptr;
  bitmap.GetHBITMAP(Gdiplus::Color(0, 0, 0, 0), &hbitmap);
  HDC screen_dc = GetDC(nullptr);
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  HGDIOBJ old_bitmap = SelectObject(mem_dc, hbitmap);
  POINT src = {0, 0};
  POINT dst = {0, 0};
  RECT win_rect{};
  GetWindowRect(hwnd_, &win_rect);
  dst.x = win_rect.left;
  dst.y = win_rect.top;
  SIZE size = {width, height};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  UpdateLayeredWindow(hwnd_, screen_dc, &dst, &size, mem_dc, &src, 0, &blend,
                      ULW_ALPHA);
  SelectObject(mem_dc, old_bitmap);
  DeleteObject(hbitmap);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
}

void FloatingLyricWindow::NotifyBoundsChanged() {
  if (!hwnd_ || !bounds_callback_) {
    return;
  }
  RECT rect{};
  GetWindowRect(hwnd_, &rect);
  bounds_callback_(rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top);
}

RECT FloatingLyricWindow::DefaultBounds() const {
  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const int width =
      std::clamp(static_cast<int>(std::round(style_.window_width)), 120, 1800);
  const int height =
      std::clamp(static_cast<int>(std::round(style_.window_height)), 36, 420);
  int x = static_cast<int>(std::round(style_.window_x));
  int y = static_cast<int>(std::round(style_.window_y));
  if (style_.window_x <= -9000.0 || style_.window_y <= -9000.0 || (style_.window_x == -1.0 && style_.window_y == -1.0)) {
    x = work_area.left + ((work_area.right - work_area.left) - width) / 2;
    y = work_area.bottom - height - 120;
  }
  x = std::clamp(x, static_cast<int>(work_area.left) - width + 80,
                 static_cast<int>(work_area.right) - 80);
  y = std::clamp(y, static_cast<int>(work_area.top),
                 static_cast<int>(work_area.bottom) - 40);
  return RECT{x, y, x + width, y + height};
}

LRESULT CALLBACK FloatingLyricWindow::WndProc(HWND hwnd, UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
  }
  auto* that = reinterpret_cast<FloatingLyricWindow*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (that) {
    return that->HandleMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT FloatingLyricWindow::HandleMessage(HWND hwnd, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept {
  switch (message) {
    case WM_NCHITTEST: {
      if (style_.locked) {
        return HTTRANSPARENT;
      }
      POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &pt);
      RECT rect{};
      GetClientRect(hwnd, &rect);
      const int edge = 10;
      const bool left = pt.x <= edge;
      const bool right = pt.x >= rect.right - edge;
      const bool top = pt.y <= edge;
      const bool bottom = pt.y >= rect.bottom - edge;
      if (left && top) return HTTOPLEFT;
      if (right && top) return HTTOPRIGHT;
      if (left && bottom) return HTBOTTOMLEFT;
      if (right && bottom) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
      return HTCAPTION;
    }
    case WM_ENTERSIZEMOVE:
      is_interacting_ = true;
      Draw();
      return 0;
    case WM_EXITSIZEMOVE:
      is_interacting_ = false;
      NotifyBoundsChanged();
      Draw();
      return 0;
    case WM_SIZE:
      Draw();
      return 0;
    case WM_CLOSE:
      Hide();
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
