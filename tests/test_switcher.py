"""End-to-end controller checks using real set metadata/PNGs and mocked desktop IPC."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]


def png(path, width, height):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress((b'\0' + b'\0' * width * 3) * height)) + chunk(b'IEND', b''))


class SwitcherFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.app = self.base / 'hunu-test'
        shutil.copytree(ROOT / 'src', self.app)
        self.output = self.base / 'wallpapers'
        self.output.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.monitors = self.base / 'monitors.json'
        self.log = self.base / 'ipc.log'
        self.set_monitors(3)
        (self.app / 'config.conf').write_text(f'OUTPUT_DIR="{self.output}"\nAPPLY_BACKEND=noctalia\n' + '\n'.join(
            f'MONITOR_{i}_ENABLED=true\nMONITOR_{i}_OUTPUT=DP-{i}\n'
            f'MONITOR_{i}_PHYSICAL_WIDTH_CM=60\nMONITOR_{i}_PHYSICAL_HEIGHT_CM=34\n'
            f'MONITOR_{i}_X_CM={(i-1)*60}\nMONITOR_{i}_Y_CM=0' for i in range(1, 4)))
        for name, code in {
            'hyprctl': "import os; print(open(os.environ['TEST_MONITORS']).read())",
            'noctalia': "import json, os, sys\nwith open(os.environ['TEST_IPC'], 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\nsys.exit(int(os.environ.get('TEST_FAIL', '0')))"
        }.items():
            path = self.bin / name
            path.write_text('#!/usr/bin/env python3\n' + code + '\n')
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        XDG_CACHE_HOME=str(self.base / 'cache'),
                        TEST_MONITORS=str(self.monitors), TEST_IPC=str(self.log))
        self.env.pop('HUNU_APP_NAME', None)

    def set_monitors(self, count, rotated=False):
        self.monitors.write_text(json.dumps([dict(name=f'DP-{i}', width=12, height=8,
                                                   transform=1 if rotated and i == 1 else 0,
                                                   mirrorOf='none', focused=i == 2) for i in range(1, count + 1)]))

    def make_set(self, name, count=3, size=(12, 8)):
        records = []
        for i in range(1, count + 1):
            file = name + '_' + 'abc'[i-1] + '.png'
            png(self.output / file, *size)
            records.append(dict(slot=i, output=f'DP-{i}', file=file))
        (self.output / (name + '.hunu.json')).write_text(json.dumps(dict(
            version=1, set=name, monitors=records, source=name)))

    def run_controller(self, *args):
        return subprocess.run(['python3', str(self.app / 'switcher-controller.py'), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def listing(self):
        result = self.run_controller('list')
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []


class SwitcherTests(SwitcherFixture):
    def test_hides_two_monitor_sets_for_three_monitor_layout(self):
        self.make_set('two', 2)
        self.make_set('three')
        result = self.listing()
        self.assertEqual([s['name'] for s in result['sets']], ['three'])
        self.assertEqual(result['hidden'], 1)
        self.assertEqual(result['focusedOutput'], 'DP-2')
        self.assertFalse(self.log.exists(), 'Browsing must never apply wallpapers')

    def test_missing_image_wrong_dimensions_and_legacy_are_hidden(self):
        self.make_set('missing')
        (self.output / 'missing_c.png').unlink()
        self.make_set('resolution', size=(10, 8))
        png(self.output / 'legacy_a.png', 12, 8)
        self.assertEqual(self.listing()['sets'], [])

    def test_full_source_preview_and_old_set_fallback(self):
        self.make_set('new')
        manifest = self.output / 'new.hunu.json'
        data = json.loads(manifest.read_text())
        data['preview'] = 'new.preview.jpg'
        manifest.write_text(json.dumps(data))
        (self.output / 'new.preview.jpg').write_bytes(b'preview fixture')
        item, = self.listing()['sets']
        self.assertTrue(item['previewIsSource'])
        self.assertEqual(item['previewUrl'], (self.output / 'new.preview.jpg').as_uri())
        (self.output / 'new.preview.jpg').unlink()
        item, = self.listing()['sets']
        self.assertFalse(item['previewIsSource'])
        self.assertEqual(item['previewUrl'], item['fallbackPreviewUrl'])
        self.assertTrue(item['previewUrl'].endswith('_a.png'))
        # Untrusted or unrelated metadata paths never become preview URLs.
        data['preview'] = '../source.jpg'
        manifest.write_text(json.dumps(data))
        self.assertFalse(self.listing()['sets'][0]['previewIsSource'])

    def test_rotation_dimensions(self):
        self.make_set('landscape')
        self.make_set('portrait')
        png(self.output / 'portrait_a.png', 8, 12)
        self.set_monitors(3, rotated=True)
        self.assertEqual([s['name'] for s in self.listing()['sets']], ['portrait'])

    def test_layout_change_blocks_apply(self):
        self.make_set('three')
        self.assertEqual(len(self.listing()['sets']), 1)
        self.set_monitors(2)
        result = self.run_controller('apply', 'three')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Monitor Setup', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_apply_records_current_and_next_wraps(self):
        self.make_set('first')
        self.make_set('second')
        order = [s['name'] for s in self.listing()['sets']]
        result = self.run_controller('apply', order[0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.listing()['current'], order[0])
        for expected in [order[1], order[0]]:
            result = self.run_controller('next')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.listing()['current'], expected)
        self.assertEqual(len(self.calls()), 9)
        self.assertEqual(self.calls()[0][:2], ['msg', 'wallpaper-set'])

    def test_previous_wraps_and_shared_apply_lock_blocks_overlap(self):
        self.make_set('first')
        self.make_set('second')
        order = [s['name'] for s in self.listing()['sets']]
        result = self.run_controller('apply', order[0])
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_controller('previous')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.listing()['current'], order[-1])
        lock = self.base / 'cache' / 'hunu-test' / 'wallpaper-apply.lock'
        with lock.open('a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_controller('next')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Another wallpaper Apply', result.stderr)
        self.assertEqual(self.listing()['current'], order[-1])

    def test_failed_apply_preserves_selection(self):
        self.make_set('first')
        self.make_set('second')
        result = self.run_controller('apply', 'first')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.env['TEST_FAIL'] = '1'
        result = self.run_controller('apply', 'second')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.listing()['current'], 'first')

    def test_gui_apply_shares_current_selection(self):
        self.make_set('manual')
        pairs = [value for i in range(1, 4) for value in (f'DP-{i}', str(self.output / f'manual_{"abc"[i-1]}.png'))]
        result = subprocess.run(['bash', str(self.app / 'apply-wallpapers.sh'), '--backend', 'noctalia', *pairs],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.listing()['current'], 'manual')

    def test_hotplug_resolution_change_rechecks_before_apply(self):
        self.make_set('old')
        self.assertEqual(len(self.listing()['sets']), 1)
        monitors = json.loads(self.monitors.read_text())
        monitors[0]['width'] = 16
        self.monitors.write_text(json.dumps(monitors))
        result = self.run_controller('apply', 'old')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
