"""CLI safety checks; no Bluetooth or printing is needed."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import unittest

BINARY = os.environ.get('S1_TEST_BINARY', str(Path.home() / 'Applications/S1 Sticker.app/Contents/MacOS/S1Sticker'))

class KeepAwakeTests(unittest.TestCase):
    def invoke(self, *args):
        result = subprocess.run([BINARY, '--keep-awake', *args], capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 1)
        data = json.loads(result.stdout)
        self.assertFalse(data['ok'])
        self.assertFalse(data['sent'])
        return data

    def test_invalid_bounds_never_connect(self):
        for args in [('--duration', '0'), ('--duration', '86401'), ('--duration', 'bad'), ('--interval', '14'), ('--interval', '301')]:
            with self.subTest(args=args):
                self.assertIn('Use --duration', self.invoke(*args)['message'])

    def test_existing_session_rejected_before_connect(self):
        path = Path.home() / 'Library/Application Support/S1Sticker/keep-awake.lock'
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertIn('already running', self.invoke('--duration', '1')['message'])

if __name__ == '__main__':
    unittest.main()
