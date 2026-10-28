import re
import struct
import unicodedata
import unittest
from pathlib import Path

STORE = Path(__file__).resolve().parents[2] / "store"
LOCALES = ["en-US", "it-IT"]
GITHUB_URL = "https://github.com/Orasz/chess-roguelike"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
COLOUR_TYPE_RGB = 2
COLOUR_TYPE_RGBA = 6

# Play's limits on the listing texts, in characters.
TITLE_MAX = 30
SHORT_MAX = 80
FULL_MAX = 4000
# Play's limits on the images, in pixels and bytes.
SCREENSHOT_SIDE_MIN = 320
SCREENSHOT_SIDE_MAX = 3840
ICON_MAX_BYTES = 1024 * 1024


def read_text(locale: str, name: str) -> str:
    """The raw text of a listing file, decoded strictly as UTF-8."""
    return (STORE / "listing" / locale / name).read_bytes().decode("utf-8")


def png_header(path: Path) -> tuple[int, int, int]:
    """The width, the height and the colour type of a PNG, read from its IHDR chunk."""
    data = path.read_bytes()
    assert data[:8] == PNG_SIGNATURE, f"{path} is not a PNG"
    length, kind = struct.unpack(">I4s", data[8:16])
    assert kind == b"IHDR" and length == 13, f"{path} does not start with an IHDR chunk"
    width, height, _depth, colour_type = struct.unpack(">IIBB", data[16:26])
    return width, height, colour_type


class ListingTextsTest(unittest.TestCase):
    def test_every_locale_has_the_three_files_as_plain_utf8_without_a_trailing_newline(self):
        for locale in LOCALES:
            for name in ["title.txt", "short_description.txt", "full_description.txt"]:
                with self.subTest(locale=locale, name=name):
                    text = read_text(locale, name)
                    self.assertTrue(text.strip(), "the file is empty")
                    self.assertEqual(text, text.rstrip("\r\n"), "the file ends with a newline")
                    self.assertEqual(text, text.strip(), "the file starts or ends with whitespace")

    def test_texts_fit_play_limits(self):
        for locale in LOCALES:
            with self.subTest(locale=locale):
                self.assertLessEqual(len(read_text(locale, "title.txt")), TITLE_MAX)
                self.assertLessEqual(len(read_text(locale, "short_description.txt")), SHORT_MAX)
                self.assertLessEqual(len(read_text(locale, "full_description.txt")), FULL_MAX)

    def test_the_title_is_the_same_in_both_languages(self):
        for locale in LOCALES:
            with self.subTest(locale=locale):
                self.assertEqual(read_text(locale, "title.txt"), "Chess Roguelike")

    def test_short_descriptions_have_no_symbols_or_emoji(self):
        # Letters, digits, spaces and plain punctuation only. Emoji and symbols (categories S*), arrows,
        # check marks and other pictograms all fall outside.
        plain_punctuation = " .,:;'-"
        for locale in LOCALES:
            with self.subTest(locale=locale):
                for char in read_text(locale, "short_description.txt"):
                    self.assertTrue(
                        unicodedata.category(char)[0] in "LN" or char in plain_punctuation,
                        f"{char!r} (U+{ord(char):04X}) is not allowed in a short description",
                    )

    def test_short_descriptions_make_no_call_to_action_ranking_or_price_claim(self):
        words = [
            "free", "gratis", "gratuito", "gratuita", "best", "migliore", "top", "number",
            "download", "scarica", "install", "installa", "play", "gioca", "try", "prova", "buy", "compra",
        ]
        for locale in LOCALES:
            with self.subTest(locale=locale):
                text = read_text(locale, "short_description.txt").lower()
                found = [word for word in words if re.search(rf"\b{word}\b", text)]
                self.assertEqual(found, [])
                self.assertNotIn("!", text)

    def test_full_descriptions_name_the_repository_and_the_three_data_sources(self):
        for locale in LOCALES:
            with self.subTest(locale=locale):
                text = read_text(locale, "full_description.txt")
                for needle in [GITHUB_URL, "GPLv3", "Lichess", "Stockfish", "Ninja Adventure", "Pixel Chess Pieces"]:
                    self.assertIn(needle, text)

    def test_listings_promise_no_feature_that_the_build_lacks(self):
        # There is no shop and there is nothing to unlock in the beta: the listing must not mention either.
        for locale in LOCALES:
            for name in ["title.txt", "short_description.txt", "full_description.txt"]:
                with self.subTest(locale=locale, name=name):
                    text = read_text(locale, name).lower()
                    for word in ["shop", "negozio", "unlock", "sblocc"]:
                        self.assertNotIn(word, text)

    def test_listings_carry_no_donation_link(self):
        for locale in LOCALES:
            for name in ["title.txt", "short_description.txt", "full_description.txt"]:
                with self.subTest(locale=locale, name=name):
                    text = read_text(locale, name).lower()
                    for word in ["donat", "sponsor", "ko-fi", "patreon", "paypal", "dona "]:
                        self.assertNotIn(word, text)

    def test_a_single_potion_claim_is_not_made_without_the_drops(self):
        # A run starts with one potion, holds up to three, and a won battle can drop another: saying "one
        # potion" alone was false once. The claim must come with the drops.
        claims = {"en-US": ("one potion", "drop"), "it-IT": ("una pozione", "lascia")}
        for locale, (claim, drops) in claims.items():
            with self.subTest(locale=locale):
                text = read_text(locale, "full_description.txt").lower()
                if claim in text:
                    self.assertIn(drops, text)

    def test_full_description_headings_are_not_in_capitals(self):
        # Play's metadata policy bans excessive capitals.
        for locale in LOCALES:
            with self.subTest(locale=locale):
                for line in read_text(locale, "full_description.txt").splitlines():
                    letters = [char for char in line if char.isalpha()]
                    self.assertFalse(len(letters) > 3 and all(char.isupper() for char in letters), line)


class ListingGraphicsTest(unittest.TestCase):
    def test_feature_graphic_is_1024_by_500_without_alpha(self):
        width, height, colour_type = png_header(STORE / "graphics" / "feature_1024x500.png")
        self.assertEqual((width, height), (1024, 500))
        self.assertEqual(colour_type, COLOUR_TYPE_RGB)

    def test_icon_is_512_square_with_alpha(self):
        path = STORE / "graphics" / "icon_512.png"
        width, height, colour_type = png_header(path)
        self.assertEqual((width, height), (512, 512))
        self.assertEqual(colour_type, COLOUR_TYPE_RGBA)
        self.assertLessEqual(path.stat().st_size, ICON_MAX_BYTES)

    def test_screenshots_follow_the_two_to_one_rule(self):
        # Task 12 fills the folder: until then there is nothing to check, and the test passes.
        folder = STORE / "screenshots"
        for path in sorted(folder.rglob("*.png")) if folder.is_dir() else []:
            with self.subTest(screenshot=path.name):
                width, height, colour_type = png_header(path)
                for side in (width, height):
                    self.assertGreaterEqual(side, SCREENSHOT_SIDE_MIN)
                    self.assertLessEqual(side, SCREENSHOT_SIDE_MAX)
                self.assertLessEqual(max(width, height), 2 * min(width, height))
                self.assertEqual(colour_type, COLOUR_TYPE_RGB, "a screenshot has no alpha channel")


if __name__ == "__main__":
    unittest.main()
