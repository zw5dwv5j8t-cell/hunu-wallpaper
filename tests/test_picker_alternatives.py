"""Distinct picker layouts, shared navigation and settings access."""
import importlib.util
import os
import unittest
from pathlib import Path

from test_picker_grid import grid_picker


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Optional Qt harness is not installed')
class AlternativePickerTests(unittest.TestCase):
    def test_layouts_navigation_and_selection(self):
        from PySide6.QtCore import Qt, QPointF
        for style in ('spotlight', 'filmstrip', 'browser'):
            with self.subTest(style=style), grid_picker(count=12, style=style) as h:
                self.assertEqual(h.root.property('pickerStyle'), style)
                self.assertIsNone(h.find('currentPreview'))
                self.assertIsNone(h.find('gridTile'))
                tiles = [item for item in h.items() if item.objectName() == 'alternativeTile' and item.parentItem().opacity() > 0]
                self.assertEqual(len(tiles), 5 if style == 'filmstrip' else 1)
                if style == 'browser':
                    library = h.find('browserLibrary')
                    self.assertTrue(library.isVisible())
                    row = next(item for item in h.items() if item.objectName() == 'browserRow' and item.property('index') == 3)
                    point = row.mapToScene(QPointF(row.width()/2, row.height()/2)).toPoint()
                    h.QTest.mouseClick(h.root, Qt.LeftButton, Qt.NoModifier, point)
                    self.assertEqual(h.root.property('selectedIndex'), 3)
                    h.QTest.keyClick(h.root, Qt.Key_Down)
                    self.assertEqual(h.root.property('selectedIndex'), 4)
                else:
                    h.QTest.keyClick(h.root, Qt.Key_Right)
                    self.assertEqual(h.root.property('selectedIndex'), 1)
                h.QTest.keyClick(h.root, Qt.Key_End)
                h.wait(lambda: h.root.property('displayedIndex') == 11)
                tiles = [item for item in h.items() if item.objectName() == 'alternativeTile' and item.parentItem().opacity() > 0]
                self.assertEqual(len(tiles), 2 if style == 'filmstrip' else 1)
                self.assertLessEqual(sum(item.objectName() == 'alternativeTile' for item in h.items()), 20 if style == 'filmstrip' else 4)
                if os.environ.get('HUNU_ALTERNATIVE_QA_DIR'):
                    path = Path(os.environ['HUNU_ALTERNATIVE_QA_DIR']) / (style + '.png')
                    h.root.grabWindow().save(str(path))
                self.assertIsNotNone(h.find('pickerSettingsButton'))
                self.assertFalse(h.warnings, h.warnings)

    def test_selection_does_not_repaint_cached_wallpaper_pixels(self):
        for style in ('grid', 'filmstrip'):
            with self.subTest(style=style), grid_picker(count=9, style=style) as h:
                h.root.setProperty('liveEnabled', False)
                h.QTest.qWait(250)
                paints = []
                canvases = [item for item in h.items() if item.objectName() == 'roundedImageCanvas']
                self.assertTrue(canvases)
                for canvas in canvases:
                    canvas.painted.connect(lambda: paints.append(True))
                for index in (1, 2, 3, 2, 1, 0):
                    h.call('choose', index)
                    h.wait(lambda: h.root.property('displayedIndex') == index)
                    h.QTest.qWait(20)
                self.assertEqual(paints, [], 'Selection borders must not rasterize photos again')

    def test_repeated_ready_notifications_do_not_redraw_loaded_images(self):
        for style in ('carousel', 'grid', 'spotlight', 'filmstrip', 'browser'):
            with self.subTest(style=style), grid_picker(count=9, style=style) as h:
                h.QTest.qWait(300)
                paints = []
                canvases = [item for item in h.items() if item.objectName() == 'roundedImageCanvas']
                for canvas in canvases:
                    canvas.painted.connect(lambda: paints.append(True))
                    js = h.engine.newQObject(canvas)
                    for _ in range(5):
                        result = js.property('imageReady').callWithInstance(js, [])
                        self.assertFalse(result.isError(), result.toString())
                h.QTest.qWait(50)
                self.assertEqual(paints, [], 'Already loaded images must not be rasterized again')

    def test_adjacent_single_previews_remain_cached(self):
        for style in ('spotlight', 'browser'):
            with self.subTest(style=style), grid_picker(count=12, style=style) as h:
                h.root.setProperty('liveEnabled', False)
                h.QTest.qWait(250)
                def tile(index):
                    return next((item for item in h.items() if item.objectName() == 'alternativeTile'
                                 and item.property('wallpaperIndex') == index), None)
                original = tile(0)
                neighbor = tile(1)
                self.assertIsNotNone(neighbor)
                h.call('choose', 1)
                h.wait(lambda: h.root.property('displayedIndex') == 1)
                h.call('choose', 0)
                h.wait(lambda: h.root.property('displayedIndex') == 0)
                self.assertEqual(tile(0), original)
                self.assertEqual(tile(1), neighbor)
                self.assertLessEqual(sum(item.objectName() == 'alternativeTile' for item in h.items()), 4)

    def test_empty_and_single_wallpaper_libraries(self):
        from PySide6.QtCore import Qt
        for style in ('spotlight', 'filmstrip', 'browser'):
            for count in (0, 1):
                with self.subTest(style=style, count=count), grid_picker(count=count, style=style) as h:
                    self.assertEqual(h.find('gridPageIndicator').property('text'), '1 / 1' if count else '0 / 0')
                    self.assertFalse(h.find('nextButton').isEnabled())
                    self.assertEqual(h.find('applyButton').isEnabled(), bool(count))
                    h.QTest.keyClick(h.root, Qt.Key_Escape)
                    self.assertEqual(h.writes[-1]['action'], 'cancel')

    def test_gear_opens_a_separate_window_and_returns_to_picker(self):
        from PySide6.QtCore import Qt, QPointF, QObject
        for style in ('carousel', 'grid', 'spotlight', 'filmstrip', 'browser'):
            with self.subTest(style=style), grid_picker(count=3, style=style) as h:
                gear = h.find('pickerSettingsButton')
                h.root.setProperty('showActionButtons', False)
                self.assertTrue(gear.isVisible(), 'Settings stays available when action buttons are hidden')
                point = gear.mapToScene(QPointF(gear.width()/2, gear.height()/2)).toPoint()
                h.QTest.mouseClick(h.root, Qt.LeftButton, Qt.NoModifier, point)
                h.wait(lambda: h.root.property('settingsOpen'))
                self.assertFalse(h.root.isVisible())
                h.wait(lambda: not h.warnings)
                settings = h.root.findChild(QObject, 'pickerSettingsWindow')
                self.assertIsNotNone(settings)
                h.wait(settings.isVisible)
                settings.close()
                h.wait(lambda: not h.root.property('settingsOpen'))
                self.assertFalse(h.root.property('settingsOpen'))
                self.assertTrue(h.root.isVisible())
                self.assertFalse(any(item['action'] == 'cancel' for item in h.writes), 'Opening settings must not cancel the preview session')
