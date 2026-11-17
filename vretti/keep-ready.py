#!/usr/bin/env python3
"""Manage the experimental Vretti Keep Ready login helper on macOS."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from uuid import UUID

home = Path.home()
root = Path(__file__).resolve().parent.parent
label = 'local.chad.VrettiKeepReady'
domain = f'gui/{os.getuid()}'
plist = home / 'Library/LaunchAgents' / (label + '.plist')
app = home / 'Applications/Vretti Keep Ready.app'
logdir = home / 'Library/Logs/VrettiKeepReady'


def loaded():
    return subprocess.run(['launchctl', 'print', f'{domain}/{label}'], capture_output=True).returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['status', 'install', 'uninstall'])
    parser.add_argument('--id', help='CoreBluetooth peripheral UUID for install')
    args = parser.parse_args()
    if args.action == 'status':
        result = subprocess.run(['launchctl', 'print', f'{domain}/{label}'], capture_output=True, text=True)
        print('Vretti Keep Ready:', 'running' if 'state = running' in result.stdout else 'not running')
        log = logdir / 'keep-ready.log'
        if log.exists(): print('\n'.join(log.read_text(errors='replace').splitlines()[-10:]))
        return
    if args.action == 'uninstall':
        if loaded(): subprocess.run(['launchctl', 'bootout', f'{domain}/{label}'], check=True)
        plist.unlink(missing_ok=True)
        print('Vretti login helper removed. The app and logs remain.')
        return
    if not args.id:
        parser.error('install requires --id with the printer peripheral UUID')
    try: identifier = str(UUID(args.id))
    except ValueError: parser.error('invalid peripheral UUID')
    if plist.exists() or loaded():
        parser.error('existing Vretti login helper found; uninstall it first')
    if app.exists():
        try:
            with (app / 'Contents/Info.plist').open('rb') as stream: installed = plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException):
            parser.error('existing app is not a recognized Vretti helper; left it unchanged')
        if installed.get('CFBundleIdentifier') != label:
            parser.error('existing app is not a recognized Vretti helper; left it unchanged')
    subprocess.run(['zsh', str(root / 'vretti/build.sh')], check=True)
    app.parent.mkdir(parents=True, exist_ok=True)
    logdir.mkdir(parents=True, exist_ok=True)
    plist.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['ditto', str(root / '.build-vretti/VrettiKeepReady.app'), str(app)], check=True)
    config = {'Label': label, 'ProgramArguments': [str(app / 'Contents/MacOS/VrettiKeepReady'), identifier, '86400'],
              'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 60,
              'StandardOutPath': str(logdir / 'keep-ready.log'),
              'StandardErrorPath': str(logdir / 'error.log')}
    with plist.open('wb') as stream: plistlib.dump(config, stream)
    subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
    print('Vretti Keep Ready installed and started.')


if __name__ == '__main__':
    try: main()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f'Vretti Keep Ready: {error}', file=sys.stderr)
        sys.exit(1)
