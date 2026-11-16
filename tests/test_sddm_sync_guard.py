"""Real detached workers with isolated cache and a fake external sync script."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / 'src/sddm-sync-guard.py'


class SddmSyncGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.cache = self.base / 'cache' / 'hunu-wallpaper'
        self.cache.mkdir(parents=True)
        self.log = self.base / 'calls'
        self.delay = self.base / 'delay'
        self.delay.write_text('0.1')
        self.script = self.base / 'sync script'
        self.script.write_text('''#!/usr/bin/env python3
import json, os, pathlib, time
base = pathlib.Path(os.environ['TEST_BASE'])
def record(event):
    with (base / 'calls').open('a') as stream:
        stream.write(json.dumps(dict(event=event, pid=os.getpid(), connector=os.environ.get('NOCTALIA_WALLPAPER_CONNECTOR'), threads=os.environ.get('MAGICK_THREAD_LIMIT'))) + '\\n')
record('start')
time.sleep(float((base / 'delay').read_text()))
record('end')
''')
        self.script.chmod(0o755)
        self.env = dict(os.environ, XDG_CACHE_HOME=str(self.base / 'cache'),
                        HUNU_APP_NAME='hunu-wallpaper', TEST_BASE=str(self.base),
                        NOCTALIA_WALLPAPER_CONNECTOR='HDMI-A-1')
        self.lock = (self.cache / 'wallpaper-apply.lock').open('a')

    def tearDown(self):
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.lock.close()
        self.delay.write_text('0.01')
        self.wait(self.idle, timeout=8)
        self.temp.cleanup()

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def wait(self, check, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(0.03)
        self.fail(f'Timed out; calls={self.calls()}')

    def idle(self):
        path = self.cache / 'sddm-sync' / 'worker.lock'
        with path.open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return True
            except BlockingIOError:
                return False

    def trigger(self):
        result = subprocess.run(['python3', str(GUARD), '--script', str(self.script)],
                                env=self.env, capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fast_hooks_wait_for_picker_then_run_once_and_exit(self):
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        for _ in range(15):
            self.trigger()
        time.sleep(0.5)
        self.assertEqual(self.calls(), [])
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.wait(self.idle)
        self.assertEqual([row['event'] for row in self.calls()], ['start', 'end'])
        self.assertIsNone(self.calls()[0]['connector'])
        self.assertEqual(self.calls()[0]['threads'], '1')
        # A subsequent invocation must start another short-lived worker.
        self.trigger()
        self.wait(self.idle)
        self.assertEqual(len(self.calls()), 4)

    def test_new_request_cancels_stale_sync_and_runs_latest(self):
        self.delay.write_text('1.5')
        self.trigger()
        self.wait(lambda: len(self.calls()) == 1)
        first = self.calls()[0]['pid']
        self.delay.write_text('0.1')
        for _ in range(5):
            self.trigger()
        self.wait(self.idle)
        calls = self.calls()
        self.assertEqual([row['event'] for row in calls], ['start', 'start', 'end'])
        self.assertNotEqual(calls[1]['pid'], first)
        self.assertEqual(calls[1]['pid'], calls[2]['pid'])

    def test_reopening_picker_cancels_sync_without_blocking_picker(self):
        self.delay.write_text('1.5')
        self.trigger()
        self.wait(lambda: len(self.calls()) == 1)
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        time.sleep(0.3)
        self.assertEqual(len(self.calls()), 1)
        self.delay.write_text('0.1')
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.wait(self.idle)
        self.assertEqual([row['event'] for row in self.calls()], ['start', 'start', 'end'])

    def test_cancels_sync_script_and_its_image_worker(self):
        child_file = self.base / 'child.pid'
        self.script.write_text('#!/bin/sh\nsleep 20 &\necho $! > "$TEST_BASE/child.pid"\nwait\n')
        self.trigger()
        self.wait(child_file.exists)
        child = int(child_file.read_text())
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        def stopped():
            stat = Path(f'/proc/{child}/stat')
            return not stat.exists() or stat.read_text().split(') ')[1].startswith('Z')
        self.wait(stopped)
        self.script.write_text('#!/bin/sh\nexit 0\n')
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.wait(self.idle)

    def test_failing_script_logs_failure_and_worker_exits(self):
        self.script.write_text('#!/bin/sh\necho sync-failed >&2\nexit 7\n')
        self.trigger()
        self.wait(self.idle)
        log = (self.cache / 'sddm-sync' / 'sync.log').read_text()
        self.assertIn('sync-failed', log)
        self.assertIn('status 7', log)
