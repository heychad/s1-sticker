"""Non-printing checks for the standalone Vretti renderer."""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest
from PIL import Image, ImageDraw

BINARY = Path(os.environ.get('VRETTI_TEST_BINARY', Path(__file__).resolve().parents[1] / '.build-vretti/VrettiPrint.app/Contents/MacOS/VrettiPrint'))


class VrettiRenderTests(unittest.TestCase):
    def run_cli(self, *args):
        result = subprocess.run([str(BINARY), *map(str, args)], capture_output=True, text=True, timeout=30)
        return result, json.loads(result.stdout)

    def test_image_fits_full_page_and_stays_upright(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / 'source.png'; output = root / 'preview.png'
            image = Image.new('RGB', (300, 200), 'white')
            ImageDraw.Draw(image).rectangle((10, 10, 60, 50), fill='black')
            image.save(source)
            result, receipt = self.run_cli('--render', source, '--output', output)
            self.assertEqual(result.returncode, 0, receipt)
            self.assertFalse(receipt['sent'])
            preview = Image.open(output).convert('L')
            self.assertEqual(preview.size, (812, 1218))
            self.assertEqual(set(preview.getdata()), {0, 255})
            x0, y0, x1, y1 = preview.point(lambda x: 255 if x < 128 else 0).getbbox()
            self.assertLess(x1, 406)
            self.assertLess(y1, 609)

    def test_rejects_overflow_and_source_overwrite_without_printing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / 'long.txt'; source.write_text('line\n' * 500)
            result, receipt = self.run_cli('--render', source, '--output', root / 'preview.png')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(receipt['sent'])
            self.assertIn('exceeds', receipt['message'])
            original = source.read_bytes()
            result, receipt = self.run_cli('--render', source, '--output', source)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(source.read_bytes(), original)
            self.assertFalse(receipt['sent'])

    def test_export_reconstructs_multiblock_page_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / 'source.png'; output = root / 'preview.png'; zpl = root / 'page.zpl'
            image = Image.new('RGB', (812, 1218), 'white'); d = ImageDraw.Draw(image)
            d.rectangle((10, 10, 800, 1200), fill='black'); image.save(source)
            result, receipt = self.run_cli('--render', source, '--output', output, '--zpl-output', zpl)
            self.assertEqual(result.returncode, 0, receipt)
            raw = zpl.read_bytes(); parts = list(re.finditer(rb'\^FO(\d+),(\d+)\^GFA,(\d+),(\d+),(\d+),([0-9A-F]+)\^FS', raw))
            self.assertGreaterEqual(len(parts), 2)
            canvas = Image.new('1', (812, 1218), 1)
            for part in parts:
                x, y, count, size, stride = map(int, part.groups()[:5]); bits = bytes.fromhex(part.group(6).decode())
                self.assertEqual(len(bits), count); self.assertEqual(count, size); self.assertLessEqual(count, 60000)
                block = Image.frombytes('1', (stride * 8, count // stride), bytes(255 - byte for byte in bits))
                canvas.paste(block, (x, y))
            self.assertEqual(canvas.convert('L').tobytes(), Image.open(output).convert('L').tobytes())


if __name__ == '__main__': unittest.main()
