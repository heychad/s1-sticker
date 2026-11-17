"""Exercise the bridge's printer routing and duplicate protection without hardware."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        with patch.dict(os.environ, {'HOME': cls.temp.name}):
            spec = importlib.util.spec_from_file_location('isolated_bridge', ROOT / 'bridge.py')
            cls.bridge = importlib.util.module_from_spec(spec); spec.loader.exec_module(cls.bridge)
        cls.calls = Path(cls.temp.name) / 'calls'
        cls.fake = Path(cls.temp.name) / 'fake-printer'
        cls.fake.write_text('#!/bin/sh\nprintf "run\\n" >> "$VRETTI_TEST_CALLS"\nprintf \'{"ok":true,"sent":true,"message":"sent"}\'\n')
        cls.fake.chmod(0o755)
        cls.bridge.BINARY = cls.fake; cls.bridge.VRETTI = cls.fake
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), cls.bridge.Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.temp.cleanup()

    def request(self, route, body, job):
        request = Request(f'http://127.0.0.1:{self.server.server_port}{route}', data=body, method='POST',
                          headers={'Authorization': 'Bearer ' + self.bridge.config['token'], 'X-Print-Id': job})
        with patch.dict(os.environ, {'VRETTI_TEST_CALLS': str(self.calls)}):
            with urlopen(request, timeout=5) as response: return json.load(response)

    def test_vretti_text_and_duplicate_send_once(self):
        body = json.dumps({'text': 'one label'}).encode()
        first = self.request('/print-text?printer=vretti', body, 'test-vretti-000001')
        again = self.request('/print-text?printer=vretti', body, 'test-vretti-000001')
        self.assertEqual(first, again)
        self.assertTrue(first['sent'])
        self.assertEqual(self.calls.read_text().splitlines(), ['run'])

    def test_unreadable_result_preserves_uncertainty(self):
        with patch.object(self.bridge.subprocess, 'run', return_value=__import__('subprocess').CompletedProcess([], 1, stdout='invalid')):
            result = self.request('/print-text?printer=vretti', json.dumps({'text': 'another label'}).encode(), 'test-vretti-000002')
        self.assertFalse(result['ok']); self.assertIsNone(result['sent'])


if __name__ == '__main__': unittest.main()
