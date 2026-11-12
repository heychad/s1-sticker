"""Exercise the installed renderer with asymmetric, tonal fixtures; never prints."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from PIL import Image, ImageDraw

BINARY = Path(os.environ.get("S1_TEST_BINARY",str(Path.home() / "Applications/S1 Sticker.app/Contents/MacOS/S1Sticker")))

class RenderingTests(unittest.TestCase):
    def render(self, source, destination, rotation, dither=False):
        command = [str(BINARY), "--render", str(source), "--output", str(destination), "--rotate", rotation]
        if dither:
            command.append("--dither")
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        return json.loads(result.stdout), Image.open(destination).convert("L")

    def test_asymmetric_rotations_and_auto(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = Image.new("RGB", (200, 100), "white")
            ImageDraw.Draw(source).rectangle((10, 10, 49, 34), fill="black")
            source.save(root / "source.png")
            for rotation, quadrant in [("0", (False, False)), ("90", (True, False)), ("180", (True, True)), ("270", (False, True)), ("auto", (True, False))]:
                info, image = self.render(root / "source.png", root / "out.png", rotation)
                self.assertEqual(info["rotation"], 90 if rotation == "auto" else int(rotation))
                self.assertEqual(image.width, 384)
                self.assertLessEqual(image.height, 802 if rotation in ("90", "270", "auto") else 226)
                mask = image.point(lambda value: 255 if value < 128 else 0)
                x0, y0, x1, y1 = mask.getbbox()
                self.assertEqual((x0 + x1) / 2 > image.width / 2, quadrant[0])
                self.assertEqual(y0,0)
                self.assertEqual(y1-y0>x1-x0,rotation in ("90","270","auto"))
                self.assertTrue(set(image.tobytes()) <= {0, 255})

    def test_grayscale_becomes_half_black_dots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            Image.new("RGB", (384, 200), (128, 128, 128)).save(root / "gray.png")
            _, dithered = self.render(root / "gray.png", root / "dots.png", "0", True)
            _, sharp = self.render(root / "gray.png", root / "sharp.png", "0")
            pixels = list(dithered.crop((10, 10, 374, 190)).tobytes())
            self.assertAlmostEqual(pixels.count(0) / len(pixels), 0.5, delta=0.03)
            self.assertEqual(set(pixels), {0, 255})
            self.assertEqual(set(sharp.crop((10, 10, 374, 190)).tobytes()), {0})

if __name__ == "__main__":
    unittest.main()
