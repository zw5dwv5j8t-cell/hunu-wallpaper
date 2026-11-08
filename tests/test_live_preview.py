"""Test preview transactions against a stateful mock of native Noctalia."""
import json
from pathlib import Path
import select
import signal
import subprocess

from test_switcher import SwitcherFixture, png


class LivePreviewFixture(SwitcherFixture):
    def setUp(self):
        super().setUp()
        self.actual = self.base / 'current.json'
        self.original = {}
        for i in range(1, 4):
            path = self.base / f'outside-hunu-{i}.png'
            png(path, 12, 8)
            self.original[f'DP-{i}'] = str(path)
        self.actual.write_text(json.dumps(self.original))
        self.env['TEST_CURRENT'] = str(self.actual)
        (self.bin / 'noctalia').write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args=sys.argv[1:]
with open(os.environ['TEST_IPC'], 'a') as f: f.write(json.dumps(args)+'\\n')
path=pathlib.Path(os.environ['TEST_CURRENT'])
state=json.loads(path.read_text())
if args[1]=='wallpaper-get':
    print(state.get(args[2], ''))
elif args[1]=='wallpaper-set':
    marker=path.with_suffix('.failed-once')
    if os.environ.get('TEST_FAIL_OUTPUT')==args[2] and not marker.exists():
        marker.touch()
        print('simulated output failure', file=sys.stderr)
        sys.exit(1)
    state[args[2]]=args[3]
    path.write_text(json.dumps(state))
''')
        self.make_set('first')
        self.make_set('second')

    def start_session(self):
        process = subprocess.Popen(['python3', str(self.app / 'switcher-controller.py'), 'session'],
                                   env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        def cleanup():
            if not process.stdin.closed:
                process.stdin.close()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()
        self.addCleanup(cleanup)
        ready = self.receive(process)
        self.assertEqual(ready['event'], 'ready')
        return process, ready

    def receive(self, process):
        readable, _, _ = select.select([process.stdout], [], [], 10)
        self.assertTrue(readable, 'Preview session did not respond')
        line = process.stdout.readline()
        self.assertTrue(line, 'Preview session ended before responding')
        return json.loads(line)

    def send(self, process, action, name=''):
        process.stdin.write(json.dumps(dict(action=action, name=name)) + '\n')
        process.stdin.flush()
        return self.receive(process)

    def current(self):
        return json.loads(self.actual.read_text())

    def memory(self):
        path = self.base / 'cache' / 'hunu-test' / 'last-applied.json'
        return path.read_bytes() if path.exists() else None


class LivePreviewTests(LivePreviewFixture):
    def test_cancel_restores_external_wallpapers_and_does_not_save_preview(self):
        pairs = [value for i in range(1, 4) for value in (f'DP-{i}', str(self.output / f'first_{"abc"[i-1]}.png'))]
        self.assertEqual(self.run_controller('record', *pairs).returncode, 0)
        remembered_before = self.memory()
        process, ready = self.start_session()
        self.assertTrue(ready['liveEnabled'])
        self.assertEqual(self.current(), self.original, 'Opening must not change wallpapers')
        self.assertEqual(self.send(process, 'preview', 'first')['event'], 'previewed')
        self.assertNotEqual(self.current(), self.original)
        self.assertEqual(self.memory(), remembered_before)
        self.assertEqual(self.send(process, 'preview', 'second')['event'], 'previewed')
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.memory(), remembered_before)

    def test_commit_keeps_and_remembers_selection(self):
        process, _ = self.start_session()
        self.send(process, 'preview', 'first')
        self.assertEqual(self.send(process, 'commit', 'second')['event'], 'committed')
        self.assertEqual(process.wait(timeout=5), 0)
        remembered = json.loads(self.memory())
        self.assertEqual(remembered, self.current())
        self.assertTrue(all(Path(p).name.startswith('second_') for p in remembered.values()))

    def test_gui_disconnect_restores_preview(self):
        process, _ = self.start_session()
        self.send(process, 'preview', 'first')
        process.stdin.close()
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(self.current(), self.original)
        self.assertIsNone(self.memory())

    def test_termination_restores_preview(self):
        process, _ = self.start_session()
        self.send(process, 'preview', 'first')
        process.send_signal(signal.SIGTERM)
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(self.current(), self.original)

    def test_partial_failure_rolls_back_and_session_can_retry(self):
        self.env['TEST_FAIL_OUTPUT'] = 'DP-2'
        process, _ = self.start_session()
        result = self.send(process, 'preview', 'first')
        self.assertEqual(result['event'], 'error')
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'preview', 'second')['event'], 'previewed')
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(self.current(), self.original)

    def test_unreadable_original_disables_live_preview_but_allows_confirmation(self):
        Path(self.original['DP-1']).unlink()
        process, ready = self.start_session()
        self.assertFalse(ready['liveEnabled'])
        self.assertEqual(self.send(process, 'preview', 'first')['event'], 'error')
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'commit', 'first')['event'], 'committed')
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(json.loads(self.memory()), self.current())

    def test_targeted_revalidation_rejects_missing_crop_and_changed_metadata(self):
        process, _ = self.start_session()
        (self.output / 'first_a.png').unlink()
        self.assertEqual(self.send(process, 'preview', 'first')['event'], 'error')
        manifest = self.output / 'second.hunu.json'
        data = json.loads(manifest.read_text())
        data['monitors'][0]['output'] = 'DISCONNECTED'
        manifest.write_text(json.dumps(data))
        self.assertEqual(self.send(process, 'preview', 'second')['event'], 'error')
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        self.assertEqual(process.wait(timeout=5), 0)

    def test_preview_lock_blocks_other_apply_and_layout_is_rechecked(self):
        process, _ = self.start_session()
        other = self.run_controller('apply', 'first')
        self.assertNotEqual(other.returncode, 0)
        self.assertEqual(self.current(), self.original)
        self.set_monitors(2)
        self.assertEqual(self.send(process, 'preview', 'first')['event'], 'error')
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        self.assertEqual(process.wait(timeout=5), 0)
