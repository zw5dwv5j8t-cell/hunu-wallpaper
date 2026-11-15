"""Render and interact with the real grid picker using stand-ins for desktop IPC."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from contextlib import contextmanager
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]


@contextmanager
def grid_picker(count=20, current=0):
    os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
    os.environ.setdefault('QT_QUICK_BACKEND', 'software')
    from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl
    from PySide6.QtGui import QGuiApplication, QImage, QColor, QPainter, QLinearGradient
    from PySide6.QtQuick import QQuickWindow
    from PySide6.QtQml import QQmlApplicationEngine, QJSValue, qmlRegisterType
    from PySide6.QtTest import QTest
    writes = []

    class Process(QObject):
        exited = Signal(int)
        runningChanged = Signal()
        def __init__(self, parent=None):
            super().__init__(parent)
            self.cmd, self.out, self.err = [], None, None
        command = Property('QVariantList', lambda s: s.cmd, lambda s, v: setattr(s, 'cmd', v))
        running = Property(bool, lambda s: True, lambda s, v: None, notify=runningChanged)
        stdinEnabled = Property(bool, lambda s: True, lambda s, v: None)
        stdout = Property(QObject, lambda s: s.out, lambda s, v: setattr(s, 'out', v))
        stderr = Property(QObject, lambda s: s.err, lambda s, v: setattr(s, 'err', v))
        @Slot(str)
        def write(self, line):
            writes.append(json.loads(line))

    class Parser(QObject):
        read = Signal(str)

    class Ipc(QObject):
        def __init__(self, parent=None):
            super().__init__(parent)
            self.name = ''
        target = Property(str, lambda s: s.name, lambda s, v: setattr(s, 'name', v))

    app = QGuiApplication.instance() or QGuiApplication([])
    for cls, name in [(Process, 'Process'), (Parser, 'SplitParser'), (Ipc, 'IpcHandler')]:
        qmlRegisterType(cls, 'HunuGridTestIo', 1, 0, name)
    with tempfile.TemporaryDirectory() as folder:
        base = Path(folder)
        module = base / 'Quickshell'
        module.mkdir()
        (module / 'qmldir').write_text('module Quickshell\nFloatingWindow 1.0 FloatingWindow.qml\nsingleton Quickshell 1.0 Quickshell.qml\n')
        (module / 'Quickshell.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var screens: []; function env(name) { return undefined } }')
        (module / 'FloatingWindow.qml').write_text('import QtQuick\nimport QtQuick.Window\nWindow { width: 1280; height: 900; signal closed() }')
        source = (ROOT / 'src/Switcher.qml').read_text().replace('import Quickshell.Wayland', '').replace('import Quickshell.Io', 'import HunuGridTestIo').replace('PanelWindow {', 'FloatingWindow {')
        source = '\n'.join(line for line in source.splitlines() if not any(token in line for token in ['anchors { top:', 'exclusionMode:', 'WlrLayershell.']))
        (base / 'Switcher.qml').write_text(source)
        sets = []
        for index in range(count):
            image = QImage(640, 360, QImage.Format_RGB32)
            painter = QPainter(image)
            gradient = QLinearGradient(0, 0, 640, 360)
            gradient.setColorAt(0, QColor.fromHsv((index * 31) % 360, 160, 170))
            gradient.setColorAt(1, QColor.fromHsv((index * 31 + 70) % 360, 210, 80))
            painter.fillRect(image.rect(), gradient)
            painter.end()
            path = base / f'wallpaper-{index}.png'
            image.save(str(path))
            sets.append(dict(name=f'Set {index}', title=f'Wallpaper {index + 1}', previewUrl=path.as_uri(),
                             fallbackPreviewUrl=path.as_uri(), previewSize=[640, 360], fallbackPreviewSize=[640, 360], previewIsSource=True))
        engine = QQmlApplicationEngine()
        engine.addImportPath(str(base))
        warnings = []
        engine.warnings.connect(lambda values: warnings.extend(value.toString() for value in values))
        engine.load(QUrl.fromLocalFile(str(base / 'Switcher.qml')))
        assert engine.rootObjects(), warnings
        root = engine.rootObjects()[0]
        js = engine.newQObject(root)
        def receive(message):
            result = js.property('receive').callWithInstance(js, [QJSValue(json.dumps(message))])
            assert not result.isError(), result.toString()
        def call(name, *arguments):
            result = js.property(name).callWithInstance(js, [QJSValue(float(value)) for value in arguments])
            assert not result.isError(), result.toString()
        def items(item=None):
            item = item or root.contentItem()
            return [item] + [child for direct in item.childItems() for child in items(direct)]
        def find(name):
            return next((item for item in items() if item.objectName() == name), None)
        def wait(predicate, timeout=3):
            deadline = time.monotonic() + timeout
            while not predicate() and time.monotonic() < deadline:
                QTest.qWait(10)
                time.sleep(0.002)
            assert predicate(), f'Timed out; Qt warnings: {warnings}'
        receive(dict(event='ready', sets=sets, layout={}, hidden=0, backend='noctalia', current=f'Set {current}' if count else '',
                     focusedOutput='', liveEnabled=True, liveReason='',
                     switcherSettings=dict(style='grid', position='center', showActionButtons=True, delayMs=100)))
        root.requestActivate()
        try:
            wait(lambda: root.property('firstFrameReady') or not count)
            yield SimpleNamespace(root=root, sets=sets, writes=writes, receive=receive, call=call, find=find, items=items, wait=wait,
                                  engine=engine, warnings=warnings, base=base, QTest=QTest)
        finally:
            root.hide()
            engine.deleteLater()
            app.processEvents()


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Optional PySide6 Qt harness is not installed')
class GridPickerTests(unittest.TestCase):
    def test_nine_tiles_paging_partial_last_page_and_keyboard_selection(self):
        from PySide6.QtCore import Qt, QPointF
        with grid_picker() as h:
            root = h.root
            def visible_tiles():
                return sorted(item.property('wallpaperIndex') for item in h.items()
                              if item.objectName() == 'gridTile' and item.parentItem().opacity() > 0)
            self.assertEqual(root.property('pickerStyle'), 'grid')
            self.assertIsNone(h.find('currentPreview'), 'Carousel assets must not load in grid mode')
            self.assertEqual(visible_tiles(), list(range(9)))
            self.assertEqual(h.find('gridPageIndicator').property('text'), '1 / 3')
            self.assertFalse(h.find('previousButton').isEnabled())
            self.assertTrue(h.find('nextButton').isEnabled())
            screenshot = os.environ.get('HUNU_GRID_QA_IMAGE')
            if screenshot:
                self.assertTrue(root.grabWindow().save(screenshot))
            h.QTest.keyClick(root, Qt.Key_Right)
            h.QTest.keyClick(root, Qt.Key_Down)
            self.assertEqual(root.property('selectedIndex'), 4)
            h.QTest.keyClick(root, Qt.Key_Left)
            h.QTest.keyClick(root, Qt.Key_Up)
            self.assertEqual(root.property('selectedIndex'), 0)
            tile = next(item for item in h.items() if item.objectName() == 'gridTile' and item.property('wallpaperIndex') == 7)
            point = tile.mapToScene(QPointF(tile.width()/2, tile.height()/2)).toPoint()
            h.QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            self.assertEqual(root.property('selectedIndex'), 7)
            h.QTest.keyClick(root, Qt.Key_PageDown)
            h.wait(lambda: root.property('displayedPage') == 1)
            self.assertEqual(root.property('selectedIndex'), 16)
            self.assertEqual(visible_tiles(), list(range(9, 18)))
            button = h.find('nextButton')
            point = button.mapToScene(QPointF(button.width()/2, button.height()/2)).toPoint()
            h.QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            h.wait(lambda: root.property('displayedPage') == 2)
            self.assertEqual(visible_tiles(), [18, 19])
            self.assertEqual(h.find('gridPageIndicator').property('text'), '3 / 3')
            self.assertFalse(h.find('nextButton').isEnabled())
            h.QTest.keyClick(root, Qt.Key_Home)
            h.wait(lambda: root.property('displayedIndex') == 0)
            h.QTest.keyClick(root, Qt.Key_End)
            h.wait(lambda: root.property('displayedIndex') == 19)
            self.assertLessEqual(sum(item.objectName() == 'gridTile' for item in h.items()), 18)
            self.assertFalse(h.warnings, h.warnings)

    def test_page_loading_keeps_outgoing_grid_and_enter_waits_for_complete_page(self):
        import http.server
        import threading
        from PySide6.QtCore import Qt
        with grid_picker() as h:
            release = threading.Event()
            requested = threading.Event()
            data = (h.base / 'wallpaper-9.png').read_bytes()
            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    requested.set()
                    release.wait(5)
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(data)
                def log_message(self, *args):
                    pass
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                h.root.setProperty('liveEnabled', False)
                changed = [dict(item) for item in h.sets]
                changed[9]['previewUrl'] = f'http://127.0.0.1:{server.server_port}/held.png'
                h.root.setProperty('sets', changed)
                h.call('changePage', 1)
                h.wait(requested.is_set)
                self.assertEqual(h.root.property('displayedPage'), 0)
                h.QTest.keyClick(h.root, Qt.Key_Return)
                self.assertTrue(h.root.property('confirmWhenVisible'))
                self.assertFalse(any(item['action'] == 'commit' for item in h.writes))
                release.set()
                h.wait(lambda: any(item['action'] == 'commit' for item in h.writes))
                self.assertEqual(h.root.property('displayedPage'), 1)
                self.assertEqual(h.writes[-1], dict(action='commit', name='Set 9'))
                quits = []
                h.engine.quit.connect(lambda: quits.append(True))
                h.receive(dict(event='committed', name='Set 9'))
                self.assertTrue(quits)
            finally:
                release.set()
                server.shutdown()
                server.server_close()
                worker.join(timeout=2)

    def test_snapshot_selection_empty_library_and_escape_waits_for_rollback(self):
        from PySide6.QtCore import Qt
        with grid_picker(current=19) as h:
            self.assertEqual(h.root.property('displayedPage'), 2)
            self.assertEqual(h.root.property('selectedIndex'), 19)
            h.root.setProperty('showActionButtons', False)
            self.assertFalse(h.find('actionButtonsRow').isVisible())
            quits = []
            h.engine.quit.connect(lambda: quits.append(True))
            h.QTest.keyClick(h.root, Qt.Key_Escape)
            self.assertEqual(h.writes[-1]['action'], 'cancel')
            self.assertFalse(quits)
            h.receive(dict(event='cancelled'))
            self.assertTrue(quits)
        with grid_picker(count=0) as h:
            self.assertEqual(h.find('gridPageIndicator').property('text'), '0 / 0')
            self.assertFalse(h.find('applyButton').isEnabled())
            self.assertFalse(h.find('nextButton').isEnabled())
            h.QTest.keyClick(h.root, Qt.Key_Return)
            self.assertFalse(any(item['action'] == 'commit' for item in h.writes))
