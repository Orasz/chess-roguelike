import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

MAKEFILE = Path(__file__).resolve().parents[2] / "Makefile"

# Stands in for Godot. `--version` prints a version; `--install-android-build-template` writes what
# FAKE_MODE says and then fails, like the real export that is made to fail on purpose.
FAKE_GODOT = """#!/bin/sh
case "$*" in
  *--version*) [ -n "$FAKE_VERSION" ] && echo "$FAKE_VERSION.official.abc"; exit 0;;
  *--install-android-build-template*)
    mkdir -p game/android/build/libs/release
    echo "$FAKE_VERSION" > game/android/.build_version
    if [ "$FAKE_MODE" = full ]; then
      echo x > game/android/build/build.gradle
      echo x > game/android/build/gradlew; chmod +x game/android/build/gradlew
      echo x > game/android/build/libs/release/godot-lib.template_release.aar
    elif [ "$FAKE_MODE" = partial ]; then
      echo x > game/android/build/build.gradle
    fi
    echo "ERROR: export failed" >&2; exit 1;;
esac
exit 0
"""


class AndroidTemplateTargetTest(unittest.TestCase):
    """`make android-template` run in a scratch directory with a fake Godot: no real template is touched."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "game").mkdir()
        shutil.copy(MAKEFILE, self.root / "Makefile")
        self.godot = self.root / "fakegodot"
        self.godot.write_text(FAKE_GODOT, encoding="utf-8")
        self.godot.chmod(0o755)
        self.sentinel = self.root / "game" / "android" / ".installed-by-make"

    def make(self, mode, version="4.7.2.stable"):
        env = dict(os.environ, FAKE_MODE=mode, FAKE_VERSION=version)
        return subprocess.run(
            ["make", "-s", "android-template", f"GODOT={self.godot}"],
            cwd=self.root, env=env, capture_output=True, text=True,
        )

    def test_a_complete_install_writes_the_sentinel_with_the_godot_version(self):
        done = self.make("full")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.sentinel.read_text().strip(), "4.7.2.stable")

    def test_an_interrupted_install_fails_and_is_retried_on_the_next_run(self):
        first = self.make("partial")
        self.assertNotEqual(first.returncode, 0)
        self.assertIn("completely", first.stdout)
        self.assertFalse(self.sentinel.exists())
        # Godot's own .build_version is there with the right version, and still the template is not "up to date".
        self.assertEqual((self.root / "game/android/.build_version").read_text().strip(), "4.7.2.stable")
        self.assertNotEqual(self.make("partial").returncode, 0)
        self.assertEqual(self.make("full").returncode, 0)
        self.assertTrue(self.sentinel.exists())

    def test_a_complete_template_is_left_alone(self):
        self.make("full")
        marker = self.root / "game/android/build/marker"
        marker.write_text("kept")
        self.assertEqual(self.make("none").returncode, 0)
        self.assertTrue(marker.exists())

    def test_another_godot_version_reinstalls(self):
        self.make("full")
        marker = self.root / "game/android/build/marker"
        marker.write_text("gone")
        self.assertEqual(self.make("full", version="4.8.0.stable").returncode, 0)
        self.assertFalse(marker.exists())
        self.assertEqual(self.sentinel.read_text().strip(), "4.8.0.stable")

    def test_an_unreadable_godot_version_stops_before_anything_is_deleted(self):
        self.make("full")
        marker = self.root / "game/android/build/marker"
        marker.write_text("kept")
        done = self.make("full", version="")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("cannot read the Godot version", done.stdout)
        self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
