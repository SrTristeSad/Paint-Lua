import json
import tempfile
import unittest
from pathlib import Path
from PIL import Image
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from compare_screenshots import compare


class CompareScreenshotsTest(unittest.TestCase):
    def test_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            ref, actual = base / "ref.png", base / "actual.png"
            Image.new("RGB", (4, 4), (50, 90, 120)).save(ref)
            Image.new("RGB", (4, 4), (50, 90, 120)).save(actual)
            result = compare(ref, actual, base / "out")
            self.assertEqual(result["identical_pixels"], 16)
            self.assertEqual(result["mae_rgb_0_to_255"], 0)
            self.assertTrue((base / "out" / "overlay.png").exists())
            self.assertTrue((base / "out" / "difference.png").exists())
            self.assertEqual(json.loads((base / "out" / "metrics.json").read_text())["width"], 4)

    def test_difference(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            ref, actual = base / "ref.png", base / "actual.png"
            Image.new("RGB", (2, 2), "black").save(ref)
            Image.new("RGB", (2, 2), "white").save(actual)
            result = compare(ref, actual, base / "out")
            self.assertEqual(result["identical_pixels"], 0)
            self.assertEqual(result["mae_rgb_0_to_255"], 255)

    def test_rejects_incompatible_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            ref, actual = base / "ref.png", base / "actual.png"
            Image.new("RGB", (2, 2), "black").save(ref)
            Image.new("RGB", (3, 2), "black").save(actual)
            with self.assertRaises(ValueError):
                compare(ref, actual, base / "out")


if __name__ == "__main__":
    unittest.main()
