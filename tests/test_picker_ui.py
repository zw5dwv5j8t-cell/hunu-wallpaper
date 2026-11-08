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
            def visual_width(item):
                return item.mapToScene(QPointF(item.width(), 0)).x() - item.mapToScene(QPointF()).x()
            self.assertGreater(visual_width(current), visual_width(following))
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
            # Hold a real asynchronous image request open. All three outgoing
            # previews must stay visible, including their original geometry.
            import http.server
            import threading
            import time
            release = threading.Event()
            requested = threading.Event()
            replacement_image = QImage(400, 200, QImage.Format_RGB32)
            replacement_image.fill(Qt.GlobalColor.darkGreen)
            self.assertTrue(replacement_image.save(str(base / 'delayed.png')))
            replacement_bytes = (base / 'delayed.png').read_bytes()

            class DelayedImage(http.server.BaseHTTPRequestHandler):
                def do_GET(handler):
                    requested.set()
                    release.wait(5)
                    handler.send_response(200)
                    handler.send_header('Content-Type', 'image/png')
                    handler.send_header('Content-Length', str(len(replacement_bytes)))
                    handler.end_headers()
                    handler.wfile.write(replacement_bytes)

                def log_message(handler, *args):
                    pass

            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), DelayedImage)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()

            def stop_server():
                release.set()
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)
            self.addCleanup(stop_server)
            delayed_sets = [dict(item, previewUrl=f'http://127.0.0.1:{server.server_port}/delayed.png') for item in sets]
            old_size = (frame.width(), frame.height())
            root.setProperty('sets', delayed_sets)
            deadline = time.monotonic() + 3
            while not requested.is_set() and time.monotonic() < deadline:
                QTest.qWait(20)
            self.assertTrue(requested.is_set())
            QTest.qWait(60)
            self.assertEqual((frame.width(), frame.height()), old_size)
            assert_clipped(QColor(Qt.GlobalColor.darkBlue))
            pending_screenshot = root.grabWindow()
            for side in [previous, following]:
                side_frame = find_visual(side, 'roundedImageFrame')
                self.assertGreater(side_frame.width(), 0)
                middle = side_frame.mapToScene(QPointF(side_frame.width()/2, side_frame.height()/2))
                pixel = pending_screenshot.pixelColor(round(middle.x()), round(middle.y()))
                self.assertGreater(pixel.alpha(), 100, 'Side preview must remain visible while loading')
                self.assertGreater(pixel.blue(), pixel.green())
            release.set()
            canvas = find_visual(current, 'roundedImageCanvas')
            deadline = time.monotonic() + 3
            while canvas.property('displayedUrl').toString() != delayed_sets[0]['previewUrl'] and time.monotonic() < deadline:
                QTest.qWait(10)
                time.sleep(0.005)  # Let the Python HTTP server reply while pumping Qt.
            QTest.qWait(220)
            assert_clipped(QColor(Qt.GlobalColor.darkGreen))
            root.setProperty('sets', sets)
            QTest.qWait(300)
            assert_clipped(QColor(Qt.GlobalColor.darkBlue))
            portrait = QImage(200, 400, QImage.Format_RGB32)
            portrait.fill(Qt.GlobalColor.darkGreen)
            self.assertTrue(portrait.save(str(base / 'portrait.png')))
            portrait_sets = [dict(s) for s in sets]
            portrait_sets[0]['previewUrl'] = (base / 'portrait.png').as_uri()
            root.setProperty('sets', portrait_sets)
            QTest.qWait(240)
            self.assertAlmostEqual(frame.width() / frame.height(), 0.5)
            self.assertAlmostEqual(frame.x() + frame.width() / 2, current.width() / 2, delta=0.5)
            self.assertAlmostEqual(frame.y() + frame.height() / 2, current.height() / 2, delta=0.5)
            assert_clipped(QColor(Qt.GlobalColor.darkGreen))
            self.assertLessEqual(frame.width(), current.width())
            self.assertLessEqual(frame.height(), current.height())
            root.setProperty('sets', sets)
            QTest.qWait(240)

            # A cold incoming neighbor must hold the whole outgoing triplet,
            # not update the center and leave an old duplicate at the side.
            root.setProperty('liveEnabled', False)
            root.setProperty('queuedName', '')
            cache_sets = []
            for i in range(13):
                path = base / f'cache-{i}.png'
                path.write_bytes((base / 'preview.png').read_bytes())
                cache_sets.append(dict(name=f'Cache {i}', title=f'Cache {i}', previewUrl=path.as_uri(),
                                       fallbackPreviewUrl=path.as_uri(), previewIsSource=True))
            release.clear()
            requested.clear()
            cache_sets[7]['previewUrl'] = f'http://127.0.0.1:{server.server_port}/cold-seven.png'
            root.setProperty('sets', cache_sets)
            QTest.qWait(160)
            root.setProperty('selectedIndex', 6)
            deadline = time.monotonic() + 3
            while not requested.is_set() and time.monotonic() < deadline:
                QTest.qWait(10)
                time.sleep(0.005)
            self.assertTrue(requested.is_set())
            QTest.qWait(50)
            self.assertEqual(root.property('displayedIndex'), 0, 'Keep outgoing triplet until every incoming asset is decoded')
            for name, index in [('previousPreview', 12), ('currentPreview', 0), ('nextPreview', 1)]:
                self.assertEqual(find_visual(root.contentItem(), name).property('neighborIndex'), index)

            def active_assets(item):
                count = 1 if item.objectName() in ('previousPreview', 'currentPreview', 'nextPreview', 'prefetchedPreview') else 0
                return count + sum(active_assets(child) for child in item.childItems())
            self.assertLessEqual(active_assets(root.contentItem()), 8, 'Cache must stay bounded')
            release.set()
            deadline = time.monotonic() + 3
            while root.property('displayedIndex') != 6 and time.monotonic() < deadline:
                QTest.qWait(10)
                time.sleep(0.005)
            self.assertEqual(root.property('displayedIndex'), 6)
            for name, index in [('previousPreview', 5), ('currentPreview', 6), ('nextPreview', 7)]:
                self.assertEqual(find_visual(root.contentItem(), name).property('neighborIndex'), index)
            root.setProperty('selectedIndex', 0)
            root.setProperty('sets', sets)
            QTest.qWait(160)
            root.setProperty('liveEnabled', True)
            previous = find_visual(root.contentItem(), 'previousPreview')
            following = find_visual(root.contentItem(), 'nextPreview')
            current = find_visual(root.contentItem(), 'currentPreview')
            frame = find_visual(current, 'roundedImageFrame')

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
            QTest.qWait(20)
            self.assertIsNone(find_visual(root.contentItem(), 'previousPreview'))
            self.assertIsNone(find_visual(root.contentItem(), 'nextPreview'))
            root.setProperty('sets', sets[:2])
            QTest.qWait(20)
            self.assertIsNone(find_visual(root.contentItem(), 'previousPreview'), 'Two sets must not duplicate the same neighbor')
            self.assertIsNotNone(find_visual(root.contentItem(), 'nextPreview'))
            root.setProperty('sets', sets)
            QTest.qWait(100)
            following = find_visual(root.contentItem(), 'nextPreview')
            next_frame = find_visual(following, 'roundedImageFrame')
            old_frame_size = (next_frame.width(), next_frame.height())
            decoder = find_visual(following, 'previewDecoder')
            reloads = []
            decoder.statusChanged.connect(lambda: reloads.append(decoder.property('status')))
            # The same prepared asset must move from side to center. It must not
            # reload or resize its rendered bitmap just because its role changes.
            point = following.mapToScene(QPointF(following.width() / 2, following.height() / 2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.qWait(450)
            self.assertEqual(root.property('displayedIndex'), 1)
            self.assertIs(find_visual(root.contentItem(), 'currentPreview'), following)
            self.assertEqual((next_frame.width(), next_frame.height()), old_frame_size)
            self.assertEqual(reloads, [], 'Promoting a prepared side preview must not decode again')
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
