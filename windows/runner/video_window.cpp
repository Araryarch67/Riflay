#include "video_window.h"

namespace video_window {
namespace {

HWND clip_ = nullptr;
HWND host_ = nullptr;
constexpr wchar_t kClass[] = L"RiflayVideoWindow";

void Register() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSEXW wc = {sizeof(wc)};
  wc.lpfnWndProc = DefWindowProcW;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  wc.lpszClassName = kClass;
  RegisterClassExW(&wc);
  registered = true;
}

HWND Make(HWND parent) {
  return CreateWindowExW(WS_EX_NOPARENTNOTIFY, kClass, L"", WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN | WS_DISABLED,
                         0, 0, 1, 1, parent, nullptr, GetModuleHandle(nullptr), nullptr);
}

}  // namespace

HWND Ensure(HWND parent) {
  if (host_ != nullptr) return host_;
  Register();
  clip_ = Make(parent);
  host_ = clip_ ? Make(clip_) : nullptr;
  if (host_ != nullptr) ShowWindow(host_, SW_SHOWNA);
  return host_;
}

void Place(const RECT& clip, const RECT& full) {
  if (clip_ == nullptr) return;
  const int w = clip.right - clip.left, h = clip.bottom - clip.top;
  if (w <= 0 || h <= 0) {
    ShowWindow(clip_, SW_HIDE);
    return;
  }
  SetWindowPos(host_, nullptr, full.left - clip.left, full.top - clip.top, full.right - full.left,
               full.bottom - full.top, SWP_NOZORDER | SWP_NOACTIVATE);
  SetWindowPos(clip_, HWND_TOP, clip.left, clip.top, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void Destroy() {
  if (clip_ != nullptr) DestroyWindow(clip_);
  clip_ = host_ = nullptr;
}

bool Visible() { return clip_ != nullptr && IsWindowVisible(clip_); }

}  // namespace video_window
