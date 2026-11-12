#!/usr/bin/env python3
"""Manage the optional Mac S1 Keep Ready login helper."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys

HOME = Path.home()
LABEL = 'local.chad.S1KeepReady'
PLIST = HOME / 'Library/LaunchAgents' / (LABEL + '.plist')
LOGS = HOME / 'Library/Logs/S1Sticker'
BINARY = HOME / 'Applications/S1 Sticker.app/Contents/MacOS/S1Sticker'
DOMAIN = f'gui/{os.getuid()}'


def launchctl(*args, check=True, capture=False):
    return subprocess.run(['launchctl', *args], check=check, text=True,
                          capture_output=capture)


def main():
    parser = argparse.ArgumentParser(description='Manage S1 Keep Ready.')
    parser.add_argument('action', choices=['status', 'install', 'uninstall'])
    args = parser.parse_args()
    if args.action == 'status':
        result = launchctl('print', f'{DOMAIN}/{LABEL}', check=False, capture=True)
        print('S1 Keep Ready:', 'running' if 'state = running' in result.stdout else 'not running')
        print('Login helper:', 'installed' if PLIST.exists() else 'not installed')
        log = LOGS / 'keep-ready.log'
        if log.exists():
            print('\nRecent activity:')
            print('\n'.join(log.read_text(errors='replace').splitlines()[-8:]))
        return
    if args.action == 'uninstall':
        if launchctl('print', f'{DOMAIN}/{LABEL}', check=False, capture=True).returncode == 0:
            launchctl('bootout', f'{DOMAIN}/{LABEL}')
        PLIST.unlink(missing_ok=True)
        print('S1 Keep Ready removed. S1 Sticker and its settings remain installed.')
        return
    if not BINARY.is_file():
        parser.error('Install the S1 Sticker Mac app first.')
    LOGS.mkdir(parents=True, exist_ok=True)
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    if launchctl('print', f'{DOMAIN}/{LABEL}', check=False, capture=True).returncode == 0:
        print('S1 Keep Ready is already installed and loaded.')
        return
    config = {'Label': LABEL, 'ProgramArguments': [str(BINARY), '--keep-awake',
              '--duration', '86400', '--interval', '60'], 'RunAtLoad': True,
              'KeepAlive': True, 'ThrottleInterval': 60,
              'StandardOutPath': str(LOGS / 'keep-ready.log'),
              'StandardErrorPath': str(LOGS / 'keep-ready-error.log')}
    with PLIST.open('wb') as stream:
        plistlib.dump(config, stream)
    launchctl('bootstrap', DOMAIN, str(PLIST))
    print('S1 Keep Ready installed and started.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f'S1 Keep Ready: {error}', file=sys.stderr)
        sys.exit(1)
