"""Test preview transactions against a stateful mock of native Noctalia."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import time
import hashlib

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
        catalog = self.receive(process)
        self.assertEqual(catalog['event'], 'catalog')
        ready = self.receive(process)
        self.assertEqual(ready['event'], 'ready')
        return process, ready

    def receive(self, process):
        readable, _, _ = select.select([process.stdout], [], [], 10)
        self.assertTrue(readable, 'Preview session did not respond')
        line = b''
        while not line.endswith(b'\n'):
            chunk = os.read(process.stdout.fileno(), 1)
            if not chunk:
                break
            line += chunk
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
    def test_thumbnail_warmup_reused_and_invalidated_without_changing_originals(self):
        preview = self.output / 'first.preview.jpg'
        subprocess.run(['magick', '-size', '1600x900', 'gradient:blue-red', str(preview)], check=True)
        manifest = self.output / 'first.hunu.json'
        metadata = json.loads(manifest.read_text())
        metadata['preview'] = preview.name
        manifest.write_text(json.dumps(metadata))
        original_hash = hashlib.sha256(preview.read_bytes()).hexdigest()
        process, ready = self.start_session()
        first = next(item for item in ready['sets'] if item['name'] == 'first')
        self.assertEqual(first['previewUrl'], preview.as_uri(), 'First use must not wait for thumbnail generation')
        folder = self.base / 'cache' / 'hunu-test' / 'switcher-thumbnails'
        self.assertFalse(folder.exists(), 'Conversion must wait until the picker has appeared')
        process.stdin.write('{"action":"warm-cache"}\n')
        process.stdin.flush()
        deadline = time.monotonic() + 5
        while not list(folder.glob('*.jpg')) and time.monotonic() < deadline:
            time.sleep(0.02)
        thumbnails = list(folder.glob('*.jpg'))
        self.assertEqual(len(thumbnails), 1)
        thumbnail = thumbnails[0]
        width, height = map(int, subprocess.check_output(['magick', 'identify', '-format', '%w %h', str(thumbnail)], text=True).split())
        self.assertLessEqual(width, 1000)
        self.assertLessEqual(height, 700)
        self.assertEqual(hashlib.sha256(preview.read_bytes()).hexdigest(), original_hash)
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        process.wait(timeout=3)
        process, ready = self.start_session()
        first = next(item for item in ready['sets'] if item['name'] == 'first')
        self.assertEqual(first['previewUrl'], thumbnail.as_uri())
        self.assertEqual(first['previewSize'], [1600, 900], 'Keep original aspect ratio when resizing')
        self.send(process, 'cancel')
        process.wait(timeout=3)
        subprocess.run(['magick', '-size', '1800x900', 'xc:green', str(preview)], check=True)
        process, ready = self.start_session()
        first = next(item for item in ready['sets'] if item['name'] == 'first')
        self.assertEqual(first['previewUrl'], preview.as_uri(), 'Changed source must not reuse stale pixels')
        self.send(process, 'cancel')

    def test_large_monitor_crop_thumbnail_never_replaces_applied_wallpaper(self):
        self.make_set('large-crop', size=(1600, 900))
        monitors = json.loads(self.monitors.read_text())
        for monitor in monitors:
            monitor.update(width=1600, height=900)
        self.monitors.write_text(json.dumps(monitors))
        original_paths = [self.output / f'large-crop_{suffix}.png' for suffix in 'abc']
        original_hashes = [hashlib.sha256(path.read_bytes()).hexdigest() for path in original_paths]
        process, ready = self.start_session()
        self.assertEqual(len(ready['sets']), 1)
        self.assertFalse(ready['sets'][0]['previewIsSource'])
        process.stdin.write('{"action":"warm-cache"}\n')
        process.stdin.flush()
        folder = self.base / 'cache' / 'hunu-test' / 'switcher-thumbnails'
        deadline = time.monotonic() + 5
        while not list(folder.glob('*.jpg')) and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertEqual(len(list(folder.glob('*.jpg'))), 1)
        self.send(process, 'cancel')
        process.wait(timeout=3)
        process, ready = self.start_session()
        self.assertIn('switcher-thumbnails', ready['sets'][0]['previewUrl'])
        self.assertEqual(self.send(process, 'commit', 'large-crop')['event'], 'committed')
        process.wait(timeout=3)
        self.assertEqual(self.current(), {f'DP-{i + 1}': str(path) for i, path in enumerate(original_paths)})
        self.assertEqual([hashlib.sha256(path.read_bytes()).hexdigest() for path in original_paths], original_hashes)


    def test_closing_picker_stops_active_thumbnail_conversion(self):
        preview = self.output / 'first.preview.jpg'
        subprocess.run(['magick', '-size', '1600x900', 'xc:blue', str(preview)], check=True)
        manifest = self.output / 'first.hunu.json'
        metadata = json.loads(manifest.read_text())
        metadata['preview'] = preview.name
        manifest.write_text(json.dumps(metadata))
        marker = self.base / 'thumbnail-worker.pid'
        self.env['TEST_THUMB_PID'] = str(marker)
        converter = self.bin / 'magick'
        converter.write_text("""#!/usr/bin/env python3
import os, pathlib, time
pathlib.Path(os.environ['TEST_THUMB_PID']).write_text(str(os.getpid()))
time.sleep(30)
""")
        converter.chmod(0o755)
        process, _ = self.start_session()
        process.stdin.write('{"action":"warm-cache"}\n')
        process.stdin.flush()
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(marker.exists())
        pid = int(marker.read_text())
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        process.wait(timeout=3)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        folder = self.base / 'cache' / 'hunu-test' / 'switcher-thumbnails'
        self.assertEqual(list(folder.iterdir()), [], 'Cancelled jobs must clean up partial files')
        self.assertEqual(self.current(), self.original)


    def test_catalog_arrives_before_parallel_snapshot_finishes(self):
        mock = self.bin / 'noctalia'
        mock.write_text(mock.read_text().replace("    print(state.get(args[2], ''))", """    import time
    gate = pathlib.Path(os.environ['TEST_CURRENT'] + '.' + args[2])
    gate.touch()
    deadline = time.monotonic() + 4
    while not all(pathlib.Path(os.environ['TEST_CURRENT'] + '.' + output).exists()
                  for output in ('DP-1', 'DP-2', 'DP-3')):
        if time.monotonic() > deadline: sys.exit(1)
        time.sleep(0.01)
    print(state.get(args[2], ''))"""))
        process, ready = self.start_session()
        self.assertTrue(ready['liveEnabled'], ready['liveReason'])
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')


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
