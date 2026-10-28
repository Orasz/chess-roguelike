import contextlib
import io
import tempfile
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


class MainTest(unittest.TestCase):
    def run_main(self, *arguments):
        out, err = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "export_presets.cfg"
            path.write_text(SAMPLE, encoding="utf-8")
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = preset.main(["preset.py", str(path), *arguments])
        return code, out.getvalue(), err.getvalue()

    def test_it_prints_one_line_per_key_in_the_order_given(self):
        code, out, _ = self.run_main("Android Play", "version/name", "version/code")
        self.assertEqual((code, out), (0, "1.2.3\n3\n"))

    def test_an_unknown_key_or_preset_exits_with_1_and_says_so_on_stderr(self):
        code, out, err = self.run_main("Android Play", "version/nope")
        self.assertEqual((code, out), (1, ""))
        self.assertIn("version/nope", err)
        self.assertEqual(self.run_main("Nope", "version/code")[0], 1)

    def test_too_few_arguments_is_a_usage_error(self):
        self.assertEqual(self.run_main("Android Play")[0], 2)


if __name__ == "__main__":
    unittest.main()
