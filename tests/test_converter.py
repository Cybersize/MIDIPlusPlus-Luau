from pathlib import Path
import base64
import importlib.util
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("midi_converter", ROOT / "Convert-MIDI.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class ConverterTests(unittest.TestCase):
    def test_all_byte_values_roundtrip_and_original_stays_unchanged(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "binary.mid"
            original = b"MThd" + bytes(range(256))
            path.write_bytes(original)
            sidecar, changed = converter.convert_file(path)
            self.assertTrue(changed)
            self.assertEqual(base64.b64decode(sidecar.read_bytes()), original)
            self.assertEqual(path.read_bytes(), original)
            self.assertTrue(sidecar.read_bytes().isascii())

    def test_unchanged_sidecars_are_not_rewritten(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "song.mid"
            path.write_bytes(b"MThd\0\x1a\r\n\xff")
            sidecar, _ = converter.convert_file(path)
            before = sidecar.stat().st_mtime_ns
            _, changed = converter.convert_file(path)
            self.assertFalse(changed)
            self.assertEqual(sidecar.stat().st_mtime_ns, before)

    def test_invalid_files_do_not_create_sidecars(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "bad.mid"
            path.write_bytes(b"not MIDI")
            with self.assertRaises(ValueError):
                converter.convert_file(path)
            self.assertFalse(path.with_name("bad.mid.b64").exists())

    def test_folder_cli_filters_non_midi_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "song.mid"
            source.write_bytes(b"MThd\0\x1a\xff")
            unrelated = Path(folder) / "keep.txt"
            unrelated.write_text("keep", encoding="ascii")
            for _ in range(2):
                result = subprocess.run([sys.executable, str(ROOT / "Convert-MIDI.py"), folder],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(unrelated.read_text(), "keep")
            self.assertFalse(Path(str(unrelated) + ".b64").exists())


if __name__ == "__main__":
    unittest.main()
