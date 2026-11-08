"""Preferences persistence, validation, launch gating, and live-preview settings."""
import json
import subprocess
import test_live_preview as preview_fixture
from test_switcher import SwitcherFixture


class SwitcherSettingsTests(SwitcherFixture):
    def settings(self, action, values=None):
        args = ['python3', str(self.app / 'switcher-settings.py'), action]
        if values is not None:
            args.append(json.dumps(values))
        return subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=5)

    def test_defaults_save_reload_and_validation_preserve_previous_file(self):
        result = self.settings('get')
        self.assertEqual(json.loads(result.stdout), dict(enabled=True, position='center', livePreview=True, delayMs=400, showActionButtons=True))
        for position in ['top', 'center', 'bottom']:
            values = dict(enabled=False, position=position, livePreview=False, delayMs=750, showActionButtons=False)
            self.assertEqual(self.settings('save', values).returncode, 0)
            self.assertEqual(json.loads(self.settings('get').stdout), values)
        before = (self.app / 'switcher-settings.json').read_bytes()
        for invalid in [{'position': 'left'}, {'enabled': 'false'}, {'delayMs': 0}, {'delayMs': True}, {'livePreview': 1}, {'showActionButtons': 'false'}, []]:
            with self.subTest(invalid=invalid):
                self.assertNotEqual(self.settings('save', invalid).returncode, 0)
                self.assertEqual((self.app / 'switcher-settings.json').read_bytes(), before)
        self.assertFalse(list(self.app.glob('.switcher-settings-*')))

    def test_disabled_hotkey_and_direct_actions_do_not_apply(self):
        self.make_set('first')
        self.assertEqual(self.settings('save', dict(enabled=False)).returncode, 0)
        for action in ['show', 'next', 'previous']:
            result = subprocess.run(['bash', str(self.app / 'switcher.sh'), action], env=self.env,
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
        for action in ['apply', 'next', 'session']:
            result = self.run_controller(action, *(['first'] if action == 'apply' else []))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('disabled', result.stderr)
        self.assertFalse(self.log.exists())
        # Disabling the picker does not disable ordinary GUI Apply/state tracking.
        pairs = ['DP-1', str(self.output / 'first_a.png')]
        self.assertEqual(self.run_controller('record', *pairs).returncode, 0)

    def test_bad_settings_are_reported_without_launching(self):
        (self.app / 'switcher-settings.json').write_text('{broken')
        result = subprocess.run(['bash', str(self.app / 'switcher.sh')], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ERROR', result.stderr)
        self.assertFalse(self.log.exists())


class PreviewPreferenceTests(preview_fixture.LivePreviewFixture):
    def test_live_preview_can_be_disabled_and_preferences_reach_picker(self):
        values = dict(enabled=True, position='bottom', livePreview=False, delayMs=900, showActionButtons=False)
        (self.app / 'switcher-settings.json').write_text(json.dumps(values))
        process, ready = self.start_session()
        self.assertEqual(ready['switcherSettings'], values)
        self.assertFalse(ready['liveEnabled'])
        self.assertFalse(self.log.exists(), 'Disabled live preview must not query or change backend wallpapers')
        self.assertEqual(self.send(process, 'preview', 'first')['event'], 'error')
        self.assertEqual(self.current(), self.original)
        self.assertEqual(self.send(process, 'commit', 'first')['event'], 'committed')
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(json.loads(self.memory()), self.current())
