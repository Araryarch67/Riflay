#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The mini player's island: the part of the window that takes clicks, [left, top, width, height] in logical
  // client pixels; empty when off (see SetIsland).
  std::vector<double> island_hit_;

  // What Settings › Appearance last asked for (see SetSeeThrough), given back when the island goes.
  bool see_through_ = false;

  // "riflay/window": the see-through window switch (see SetSeeThrough) and the island's shape.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;

  // "riflay/video_window": the music video's own windows (see video_window.cpp).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> video_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
