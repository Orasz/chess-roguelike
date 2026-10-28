import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class LegalCopiesTest(unittest.TestCase):
    """The About screen shows the copies in game/legal/, which the export ships. They must be the
    repository's own files: `make legal` refreshes them."""

    def test_shipped_copies_match_the_repository_files(self):
        for source, shipped in [("LICENSE", "game/legal/GPL-3.0.txt"), ("CREDITS.md", "game/legal/CREDITS.md")]:
            with self.subTest(shipped=shipped):
                self.assertTrue((ROOT / shipped).is_file(), f"{shipped} is missing: run `make legal`")
                self.assertEqual(
                    (ROOT / source).read_bytes(),
                    (ROOT / shipped).read_bytes(),
                    f"{shipped} differs from {source}: run `make legal`",
                )


class CreditsTest(unittest.TestCase):
    """CREDITS.md lists what the Play bundle ships besides our own code, and says where its licence texts are."""

    def test_the_android_libraries_the_export_template_bundles_are_credited(self):
        text = (ROOT / "CREDITS.md").read_text(encoding="utf-8")
        for name in [
            "androidx.fragment:fragment` 1.8.6",
            "core-splashscreen` 1.0.1",
            "documentfile` 1.1.0",
            "startup-runtime` 1.1.1",
            "profileinstaller` 1.3.1",
            "kotlin-stdlib` and `kotlin-stdlib-common` 2.1.21",
            "kotlinx-coroutines-core`",
        ]:
            with self.subTest(name=name):
                self.assertIn(name, text)
        self.assertIn("Apache-2.0", text)
        self.assertIn('"Licence texts"', text)


if __name__ == "__main__":
    unittest.main()
