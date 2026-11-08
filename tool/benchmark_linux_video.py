#!/usr/bin/env python3
"""Measure the full Linux app in a copied checkout and an isolated compositor.

python3 tool/benchmark_linux_video.py --runs 3 --output build/perf/linux-video-2026-11-08
Use --runs 1 --modes balanced for a shorter smoke run. No account data is copied.
"""
import argparse
from contextlib import nullcontext
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CPU_LIMIT = {"lightweight": 0.16, "balanced": 0.7, "heavy": 0.7}
RAM_LIMIT = {"lightweight": 85, "balanced": 260, "heavy": 275}


def run(command, log, **kwargs):
    with open(log, "a") as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True, **kwargs)


def fixtures(folder, log):
    manifest = folder / "manifest.json"
    if manifest.exists():
        saved = json.loads(manifest.read_text())
        return saved["tracks"], Path(saved["audio"]), {k: Path(v) for k, v in saved["videos"].items()}
    folder.mkdir(parents=True)
    ff = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    tracks = []

    def track(path, title, artist="Benchmark Artist", album="Benchmark Album"):
        return {"id": path.as_uri(), "uri": path.as_uri(), "title": title,
                "artist": artist, "album": album, "durationMs": 240000, "tagged": True}

    for album in range(12):
        cover = folder / f"cover-{album}.jpg"
        run(ff + ["-f", "lavfi", "-i", f"color=c=0x{album * 19:02x}4080:s=1000x1000",
                  "-frames:v", "1", str(cover)], log)
        audio = folder / f"album-{album}.flac"
        run(ff + ["-f", "lavfi", "-i", "anoisesrc=c=pink:a=0.05:d=12:r=48000", "-i", str(cover),
                  "-map", "0", "-map", "1", "-ac", "2", "-c:v", "copy", "-disposition:v", "attached_pic",
                  "-metadata", f"album=Album {album}", str(audio)], log)
        for index in range(10):
            path = folder / f"album-{album}-track-{index}.flac"
            os.link(audio, path)
            tracks.append(track(path, f"A long song title for track {index} from album {album}",
                                f"Artist {album}", f"Album {album}"))
    audio = folder / "hires.flac"
    run(ff + ["-f", "lavfi", "-i", "anoisesrc=c=pink:a=0.05:d=240:r=96000", "-i", str(cover),
              "-map", "0", "-map", "1", "-ac", "2", "-sample_fmt", "s32", "-c:v", "copy",
              "-disposition:v", "attached_pic", str(audio)], log)
    tracks.append(track(audio, "A long hi-res song title to exercise the playing marquee"))
    videos = {}
    for mode, height in [("lightweight", 480), ("balanced", 720), ("heavy", 1080)]:
        video = folder / f"video-{height}.mp4"
        width = {480: 854, 720: 1280, 1080: 1920}[height]
        run(ff + ["-f", "lavfi", "-i", f"testsrc2=size={width}x{height}:rate=30",
                  "-f", "lavfi", "-i", "anoisesrc=c=pink:a=0.05:r=48000", "-t", "150",
                  "-c:v", "libx264", "-preset", "ultrafast", "-crf", "26", "-pix_fmt", "yuv420p",
                  "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(video)], log)
        videos[mode] = video
        tracks.append(track(video, f"A long music video title at {height}p for the playing marquee"))
    manifest.write_text(json.dumps({"tracks": tracks, "audio": str(audio), "videos": {k: str(v) for k, v in videos.items()}}))
    return tracks, audio, videos


def seed(folder, tracks, mode, decoder="automatic"):
    appdata = folder / "data/dev.riflay.riflay"
    appdata.mkdir(parents=True)
    prefs = {"flutter.library.v1": json.dumps(tracks), "flutter.deviceSetup.v1": True,
             "flutter.layout.v1": json.dumps({"performance": mode, "visualizer": True, "visualizerStable": True,
                                               "videoDecoder": decoder}),
             "flutter.discord.enabled": False, "flutter.autoplay.v1": False,
             "flutter.volume.v1": 0.0, "flutter.loop.v1": "one", "flutter.videoMode.on": False}
    (appdata / "shared_preferences.json").write_text(json.dumps(prefs))
    for name in ["cache", "config"]:
        (folder / name).mkdir()


def gpu_name():
    """NVIDIA's name and driver when nvidia-smi answers (it doesn't after a driver update until a reboot)."""
    if shutil.which("nvidia-smi"):
        smi = subprocess.run(["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"],
                             capture_output=True, text=True)
        if smi.returncode == 0:
            return smi.stdout.strip()
    return "See compositorGlRenderer"


def validate_samples(samples):
    """Refuse a 'native' comparison that silently fell back or stopped moving."""
    if len(samples) != 5:
        raise ValueError("Expected all five measurement phases")
    for s in samples:
        if s["sampleSeconds"] < 1 or s["logicalProcessors"] < 1:
            raise ValueError("Invalid sample interval or CPU count")
        if s["phase"] != "idle_home" and (s["audioOutput"] != "pipewire" or
                                            not s["audioDevice"].startswith("pipewire/riflay_benchmark_")):
            raise ValueError("Benchmark audio did not use the isolated silent sink")
        if s["phase"] in ["audio_playing", "video_playing", "video_unfocused_released"]:
            if not s["audioPlaying"] or s["audioPositionEndMs"] <= s["audioPositionStartMs"]:
                raise ValueError("Audio was not progressing")
        if s["phase"] == "video_playing":
            if not s["videoPlaying"] or s["videoPositionEndMs"] <= s["videoPositionStartMs"]:
                raise ValueError("Video was not progressing")
            if s["backend"] == "native":
                if not s["nativeReady"] or s["textureReady"] or not s["surfaceAfter"]["visible"]:
                    raise ValueError("Native backend fell back or was hidden")
                if s["surfaceAfter"]["frames"] <= s["surfaceBefore"]["frames"]:
                    raise ValueError("Native renderer did not draw frames")
            elif not s["textureReady"] or s["nativeReady"]:
                raise ValueError("Texture backend was not active")
        if s["phase"] == "video_paused":
            if s["audioPlaying"] or s["videoPlaying"] or abs(s["videoPositionEndMs"] - s["videoPositionStartMs"]) > 100:
                raise ValueError("Paused playback was still moving")
        if s["phase"] == "video_unfocused_released" and (s["nativeReady"] or s["textureReady"]):
            raise ValueError("Unfocused renderer was not released")


def report(output, results, metadata):
    (output / "results.json").write_text(json.dumps({"metadata": metadata, "samples": results}, indent=2))
    groups = {}
    for result in results:
        key = (result["mode"], result["backend"], result["phase"])
        groups.setdefault(key, []).append(result)
    rows = []
    for (mode, backend, phase), samples in groups.items():
        cpu = statistics.median(s["cpuTotalPercent"] for s in samples)
        core = statistics.median(s["cpuOneCorePercent"] for s in samples)
        mem = {key: statistics.median(max(s["memoryBefore"][key], s["memoryAfter"][key]) for s in samples)
               for key in ["privateMiB", "pssMiB", "rssMiB", "peakRssMiB"]}
        idle = phase in ["idle_home", "video_paused"]
        limit = 0.8 / metadata["logicalProcessors"] if idle else CPU_LIMIT[mode]
        timings = statistics.median(s["reportedFrameTimingsPerSecond"] for s in samples)
        rows.append({"mode": mode, "backend": backend, "phase": phase, "runs": len(samples),
                     "cpuTotalPercent": cpu, "cpuOneCorePercent": core, **mem,
                     "cpuTotalMinPercent": min(s["cpuTotalPercent"] for s in samples),
                     "cpuTotalMaxPercent": max(s["cpuTotalPercent"] for s in samples),
                     "cpuLimitTotalPercent": limit, "cpuPass": cpu < limit,
                     "reportedFrameTimingsPerSecond": timings,
                     "idleFrameTimingsPass": timings == 0 if idle else None,
                     "ramLimitMiB": RAM_LIMIT[mode], "privatePass": mem["privateMiB"] <= RAM_LIMIT[mode],
                     "pssPass": mem["pssMiB"] <= RAM_LIMIT[mode], "rssPass": mem["rssMiB"] <= RAM_LIMIT[mode]})
    (output / "summary.json").write_text(json.dumps(rows, indent=2))
    with (output / "summary.csv").open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]) if rows else [])
        writer.writeheader()
        writer.writerows(rows)
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2))
    intro = ["# Linux full-app CPU and RAM measurement", "", "## Video playback result", "",
             "| Mode | Runs | CPU total % | CPU reference max % | Private MiB | RAM reference max | Result |",
             "|---|---:|---:|---:|---:|---:|---|"]
    for row in rows:
        if row["backend"] == "native" and row["phase"] == "video_playing":
            passed = row["cpuPass"] and row["privatePass"]
            intro.append(f"| {row['mode']} | {row['runs']} | {row['cpuTotalPercent']:.3f} | "
                         f"{CPU_LIMIT[row['mode']]} | {row['privateMiB']:.1f} | {RAM_LIMIT[row['mode']]} | "
                         f"{'PASS' if passed else 'FAIL'} |")
    intro += ["", "Values are medians, not maximum-use guarantees. Numerical RAM comparisons above use Linux private",
              "memory; PSS, RSS, lifetime peak RSS, CPU min/max and every run are retained in the data below.", ""]
    lines = intro + ["## Method", "",
             "Normal Riflay startup and UI in a profile build, 1280×800 at 1×, isolated headless Weston.",
             "120 local songs with 1000×1000 embedded covers, one 24-bit/96 kHz audio track, and H.264/AAC",
             "music-video fixtures at 480p/720p/1080p according to mode. No signed-in account or streaming.",
             "Audio uses the normal PipeWire backend through a temporary null sink; DSP is unmuted and the visualizer receives real audio.",
             "Application CPU excludes the compositor, audio server, and GPU utilization/VRAM, as a process CPU metric normally does.",
             "Fresh application data/config/cache and process per run. Each CPU interval is measured from /proc/self/stat.",
             "CPU total = one-core percent / logical CPU count. Completed child CPU time is included.",
             "Memory is /proc/self/smaps_rollup: private clean+dirty, PSS and RSS, in MiB.",
             "Per-run memory uses the larger of the before/after snapshots; the table is the median of runs.",
             "The JSON/CSV also includes peakRssMiB, the process lifetime high-water mark (not a per-phase peak).",
             "FrameTiming counts can omit texture-only raster work and are not a raster-thread-idle assertion.",
             "Unfocused samples begin only after the video's 20-second release timeout has actually released its player.",
             "", "Windows private working set and Linux memory accounting differ. All three Linux RAM metrics are",
             "reported against the numerical Windows reference; a private-only pass is not an RSS pass.",
             "The Windows numbers are historical measurements, not a guarantee across GPUs, platforms or media.",
             "", "## Machine and build", "", f"GPU: {metadata['gpu']}",
             f"Logical processors: {metadata['logicalProcessors']}; Flutter {metadata['flutter']['frameworkVersion']} profile.",
             f"Compositor GL renderer: {', '.join(metadata.get('compositorGlRenderer', []))}.",
             f"Copied source SHA-256: `{metadata['sourceSha256']}`.",
             "", "[Complete machine/build metadata](metadata.json) · [Raw measurements](results.json) · [Summary JSON](summary.json) · [CSV](summary.csv)", "",
             "## Medians", "", "| Mode | Backend | State | n | CPU total % | One-core % | Private MiB | PSS MiB | RSS MiB | CPU within reference |", 
             "|---|---|---|---:|---:|---:|---:|---:|---:|---|"]
    for row in rows:
        lines.append(f"| {row['mode']} | {row['backend']} | {row['phase']} | {row['runs']} | "
                     f"{row['cpuTotalPercent']:.3f} | {row['cpuOneCorePercent']:.2f} | {row['privateMiB']:.1f} | "
                     f"{row['pssMiB']:.1f} | {row['rssMiB']:.1f} | {'PASS' if row['cpuPass'] else 'FAIL'} |")
    lines += ["", "Reference upper values: Lightweight 0.16% total / 85 MiB, Balanced 0.7% / 260 MiB,",
              "Heavy 0.7% / 275 MiB. Idle/paused CPU reference is <0.8% of one core, with no ongoing UI frames.",
              "See summary.json/CSV for separate private, PSS and RSS pass/fail results, and results.json for raw",
              "samples, playback progress, actual decoder, renderer attachment and frame counts.", ""]
    (output / "report.md").write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--sample-seconds", type=int, default=10)
    parser.add_argument("--settle-seconds", type=int, default=4)
    parser.add_argument("--modes", nargs="+", default=["lightweight", "balanced", "heavy"], choices=list(CPU_LIMIT))
    parser.add_argument("--output", type=Path, default=ROOT / "build/perf/linux-video-2026-11-08")
    parser.add_argument("--video-decoder", default="automatic", choices=["automatic", "hardware", "software"],
                        help="Settings > Layout > Video decoding for every case (software: CPU, no GPU decoder)")
    parser.add_argument("--stacks", metavar="PHASE",
                        help="Debug build that prints who asks for frames in PHASE (e.g. video_playing); no numbers")
    parser.add_argument("--work-dir", type=Path, help="Keep the isolated build and generated fixtures here for reruns")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.runs < 1 or args.sample_seconds < 1:
        parser.error("Runs and sample duration must be positive")
    results = []
    metadata = {"logicalProcessors": os.cpu_count(), "sampleSeconds": args.sample_seconds,
                "settleSeconds": args.settle_seconds, "runsRequested": args.runs,
                "videoDecoder": args.video_decoder,
                "startedUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "gitHead": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "cpu": subprocess.check_output(["lscpu", "-J"], text=True),
                "gpu": gpu_name(),
                "flutter": json.loads(subprocess.check_output(["flutter", "--version", "--machine"], text=True))}
    if args.work_dir:
        args.work_dir.mkdir(parents=True, exist_ok=True)
    context = nullcontext(str(args.work_dir.resolve())) if args.work_dir else tempfile.TemporaryDirectory(prefix="riflay-full-video-bench-")
    with context as scratch:
        temp = Path(scratch)
        source = temp / "source"
        source.mkdir(exist_ok=True)
        sources = [ROOT / name for name in ["lib", "assets", "linux", "tool", "third_party", "pubspec.yaml",
                                            "pubspec.lock", "analysis_options.yaml", "l10n.yaml", "AGENT.md"]]
        subprocess.run(["rsync", "-a", "--exclude=ephemeral", *map(str, sources), str(source)], check=True)
        digest = hashlib.sha256()
        for path in sorted(source.rglob("*")):
            if path.is_file() and path.suffix in [".dart", ".cc", ".h", ".yaml", ".txt", ".py"]:
                digest.update(str(path.relative_to(source)).encode())
                digest.update(path.read_bytes())
        metadata["sourceSha256"] = digest.hexdigest()
        metadata["copiedSource"] = str(source)
        print("BENCH_RUN preparing fixtures and isolated profile build", flush=True)
        tracks, audio, videos = fixtures(temp / "fixtures", output / "fixtures.log")
        run(["flutter", "pub", "get", "--offline"], output / "build.log", cwd=source, timeout=180)
        flavor = "debug" if args.stacks else "profile"
        run(["flutter", "build", "linux", f"--{flavor}", "--no-pub", "-t", "tool/linux_video_benchmark_app.dart"],
            output / "build.log", cwd=source, timeout=600)
        runtime = temp / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        compositor_env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime))
        audio_runtime = os.environ["XDG_RUNTIME_DIR"]
        sink = f"riflay_benchmark_{os.getpid()}"
        module = subprocess.check_output(["pactl", "load-module", "module-null-sink", f"sink_name={sink}",
                                          "sink_properties=device.description=RiflayBenchmark"], text=True).strip()
        metadata["audioSink"] = "Temporary PipeWire null sink; unmuted DSP"
        weston_log = output / "weston.log"
        compositor = subprocess.Popen(["weston", "--backend=headless", "--renderer=gl", "--no-config",
                                       "--width=1280", "--height=800", "--idle-time=0", "--socket=riflay-benchmark",
                                       f"--log={weston_log}"], env=compositor_env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if (runtime / "riflay-benchmark").exists():
                    break
                if compositor.poll() is not None:
                    raise RuntimeError(f"Weston failed; read {weston_log}")
                time.sleep(0.1)
            else:
                raise TimeoutError("Weston did not create its socket")
            time.sleep(1)
            metadata["compositorGlRenderer"] = re.findall(r"GL renderer: (.+)", weston_log.read_text())
            cases = [(mode, "native") for mode in args.modes]
            if "balanced" in args.modes:
                cases.insert(2, ("balanced", "texture"))
            for iteration in range(1, args.runs + 1):
                for mode, backend in cases if iteration % 2 else reversed(cases):
                    case = Path(tempfile.mkdtemp(prefix=f"{mode}-{backend}-{iteration}-", dir=temp))
                    seed(case, tracks, mode, args.video_decoder)
                    env = dict(compositor_env, WAYLAND_DISPLAY="riflay-benchmark", GDK_BACKEND="wayland",
                               XDG_DATA_HOME=str(case / "data"), XDG_CACHE_HOME=str(case / "cache"),
                               XDG_CONFIG_HOME=str(case / "config"), RIFLAY_BENCH_BACKEND=backend,
                               RIFLAY_BENCH_RUN=str(iteration), RIFLAY_BENCH_SAMPLE_SECONDS=str(args.sample_seconds),
                               RIFLAY_BENCH_SETTLE_SECONDS=str(args.settle_seconds),
                               RIFLAY_BENCH_AUDIO=str(audio), RIFLAY_BENCH_VIDEO=str(videos[mode]),
                               RIFLAY_BENCH_SINK=sink, PIPEWIRE_RUNTIME_DIR=audio_runtime,
                               PULSE_SERVER=os.environ.get("PULSE_SERVER", f"unix:{audio_runtime}/pulse/native"),
                               PULSE_SINK=sink, **({"RIFLAY_BENCH_STACKS": args.stacks} if args.stacks else {}))
                    env.pop("DISPLAY", None)
                    print(f"BENCH_RUN {iteration}/{args.runs} {mode} {backend}", flush=True)
                    path = output / f"{mode}-{backend}-{iteration}.log"
                    with path.open("w") as stream:
                        process = subprocess.Popen([str(source / f"build/linux/x64/{flavor}/bundle/riflay")],
                                                   env=env, stdout=stream, stderr=subprocess.STDOUT)
                        try:
                            process.wait(timeout=240)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                            raise
                    samples = [json.loads(line[6:]) for line in path.read_text().splitlines() if line.startswith("BENCH ")]
                    results.extend(samples)
                    report(output, results, metadata)
                    for sample in samples:
                        print(f"BENCH_RESULT {mode} {backend} run={iteration} {sample['phase']} "
                              f"cpu_total={sample['cpuTotalPercent']:.3f}% "
                              f"private={sample['memoryAfter']['privateMiB']:.1f}MiB "
                              f"pss={sample['memoryAfter']['pssMiB']:.1f}MiB "
                              f"rss={sample['memoryAfter']['rssMiB']:.1f}MiB", flush=True)
                    if process.returncode != 0 or len(samples) != 5:
                        raise RuntimeError(f"Incomplete measurement; read {path}")
                    validate_samples(samples)
        finally:
            compositor.terminate()
            compositor.wait(timeout=10)
            subprocess.run(["pactl", "unload-module", module], check=True)
        print(f"BENCH_DONE {output / 'report.md'}", flush=True)


if __name__ == "__main__":
    main()
