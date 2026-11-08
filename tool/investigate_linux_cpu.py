#!/usr/bin/env python3
"""Controlled full-app CPU experiments; no production source is changed.

Requires the same packages as benchmark_linux_video.py. Optional --compat-lib
points to matching NVIDIA libraries extracted into a temporary directory.
"""
import argparse
import difflib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, default=Path('/tmp/riflay-cpu-profile-work'))
    parser.add_argument('--output', type=Path, default=ROOT / 'build/perf/cpu-investigation-2026-11-08')
    parser.add_argument('--compat-lib', type=Path)
    parser.add_argument('--perf', type=Path)
    parser.add_argument('--perf-lib', type=Path)
    args = parser.parse_args()
    work, output = args.work_dir.resolve(), args.output.resolve()
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('bench', ROOT / 'tool/benchmark_linux_video.py')
    bench = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bench)
    source = work / 'source'
    source.mkdir(exist_ok=True)
    names = ['lib', 'assets', 'linux', 'tool', 'third_party', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml', 'AGENT.md']
    subprocess.run(['rsync', '-a', '--exclude=ephemeral', *[str(ROOT / n) for n in names], str(source)], check=True)
    mainfile = source / 'lib/main.dart'
    original = mainfile.read_text()
    target = '  runApp(RiflayApp(controller: controller));'
    assert original.count(target) == 1
    replacement = '''  final profilingUiEnabled = ValueNotifier(true);
  bench_dev.registerExtension('ext.riflay.profile.ui', (method, params) async {
    profilingUiEnabled.value = params['enabled'] == 'true';
    return bench_dev.ServiceExtensionResponse.result('{}');
  });
  runApp(ValueListenableBuilder<bool>(
    valueListenable: profilingUiEnabled,
    builder: (_, enabled, child) => TickerMode(enabled: enabled, child: child!),
    child: RiflayApp(controller: controller),
  ));'''
    modified = "import 'dart:developer' as bench_dev;\n" + original.replace(target, replacement)
    mainfile.write_text(modified)
    (output / 'instrumentation.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True), modified.splitlines(True), fromfile='lib/main.dart', tofile='copied/lib/main.dart')))
    print('INVESTIGATE preparing the isolated profile app and fixtures', flush=True)
    tracks, audio, videos = bench.fixtures(work / 'fixtures', output / 'fixtures.log')
    bench.run(['flutter', 'pub', 'get', '--offline'], output / 'build.log', cwd=source, timeout=180)
    bench.run(['flutter', 'build', 'linux', '--profile', '--no-pub', '-t', 'tool/cpu_investigation_app.dart'], output / 'build.log', cwd=source, timeout=600)
    runtime = work / 'runtime'
    runtime.mkdir(mode=0o700, exist_ok=True)
    data = work / f'data-{int(time.time())}'
    bench.seed(data, tracks, 'balanced')
    sink = f'riflay_benchmark_profile_{os.getpid()}'
    module = subprocess.check_output(['pactl', 'load-module', 'module-null-sink', f'sink_name={sink}', 'sink_properties=device.description=RiflayCpuProfile'], text=True).strip()
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY='riflay-profile', GDK_BACKEND='wayland',
               XDG_DATA_HOME=str(data / 'data'), XDG_CONFIG_HOME=str(data / 'config'), XDG_CACHE_HOME=str(data / 'cache'),
               PIPEWIRE_RUNTIME_DIR=os.environ['XDG_RUNTIME_DIR'], PULSE_SERVER=f"unix:{os.environ['XDG_RUNTIME_DIR']}/pulse/native",
               RIFLAY_BENCH_SINK=sink, RIFLAY_PROFILE_MEDIA=str(videos['balanced']), RIFLAY_PROFILE_OUTPUT=str(output))
    env.pop('DISPLAY', None)
    if args.compat_lib:
        env['LD_LIBRARY_PATH'] = str(args.compat_lib.resolve())
    compositor = subprocess.Popen(['weston', '--backend=headless', '--renderer=gl', '--no-config', '--width=1280', '--height=800',
                                   '--idle-time=0', '--socket=riflay-profile', f'--log={output / "weston.log"}'],
                                  env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    native_profiles = []
    samples = []
    try:
        for _ in range(100):
            if (runtime / 'riflay-profile').exists():
                break
            if compositor.poll() is not None:
                raise RuntimeError('Headless compositor failed')
            time.sleep(.1)
        process = subprocess.Popen(['dbus-run-session', '--', str(source / 'build/linux/x64/profile/bundle/riflay')],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        with (output / 'app.log').open('w') as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if line.startswith('PROFILE_READY '):
                    ready = json.loads(line[len('PROFILE_READY '):])
                    print('INVESTIGATE_READY', ready, flush=True)
                    if ready['profile'] and args.perf:
                        path = output / f"native-{ready['case']}.data"
                        perfenv = dict(os.environ)
                        if args.perf_lib:
                            perfenv['LD_LIBRARY_PATH'] = str(args.perf_lib.resolve())
                        stream = (output / f"native-{ready['case']}-record.log").open('w')
                        recorder = subprocess.Popen([str(args.perf), 'record', '-e', 'cpu-clock:u', '-F', '199',
                                                      '--call-graph', 'dwarf,8192', '-p', str(ready['pid']),
                                                      '-o', str(path), '--', 'sleep', '12'],
                                                     env=perfenv, stdout=stream, stderr=subprocess.STDOUT)
                        native_profiles.append((recorder, stream, path, perfenv))
                if line.startswith('PROFILE_RESULT '):
                    result = json.loads(line[len('PROFILE_RESULT '):])
                    samples.append(result)
                    (output / 'results.json').write_text(json.dumps(samples, indent=2))
                    print(f"INVESTIGATE_RESULT {result['case']} run={result['run']} profiled={result['profile']} "
                          f"cpu={result['cpuTotalPercent']:.3f}% frames={result['reportedFrameTimingsPerSecond']:.1f}/s "
                          f"top={result['threads'][:3]}", flush=True)
        process.wait(timeout=10)
        if process.returncode or len(samples) != 20:
            raise RuntimeError(f'Incomplete investigation ({len(samples)} samples); see app.log')
        for recorder, stream, path, perfenv in native_profiles:
            recorder.wait(timeout=15)
            stream.close()
            if recorder.returncode == 0:
                bench.run([str(args.perf), 'report', '--stdio', '--no-children', '--percent-limit', '0.5',
                           '--sort', 'comm,dso,symbol', '-i', str(path)], path.with_suffix('.txt'), env=perfenv)
        rows = []
        for name in sorted({s['case'] for s in samples if not s['profile']}):
            current = [s for s in samples if s['case'] == name and not s['profile']]
            rows.append({'case': name, 'cpuTotalPercentMedian': statistics.median(s['cpuTotalPercent'] for s in current),
                         'framesPerSecondMedian': statistics.median(s['reportedFrameTimingsPerSecond'] for s in current),
                         'runs': len(current)})
        (output / 'summary.json').write_text(json.dumps(rows, indent=2))
        print('INVESTIGATE_DONE', output, flush=True)
    finally:
        compositor.terminate()
        compositor.wait(timeout=10)
        subprocess.run(['pactl', 'unload-module', module], check=True)


if __name__ == '__main__':
    main()
