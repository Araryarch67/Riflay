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
samples, threads_at = [], {}
while app.poll() is None:
    try:
        f = open(f'/proc/{app.pid}/stat').read().rsplit(')', 1)[1].split()
        samples.append((time.monotonic() - start, int(f[11]) + int(f[12])))
        if (len(samples) - 1) % round(args.interval / 0.1) == 0:
            threads_at[len(samples) - 1] = by_thread()
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
worst = max((share(samples[j], samples[j + step]), samples[j][0]) for j in range(len(samples) - step))
print(f'worst {args.interval:g} s window: {worst[0]:.2f}% from {worst[1]:.1f} s')
