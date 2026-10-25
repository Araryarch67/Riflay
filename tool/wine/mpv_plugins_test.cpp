// Plays a file through an mpv audio filter chain into a WAV file, the way the
// app plays it (libmpv, ao=pcm instead of a sound card). Run under Wine by
// tool/test_plugins_wine.sh, which checks the level of the result.
//
//   mpv_plugins_test.exe <in.wav> <out.wav> <af chain>
#include <windows.h>

#include <cstdio>

#include <mpv/client.h>

int main(int argc, char** argv) {
  if (argc < 4) return 2;
  mpv_handle* mpv = mpv_create();
  if (!mpv) return 2;
  mpv_set_option_string(mpv, "vo", "null");
  mpv_set_option_string(mpv, "ao", "pcm");
  mpv_set_option_string(mpv, "ao-pcm-file", argv[2]);
  mpv_set_option_string(mpv, "af", argv[3]);
  mpv_request_log_messages(mpv, "warn");
  if (mpv_initialize(mpv) < 0) return 2;
  const char* cmd[] = {"loadfile", argv[1], nullptr};
  mpv_command(mpv, cmd);
  int status = 1;
  for (;;) {
    mpv_event* e = mpv_wait_event(mpv, 0.1);
    if (e->event_id == MPV_EVENT_LOG_MESSAGE) {
      auto* m = static_cast<mpv_event_log_message*>(e->data);
      std::printf("[%s] %s", m->prefix, m->text);
    } else if (e->event_id == MPV_EVENT_END_FILE) {
      auto* end = static_cast<mpv_event_end_file*>(e->data);
      status = end->reason == MPV_END_FILE_REASON_EOF ? 0 : 1;
      if (status) std::printf("ended early: %s\n", mpv_error_string(end->error));
      break;
    } else if (e->event_id == MPV_EVENT_SHUTDOWN) {
      break;
    }
  }
  mpv_terminate_destroy(mpv);
  return status;
}
