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
        from PySide6.QtGui import QGuiApplication, QImage
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

            fixture = QImage(400, 200, QImage.Format_RGB32)
            fixture.fill(Qt.GlobalColor.darkBlue)
            self.assertTrue(fixture.save(str(base / 'preview.png')))
            image_url = (base / 'preview.png').as_uri()
            sets = [dict(name=n, title=n, previewUrl=image_url, fallbackPreviewUrl=image_url, previewIsSource=True)
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
            frame = find_visual(current, 'roundedImageFrame')
            self.assertGreater(frame.width(), 0)
            self.assertAlmostEqual(frame.width() / frame.height(), 2)
            self.assertLessEqual(frame.width(), current.width())
            self.assertLessEqual(frame.height(), current.height())
            self.assertGreater(frame.property('cornerRadius'), 0)
            current.setProperty('shadowEnabled', False)
            QTest.qWait(60)

            def assert_clipped(expected_color):
                screenshot = root.grabWindow()
                origin = frame.mapToScene(QPointF())
                left, top = round(origin.x()), round(origin.y())
                right, bottom = round(origin.x() + frame.width()), round(origin.y() + frame.height())
                for x, y in [(left + 2, top + 2), (right - 3, top + 2),
                             (left + 2, bottom - 3), (right - 3, bottom - 3)]:
                    self.assertEqual(screenshot.pixelColor(x, y).alpha(), 0, 'Actual image corners must be transparent')
                center = screenshot.pixelColor(round(origin.x() + frame.width() / 2), round(origin.y() + frame.height() / 2))
                self.assertEqual(center, expected_color)

            from PySide6.QtGui import QColor
            assert_clipped(QColor(Qt.GlobalColor.darkBlue))
            portrait = QImage(200, 400, QImage.Format_RGB32)
            portrait.fill(Qt.GlobalColor.darkGreen)
            self.assertTrue(portrait.save(str(base / 'portrait.png')))
            portrait_sets = [dict(s) for s in sets]
            portrait_sets[0]['previewUrl'] = (base / 'portrait.png').as_uri()
            motion = []
            frame.slideOffsetChanged.connect(lambda: motion.append(frame.property('slideOffset')))
            root.setProperty('sets', portrait_sets)
            QTest.qWait(240)
            self.assertAlmostEqual(frame.width() / frame.height(), 0.5)
            self.assertTrue(any(abs(offset) > 0.1 for offset in motion), 'A source change should animate')
            self.assertAlmostEqual(frame.property('slideOffset'), 0)
            assert_clipped(QColor(Qt.GlobalColor.darkGreen))
            self.assertLessEqual(frame.width(), current.width())
            self.assertLessEqual(frame.height(), current.height())
            root.setProperty('sets', sets)
            QTest.qWait(240)

            content = find_visual(root.contentItem(), 'switcherContent')
            center_y = content.y()
            root.setProperty('verticalPosition', 'top')
            self.assertEqual(content.y(), 32)
            self.assertLess(content.y(), center_y)
            root.setProperty('verticalPosition', 'bottom')
            self.assertGreater(content.y(), center_y)
            root.setProperty('verticalPosition', 'center')
            self.assertEqual(content.y(), center_y)

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
            root.setProperty('showActionButtons', False)
            self.assertFalse(find_visual(root.contentItem(), 'applyButton').property('visible'))
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(len(writes), 2, 'Enter must wait for the current Apply')
            receive(dict(event='previewed', name='First'))
            self.assertEqual(writes[-1], dict(action='commit', name='Third'))
            # Icon buttons are larger, have no text, and share keyboard actions.
            root.setProperty('showActionButtons', True)
            QTest.qWait(30)
            root.setProperty('intent', '')
            root.setProperty('inFlight', '')
            apply_button = find_visual(root.contentItem(), 'applyButton')
            cancel_button = find_visual(root.contentItem(), 'cancelButton')
            for button in [apply_button, cancel_button, find_visual(root.contentItem(), 'previousButton'),
                           find_visual(root.contentItem(), 'nextButton')]:
                self.assertGreaterEqual(button.width(), 64)
                self.assertGreaterEqual(button.height(), 64)
                self.assertEqual(button.property('text'), '')
            previous_button = find_visual(root.contentItem(), 'previousButton')
            self.assertGreater(apply_button.mapToScene(QPointF()).y(), previous_button.mapToScene(QPointF()).y())
            point = apply_button.mapToScene(QPointF(32, 32)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertEqual(writes[-1], dict(action='commit', name='Third'))
            root.setProperty('intent', '')
            root.setProperty('inFlight', '')
            point = cancel_button.mapToScene(QPointF(32, 32)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertEqual(writes[-1]['action'], 'cancel')
            # Independently verify that Escape waits for a restoration reply.
            root.setProperty('intent', '')
            root.setProperty('inFlight', '')
            root.setProperty('showActionButtons', False)
            self.assertFalse(cancel_button.property('visible'))
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
