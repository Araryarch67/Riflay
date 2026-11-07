#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "video_window.h"

namespace {

#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

// Settings > Appearance > Window opacity: below 100% the window shows what is
// behind it. Windows 11 (22H2+) blurs it with the acrylic backdrop; older
// Windows lets it through unblurred. Opaque windows keep neither (cheaper).
void SetSeeThrough(HWND hwnd, bool on) {
  const int backdrop = on ? 3 /* acrylic */ : 1 /* none */;
  const bool has_backdrop =
      SUCCEEDED(DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop, sizeof(backdrop)));
  MARGINS margins = on ? MARGINS{-1, -1, -1, -1} : MARGINS{0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  // No system backdrop (Windows 10): ask for a plain transparent window.
  // SetWindowCompositionAttribute has no header; window_manager reaches it the same way.
  struct AccentPolicy {
    int state;
    int flags;
    int color;
    int animation;
  };
  struct CompositionData {
    int attribute;
    void* data;
    ULONG size;
  };
  using SetWindowCompositionAttributeFn = BOOL(WINAPI*)(HWND, CompositionData*);
  HMODULE user32 = GetModuleHandle(TEXT("user32.dll"));
  auto set_attribute = user32 ? reinterpret_cast<SetWindowCompositionAttributeFn>(
                                    GetProcAddress(user32, "SetWindowCompositionAttribute"))
                              : nullptr;
  if (set_attribute) {
    // 0 disabled, 2 transparent gradient. Also resets what window_manager set at start-up.
    AccentPolicy policy = {on && !has_backdrop ? 2 : 0, 2, 0, 0};
    CompositionData data = {19 /* WCA_ACCENT_POLICY */, &policy, sizeof(policy)};
    set_attribute(hwnd, &data);
  }
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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "riflay/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setSeeThrough") return result->NotImplemented();
    const auto* on = std::get_if<bool>(call.arguments());
    if (on == nullptr) return result->Error("bad-args", "A bool is expected");
    SetSeeThrough(GetHandle(), *on);
    result->Success();
  });

  video_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "riflay/video_window",
      &flutter::StandardMethodCodec::GetInstance());
  video_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& name = call.method_name();
    if (name == "ensure") {
      HWND host = video_window::Ensure(GetHandle());
      if (host == nullptr) return result->Error("no-window", "The video window could not be made");
      return result->Success(flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(host))));
    }
    if (name == "place") {
      // [clip left, top, right, bottom, full left, top, right, bottom], in the client area's pixels.
      const auto* list = std::get_if<flutter::EncodableList>(call.arguments());
      if (list == nullptr || list->size() != 8) return result->Error("bad-args", "Eight numbers are expected");
      int v[8];
      for (size_t i = 0; i < 8; i++) {
        const auto& e = (*list)[i];
        if (const auto* n = std::get_if<int32_t>(&e)) {
          v[i] = *n;
        } else if (const auto* l = std::get_if<int64_t>(&e)) {
          v[i] = static_cast<int>(*l);
        } else {
          return result->Error("bad-args", "Eight integers are expected");
        }
      }
      video_window::Place(RECT{v[0], v[1], v[2], v[3]}, RECT{v[4], v[5], v[6], v[7]});
      return result->Success();
    }
    if (name == "destroy") {
      video_window::Destroy();
      return result->Success();
    }
    result->NotImplemented();
  });

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
  window_channel_ = nullptr;
  video_channel_ = nullptr;
  video_window::Destroy();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The music video's windows are disabled, so the mouse over them comes here: the Flutter view under them takes it
  // (its client area starts where this window's does, so the coordinates hold).
  if (message >= WM_MOUSEFIRST && message <= WM_MOUSELAST && flutter_controller_ && video_window::Visible()) {
    return SendMessage(flutter_controller_->view()->GetNativeWindow(), message, wparam, lparam);
  }

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
