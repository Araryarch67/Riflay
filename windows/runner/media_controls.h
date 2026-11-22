#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Windows' System Media Transport Controls for Riflay's window: the media flyout, the lock screen, keyboard media
// keys (Fn shortcuts included) and Bluetooth headsets reach the app through it, focused or not.
//
// "riflay/media_session" (lib/services/media_session/windows_media_controls.dart):
//   Dart -> here: enable, metadata {id, title, artist, album, art}, state {status, positionMs, durationMs, rate,
//                 canNext, canPrevious}, disable.
//   here -> Dart: command {command: play | pause | stop | next | previous | seek, positionMs}.
//
// The system raises its events on a worker thread; they are posted to the window (kCommandMessage) and sent to Dart
// from the platform thread, where Flutter's channels must be used.
class MediaControls {
 public:
  static constexpr UINT kCommandMessage = WM_APP + 0x52;

  MediaControls(flutter::BinaryMessenger* messenger, HWND window);
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // Handles kCommandMessage; false for any other message.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
