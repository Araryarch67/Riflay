#!/usr/bin/env python3
"""Download a GitHub release asset through its API, retaining checksum verification."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url')
    parser.add_argument('output', type=Path)
    parser.add_argument('--sha256')
    args = parser.parse_args()
    url = urlparse(args.url)
    parts = url.path.strip('/').split('/')
    if url.scheme != 'https' or url.hostname != 'github.com' or len(parts) != 6 or parts[2:4] != ['releases', 'download']:
        parser.error('expected an HTTPS GitHub release asset URL')
    repo = '/'.join(parts[:2])
    tag, asset = map(unquote, parts[4:])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Commit the file only after the whole download and its checksum succeed.
    handle, temporary = tempfile.mkstemp(prefix=args.output.name + '.', dir=args.output.parent)
    os.close(handle)
    try:
        commands = []
        if shutil.which('gh'):
            # gh resolves the release's asset ID and follows its API download redirect. This avoids the
            # /releases/download route, which can return 504 even while the asset API works.
            commands.append(['gh', 'release', 'download', tag, '--repo', repo, '--pattern', asset,
                             '--output', temporary, '--clobber'])
        commands.append(['curl', '--fail', '--location', '--retry', '3', '--retry-all-errors',
                         '--connect-timeout', '30', '--max-time', '300', '--output', temporary, args.url])
        for command in commands:
            result = subprocess.run(command, check=False)
            if result.returncode == 0:
                break
        else:
            raise SystemExit('Release asset download failed: ' + asset)
        if args.sha256:
            checksum = hashlib.sha256()
            with open(temporary, 'rb') as downloaded:
                for chunk in iter(lambda: downloaded.read(1024 * 1024), b''):
                    checksum.update(chunk)
            if checksum.hexdigest().lower() != args.sha256.lower():
                raise SystemExit('SHA-256 mismatch: ' + asset)
        os.replace(temporary, args.output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    main()
