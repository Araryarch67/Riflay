#!/usr/bin/env python3
"""Runs a command and reads its CPU from outside the way btop does: utime + stime of the process from /proc, as a
share of all the processor's threads (btop's proc_per_core = false), every 2 s (its update_ms) and in 100 ms steps.
Lines the app prints that start with "MV " or "CPU " are shown with their time, to see which step a sample belongs to.

  tool/btop_watch.py [--prefs JSON] [--interval 2] -- build/linux/x64/release/bundle/riflay

--prefs seeds a throwaway data folder's shared preferences (keys as SharedPreferences stores them, "flutter.…").
"""
import argparse, json, os, pathlib, subprocess, tempfile, threading, time

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--prefs', default='{}')
parser.add_argument('--interval', type=float, default=2.0)
parser.add_argument('--threads', type=float, default=0.5,
                    help='for samples above this %%, the threads behind them (thread CPU in ms)')
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command

data = pathlib.Path(tempfile.mkdtemp(prefix='btop-watch.'))
(data / 'dev.riflay.riflay').mkdir()
(data / 'dev.riflay.riflay' / 'shared_preferences.json').write_text(args.prefs)
env = dict(os.environ, XDG_DATA_HOME=str(data))
start = time.monotonic()
app = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
marks = []
threading.Thread(target=lambda: [marks.append((time.monotonic() - start, l.strip()))
                                 for l in app.stdout if l.startswith(('MV ', 'CPU '))], daemon=True).start()
hz, threads = os.sysconf('SC_CLK_TCK'), os.cpu_count()
def by_thread():
    out = {}
    for tid in os.listdir(f'/proc/{app.pid}/task'):
        try:
            st = open(f'/proc/{app.pid}/task/{tid}/stat').read()
        except OSError:
            continue
        name = 'main' if tid == str(app.pid) else st[st.index('(') + 1:st.rindex(')')]
        f = st.rsplit(')', 1)[1].split()
        out[name] = out.get(name, 0) + int(f[11]) + int(f[12])
    return out
def memory():
    """Private (Private_Clean + Private_Dirty) and RSS in MiB, from smaps_rollup."""
    kb = {}
    for line in open(f'/proc/{app.pid}/smaps_rollup'):
        k, _, v = line.partition(':')
        if k in ('Rss', 'Private_Clean', 'Private_Dirty'):
            kb[k] = int(v.split()[0])
    return ((kb.get('Private_Clean', 0) + kb.get('Private_Dirty', 0)) / 1024, kb.get('Rss', 0) / 1024)
samples, threads_at, memory_at = [], {}, {}
while app.poll() is None:
    try:
        f = open(f'/proc/{app.pid}/stat').read().rsplit(')', 1)[1].split()
        samples.append((time.monotonic() - start, int(f[11]) + int(f[12])))
        if (len(samples) - 1) % round(args.interval / 0.1) == 0:
            threads_at[len(samples) - 1] = by_thread()
            memory_at[len(samples) - 1] = memory()
    except OSError:
        break
    time.sleep(0.1)

def share(a, b):
    return (b[1] - a[1]) / hz / (b[0] - a[0]) / threads * 100

step = max(1, round(args.interval / 0.1))
print(f'{threads} threads; each sample is the % of all of them, as btop shows a process')
for t, line in marks:
    print(f'{t:6.1f} s  {line[:140]}')
print(f'every {args.interval:g} s:')
for i in range(0, len(samples) - step, step):
    a, b = samples[i], samples[i + step]
    print(f'  {a[0]:5.1f} s  {share(a, b):5.2f}%  ' + '#' * round(share(a, b) * 20))
    if share(a, b) >= args.threads and i in threads_at and i + step in threads_at:
        d = {k: v - threads_at[i].get(k, 0) for k, v in threads_at[i + step].items()}
        top = sorted(((v, k) for k, v in d.items() if v > 0), reverse=True)[:7]
        print('           ' + ', '.join(f'{k} {v * 1000 // hz} ms' for v, k in top))
# Each step from one "MV at" line to the next: the average over it, skipping its first 3 s (the step's own start),
# and its peak (the worst 2 s btop sample, start included).
steps = [(t, line) for t, line in marks if line.startswith('MV at')]
if len(steps) > 1:
    print('average of each step (after its first 3 s):')
    for (t0, l0), (t1, _) in zip(steps, steps[1:]):
        inside = [i for i, s in enumerate(samples) if t0 + 3 <= s[0] <= t1]
        if len(inside) > 1:
            a, b = samples[inside[0]], samples[inside[-1]]
            mem = [memory_at[i] for i in inside if i in memory_at]
            ram = (f'  private {sum(m[0] for m in mem) / len(mem):4.0f} (max {max(m[0] for m in mem):4.0f}) MiB, '
                   f'RSS {sum(m[1] for m in mem) / len(mem):4.0f} (max {max(m[1] for m in mem):4.0f})') if mem else ''
            # The step's worst btop sample, its start included: targets are for peaks, not the average.
            whole = [i for i, x in enumerate(samples) if t0 <= x[0] < t1]
            peak = max((share(samples[j], samples[j + step]), samples[j][0]) for j in whole if j + step < len(samples))
            print(f'  {share(a, b):5.2f}% avg, peak {peak[0]:4.2f}% at {peak[1]:5.1f} s  {l0.split(": ", 1)[-1][:50]}{ram}')
            marks_in = [i for i in inside if i in threads_at]
            if len(marks_in) > 1:
                d = {k: v - threads_at[marks_in[0]].get(k, 0) for k, v in threads_at[marks_in[-1]].items()}
                secs = samples[marks_in[-1]][0] - samples[marks_in[0]][0]
                top = sorted(((v, k) for k, v in d.items() if v > 0), reverse=True)[:7]
                print('          ' + ', '.join(f'{k} {v / hz / secs * 100:.1f}%' for v, k in top) + ' of one core')
worst = max((share(samples[j], samples[j + step]), samples[j][0]) for j in range(len(samples) - step))
print(f'worst {args.interval:g} s window: {worst[0]:.2f}% from {worst[1]:.1f} s')
