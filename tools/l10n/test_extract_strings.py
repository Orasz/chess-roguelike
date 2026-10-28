import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from . import extract_strings


class ExtractStringsTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.root = Path(self._dir.name) / "game"
        self.root.mkdir()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def entries(self):
        return [(e.context, e.message) for e in extract_strings.extract(self.root)]

    def test_collects_tr_calls_with_and_without_context(self):
        self.write("a.gd", (
            'func f() -> void:\n'
            '\tvar a := tr("Plain")\n'
            '\tvar b := _translator.tr("Piece", "lost piece") + str(1)\n'
            '\tvar c := tr("Say \\"hi\\"\\n%s") % x\n'
            '\t# tr("Commented out")\n'
            '\tvar d := tr(\n\t\t"Over lines"\n\t)\n'
        ))
        self.assertEqual(
            self.entries(),
            [("", "Over lines"), ("", "Plain"), ("", 'Say "hi"\n%s'), ("lost piece", "Piece")],
        )

    def test_collects_scene_texts(self):
        self.write("s.tscn", (
            '[node name="Title" type="Label" parent="."]\n'
            'text = "Chess Roguelike"\n'
            'autowrap_mode = 3\n'
            '[node name="Box" type="Label" parent="."]\n'
            'text = "Two\nlines"\n'
            '[node name="Empty" type="Label" parent="."]\n'
            'text = ""\n'
        ))
        self.assertEqual(self.entries(), [("", "Chess Roguelike"), ("", "Two\nlines")])

    def test_skips_tests_addons_and_the_android_build_template(self):
        self.write("kept/a.gd", 'var a := tr("Kept")\n')
        skipped_files = (
            "addons/gut/a.gd", "test/unit/a.gd", "tools/a.gd", "spike/a.gd", "spike/a.tscn",
            "android/build/a.gd", "android/build/a.tscn",
        )
        for skipped in skipped_files:
            self.write(skipped, 'var a := tr("Skipped")\ntext = "Skipped"\n')
        self.assertEqual(self.entries(), [("", "Kept")])

    def test_a_call_that_is_not_a_literal_is_an_error(self):
        self.write("a.gd", 'var a := tr(name)\n')
        with self.assertRaises(extract_strings.ExtractError):
            extract_strings.extract(self.root)

    def test_output_is_sorted_and_stable(self):
        self.write("b.gd", 'var a := tr("Zebra")\nvar b := tr("Apple", "ctx")\nvar c := tr("Apple")\n')
        self.write("a.tscn", 'text = "Mango"\ntext = "Apple"\n')
        first = extract_strings.render_pot(extract_strings.extract(self.root))
        second = extract_strings.render_pot(extract_strings.extract(self.root))
        self.assertEqual(first, second)
        order = [line for line in first.splitlines() if line.startswith("msgid ") and line != 'msgid ""']
        self.assertEqual(order, ['msgid "Apple"', 'msgid "Mango"', 'msgid "Zebra"', 'msgid "Apple"'])
        self.assertIn('msgctxt "ctx"\nmsgid "Apple"\nmsgstr ""\n', first)
        self.assertNotIn(":", "".join(l for l in first.splitlines() if l.startswith("#")))

    def test_check_fails_on_a_stale_catalog(self):
        self.write("a.gd", 'var a := tr("One")\n')
        pot = Path(self._dir.name) / "messages.pot"
        pot.write_text(extract_strings.render_pot(extract_strings.extract(self.root)), encoding="utf-8")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(extract_strings.main([str(self.root), "--check", str(pot)]), 0)
            self.write("a.gd", 'var a := tr("One")\nvar b := tr("Two")\n')
            self.assertEqual(extract_strings.main([str(self.root), "--check", str(pot)]), 1)
            self.assertEqual(extract_strings.main([str(self.root), "--check", str(pot.with_name("missing.pot"))]), 1)


if __name__ == "__main__":
    unittest.main()
