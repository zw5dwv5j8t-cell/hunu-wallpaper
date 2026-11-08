"""Optional native Qt render/interaction check of the production workspace.

Desktop process/portal integration is substituted; backend behavior has separate tests.
"""
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Optional PySide6 Qt harness is not installed')
class AppInteractionTests(unittest.TestCase):
    def test_workspace_controls_and_primary_actions(self):
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        os.environ.setdefault('QT_QUICK_BACKEND', 'software')
        from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl, Qt, QPointF
        from PySide6.QtGui import QGuiApplication, QImage
        from PySide6.QtQuick import QQuickWindow
        from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterType
        from PySide6.QtTest import QTest
        from qt_fixtures import prepare_controls

        class Process(QObject):
            exited = Signal(int)
            runningChanged = Signal()
            def __init__(self, parent=None):
                super().__init__(parent)
                self._cmd, self._out, self._err = [], None, None
            command = Property('QVariantList', lambda s: s._cmd, lambda s, v: setattr(s, '_cmd', v))
            running = Property(bool, lambda s: False, lambda s, v: None, notify=runningChanged)
            stdout = Property(QObject, lambda s: s._out, lambda s, v: setattr(s, '_out', v))
            stderr = Property(QObject, lambda s: s._err, lambda s, v: setattr(s, '_err', v))
            @Slot(int)
            def signal(self, value):
                pass

        class Collector(QObject):
            streamFinished = Signal()
            text = Property(str, lambda s: '')

        class Parser(QObject):
            read = Signal(str)

        app = QGuiApplication.instance() or QGuiApplication([])
        for cls, name in [(Process, 'Process'), (Collector, 'StdioCollector'), (Parser, 'SplitParser')]:
            qmlRegisterType(cls, 'HunuWorkspaceTestIo', 1, 0, name)
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for file in (ROOT / 'src').glob('*.qml'):
                contents = file.read_text().replace('import Quickshell\n', '').replace('import Quickshell.Io', 'import HunuWorkspaceTestIo')
                (base / file.name).write_text(contents)
            shutil.copy(ROOT / 'src' / 'qmldir', base / 'qmldir')
            prepare_controls(base)
            # Real preview media can be supplied for screenshot inspection.
            image = QImage(1200, 700, QImage.Format_RGB32)
            image.fill(Qt.GlobalColor.darkCyan)
            image_path = base / 'Mountain Lake.png'
            if os.environ.get('HUNU_QA_IMAGE'):
                shutil.copy(os.environ['HUNU_QA_IMAGE'], image_path)
            else:
                image.save(str(image_path))
            (base / 'Harness.qml').write_text('''import QtQuick
import QtQuick.Controls
ApplicationWindow {
    visible: true; width: 1120; height: 900; color: Theme.base
    WorkspaceView { id: workspace; objectName: "workspace"; anchors.fill: parent }
    SetupView { id: setup; objectName: "setup"; anchors.fill: parent; visible: false; allowCancel: true }
}
''')
            engine = QQmlApplicationEngine()
            engine.setOutputWarningsToStandardError(False)
            engine.addImportPath(str(base))
            warnings = []
            engine.warnings.connect(lambda values: warnings.extend(v.toString() for v in values))
            engine.load(QUrl.fromLocalFile(str(base / 'Harness.qml')))
            self.assertTrue(engine.rootObjects(), warnings)
            root = engine.rootObjects()[0]
            workspace = root.findChild(QObject, 'workspace')
            values = dict(configPath=str(base / 'config.conf'), sourcePath=str(image_path), sourceUrl=image_path.as_uri(),
                          outputDirectory='/home/hunu/Pictures/Wallpapers', monitorCount=3, activeSlots=[1,2,3],
                          outputName=['','DP-1','DP-2','HDMI-A-1'], pixelW=[0,1920,3840,1920], pixelH=[0,1080,2160,1080],
                          physX=[0,0,6000,13200],physY=[0,700,0,700],physW=[1,5800,7000,5800],physH=[1,3300,4000,3300],
                          desktopW=19000, desktopH=4000, previewW=19000, previewH=10693,
                          baseX=[0,0,6000,13200],baseY=[0,4046,3346,4046],cropW=[1,5800,7000,5800],cropH=[1,3300,4000,3300],
                          sourceW=5760,sourceH=3240,idealW=5760,idealH=2160,sourceSufficient=True,
                          xMin=[0,-100,-100,-100],xMax=[0,100,100,100],yMin=[0,-100,-100,-100],yMax=[0,100,100,100],
                          upscalerChecked=True,applyBackend='noctalia',backendReady=True,backendStatus='Noctalia is ready',
                          generatedFile=['',str(image_path),str(image_path),str(image_path)], statusMessage='Ready to generate')
            for name, value in values.items():
                workspace.setProperty(name, value)
            root.requestActivate()
            QTest.qWait(160)
            scroll = root.findChild(QObject, 'workspaceScroll')
            self.assertLessEqual(scroll.property('contentHeight'), scroll.property('availableHeight') + 1)
            generate = root.findChild(QObject, 'generateWallpapers')
            apply = root.findChild(QObject, 'applyWallpapers')
            self.assertTrue(generate.property('enabled'))
            self.assertTrue(apply.property('enabled'))
            for button in [generate, apply, root.findChild(QObject, 'openSettings')]:
                pos = button.mapToScene(QPointF(button.width()/2,button.height()/2))
                self.assertGreaterEqual(pos.y(), 0)
                self.assertLess(pos.y(), root.height())
            if os.environ.get('HUNU_QA_OUTPUT'):
                root.grabWindow().save(os.environ['HUNU_QA_OUTPUT'])
            def find_visual(item, name):
                if item.objectName() == name:
                    return item
                for child in item.childItems():
                    result = find_visual(child, name)
                    if result is not None:
                        return result
                return None
            slider = find_visual(root.contentItem(), 'offsetSlider-1-x')
            point = slider.mapToScene(QPointF(slider.width()*0.8, slider.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            js_workspace = engine.newQObject(workspace)
            offsets = js_workspace.property('offsetX')
            self.assertGreater(offsets.property('1').toNumber(), 0)
            self.assertEqual(offsets.property('1').toNumber(), offsets.property('2').toNumber())
            # Exact-entry input still commits the shared position on Enter.
            field = find_visual(root.contentItem(), 'offsetInput-1-x')
            point = field.mapToScene(QPointF(field.width()/2, field.height()/2)).toPoint()
            QTest.mouseClick(root, Qt.LeftButton, Qt.NoModifier, point)
            QTest.keyClick(root, Qt.Key_A, Qt.ControlModifier)
            QTest.keyClick(root, Qt.Key_2)
            QTest.keyClick(root, Qt.Key_5)
            QTest.keyClick(root, Qt.Key_Return)
            self.assertEqual(js_workspace.property('offsetX').property('1').toNumber(), 25)
            self.assertFalse(apply.property('enabled'), 'Editing invalidates generated results')
            root.resize(900,700)
            QTest.qWait(40)
            self.assertGreater(scroll.property('contentHeight'), scroll.property('availableHeight'))
            flickable = scroll.property('contentItem')
            self.assertTrue(flickable.setProperty('contentY', 80))
            self.assertGreater(flickable.property('contentY'), 0)
            flickable.setProperty('contentY', 0)
            self.assertLess(generate.mapToScene(QPointF()).y() + generate.height(), root.height())
            root.resize(1120,900)
            QTest.qWait(40)
            mode = root.findChild(QObject, 'compositionMode')
            mode.selected.emit(1)
            self.assertEqual(workspace.property('mode'), 'quality')
            mode.selected.emit(0)
            self.assertEqual(workspace.property('mode'), 'linked')
            setup = root.findChild(QObject, 'setup')
            workspace.setProperty('visible', False)
            setup.setProperty('visible', True)
            setup.setProperty('monitors', [dict(name=f'DP-{i}', model='Display', width=1920, height=1080,
                                                suggestedWidth=60, suggestedHeight=34, make='Display', orientation='landscape', refresh='60.00') for i in (1,2,3)])
            setup.setProperty('detectedCount', 3)
            setup.setProperty('supportedCount', 3)
            for i in (1,2,3):
                setup.setProperty(f'slot{i}Index', i-1)
                setup.setProperty(f'slot{i}WidthCm', 60)
                setup.setProperty(f'slot{i}HeightCm', 34)
                setup.setProperty(f'slot{i}Xcm', (i-1)*60)
                setup.setProperty(f'slot{i}Ycm', 0)
            setup.setProperty('page', 1)
            QTest.qWait(100)
            from PySide6.QtQml import QJSValue
            js = engine.newQObject(setup)
            result = js.property('assignmentValid').callWithInstance(js, [])
            self.assertTrue(result.toBool())
            if os.environ.get('HUNU_QA_SETUP_OUTPUT'):
                root.grabWindow().save(os.environ['HUNU_QA_SETUP_OUTPUT'])
            self.assertFalse([w for w in warnings if 'TypeError' in w or 'Cannot assign' in w], warnings)
            root.hide()
            engine.deleteLater()
            app.processEvents()
