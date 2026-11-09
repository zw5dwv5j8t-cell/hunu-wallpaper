"""Native settings parity and the same lifecycle checks through the Rust bridge."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import test_parallel_startup as parallel

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'native/target/release/hunu-switcher-native'


@unittest.skipUnless(BINARY.is_file(), 'Build the Rust startup helper first')
class NativeParallelStartupTests(parallel.ParallelStartupTests):
    def setUp(self):
        super().setUp()
        shutil.copy2(BINARY, self.app / 'hunu-switcher-native')


@unittest.skipUnless(BINARY.is_file(), 'Build the Rust startup helper first')
class NativeSettingsTests(unittest.TestCase):
    def test_preferences_match_python_validation(self):
        cases = [None, {}, {'enabled': False}, {'enabled': True, 'position': 'top', 'delayMs': 100},
                 {'enabled': 1}, {'livePreview': 'false'}, {'showActionButtons': None},
                 {'position': 'left'}, {'delayMs': 400.0}, {'delayMs': True},
                 {'delayMs': 99}, {'delayMs': 1501}, [], None, 'invalid-json']
        with tempfile.TemporaryDirectory(prefix='native settings ') as folder:
            app = Path(folder)
            shutil.copy2(ROOT / 'src/switcher-settings.py', app)
            for value in cases:
                with self.subTest(value=value):
                    settings = app / 'switcher-settings.json'
                    if value is None:
                        settings.unlink(missing_ok=True)
                    else:
                        settings.write_text(value if value == 'invalid-json' else json.dumps(value))
                    native = subprocess.run([str(BINARY), 'enabled', str(app)], capture_output=True, text=True)
                    python = subprocess.run(['python3', str(app / 'switcher-settings.py'), 'enabled'], capture_output=True, text=True)
                    self.assertEqual(native.returncode, python.returncode)
                    self.assertEqual(native.stdout, python.stdout)
