"""Exercise real parallel launcher/controller/transport with a delayed Qt stand-in."""
import json
import os
import signal
import subprocess
import time
from pathlib import Path

from test_live_preview import LivePreviewFixture


class ParallelStartupTests(LivePreviewFixture):
    def setUp(self):
        super().setUp()
        self.env.pop('HUNU_SWITCHER_PARALLEL', None)
        self.env['HUNU_SWITCHER_TRACE'] = '1'
        self.env['XDG_RUNTIME_DIR'] = str(self.base / 'runtime')
        self.env['TEST_APP'] = str(self.app)
        self.env['TEST_LAUNCH'] = str(self.base / 'qt-started')
        quickshell = self.bin / 'quickshell'
        quickshell.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, time
pathlib.Path(os.environ['TEST_LAUNCH']).write_text(str(os.getpid()))
time.sleep(30 if os.environ.get('TEST_QT_HOLD') else 0.2)
pathlib.Path(os.environ['TEST_LAUNCH'] + '.connected').write_text(str(time.time() * 1000 - int(os.environ['HUNU_SWITCHER_STARTED_MS'])))
if os.environ.get('TEST_QT_FAIL'):
    sys.exit(7)
os.execv(sys.executable, [sys.executable, os.environ['TEST_APP'] + '/switcher-transport.py', os.environ['HUNU_SWITCHER_SOCKET']])
''')
        quickshell.chmod(0o755)

    def session_command(self):
        return ['bash', str(self.app / 'switcher.sh')]

    def children(self, process):
        self.launch_events = []
        while True:
            line = process.stderr.readline()
            self.assertTrue(line, 'Missing controller startup trace')
            if line.startswith('HUNU_SWITCHER '):
                event = json.loads(line.removeprefix('HUNU_SWITCHER '))
                self.launch_events.append(event)
                if event['stage'] == 'controller-started':
                    return [event['pid'], int(Path(self.env['TEST_LAUNCH']).read_text())]

    def assert_gone(self, pids):
        for pid in pids:
            with self.assertRaises(ProcessLookupError, msg=f'Child {pid} remained running'):
                os.kill(pid, 0)
        self.assertEqual(list((self.base / 'runtime').glob('hunu-picker.*')), [])

    def test_prepares_results_before_qt_connects_then_cancel_cleans_up(self):
        process, ready = self.start_session()
        children = self.children(process)
        self.assertEqual(len(children), 2)
        self.assertTrue(ready['liveEnabled'])
        self.assertEqual(self.send(process, 'preview', 'first')['event'], 'previewed')
        self.assertEqual(self.send(process, 'cancel')['event'], 'cancelled')
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(self.current(), self.original)
        events = self.launch_events + [json.loads(line.removeprefix('HUNU_SWITCHER ')) for line in process.stderr.read().splitlines()
                  if line.startswith('HUNU_SWITCHER ')]
        snapshot = next(event for event in events if event['stage'] == 'snapshot')
        connected_at = float(Path(self.env['TEST_LAUNCH'] + '.connected').read_text())
        self.assertLess(snapshot['launchElapsedMs'], connected_at, 'Prepare while the Qt stand-in is still loading')
        self.assert_gone(children)

    def test_commit_cleans_up_both_children_and_remembers_original_files(self):
        process, _ = self.start_session()
        children = self.children(process)
        self.assertEqual(self.send(process, 'commit', 'second')['event'], 'committed')
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(json.loads(self.memory()), self.current())
        self.assert_gone(children)

    def test_transport_disconnect_restores_and_stops_controller(self):
        process, _ = self.start_session()
        children = self.children(process)
        self.send(process, 'preview', 'first')
        process.stdin.close()
        process.wait(timeout=5)
        self.assertEqual(self.current(), self.original)
        self.assert_gone(children)

    def test_launcher_termination_restores_and_stops_children(self):
        process, _ = self.start_session()
        children = self.children(process)
        self.send(process, 'preview', 'first')
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=5)
        self.assertEqual(self.current(), self.original)
        self.assert_gone(children)

    def test_interrupting_startup_stops_controller_before_client_connects(self):
        self.env['TEST_QT_HOLD'] = '1'
        process = subprocess.Popen(self.session_command(), env=self.env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while not Path(self.env['TEST_LAUNCH']).exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(Path(self.env['TEST_LAUNCH']).exists())
        children = self.children(process)
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=5)
        self.assertEqual(self.current(), self.original)
        self.assert_gone(children)


    def test_qt_failure_before_connect_stops_waiting_controller(self):
        self.env['TEST_QT_FAIL'] = '1'
        result = subprocess.run(self.session_command(), env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(self.current(), self.original)
        self.assertEqual(list((self.base / 'runtime').glob('hunu-picker.*')), [])
