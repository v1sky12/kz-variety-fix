import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import zipfile

import zstandard

from install_kz_variety_fix import install, replace_place, rollback
from rbxl_container import ContainerError, chunks, property_header, replace_source_arrays, validate

ROOT = Path(__file__).resolve().parents[1]


def damage_source_length(data: bytes) -> bytes:
    out = [data[:32]]
    changed = False
    for chunk in chunks(data):
        if not changed and chunk.tag == b"PROP":
            _, name, kind, offset = property_header(chunk.payload)
            if name == b"Source" and kind == 1:
                payload = bytearray(chunk.payload)
                size = struct.unpack_from("<I", payload, offset)[0]
                struct.pack_into("<I", payload, offset, size + 1)
                encoded = zstandard.ZstdCompressor().compress(payload)
                out.append(chunk.tag + struct.pack("<III", len(encoded), len(payload), 0) + encoded)
                changed = True
                continue
        out.append(chunk.encoded)
    assert changed
    return b"".join(out)


class ContainerAndInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.place = (ROOT / "kz_variety_fix.rbxl").read_bytes()
        cls.report = validate(cls.place)
        cls.damaged = damage_source_length(cls.place)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def package(self, data):
        path = self.root / "update.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("kz_variety_fix.rbxl", data)
        return path

    def test_actual_place_structure_is_complete(self):
        self.assertEqual(self.report["scripts"], 428)
        self.assertEqual(self.report["instances"], 135676)
        self.assertEqual(self.report["classes"], 92)

    def test_stale_source_length_is_detected(self):
        with self.assertRaises(ContainerError):
            validate(self.damaged)

    def test_unicode_source_is_serialized_with_byte_length(self):
        source = self.report["sources"][17034] + "\n-- проверка длины\n".encode()
        modified = validate(replace_source_arrays(self.place, {17034: source}))
        self.assertEqual(modified["sources"][17034], source)
        for instance, before in self.report["sources"].items():
            if instance != 17034:
                self.assertEqual(modified["sources"][instance], before)

    def test_bad_utf8_source_is_rejected(self):
        with self.assertRaises(ContainerError):
            replace_source_arrays(self.place, {17034: b"--\xff"})

    def test_missing_footer_and_trailing_data_are_rejected(self):
        for data in (self.place[:-1], self.place + b"garbage"):
            with self.subTest(size=len(data)), self.assertRaises(ContainerError):
                validate(data)

    def test_unknown_script_replacement_is_rejected(self):
        with self.assertRaises(ContainerError):
            replace_source_arrays(self.place, {-10: b"return {}"})

    def test_invalid_place_never_overwrites_existing_destination(self):
        target = self.root / "map.rbxl"
        target.write_bytes(self.place)
        with self.assertRaises(ContainerError):
            install(self.package(self.damaged), target)
        self.assertEqual(target.read_bytes(), self.place)
        self.assertEqual(list(self.root.glob("*.backup-*")), [])

    def test_first_install_has_no_phantom_backup(self):
        target = self.root / "new/map.rbxl"
        self.assertIsNone(install(self.package(self.place), target))
        self.assertEqual(target.read_bytes(), self.place)

    def test_install_and_rollback_preserve_both_versions(self):
        changed = replace_source_arrays(self.place, {17034: self.report["sources"][17034] + b"\n-- v2\n"})
        target = self.root / "map.rbxl"
        target.write_bytes(self.place)
        backup = install(self.package(changed), target)
        self.assertEqual(backup.read_bytes(), self.place)
        self.assertEqual(target.read_bytes(), changed)
        undone = rollback(backup, target)
        self.assertEqual(target.read_bytes(), self.place)
        self.assertEqual(undone.read_bytes(), changed)

    def test_repeated_backups_have_unique_names(self):
        target = self.root / "map.rbxl"
        target.write_bytes(self.place)
        one = replace_place(self.place, target)
        two = replace_place(self.place, target)
        self.assertNotEqual(one, two)
        self.assertTrue(one.exists() and two.exists())

    def test_failed_atomic_replace_leaves_original_intact(self):
        target = self.root / "map.rbxl"
        target.write_bytes(self.place)
        with patch("install_kz_variety_fix.os.replace", side_effect=OSError("simulated interruption")):
            with self.assertRaises(OSError):
                replace_place(self.place, target)
        self.assertEqual(target.read_bytes(), self.place)

    def test_archive_with_two_places_is_rejected(self):
        archive = self.package(self.place)
        with zipfile.ZipFile(archive, "a") as handle:
            handle.writestr("other.rbxl", self.place)
        with self.assertRaises(ValueError):
            install(archive, self.root / "map.rbxl")


if __name__ == "__main__":
    unittest.main()
