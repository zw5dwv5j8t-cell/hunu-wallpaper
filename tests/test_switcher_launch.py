"""Verify repeated hotkeys forward IPC and installer preserves user configuration."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SwitcherLaunchTests(unittest.TestCase):
    def test_repeated_hotkey_forwards_to_existing_picker(self):
        with tempfile.TemporaryDirectory(prefix='hunu picker ') as temp:
            base = Path(temp)
            shutil.copy(ROOT / 'src' / 'switcher.sh', base / 'switcher.sh')
            shutil.copy(ROOT / 'src' / 'switcher-settings.py', base / 'switcher-settings.py')
            client = base / 'quickshell'
            client.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys, time
base = pathlib.Path(os.environ['TEST_BASE'])
if 'ipc' in sys.argv:
    with (base / 'calls').open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
else:
    assert sys.argv[1:3] == ['--no-duplicate', '-p']
    assert os.environ['QT_QPA_PLATFORMTHEME'] == ''
    assert os.environ['QT_QUICK_CONTROLS_STYLE'] == 'Basic'
    assert 'HUNU_SWITCHER_SOCKET' not in os.environ
    (base / 'started').touch()
    while not (base / 'stop').exists(): time.sleep(0.02)
''')
            client.chmod(0o755)
            env = dict(os.environ, PATH=f'{base}:{os.environ["PATH"]}',
                       XDG_RUNTIME_DIR=str(base / 'runtime'), TEST_BASE=str(base),
                       HUNU_SWITCHER_SOCKET='/tmp/stale-picker.sock', HUNU_SWITCHER_PARALLEL='0')
            first = subprocess.Popen(['bash', str(base / 'switcher.sh')], env=env)
            try:
                deadline = time.monotonic() + 5
                while not (base / 'started').exists():
                    self.assertIsNone(first.poll())
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.02)
                second = subprocess.run(['bash', str(base / 'switcher.sh')], env=env,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertEqual(json.loads((base / 'calls').read_text()),
                                 ['-p', str(base / 'Switcher.qml'), 'ipc', 'call', 'picker', 'next'])
                self.assertIsNone(first.poll())
            finally:
                (base / 'stop').touch()
                self.assertEqual(first.wait(timeout=5), 0)

    def test_installer_includes_switcher_and_preserves_monitor_config(self):
        with tempfile.TemporaryDirectory(prefix='hunu install ') as temp:
            base = Path(temp)
            bin_dir = base / 'bin'
            bin_dir.mkdir()
            # Installer wiring test only: these stubs satisfy availability checks.
            for name in ['hyprctl', 'quickshell']:
                stub = bin_dir / name
                stub.write_text('#!/usr/bin/env bash\nexit 0\n')
                stub.chmod(0o755)
            env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}', HUNU_APP_NAME='hunu-picker-test',
                       XDG_CONFIG_HOME=str(base / 'config'), XDG_DATA_HOME=str(base / 'data'),
                       XDG_STATE_HOME=str(base / 'state'))
            install = base / 'config' / 'hunu-picker-test'
            install.mkdir(parents=True)
            (install / 'config.conf').write_text('APPLY_BACKEND=noctalia\n# Keep my setup\n')
            preferences = '{"enabled":false,"position":"bottom","livePreview":false,"delayMs":750}'
            (install / 'switcher-settings.json').write_text(preferences)
            for _ in range(2):
                result = subprocess.run(['bash', str(ROOT / 'install.sh')], cwd=ROOT, env=env,
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((install / 'config.conf').read_text(), 'APPLY_BACKEND=noctalia\n# Keep my setup\n')
                self.assertEqual((install / 'switcher-settings.json').read_text(), preferences)
            from qt_fixtures import CONTROLS
            for name in ['Switcher.qml', 'switcher.sh', 'switcher-controller.py', 'switcher-settings.py', 'list-wallpaper-sets.py', 'SavedSetPreview.qml'] + [name + '.qml' for name in CONTROLS]:
                self.assertEqual((install / name).read_bytes(), (ROOT / 'src' / name).read_bytes())
            self.assertTrue(os.access(install / 'switcher.sh', os.X_OK))


if __name__ == '__main__':
    unittest.main()
