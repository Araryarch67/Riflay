"""Exercise a real .sflx through the same host Riflay bundles; never uses app credentials."""
import argparse
import concurrent.futures
import json
import pathlib
import shutil
import subprocess
import tempfile
import sys

sys.stdout.reconfigure(encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--provider", default="jiosaavn")
    parser.add_argument("--query", default="Daft Punk One More Time")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    log = (output / 'host.log').open('w', encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix="riflay-sflx-smoke-") as root:
        process = subprocess.Popen([str(pathlib.Path(args.host).resolve()), root],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=log, text=True, encoding="utf-8")
        reader = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        counter = 0

        def call(method, params, timeout=90):
            nonlocal counter
            counter += 1
            process.stdin.write(json.dumps({"id": counter, "method": method, "params": params}) + "\n")
            process.stdin.flush()
            line = reader.submit(process.stdout.readline).result(timeout=timeout)
            if not line:
                raise RuntimeError("Extension host exited")
            result = json.loads(line)
            if "error" in result:
                raise RuntimeError(result["error"])
            return result.get("result")

        try:
            installed = call("install", {"path": str(pathlib.Path(args.package).resolve())})
            print("Installed:", installed, flush=True)
            call("enable", {"extension": args.provider, "enabled": True})
            tracks = call("call", {"extension": args.provider, "operation": "search",
                                   "args": {"query": args.query, "limit": 10}})
            if isinstance(tracks, dict):
                tracks = tracks.get("tracks", [])
            tracks = [t for t in tracks if t.get("item_type", "track") == "track"]
            if not tracks:
                raise RuntimeError("Provider returned no songs")
            track = tracks[0]
            print("Track:", json.dumps(track, ensure_ascii=False), flush=True)
            ffmpeg = shutil.which("ffmpeg")
            if ffmpeg:
                call("ffmpegExecutable", {"path": ffmpeg})
            request = {"service": args.provider, "source": args.provider,
                       "spotify_id": str(track["id"]), "track_name": track.get("name", ""),
                       "artist_name": track.get("artists", ""), "album_name": track.get("album_name", ""),
                       "cover_url": track.get("images", track.get("cover_url", "")),
                       "duration_ms": track.get("duration_ms", 0), "isrc": track.get("isrc", ""),
                       "output_dir": str(output), "quality": "AAC_320", "embed_metadata": True,
                       "embed_lyrics": False, "filename_format": "{artist} - {title}",
                       "item_id": "riflay-spotiflac-smoke", "use_fallback": False}
            result = call("download", {"directory": str(output), "request": request}, timeout=600)
            print("Download:", json.dumps(result, ensure_ascii=False), flush=True)
            path = pathlib.Path(result.get("file_path", ""))
            if result.get("success") is not True or not path.is_file() or path.stat().st_size < 1024:
                raise RuntimeError("No valid audio file was produced")
            if ffmpeg:
                decoded = subprocess.run([ffmpeg, "-v", "error", "-i", str(path), "-f", "null", "-"],
                                         capture_output=True, text=True, timeout=120)
                if decoded.returncode != 0 or decoded.stderr.strip():
                    raise RuntimeError("Audio decoding failed: " + decoded.stderr[:400])
            print("VERIFIED:", str(path), "bytes:", path.stat().st_size, flush=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            reader.shutdown(wait=True)
            log.close()


if __name__ == "__main__":
    main()
