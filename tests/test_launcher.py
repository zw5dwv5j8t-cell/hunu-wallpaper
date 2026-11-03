"""Exercise launcher locking with concurrent launches and process exit."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def test_duplicate_exit_release_and_separate_install(self):
        with tempfile.TemporaryDirectory(prefix='hunu launcher ') as temp:
            base = Path(temp)
            bin_dir = base / 'bin'
            bin_dir.mkdir()
            client = bin_dir / 'quickshell'
            client.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, time
assert sys.argv[1:3] == ['--no-duplicate', '-p'], sys.argv
config = pathlib.Path(sys.argv[3])
(config / 'started').touch()
while not (config / 'stop').exists():
    time.sleep(0.02)
''')
            client.chmod(0o755)
            installs = [base / 'normal install', base / 'test install']
            for install in installs:
                install.mkdir()
                shutil.copy2(ROOT / 'src' / 'launch.sh', install / 'launch.sh')
            env = dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}',
                       XDG_RUNTIME_DIR=str(base / 'runtime'))
            processes = []
            try:
                for install in installs:
                    process = subprocess.Popen(['bash', str(install / 'launch.sh')], env=env)
                    processes.append(process)
                    deadline = time.monotonic() + 5
                    while not (install / 'started').exists():
                        self.assertIsNone(process.poll())
                        self.assertLess(time.monotonic(), deadline, 'launcher did not start')
                        time.sleep(0.02)
                    duplicate = subprocess.run(['bash', str(install / 'launch.sh')],
                                               env=env, capture_output=True, text=True, timeout=5)
                    self.assertEqual(duplicate.returncode, 0, duplicate.stderr)
                    self.assertIn('already running', duplicate.stdout)
                # A second installation can run concurrently with the first.
                self.assertTrue(all(p.poll() is None for p in processes))
                for install, process in zip(installs, processes):
                    (install / 'stop').touch()
                    self.assertEqual(process.wait(timeout=5), 0)
                    # Lock is released after exit and the installation can reopen.
                    result = subprocess.run(['bash', str(install / 'launch.sh')],
                                            env=env, capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn('already running', result.stdout)
            finally:
                for install in installs:
                    (install / 'stop').touch()
                for process in processes:
                    process.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
