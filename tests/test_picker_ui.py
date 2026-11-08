"""Optional Qt interaction test. Quickshell/layer-shell types are substituted.

Requires PySide6-Essentials; backend behavior is tested separately with IPC mocks.
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Optional PySide6 Qt harness is not installed')
class PickerInteractionTests(unittest.TestCase):
    def test_preview_follows_highlight_and_confirmation_waits_for_inflight_apply(self):
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        os.environ.setdefault('QT_QUICK_BACKEND', 'software')
        from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl, Qt, QPointF
        from PySide6.QtGui import QGuiApplication
        from PySide6.QtQuick import QQuickWindow  # Registers the Python window wrapper.
        from PySide6.QtQml import QQmlApplicationEngine, QJSValue, qmlRegisterType
        from PySide6.QtTest import QTest
        writes = []

        class Process(QObject):
            exited = Signal(int)
            runningChanged = Signal()

            def __init__(self, parent=None):
                super().__init__(parent)
                self._out, self._err, self._cmd = None, None, []

            command = Property('QVariantList', lambda s: s._cmd, lambda s, v: setattr(s, '_cmd', v))
            running = Property(bool, lambda s: True, lambda s, v: None, notify=runningChanged)
            stdinEnabled = Property(bool, lambda s: True, lambda s, v: None)
            stdout = Property(QObject, lambda s: s._out, lambda s, v: setattr(s, '_out', v))
            stderr = Property(QObject, lambda s: s._err, lambda s, v: setattr(s, '_err', v))

            @Slot(str)
            def write(self, line):
                writes.append(json.loads(line))

        class Collector(QObject):
            streamFinished = Signal()
            text = Property(str, lambda s: '')

        class Parser(QObject):
            read = Signal(str)

        class Ipc(QObject):
            def __init__(self, parent=None):
                super().__init__(parent)
                self._target = ''
            target = Property(str, lambda s: s._target, lambda s, v: setattr(s, '_target', v))

        app = QGuiApplication.instance() or QGuiApplication([])
        for cls, name in [(Process, 'Process'), (Collector, 'StdioCollector'), (Parser, 'SplitParser'), (Ipc, 'IpcHandler')]:
            qmlRegisterType(cls, 'Quickshell.Io', 1, 0, name)
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            module = base / 'Quickshell'
            module.mkdir()
            (module / 'qmldir').write_text('module Quickshell\nFloatingWindow 1.0 FloatingWindow.qml\nsingleton Quickshell 1.0 Quickshell.qml\n')
            (module / 'Quickshell.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var screens: [] }')
            (module / 'FloatingWindow.qml').write_text('import QtQuick\nimport QtQuick.Window\nWindow { width: 1280; height: 900; signal closed() }')
            source = (ROOT / 'src' / 'Switcher.qml').read_text()
            source = source.replace('import Quickshell.Wayland', '').replace('PanelWindow {', 'FloatingWindow {')
            source = '\n'.join(line for line in source.splitlines() if not any(v in line for v in
                               ['anchors { top:', 'exclusionMode:', 'WlrLayershell.']))
            (base / 'Switcher.qml').write_text(source)
            engine = QQmlApplicationEngine()
            engine.addImportPath(str(base))
            engine.load(QUrl.fromLocalFile(str(base / 'Switcher.qml')))
            self.assertTrue(engine.rootObjects())
            root = engine.rootObjects()[0]
            js = engine.newQObject(root)

            def receive(payload):
                result = js.property('receive').callWithInstance(js, [QJSValue(json.dumps(payload))])
                self.assertFalse(result.isError(), result.toString())

            sets = [dict(name=n, title=n, previewUrl='', fallbackPreviewUrl='', previewIsSource=True)
                    for n in ['First', 'Second', 'Third']]
            receive(dict(event='ready', sets=sets, layout={}, hidden=0, backend='noctalia', liveEnabled=True,
                         liveReason='', focusedOutput='', current='First'))
            root.requestActivate()
            QTest.qWait(100)
            def find_visual(item, name):
                if item.objectName() == name:
                    return item
                for child in item.childItems():
                    result = find_visual(child, name)
                    if result is not None:
                        return result
                return None

            previous = find_visual(root.contentItem(), 'previousPreview')
            following = find_visual(root.contentItem(), 'nextPreview')
            current = find_visual(root.contentItem(), 'currentPreview')
            self.assertIsNotNone(previous)
            self.assertIsNotNone(following)
            self.assertEqual(previous.property('neighborIndex'), 2, 'Previous must wrap at the first set')
            self.assertEqual(following.property('neighborIndex'), 1)
            self.assertGreater(current.property('width'), following.property('width'))
            root.setProperty('sets', sets[:1])
            self.assertFalse(previous.property('visible'))
            self.assertFalse(following.property('visible'))
            root.setProperty('sets', sets[:2])
            self.assertFalse(previous.property('visible'), 'Two sets must not duplicate the same neighbor')
            self.assertTrue(following.property('visible'))
            root.setProperty('sets', sets)
            # Side previews must be clickable without confirming the selection.
            point = following.mapToScene(QPointF(following.width() / 2, following.height() / 2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.qWait(450)
            self.assertEqual(writes, [dict(action='preview', name='Second')])
            # Finishing an old request must not bypass the quiet period for a
            # newer selection. Rapid choices replace each other, not queue up.
            QTest.keyClick(root, Qt.Key_Right)  # Third, while Second is in flight.
            QTest.qWait(200)
            receive(dict(event='previewed', name='Second'))
            self.assertEqual(len(writes), 1)
            QTest.keyClick(root, Qt.Key_Right)  # First supersedes Third.
            QTest.qWait(450)
            self.assertEqual(writes[-1], dict(action='preview', name='First'))
            self.assertEqual(len(writes), 2, 'Intermediate Third must never be sent')
            QTest.keyClick(root, Qt.Key_Right)
            QTest.keyClick(root, Qt.Key_Right)
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(len(writes), 2, 'Enter must wait for the current Apply')
            receive(dict(event='previewed', name='First'))
            self.assertEqual(writes[-1], dict(action='commit', name='Third'))
            # Independently verify that Escape waits for a restoration reply.
            root.setProperty('intent', '')
            root.setProperty('inFlight', '')
            quit_requests = []
            engine.quit.connect(lambda: quit_requests.append(True))
            QTest.keyClick(root, Qt.Key_Escape)
            self.assertEqual(writes[-1]['action'], 'cancel')
            self.assertFalse(quit_requests)
            receive(dict(event='cancelled'))
            self.assertTrue(quit_requests)
            root.hide()
            engine.deleteLater()
            app.processEvents()
