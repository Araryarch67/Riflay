"""Build the shared SpotiFLAC runtime using the target platform's toolchain."""
import argparse, os, pathlib, shutil, subprocess
root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--target', choices=['android', 'ios', 'desktop'], required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
out = pathlib.Path(args.output).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
go = os.environ.get('RIFLAY_GO_EXECUTABLE') or shutil.which('go')
if not go: raise SystemExit('Go 1.25 or newer is required to build SpotiFLAC.')
env = os.environ.copy()
env['GOTOOLCHAIN'] = 'local'
module = root / 'tool/spotiflac_bridge'
def run(command): subprocess.run(command, cwd=module, env=env, check=True)
if args.target == 'desktop':
    env['CGO_ENABLED'] = '0'
    run([go, 'build', '-mod=readonly', '-trimpath', '-ldflags=-s -w', '-o', str(out), '.'])
else:
    tools = root / 'build/spotiflac-tools'
    tools.mkdir(parents=True, exist_ok=True)
    suffix = '.exe' if os.name == 'nt' else ''
    for tool in ['gomobile', 'gobind']:
        run([go, 'build', '-mod=readonly', '-o', str(tools / (tool + suffix)), 'golang.org/x/mobile/cmd/' + tool])
    env['PATH'] = str(tools) + os.pathsep + str(pathlib.Path(go).parent) + os.pathsep + env['PATH']
    env['CGO_ENABLED'] = '1'
    command = [str(tools / ('gomobile' + suffix)), 'bind', '-target=' + args.target, '-o', str(out)]
    command += ['-androidapi=24'] if args.target == 'android' else ['-iosversion=15.0']
    run(command + ['./bridge'])
