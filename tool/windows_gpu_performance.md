# Windows GPU regression scenario

Build the isolated scenario, then launch the external sampler:

```powershell
flutter build windows --release --no-pub -t tool/windows_gpu_app.dart --dart-define=RIFLAY_NO_UPDATE_CHECK=true
.\tool\profile_windows_gpu.ps1 -GpuOnly -OutputDirectory build/windows-gpu-profile
```

The scenario uses a throwaway application profile. It caches the Kyapi MV
without reencoding audio or video, then plays the same 720p H.264 frames for
each run. Video decoding must actually activate and playback must continue
through the measured phase. The test opens lyrics, minimizes the real Windows
window, restores it and pauses. Do not interact with the test window while
sampling; restoring during the hidden phase invalidates that run.

The sampler includes the app and its children and normalizes processor time
across all logical processors, like Task Manager. Samples are approximately
one second apart; a reported peak is a sampled peak, not an absolute bound on
instantaneous CPU use. Each output directory contains phase timestamps,
stdout/stderr and CPU samples. Compare equivalent phases; startup, seeking,
minimize and restore transitions are outside the steady phases.

`-Renderer off` (default) uses Skia's GPU backend. `-Renderer on` selects
Windows Impeller for comparison. Neither option requests software rendering.
The native renderer logs `Sleepable GPU completion` only when ANGLE's own
D3D11 completion query is available. Older/unsupported drivers keep the
original completion mechanism. Hardware decoding may still use copy-back
(`d3d11va-copy`); it is not zero-copy video rendering.

Rebuild the ordinary app after testing, because the scenario deliberately
exits when complete:

```powershell
flutter build windows --release --no-pub --dart-define=RIFLAY_NO_UPDATE_CHECK=true
```

The 0.3% active-video peak target has not been established. Background and
active-video results must be reported separately; successful background
numbers cannot be used as evidence that active MV/lyrics meet that target.
