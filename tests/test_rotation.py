"""Timer configuration is isolated; rotation applies real fixtures to mocked IPC."""
import json
import subprocess
import shutil

from test_switcher import SwitcherFixture
from test_live_preview import LivePreviewFixture


class RotationSettingsTests(SwitcherFixture):
    def setUp(self):
        super().setUp()
        self.env['XDG_CONFIG_HOME'] = str(self.base / 'xdg')
        self.env['TEST_SYSTEMCTL_LOG'] = str(self.base / 'systemctl.jsonl')
        self.env['WAYLAND_DISPLAY'] = 'wayland-test'
        mock = self.bin / 'systemctl'
        mock.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args=sys.argv[1:]
with open(os.environ['TEST_SYSTEMCTL_LOG'], 'a') as stream: stream.write(json.dumps(args)+'\\n')
if os.environ.get('TEST_SYSTEMD_DOWN') or os.environ.get('TEST_SYSTEMD_FAIL') == args[1]:
    print('test user session unavailable', file=sys.stderr)
    sys.exit(1)
''')
        mock.chmod(0o755)

    def rotation(self, action, values=None):
        args = ['python3', str(self.app / 'rotation-settings.py'), action]
        if values is not None:
            args.append(json.dumps(values))
        return subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=10)

    def calls(self):
        path = self.base / 'systemctl.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_disabled_defaults_no_units_and_validation(self):
        values = json.loads(self.rotation('get').stdout)
        self.assertFalse(values['enabled'])
        self.assertEqual(values['intervalMinutes'], 15)
        self.assertTrue(values['avoidRepeat'])
        self.assertTrue(values['available'])
        self.assertEqual(self.rotation('save', dict(intervalMinutes=30)).returncode, 0)
        units = self.base / 'xdg/systemd/user'
        self.assertFalse(units.exists())
        before = (self.app / 'rotation-settings.json').read_bytes()
        for bad in ({'enabled': 1}, {'intervalMinutes': True}, {'intervalMinutes': 0}, {'intervalMinutes': 1441}, {'intervalMinutes': 2.5}, {'avoidRepeat': 'yes'}, []):
            with self.subTest(values=bad):
                self.assertNotEqual(self.rotation('save', bad).returncode, 0)
                self.assertEqual((self.app / 'rotation-settings.json').read_bytes(), before)

    def test_enable_interval_update_and_disable(self):
        result = self.rotation('save', dict(enabled=True, intervalMinutes=7, avoidRepeat=False))
        self.assertEqual(result.returncode, 0, result.stderr)
        units = self.base / 'xdg/systemd/user'
        timer, = units.glob('*.timer')
        service, = units.glob('*.service')
        self.assertIn('OnActiveSec=7min', timer.read_text())
        self.assertIn('OnUnitInactiveSec=7min', timer.read_text())
        self.assertIn('Type=oneshot', service.read_text())
        self.assertIn('"' + str(self.app / 'switcher-controller.py') + '" rotate', service.read_text())
        self.assertNotIn('quickshell', service.read_text())
        self.assertIn(['--user', 'import-environment', 'WAYLAND_DISPLAY'], self.calls())
        self.assertIn(['--user', 'enable', '--now', timer.name], self.calls())
        self.assertEqual(self.rotation('save', dict(enabled=True, intervalMinutes=21)).returncode, 0)
        self.assertIn('OnActiveSec=21min', timer.read_text())
        self.assertEqual(self.rotation('disable').returncode, 0)
        self.assertFalse(timer.exists())
        self.assertFalse(service.exists())
        self.assertFalse(json.loads(self.rotation('get').stdout)['enabled'])
        self.assertIn(['--user', 'disable', '--now', timer.name], self.calls())

    def test_session_refresh_failure_keeps_saved_enabled_state_visible(self):
        (self.app / 'rotation-settings.json').write_text('{"enabled":true,"intervalMinutes":7}')
        self.env['TEST_SYSTEMD_FAIL'] = 'import-environment'
        result = self.rotation('get')
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)
        self.assertTrue(values['enabled'])
        self.assertEqual(values['intervalMinutes'], 7)
        self.assertFalse(values['available'])

    def test_timer_paths_with_spaces_and_specifier_characters_are_quoted(self):
        nested = self.base / 'space % $ folder' / 'hunu-test'
        shutil.copytree(self.app, nested)
        self.app = nested
        result = self.rotation('save', dict(enabled=True))
        self.assertEqual(result.returncode, 0, result.stderr)
        folder = self.base / 'xdg/systemd/user'
        service, = folder.glob('*.service')
        self.assertIn('space %% $$ folder', service.read_text())
        if shutil.which('systemd-analyze'):
            checked = subprocess.run(['systemd-analyze', 'verify', *map(str, folder.iterdir())],
                                     capture_output=True, text=True, timeout=10)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_unavailable_session_and_failed_activation_do_not_save_enable(self):
        self.env['TEST_SYSTEMD_DOWN'] = '1'
        result = self.rotation('save', dict(enabled=True))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('systemd user session', result.stderr)
        self.assertFalse((self.app / 'rotation-settings.json').exists())
        self.env.pop('TEST_SYSTEMD_DOWN')
        self.env['TEST_SYSTEMD_FAIL'] = 'enable'
        result = self.rotation('save', dict(enabled=True))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.app / 'rotation-settings.json').exists())
        self.assertFalse(list((self.base / 'xdg/systemd/user').glob('*.timer')))

    def test_failed_update_restores_previous_interval_and_refuses_unrelated_units(self):
        self.assertEqual(self.rotation('save', dict(enabled=True, intervalMinutes=7)).returncode, 0)
        timer, = (self.base / 'xdg/systemd/user').glob('*.timer')
        before = timer.read_bytes()
        self.env['TEST_SYSTEMD_FAIL'] = 'restart'
        self.assertNotEqual(self.rotation('save', dict(enabled=True, intervalMinutes=9)).returncode, 0)
        self.assertEqual(timer.read_bytes(), before)
        self.assertEqual(json.loads(self.rotation('get').stdout)['intervalMinutes'], 7)
        self.env.pop('TEST_SYSTEMD_FAIL')
        timer.write_text('# unrelated user file\n')
        self.assertNotEqual(self.rotation('save', dict(enabled=True)).returncode, 0)
        self.assertEqual(timer.read_text(), '# unrelated user file\n')


class RotationTransactionTests(LivePreviewFixture):
    def enable_rotation(self):
        (self.app / 'rotation-settings.json').write_text('{"enabled":true,"intervalMinutes":1,"avoidRepeat":true}')

    def test_random_choices_avoid_repeats_and_incompatible_sets(self):
        self.enable_rotation()
        self.make_set('two-monitors', count=2)
        previous = self.current()
        for _ in range(3):
            result = self.run_controller('rotate')
            self.assertEqual(result.returncode, 0, result.stderr)
            current = self.current()
            self.assertNotEqual(current, previous)
            self.assertTrue(all('two-monitors' not in path for path in current.values()))
            self.assertEqual(json.loads(self.memory()), current)
            previous = current

    def test_disabled_rotation_does_nothing_and_picker_disable_is_independent(self):
        self.assertEqual(self.run_controller('rotate').returncode, 0)
        self.assertEqual(self.current(), self.original)
        self.assertFalse(self.log.exists())
        self.enable_rotation()
        (self.app / 'switcher-settings.json').write_text('{"enabled":false}')
        result = self.run_controller('rotate')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.current(), self.original)

    def test_single_compatible_set_applies_after_external_change_then_skips_repeat(self):
        self.enable_rotation()
        self.make_set('second', count=2)
        pairs = [value for i in range(1, 4) for value in (f'DP-{i}', str(self.output / f'first_{"abc"[i-1]}.png'))]
        self.assertEqual(self.run_controller('record', *pairs).returncode, 0)
        self.assertEqual(self.current(), self.original, 'Recorded state may differ from externally changed wallpapers')
        self.assertEqual(self.run_controller('rotate').returncode, 0)
        self.assertNotEqual(self.current(), self.original)
        before = [item for item in self.calls() if item[1] == 'wallpaper-set']
        self.assertEqual(len(before), 3)
        self.assertEqual(self.run_controller('rotate').returncode, 0)
        after = [item for item in self.calls() if item[1] == 'wallpaper-set']
        self.assertEqual(before, after, 'A sole already-applied candidate should not be reapplied')

    def test_rotation_skips_while_picker_owns_transaction(self):
        self.enable_rotation()
        process, _ = self.start_session()
        before = self.log.read_bytes()
        self.assertEqual(self.run_controller('rotate').returncode, 0)
        self.assertEqual(self.log.read_bytes(), before)
        self.assertEqual(self.current(), self.original)
        self.send(process, 'cancel')

    def test_partial_apply_failure_restores_snapshot_without_recording(self):
        self.enable_rotation()
        self.env['TEST_FAIL_OUTPUT'] = 'DP-2'
        result = self.run_controller('rotate')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.current(), self.original)
        self.assertIsNone(self.memory())
