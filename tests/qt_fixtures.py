"""Native Qt fixtures: use production controls/palette without external theme IPC."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
CONTROLS = ['HunuActionButton', 'HunuIcon', 'HunuText', 'HunuCheckBox', 'HunuToggle',
            'HunuComboBox', 'HunuScrollBar', 'HunuScrollView', 'HunuSlider', 'HunuSpinBox', 'HunuSegmented', 'HunuSettingsRow']


def prepare_controls(folder, io_module=None):
    folder = Path(folder)
    for name in CONTROLS:
        shutil.copy(ROOT / 'src' / (name + '.qml'), folder / (name + '.qml'))
    for name in ['PickerPreferences', 'PickerSettingsPanel', 'PickerSettingsWindow', 'PickerAlternatives']:
        target = folder / (name + '.qml')
        if not target.exists():
            contents = (ROOT / 'src' / (name + '.qml')).read_text()
            if io_module:
                contents = contents.replace('import Quickshell.Io', 'import ' + io_module)
            target.write_text(contents)
    theme = (ROOT / 'src' / 'Theme.qml').read_text()
    theme = theme.replace('import Quickshell\n', '').replace('import Quickshell.Io\n', '')
    theme = theme[:theme.index('    // Detect optional providers first.')] + '}\n'
    (folder / 'Theme.qml').write_text(theme)
    qmldir = folder / 'qmldir'
    current = qmldir.read_text() if qmldir.exists() else 'singleton Theme 1.0 Theme.qml\n'
    for name in CONTROLS + ['PickerPreferences', 'PickerSettingsPanel', 'PickerSettingsWindow', 'PickerAlternatives']:
        if name + ' 1.0' not in current:
            current += f'{name} 1.0 {name}.qml\n'
    qmldir.write_text(current)
