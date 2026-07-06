#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>

#include <flutter/standard_method_codec.h>
#include "flutter/generated_plugin_registrant.h"
#include "floating_lyric_window.h"

namespace {

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) {
    return "";
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size <= 0) {
    return "";
  }
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

std::string ResolveDeviceName() {
  wchar_t buffer[MAX_COMPUTERNAME_LENGTH + 1]{};
  DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
  if (GetComputerNameW(buffer, &size)) {
    return WideToUtf8(std::wstring(buffer, size));
  }
  return "Windows PC";
}

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  if (!value) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(value);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  native_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.aetheria.app/notification",
          &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto method = call.method_name();
        if (method == "canDrawOverlays") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "requestOverlayPermission") {
          result->Success();
          return;
        }
        if (method == "getDeviceName") {
          result->Success(flutter::EncodableValue(ResolveDeviceName()));
          return;
        }
        if (method == "showFloatingLyrics") {
          FloatingLyricWindow::GetInstance().Show();
          result->Success();
          return;
        }
        if (method == "hideFloatingLyrics") {
          FloatingLyricWindow::GetInstance().Hide();
          result->Success();
          return;
        }
        if (method == "updateFloatingLyricsStyle") {
          if (const auto* map = AsMap(call.arguments())) {
            FloatingLyricWindow::GetInstance().UpdateStyle(*map);
          }
          result->Success();
          return;
        }
        if (method == "updateFloatingLyrics") {
          if (const auto* map = AsMap(call.arguments())) {
            FloatingLyricWindow::GetInstance().UpdateLyrics(*map);
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  FloatingLyricWindow::GetInstance().SetBoundsCallback(
      [this](int x, int y, int width, int height) {
        if (!native_channel_) {
          return;
        }
        flutter::EncodableMap event = {
            {flutter::EncodableValue("type"),
             flutter::EncodableValue("boundsChanged")},
            {flutter::EncodableValue("x"), flutter::EncodableValue(x)},
            {flutter::EncodableValue("y"), flutter::EncodableValue(y)},
            {flutter::EncodableValue("width"), flutter::EncodableValue(width)},
            {flutter::EncodableValue("height"), flutter::EncodableValue(height)}};
        native_channel_->InvokeMethod(
            "floatingLyricsEvent",
            std::make_unique<flutter::EncodableValue>(event));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    FloatingLyricWindow::GetInstance().Hide();
    FloatingLyricWindow::GetInstance().SetBoundsCallback(nullptr);
    native_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
