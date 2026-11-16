# Windows video renderer

Windows native sources from `media_kit_video` 2.0.1 (MIT; see LICENSE).
`windows/CMakeLists.txt` substitutes these sources for that plugin's native
target. Dart and other platforms continue to use the upstream package.

Riflay changes:

- Coalesce queued render callbacks and consume `mpv_render_context_update`
  before rendering, preserving callbacks that arrive during a frame.
- Copy the shared GPU texture only after a new video frame was rendered.
- Use atomic flags across the mpv callback and render worker threads.
- Wait for GPU completion with a D3D event query on ANGLE's own device,
  sleeping between readiness checks instead of busy-waiting in `glFinish`.
  Unsupported drivers and failed/slow queries retain `glFinish` as fallback.

Keep this copy synchronized when upgrading media_kit_video. GPU completion
and shared-texture synchronization are preserved; playback frame rate and
video/audio quality are unchanged.

The completion query uses the same D3D11 device exposed by ANGLE's EGL device
query extension. It never uses the separate texture-export device to infer GL
completion. The immediate context is protected for multithreaded access.
See Microsoft's [GetData documentation](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-getdata)
and [ID3D11Multithread](https://learn.microsoft.com/en-us/windows/win32/api/d3d11_4/nn-d3d11_4-id3d11multithread).
