#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"
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

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif

// The mini player's island. The window stays the size of the open island and is
// see-through (Flutter draws the pill, anti-aliased, and animates it); only
// [hit], a rectangle in logical client pixels, is kept as the window's region, so
// clicks around the closed pill reach the windows behind. Windows 11's own rounded
// corners and border would outline the whole window, so they go while it's on.
// An empty [hit] gives the plain window back, see-through again only if the
// Appearance settings asked for it ([see_through]).
void SetIsland(HWND hwnd, const std::vector<double>& hit, bool see_through) {
  const bool on = hit.size() == 4;
  const int corner = on ? 1 /* DWMWCP_DONOTROUND */ : 0 /* DWMWCP_DEFAULT */;
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, sizeof(corner));
  const COLORREF border = on ? 0xFFFFFFFE /* DWMWA_COLOR_NONE */ : 0xFFFFFFFF /* DWMWA_COLOR_DEFAULT */;
  DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &border, sizeof(border));
  if (!on) {
    SetWindowRgn(hwnd, nullptr, TRUE);
    SetSeeThrough(hwnd, see_through);
    return;
  }
  // Fully clear where Flutter draws nothing: no system backdrop, the frame over the
  // whole client area and a transparent accent (what SetSeeThrough does on Windows 10).
  const int backdrop = 1 /* none */;
  DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop, sizeof(backdrop));
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);
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
    AccentPolicy policy = {2 /* transparent gradient */, 2, 0, 0};
    CompositionData data = {19 /* WCA_ACCENT_POLICY */, &policy, sizeof(policy)};
    set_attribute(hwnd, &data);
  }

  // The region is in window coordinates; the client area starts inside the
  // window's resize borders (invisible until a region is set, then a grey rim).
  // Never past the client area: the borders around it would show as a white rim.
  RECT window, client;
  if (!GetWindowRect(hwnd, &window) || !GetClientRect(hwnd, &client)) return;
  POINT origin = {0, 0};
  ClientToScreen(hwnd, &origin);
  const int x = origin.x - window.left, y = origin.y - window.top;
  const double scale = GetDpiForWindow(hwnd) / 96.0;
  auto px = [scale](double v) { return static_cast<int>(v * scale + 0.5); };
  auto clamp = [](int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); };
  const int left = clamp(px(hit[0]), 0, client.right), top = clamp(px(hit[1]), 0, client.bottom);
  const int right = clamp(px(hit[0] + hit[2]), 0, client.right);
  const int bottom = clamp(px(hit[1] + hit[3]), 0, client.bottom);
  // The region belongs to the window from here on (no DeleteObject).
  SetWindowRgn(hwnd, CreateRectRgn(x + left, y + top, x + right, y + bottom), TRUE);
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
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  media_controls_ = std::make_unique<MediaControls>(flutter_controller_->engine()->messenger(), GetHandle());

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "riflay/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "innoInstallLocation") {
      // This per-user registration is written by windows/installer/riflay.iss.
      constexpr wchar_t key[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
                               L"{DC558C20-B893-4F78-A05F-6E08F3F2435E}_is1";
      constexpr DWORD flags = RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY;
      DWORD bytes = 0;
      if (RegGetValueW(HKEY_CURRENT_USER, key, L"InstallLocation", flags, nullptr, nullptr, &bytes) != ERROR_SUCCESS ||
          bytes < sizeof(wchar_t) || bytes > 65536) {
        return result->Success();
      }
      std::vector<wchar_t> location(bytes / sizeof(wchar_t) + 1, L'\0');
      if (RegGetValueW(HKEY_CURRENT_USER, key, L"InstallLocation", flags, nullptr, location.data(), &bytes) !=
          ERROR_SUCCESS) {
        return result->Success();
      }
      return result->Success(flutter::EncodableValue(Utf8FromUtf16(location.data())));
    }
    if (call.method_name() == "currentMonitorWorkArea") {
      auto hwnd = GetHandle();
      auto monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info{};
      info.cbSize = sizeof(info);
      if (!GetMonitorInfo(monitor, &info)) return result->Error("monitor", "No monitor for this window");
      const double scale = GetDpiForWindow(hwnd) / 96.0;
      return result->Success(flutter::EncodableValue(flutter::EncodableList{
          info.rcWork.left / scale, info.rcWork.top / scale,
          info.rcWork.right / scale, info.rcWork.bottom / scale}));
    }
    if (call.method_name() == "moveDockedIsland") {
      const auto* grab = std::get_if<double>(call.arguments());
      POINT cursor{};
      if (!grab || !GetCursorPos(&cursor)) return result->Error("position", "No island drag position");
      auto monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info{};
      info.cbSize = sizeof(info);
      if (!GetMonitorInfo(monitor, &info)) return result->Error("monitor", "No monitor for the pointer");
      const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
      SetWindowPos(GetHandle(), nullptr, cursor.x - static_cast<int>(*grab * scale), info.rcWork.top,
                   0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      return result->Success();
    }
    if (call.method_name() == "setSwitcherVisible") {
      const auto* visible = std::get_if<bool>(call.arguments());
      if (visible == nullptr) return result->Error("bad-args", "A bool is expected");
      auto style = GetWindowLongPtr(GetHandle(), GWL_EXSTYLE);
      style = *visible ? ((style & ~WS_EX_TOOLWINDOW) | WS_EX_APPWINDOW)
                       : ((style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW);
      SetWindowLongPtr(GetHandle(), GWL_EXSTYLE, style);
      SetWindowPos(GetHandle(), nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
      return result->Success();
    }
    if (call.method_name() == "setIsland") {
      // [left, top, width, height] of the part that takes clicks, or nothing to turn it off.
      const auto* list = std::get_if<flutter::EncodableList>(call.arguments());
      if (list == nullptr) return result->Error("bad-args", "A list is expected");
      island_hit_.clear();
      for (const auto& e : *list) {
        const auto* n = std::get_if<double>(&e);
        if (n == nullptr) return result->Error("bad-args", "Numbers are expected");
        island_hit_.push_back(*n);
      }
      if (island_hit_.size() != 4) island_hit_.clear();
      SetIsland(GetHandle(), island_hit_, see_through_);
      return result->Success();
    }
    if (call.method_name() != "setSeeThrough") return result->NotImplemented();
    const auto* on = std::get_if<bool>(call.arguments());
    if (on == nullptr) return result->Error("bad-args", "A bool is expected");
    see_through_ = *on;
    // The island keeps its own clear window; the setting returns with the plain one.
    if (island_hit_.empty()) SetSeeThrough(GetHandle(), *on);
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
  media_controls_ = nullptr;
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

  // The system's media buttons, posted from its own thread (see media_controls.h).
  if (media_controls_ && media_controls_->HandleMessage(message, wparam, lparam)) return 0;

  // The island's pill follows the window as it grows and shrinks.
  if (message == WM_SIZE && !island_hit_.empty()) SetIsland(hwnd, island_hit_, see_through_);

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
