"""Unit tests for structural Brush screenshot validation."""
import unittest
from PIL import Image

from tools.check_ui_screenshots import ScreenshotCheckError, check_brush_layout, check_tool_rail_layout


class BrushLayoutCheckTests(unittest.TestCase):
    def test_accepts_light_left_dark_right(self):
        im = Image.new("RGB", (1024, 768), (45, 45, 45))
        # Draw the left panel white and the expected split remains dark.
        from PIL import ImageDraw
        draw = ImageDraw.Draw(im)
        draw.rectangle((172, 94, 461, 708), fill=(250, 250, 250))
        check_brush_layout(im)

    def test_rejects_uniform_panel(self):
        im = Image.new("RGB", (1024, 768), (60, 60, 60))
        with self.assertRaises(ScreenshotCheckError):
            check_brush_layout(im)

    def test_rejects_small_screenshots(self):
        im = Image.new("RGB", (200, 100), (255, 255, 255))
        with self.assertRaises(ScreenshotCheckError):
            check_brush_layout(im)

    def test_tool_rail_left_right_and_popup(self):
        from PIL import ImageDraw

        left = Image.new("RGB", (1024, 768), (190, 190, 190))
        ImageDraw.Draw(left).rectangle((0, 0, 59, 689), fill=(95, 95, 95))
        check_tool_rail_layout(left, "left")
        with self.assertRaises(ScreenshotCheckError):
            check_tool_rail_layout(left, "popup")

        right = Image.new("RGB", (1024, 768), (190, 190, 190))
        ImageDraw.Draw(right).rectangle((965, 0, 1023, 689), fill=(95, 95, 95))
        check_tool_rail_layout(right, "right")
        with self.assertRaises(ScreenshotCheckError):
            check_tool_rail_layout(right, "left")

        popup = Image.new("RGB", (1024, 768), (190, 190, 190))
        check_tool_rail_layout(popup, "popup")
        with self.assertRaises(ScreenshotCheckError):
            check_tool_rail_layout(popup, "right")

    def test_invalid_rail_geometry_rejected(self):
        small = Image.new("RGB", (640, 480), (190, 190, 190))
        with self.assertRaises(ScreenshotCheckError):
            check_tool_rail_layout(small, "left")
        standard = Image.new("RGB", (1024, 768), (190, 190, 190))
        with self.assertRaises(ValueError):
            check_tool_rail_layout(standard, "unknown")


if __name__ == "__main__":
    unittest.main()
