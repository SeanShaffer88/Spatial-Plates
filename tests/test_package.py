"""Package-layout regressions. Run with: python3 tests/test_package.py"""
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from package_release import PACKAGE_FILES, build, get_version  # noqa: E402


class ReleasePackageTests(unittest.TestCase):
    def test_version_is_consistent_and_archive_has_installable_root(self):
        version = get_version()
        with tempfile.TemporaryDirectory() as temp_dir:
            archive_path = build(Path(temp_dir) / f"SpatialPlates-{version}.zip")
            with zipfile.ZipFile(archive_path) as archive:
                names = set(archive.namelist())
                expected = {f"SpatialPlates/{filename}" for filename in PACKAGE_FILES}
                self.assertEqual(names, expected)
                self.assertIn("SpatialPlates/SpatialPlates.toc", names)
                self.assertNotIn("Spatial-Plates/SpatialPlates.toc", names)
                self.assertFalse(any(name.startswith("SpatialPlates/SpatialPlates/") for name in names))


if __name__ == "__main__":
    unittest.main()
