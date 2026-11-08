#ifndef RIFLAY_NATIVE_VIDEO_H_
#define RIFLAY_NATIVE_VIDEO_H_

#include <flutter_linux/flutter_linux.h>

// Wraps the Flutter view in a GTK overlay and registers riflay/video_window.
// Both X11 and Wayland use libmpv's render API, never a foreign window ID.
GtkWidget* native_video_wrap(FlView* view);

#endif
