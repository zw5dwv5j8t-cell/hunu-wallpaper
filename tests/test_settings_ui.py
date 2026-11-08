"""Optional Qt check of the actual main-app Settings dialog with IPC substituted."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Optional PySide6 Qt harness is not installed')
class SettingsInteractionTests(unittest.TestCase):
    def test_switcher_settings_load_controls_and_save_payload(self):
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        os.environ.setdefault('QT_QUICK_BACKEND', 'software')
        from PySide6.QtCore import QObject, Property, Signal, QUrl, Qt, QPointF
        from PySide6.QtGui import QGuiApplication
        from PySide6.QtQuick import QQuickWindow
        from PySide6.QtQml import QQmlApplicationEngine, QJSValue, qmlRegisterType
        from PySide6.QtTest import QTest
        commands = []

        class Process(QObject):
            exited = Signal(int)
            runningChanged = Signal()

            def __init__(self, parent=None):
                super().__init__(parent)
                self._cmd, self._out, self._err = [], None, None

            def set_command(self, value):
                self._cmd = value
                commands.append(value)
            command = Property('QVariantList', lambda s: s._cmd, set_command)
            running = Property(bool, lambda s: False, lambda s, v: None, notify=runningChanged)
            stdout = Property(QObject, lambda s: s._out, lambda s, v: setattr(s, '_out', v))
            stderr = Property(QObject, lambda s: s._err, lambda s, v: setattr(s, '_err', v))

        class Collector(QObject):
            streamFinished = Signal()
            text = Property(str, lambda s: '')

        app = QGuiApplication.instance() or QGuiApplication([])
        qmlRegisterType(Process, 'HunuSettingsTestIo', 1, 0, 'Process')
        qmlRegisterType(Collector, 'HunuSettingsTestIo', 1, 0, 'StdioCollector')
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / 'Quickshell').mkdir()
            (base / 'Quickshell' / 'qmldir').write_text('module Quickshell\n')
            (base / 'qmldir').write_text('singleton Theme 1.0 Theme.qml\nsingleton AppInfo 1.0 AppInfo.qml\nSettingsView 1.0 SettingsView.qml\n')
            (base / 'SettingsView.qml').write_text((ROOT / 'src' / 'SettingsView.qml').read_text().replace('import Quickshell\n', '').replace('import Quickshell.Io', 'import HunuSettingsTestIo'))
            shutil.copy(ROOT / 'src' / 'AppInfo.qml', base / 'AppInfo.qml')
            (base / 'Theme.qml').write_text('''pragma Singleton
import QtQuick
QtObject { property color base: '#181825'; property color text: '#cdd6f4'; property color subtext: '#a6adc8'; property color success: '#a6e3a1'; property color muted: '#6c7086'; property bool usingSystemTheme: false }
''')
            (base / 'Harness.qml').write_text('''import QtQuick
import QtQuick.Controls
ApplicationWindow {
    visible: true; width: 960; height: 760
    property alias settingsDialog: settings
    QtObject {
        id: ws
        property bool busy: false
        property string outputDirectory: '/tmp/wallpapers'
        property var applyBackendValues: ['serpantinum','hyprpaper','awww','noctalia']
        property string applyBackend: 'noctalia'
        property bool backendReady: true
        property string backendStatus: 'Ready'
        property bool cacheChecked: true
        property int cacheBytes: 0
        property int cacheFiles: 0
        property bool upscalerAvailable: false
    }
    SettingsView { id: settings; objectName: "settingsDialog"; workspace: ws }
    Component.onCompleted: settings.open()
}
''')
            engine = QQmlApplicationEngine()
            engine.addImportPath(str(base))
            engine.load(QUrl.fromLocalFile(str(base / 'Harness.qml')))
            self.assertTrue(engine.rootObjects())
            root = engine.rootObjects()[0]
            settings = root.findChild(QObject, 'settingsDialog')
            pages = settings.findChild(QObject, 'settingsPages')
            self.assertIsNotNone(pages)
            pages.setProperty('currentIndex', 1)
            js = engine.newQObject(settings)
            values = dict(enabled=True, position='top', livePreview=False, delayMs=750, showActionButtons=False)
            result = js.property('readSwitcherValues').callWithInstance(js, [QJSValue(json.dumps(values))])
            self.assertFalse(result.isError(), result.toString())
            QTest.qWait(100)
            enabled = settings.findChild(QObject, 'switcherEnabledSetting')
            position = settings.findChild(QObject, 'switcherPositionSetting')
            buttons = settings.findChild(QObject, 'switcherButtonsSetting')
            delay = settings.findChild(QObject, 'switcherDelaySetting')
            self.assertTrue(enabled.property('checked'))
            self.assertEqual(position.property('currentIndex'), 0)
            self.assertFalse(buttons.property('checked'))
            self.assertEqual(delay.property('value'), 750)
            self.assertFalse(delay.property('enabled'), 'Delay control follows live-preview toggle')
            point = enabled.mapToScene(QPointF(15, enabled.height() / 2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertFalse(settings.property('switcherEnabled'))
            self.assertFalse(position.property('enabled'))
            save_button = settings.findChild(QObject, 'saveSwitcherSettings')
            point = save_button.mapToScene(QPointF(save_button.width() / 2, save_button.height() / 2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            saves = [command for command in commands if 'save' in command]
            self.assertTrue(saves)
            self.assertEqual(json.loads(saves[-1][-1]), dict(values, enabled=False))
            root.close()
            engine.deleteLater()
            app.processEvents()
