import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "import_source", Path(__file__).with_name("import_source.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ImportSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def archive(self, entries, name="Microgen-0.1.0-source.zip"):
        with zipfile.ZipFile(self.root / name, "w") as z:
            for path, content in entries:
                z.writestr(path, content)

    def test_waits_without_archive(self):
        self.assertFalse(module.import_source(self.root)["ready"])

    def test_imports_project_and_preserves_signing_bytes(self):
        self.archive([("Microgen-0.1.0/project.godot", "config_version=5"),
                      ("Microgen-0.1.0/main.gd", "extends Node2D"),
                      ("Microgen-0.1.0/tools/development.keystore", b"\x00\xff")])
        result = module.import_source(self.root)
        self.assertTrue(result["ready"])
        self.assertEqual(len(result["imported"]), 3)
        self.assertEqual((self.root / "tools/development.keystore").read_bytes(), b"\x00\xff")

    def test_existing_project_is_not_overwritten(self):
        (self.root / "project.godot").write_text("existing")
        self.archive([("project.godot", "replacement")])
        self.assertFalse(module.import_source(self.root)["imported"])
        self.assertEqual((self.root / "project.godot").read_text(), "existing")

    def test_rejects_traversal_before_writing(self):
        self.archive([("project/project.godot", "valid"),
                      ("project/../escape", "invalid")])
        with self.assertRaises(ValueError):
            module.import_source(self.root)
        self.assertFalse((self.root / "project.godot").exists())

    def test_does_not_replace_workflow(self):
        (self.root / ".github/workflows").mkdir(parents=True)
        existing = self.root / ".github/workflows/android.yml"
        existing.write_text("keep")
        self.archive([("p/project.godot", "valid"),
                      ("p/.github/workflows/android.yml", "replace"),
                      ("p/ci/import_source.py", "replace")])
        self.assertTrue(module.import_source(self.root)["ready"])
        self.assertEqual(existing.read_text(), "keep")
        self.assertFalse((self.root / "ci/import_source.py").exists())

    def test_rejects_ambiguous_archives(self):
        self.archive([("project.godot", "one")], "first-source.zip")
        self.archive([("project.godot", "two")], "second-source.zip")
        with self.assertRaises(ValueError):
            module.import_source(self.root)

if __name__ == "__main__":
    unittest.main()
