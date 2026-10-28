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


if __name__ == "__main__":
    unittest.main()
