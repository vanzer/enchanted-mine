"""Regression checks for archive leakage and shader include boundaries."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

from package import build
from shader_sources import expand_shader


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.shaders = self.root / "shaders"
        self.shaders.mkdir()
        (self.shaders / "lib").mkdir()
        (self.shaders / "lib/settings.glsl").write_text("#define STEPS 32\n")
        (self.shaders / "final.vsh").write_text('#version 120\n#include "/lib/settings.glsl"\n')
        (self.shaders / "final.fsh").write_text("#version 120\nvoid main() {}\n")
        (self.root / "README.md").write_text("Test documentation\n")
        (self.root / "LICENSE").write_text("Test license\n")

    def test_archive_layout_content_and_reproducibility(self):
        output = build(self.root)
        before = output.read_bytes()
        with ZipFile(output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(set(archive.namelist()), {
                "README.md", "LICENSE", "shaders/final.vsh", "shaders/final.fsh",
                "shaders/lib/settings.glsl",
            })
            self.assertEqual(archive.read("shaders/final.vsh"), (self.shaders / "final.vsh").read_bytes())
        os.utime(self.shaders / "final.vsh", (1700000000, 1700000000))
        self.assertEqual(build(self.root).read_bytes(), before)

    def test_hidden_and_unknown_files_rejected_without_replacing_archive(self):
        output = build(self.root)
        before = output.read_bytes()
        for name in (".env", "lib/.secret.glsl", "notes.txt", "payload.exe"):
            with self.subTest(name=name):
                path = self.shaders / name
                path.write_text("dummy test data")
                try:
                    with self.assertRaises(ValueError):
                        build(self.root)
                    self.assertEqual(output.read_bytes(), before)
                finally:
                    path.unlink()

    def test_shader_file_and_directory_symlinks_rejected(self):
        outside = self.root / "dummy.glsl"
        outside.write_text("dummy external data")
        for name, target in (("leak.glsl", outside), ("linked", self.root),
                             ("missing.glsl", self.root / "missing")):
            with self.subTest(name=name):
                link = self.shaders / name
                link.symlink_to(target, target_is_directory=target.is_dir())
                try:
                    with self.assertRaises(ValueError):
                        build(self.root)
                finally:
                    link.unlink()

    def test_shader_root_symlink_rejected(self):
        actual = self.root / "actual-shaders"
        self.shaders.rename(actual)
        self.shaders.symlink_to(actual, target_is_directory=True)
        with self.assertRaises(ValueError):
            build(self.root)

    def test_output_directory_symlink_rejected(self):
        actual = self.root / "actual-dist"
        actual.mkdir()
        (self.root / "dist").symlink_to(actual, target_is_directory=True)
        with self.assertRaises(ValueError):
            build(self.root)
        self.assertEqual(list(actual.iterdir()), [])

    def test_output_archive_symlink_rejected(self):
        destination = self.root / "dist"
        destination.mkdir()
        outside = self.root / "untouched.zip"
        outside.write_bytes(b"dummy original")
        (destination / "EnchantedMine.zip").symlink_to(outside)
        with self.assertRaises(ValueError):
            build(self.root)
        self.assertEqual(outside.read_bytes(), b"dummy original")

    def test_document_symlink_rejected(self):
        document = self.root / "README.md"
        document.unlink()
        document.symlink_to(self.root / "LICENSE")
        with self.assertRaises(ValueError):
            build(self.root)

    def test_missing_pair_rejected(self):
        (self.shaders / "final.fsh").unlink()
        with self.assertRaises(ValueError):
            build(self.root)

    def test_include_expansion_and_settings(self):
        source = expand_shader(self.shaders / "final.vsh", self.shaders, {"STEPS": 64})
        self.assertIn("#define STEPS 64", source)
        self.assertNotIn("#include", source)
        (self.shaders / "lib/relative.glsl").write_text('#include "settings.glsl"\n')
        self.assertIn("#define STEPS 32", expand_shader(self.shaders / "lib/relative.glsl", self.shaders))

    def test_include_escape_and_cycle_rejected(self):
        path = self.shaders / "final.vsh"
        for include in ("../dummy.glsl", "/../dummy.glsl", "/final.vsh", "lib/../../dummy.glsl",
                        "lib\\settings.glsl"):
            with self.subTest(include=include):
                path.write_text(f'#include "{include}"\n')
                with self.assertRaises(ValueError):
                    build(self.root)

    def test_failed_write_keeps_previous_archive_and_cleans_temporary_file(self):
        output = build(self.root)
        before = output.read_bytes()
        with patch("package.os.replace", side_effect=OSError("simulated write failure")):
            with self.assertRaises(OSError):
                build(self.root)
        self.assertEqual(output.read_bytes(), before)
        self.assertEqual(list(output.parent.iterdir()), [output])

    def test_branching_includes_have_a_total_expansion_limit(self):
        previous = "settings.glsl"
        for index in range(13):
            name = f"branch{index}.glsl"
            (self.shaders / "lib" / name).write_text(f'#include "{previous}"\n#include "{previous}"\n')
            previous = name
        with self.assertRaisesRegex(ValueError, "budget exceeded"):
            expand_shader(self.shaders / "lib" / previous, self.shaders)

    def test_include_byte_budget_counts_repeated_files(self):
        path = self.shaders / "final.vsh"
        path.write_text('#include "/lib/settings.glsl"\n' * 4)
        # Each individual file fits, but repeated includes exhaust the total budget.
        with patch("shader_sources.MAX_SOURCE_BYTES", path.stat().st_size + 30):
            with self.assertRaisesRegex(ValueError, "budget exceeded"):
                expand_shader(path, self.shaders)


if __name__ == "__main__":
    unittest.main()
