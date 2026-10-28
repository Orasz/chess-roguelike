import unittest
from pathlib import Path

from . import preset

CFG = Path(__file__).resolve().parents[2] / "game" / "export_presets.cfg"

SAMPLE = """\
[preset.0]

name="Android Dev"
export_path="../build/dev.apk"

[preset.0.options]

package/unique_name="io.example.dev"
version/code=7

[preset.1]

name="Android Play"

[preset.1.options]

package/unique_name="io.example.play"
version/code=3
version/name="1.2.3"
"""


class ReadOptionsTest(unittest.TestCase):
    def test_the_options_belong_to_the_preset_with_that_name(self):
        options = preset.read_options(SAMPLE, "Android Play")
        self.assertEqual(options["package/unique_name"], "io.example.play")
        self.assertEqual(options["version/code"], "3")
        self.assertEqual(options["version/name"], "1.2.3")

    def test_an_unknown_preset_is_an_error(self):
        with self.assertRaises(KeyError):
            preset.read_options(SAMPLE, "Nope")

    def test_the_real_play_preset_carries_the_identity_and_the_version(self):
        options = preset.read_options(CFG.read_text(encoding="utf-8"), "Android Play")
        self.assertEqual(options["package/unique_name"], "io.github.orasz.chessroguelike")
        self.assertTrue(options["version/code"].isdigit())
        self.assertTrue(options["version/name"])


if __name__ == "__main__":
    unittest.main()
