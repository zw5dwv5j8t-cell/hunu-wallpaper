"""Backend contract tests; no desktop session is required."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NoctaliaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.log = self.path / 'calls.jsonl'
        client = self.path / 'quickshell'
        client.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['IPC_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if 'show' in sys.argv:
    print(os.environ.get('IPC_SHOW', 'target wallpaper\\n  function set(path: string, screen: string): void'))
sys.exit(int(os.environ.get('IPC_EXIT', '0')))
''')
        client.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.path}:{os.environ["PATH"]}',
                        IPC_LOG=str(self.log), XDG_CACHE_HOME=str(self.path / "cache"))
        self.image = self.path / 'wall paper, special.png'
        self.image.touch()

    def run_script(self, name, *args):
        return subprocess.run(['bash', str(ROOT / 'src' / name), *map(str, args)],
                              env=self.env, text=True, capture_output=True,
                              cwd=self.path)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_ready(self):
        result = self.run_script('check-apply-backend.sh', 'noctalia')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('BACKEND_READY=true', result.stdout)
        self.assertEqual(self.calls(), [['-c', 'noctalia-shell', 'ipc', 'show']])

    def test_unavailable_and_missing_endpoint(self):
        for settings in ({'IPC_EXIT': '1'}, {'IPC_SHOW': 'target other\n  function set()'},
                         {'IPC_SHOW': 'target wallpaper\n  function setOther()'}):
            with self.subTest(settings=settings):
                self.env.pop('IPC_EXIT', None)
                self.env.pop('IPC_SHOW', None)
                self.env.update(settings)
                result = self.run_script('check-apply-backend.sh', 'noctalia')
                self.assertEqual(result.returncode, 0)
                self.assertIn('BACKEND_READY=false', result.stdout)

    def test_apply_multiple_outputs_and_relative_path(self):
        result = self.run_script('apply-wallpapers.sh', '--backend', 'noctalia',
                                 'DP-1', self.image.name, 'HDMI-A-1', self.image)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            ['-c', 'noctalia-shell', 'ipc', 'call', 'wallpaper', 'set', str(self.image), output]
            for output in ['DP-1', 'HDMI-A-1']])

    def test_validate_all_images_before_applying(self):
        result = self.run_script('apply-wallpapers.sh', '--backend', 'noctalia',
                                 'DP-1', self.image, 'DP-2', self.path / 'missing.png')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_apply_failure_stops_remaining_outputs(self):
        self.env['IPC_EXIT'] = '1'
        result = self.run_script('apply-wallpapers.sh', '--backend', 'noctalia',
                                 'DP-1', self.image, 'DP-2', self.image)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Noctalia Apply failed for DP-1', result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_save_and_load_backend(self):
        config = self.path / 'config.conf'
        config.write_text('APPLY_BACKEND=awww\nMONITOR_1_OUTPUT=DP-1\n')
        result = self.run_script('save-apply-backend.sh', config, 'noctalia')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_script('load-monitor-config.sh', config)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('APPLY_BACKEND=noctalia', result.stdout)
        self.assertIn('MONITOR_1_OUTPUT=DP-1', config.read_text())


class NativeNoctaliaTests(NoctaliaTests):
    def setUp(self):
        super().setUp()
        # Both clients exist: the native executable must take precedence.
        (self.path / 'noctalia').write_bytes((self.path / 'quickshell').read_bytes())
        (self.path / 'noctalia').chmod(0o755)

    def test_ready(self):
        result = self.run_script('check-apply-backend.sh', 'noctalia')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('BACKEND_READY=true', result.stdout)
        self.assertEqual(self.calls(), [['msg', 'wallpaper-get']])

    def test_unavailable_and_missing_endpoint(self):
        self.env['IPC_EXIT'] = '1'
        result = self.run_script('check-apply-backend.sh', 'noctalia')
        self.assertEqual(result.returncode, 0)
        self.assertIn('BACKEND_READY=false', result.stdout)
        self.assertEqual(self.calls(), [['msg', 'wallpaper-get']])

    def test_apply_multiple_outputs_and_relative_path(self):
        result = self.run_script('apply-wallpapers.sh', '--backend', 'noctalia',
                                 'DP-1', self.image.name, 'HDMI-A-1', self.image)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            ['msg', 'wallpaper-set', output, str(self.image)]
            for output in ['DP-1', 'HDMI-A-1']])


if __name__ == '__main__':
    unittest.main()
