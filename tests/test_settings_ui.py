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
            from qt_fixtures import prepare_controls
            prepare_controls(base, io_module="HunuSettingsTestIo")
            (base / 'Harness.qml').write_text('''import QtQuick
import QtQuick.Controls
ApplicationWindow {
    visible: true; width: 960; height: 760; color: Theme.base
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
        function saveApplyBackend(value) { applyBackend = value }
        function manageCache(action) {}
    }
    SettingsView { id: settings; objectName: "settingsDialog"; workspace: ws }
    Component.onCompleted: settings.open()
}
''')
            engine = QQmlApplicationEngine()
            engine.setOutputWarningsToStandardError(False)
            engine.addImportPath(str(base))
            warnings = []
            engine.warnings.connect(lambda values: warnings.extend(v.toString() for v in values))
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
            point = position.mapToScene(QPointF(position.width()*5/6, position.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertEqual(settings.property('switcherPosition'), 'bottom')
            point = position.mapToScene(QPointF(position.width()/6, position.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertEqual(settings.property('switcherPosition'), 'top')

            style = settings.findChild(QObject, 'switcherStyleSetting')
            self.assertEqual(style.property('currentIndex'), 0, 'Old preferences keep Carousel')
            point = style.mapToScene(QPointF(style.width()*3/4, style.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.keyClick(root, Qt.Key_Down)
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(settings.property('switcherStyle'), 'grid')
            for expected in ['spotlight', 'filmstrip', 'browser']:
                QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
                QTest.keyClick(root, Qt.Key_Down)
                QTest.keyClick(root, Qt.Key_Return)
                self.assertEqual(settings.property('switcherStyle'), expected)
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.keyClick(root, Qt.Key_Home)
            QTest.keyClick(root, Qt.Key_Down)
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(settings.property('switcherStyle'), 'grid')
            point = enabled.mapToScene(QPointF(15, enabled.height() / 2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertFalse(settings.property('switcherEnabled'))
            self.assertFalse(position.property('enabled'))
            save_button = settings.findChild(QObject, 'saveSwitcherSettings')
            point = save_button.mapToScene(QPointF(save_button.width() / 2, save_button.height() / 2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            saves = [command for command in commands if 'save' in command]
            self.assertTrue(saves)
            self.assertEqual(json.loads(saves[-1][-1]), dict(values, enabled=False, style='grid'))
            settings.setProperty('switcherEnabled', True)
            settings.setProperty('switcherLivePreview', True)
            QTest.qWait(20)
            point = delay.mapToScene(QPointF(delay.width()/2, delay.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.keyClick(root, Qt.Key_A, Qt.ControlModifier)
            for key in [Qt.Key_6, Qt.Key_5, Qt.Key_0]:
                QTest.keyClick(root, key)
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(settings.property('switcherDelayMs'), 650)

            preferences = settings.findChild(QObject, 'pickerPreferences')
            prefs_js = engine.newQObject(preferences)
            result = prefs_js.property('readRotationValues').callWithInstance(prefs_js, [QJSValue(json.dumps(dict(
                enabled=True, intervalMinutes=20, avoidRepeat=True, available=True)))])
            self.assertFalse(result.isError(), result.toString())
            scroll = settings.findChild(QObject, 'switcherSettingsPage')
            flick = scroll.property('contentItem')
            flick.setProperty('contentY', max(0, flick.property('contentHeight') - flick.height()))
            QTest.qWait(30)
            repeat = settings.findChild(QObject, 'rotationRepeatSetting')
            point = repeat.mapToScene(QPointF(repeat.width()/2, repeat.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertFalse(preferences.property('rotationAvoidRepeat'))
            interval = settings.findChild(QObject, 'rotationIntervalSetting')
            point = interval.mapToScene(QPointF(interval.width()/2, interval.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.keyClick(root, Qt.Key_A, Qt.ControlModifier)
            QTest.keyClick(root, Qt.Key_4)
            QTest.keyClick(root, Qt.Key_5)
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(preferences.property('rotationMinutes'), 45)
            self.assertTrue(preferences.property('rotationDirty'))
            js.property('saveSwitcherSettings').callWithInstance(js)
            picker_save = next(process for process in preferences.findChildren(Process)
                               if 'save' in process._cmd and 'switcher-settings.py' in process._cmd[1])
            picker_save.exited.emit(0)
            rotation_save = next(command for command in reversed(commands)
                                 if len(command) > 2 and command[1].endswith('rotation-settings.py') and command[2] == 'save')
            self.assertEqual(json.loads(rotation_save[-1]), dict(enabled=True, intervalMinutes=45, avoidRepeat=False))

            # The styled combo must still open, navigate, and activate normally.
            pages.setProperty('currentIndex', 0)
            root.requestActivate()
            QTest.qWait(50)
            backend = settings.findChild(QObject, 'applyBackendSetting')
            point = backend.mapToScene(QPointF(backend.width()/2, backend.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.keyClick(root, Qt.Key_Up)
            QTest.keyClick(root, Qt.Key_Return)
            QTest.qWait(30)
            self.assertEqual(backend.property('currentIndex'), 2)
            self.assertFalse([w for w in warnings if 'TypeError' in w or 'Cannot assign' in w], warnings)
            root.close()
            engine.deleteLater()
            app.processEvents()
