"""Exercise generation of full-source previews alongside actual monitor crops."""
import json
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('magick'), 'ImageMagick is required for generation checks')
class GenerationPreviewTests(unittest.TestCase):
    def test_both_modes_publish_preview_and_keep_original(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source = base / 'source.png'
            subprocess.run(['magick', '-size', '80x60', 'gradient:', str(source)], check=True)
            original = source.read_bytes()
            config = base / 'config.conf'
            import os
            env = dict(os.environ, XDG_CACHE_HOME=str(base / 'cache'))
            for mode in ['linked', 'quality']:
                with self.subTest(mode=mode):
                    output = base / mode
                    output.mkdir()
                    config.write_text(f'''OUTPUT_DIR="{output}"
MONITOR_1_ENABLED=true
MONITOR_1_OUTPUT=DP-1
MONITOR_1_WIDTH=12
MONITOR_1_HEIGHT=8
MONITOR_1_PHYSICAL_WIDTH_CM=3
MONITOR_1_PHYSICAL_HEIGHT_CM=2
MONITOR_1_X_CM=0
MONITOR_1_Y_CM=0
MONITOR_2_ENABLED=false
MONITOR_3_ENABLED=false
''')
                    result = subprocess.run(['bash', str(ROOT / 'src' / 'split-wallpaper.sh'), str(source),
                                             '--config', str(config), '--mode', mode], env=env,
                                            capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    manifest, = output.glob('*.hunu.json')
                    data = json.loads(manifest.read_text())
                    preview = output / data['preview']
                    self.assertTrue(preview.is_file())
                    self.assertEqual(preview.name, data['set'] + '.preview.jpg')
                    for image, size in [(preview, '80x60'), (output / data['monitors'][0]['file'], '12x8')]:
                        probe = subprocess.run(['magick', 'identify', '-format', '%wx%h', str(image)],
                                               capture_output=True, text=True, check=True)
                        self.assertEqual(probe.stdout, size)
                    self.assertEqual(source.read_bytes(), original)
                    self.assertFalse([p for p in output.glob('.hunu-generation.*') if p.is_dir()])
                    # A failure writing the preview must not publish partial new
                    # sets or remove an already completed set.
                    expected = {p.name: p.read_bytes() for p in output.iterdir() if p.is_file()}
                    tools = base / ('tools-' + mode)
                    tools.mkdir()
                    wrapper = tools / 'magick'
                    wrapper.write_text('#!/usr/bin/env bash\nfor arg; do\n'
                                       'case "$arg" in *.preview.jpg) exit 23 ;; esac\ndone\n'
                                       + 'exec ' + shlex.quote(shutil.which('magick')) + ' "$@"\n')
                    wrapper.chmod(0o755)
                    failure_env = dict(env, PATH=str(tools) + os.pathsep + os.environ['PATH'])
                    failed = subprocess.run(['bash', str(ROOT / 'src' / 'split-wallpaper.sh'), str(source),
                                             '--config', str(config), '--mode', mode], env=failure_env,
                                            capture_output=True, text=True, timeout=30)
                    self.assertNotEqual(failed.returncode, 0)
                    self.assertEqual({p.name: p.read_bytes() for p in output.iterdir() if p.is_file()}, expected)
                    self.assertFalse([p for p in output.glob('.hunu-generation.*') if p.is_dir()])


if __name__ == '__main__':
    unittest.main()
