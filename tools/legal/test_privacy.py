import unittest
from pathlib import Path

POLICY = Path(__file__).resolve().parents[2] / "PRIVACY.md"
ISSUES_URL = "https://github.com/Orasz/chess-roguelike/issues"


class PrivacyPolicyTest(unittest.TestCase):
    """The privacy policy is published in two languages, and each one tells how to get in touch."""

    def test_both_languages_are_there_with_the_contact(self):
        text = POLICY.read_text(encoding="utf-8")
        self.assertIn("\n## English\n", text)
        self.assertIn("\n## Italiano\n", text)
        english, italian = text.split("\n## English\n")[1].split("\n## Italiano\n")
        self.assertIn(ISSUES_URL, english)
        self.assertIn(ISSUES_URL, italian)

    def test_the_play_section_names_what_the_developer_sees_and_the_old_claims_are_gone(self):
        text = POLICY.read_text(encoding="utf-8")
        english, italian = text.split("\n## English\n")[1].split("\n## Italiano\n")
        for language, section in [("English", english), ("Italiano", italian)]:
            with self.subTest(language=language):
                play = section.split("### Google Play")[1].split("###")[0]
                self.assertIn("stack trace", play.lower())
                self.assertNotIn("aggregat", section.lower())
                self.assertNotIn("third-party sdk", section.lower())
                self.assertNotIn("sdk di terzi", section.lower())
                self.assertNotIn("identifies you", section.lower())

    def test_the_save_is_not_said_to_stay_on_the_phone_absolutely(self):
        """Android's device-to-device transfer may copy the save to a new phone, so "never leaves" is inexact."""
        text = POLICY.read_text(encoding="utf-8")
        english, italian = text.split("\n## English\n")[1].split("\n## Italiano\n")
        self.assertNotIn("never leaves the phone", english)
        self.assertNotIn("non esce mai dal telefono", italian)
        self.assertIn("cloud backup", english)
        self.assertIn("new phone", english)
        self.assertIn("backup su cloud", italian)
        self.assertIn("telefono nuovo", italian)


if __name__ == "__main__":
    unittest.main()
