#ifndef RUNNER_VIDEO_WINDOW_H_
#define RUNNER_VIDEO_WINDOW_H_

#include <windows.h>

// The music video's own windows, over the Flutter view: mpv draws into them
// with Direct3D 11 (its own swap chain, decoded on the graphics card), so a
// video frame never makes Flutter redraw the window.
//
// Two of them: the clip window is the part of the video's box that is in view
// (a scrolled panel cuts it), and the host window inside it is the whole box,
// offset by what is cut off. mpv is handed the host. Both are disabled: the
// mouse goes to the main window, which passes it on to the Flutter view (see
// FlutterWindow::MessageHandler), so the page under the video still scrolls
// and takes clicks.
namespace video_window {

// The host window mpv draws into, made (hidden) the first time.
HWND Ensure(HWND parent);

// Shows the video's box |full| cut to |clip| (both in the parent's client
// pixels); an empty |clip| hides it.
void Place(const RECT& clip, const RECT& full);

void Destroy();

// Whether it is on screen now (mouse input over it needs passing on).
bool Visible();

}  // namespace video_window

#endif  // RUNNER_VIDEO_WINDOW_H_
