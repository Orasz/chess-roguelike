"""Pins the two vendored files that the engine build depends on, so that a change to either is deliberate.

The net is a binary that the extension embeds; the patch is applied to a copy of Stockfish at build time. Both
carry their expected hash in CREDITS.md and in the patch's own preamble, and these tests hold those values.
"""

import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NET = ROOT / "native" / "nn-61e7af4bb97d.nnue"
PATCH = ROOT / "native" / "patches" / "sf19-light-net.patch"

NET_SHA256 = "61e7af4bb97d51eeeb25d322916f86513b5cd3a827ce189c98c6e31946f99e5b"
# The patch as downloaded from the commit's `.patch` URL (see its preamble): everything below the comment
# preamble and the blank line that follows it. It starts with the mbox line "From <commit> ...".
PATCH_BODY_SHA256 = "37a59c2ba8b615077f1d0f321e541bd317c6ab8d6af1d75099a7093f101d65d9"


def split_patch(data: bytes) -> tuple[bytes, bytes]:
    """The preamble (the leading `#` lines and the blank line after them) and the body that follows."""
    lines = data.splitlines(keepends=True)
    index = 0
    while index < len(lines) and lines[index].startswith(b"#"):
        index += 1
    if index < len(lines) and lines[index].strip() == b"":
        index += 1
    return b"".join(lines[:index]), b"".join(lines[index:])


class VendoredFilesTest(unittest.TestCase):
    def test_the_light_net_is_the_one_the_credits_name(self):
        self.assertEqual(hashlib.sha256(NET.read_bytes()).hexdigest(), NET_SHA256)

    def test_the_patch_body_matches_the_hash_pinned_here(self):
        _, body = split_patch(PATCH.read_bytes())
        self.assertTrue(body.startswith(b"From 81348d3fb4f68bda5c442e7459de78ab00acbc55"), body[:60])
        self.assertEqual(hashlib.sha256(body).hexdigest(), PATCH_BODY_SHA256)

    def test_the_patch_body_matches_the_hash_its_own_preamble_states(self):
        preamble, body = split_patch(PATCH.read_bytes())
        stated = re.search(rb"SHA-256 of the file as downloaded[^\n]*\n#\s+([0-9a-f]{64})", preamble)
        self.assertIsNotNone(stated, "the preamble no longer states the hash of the downloaded file")
        self.assertEqual(stated.group(1).decode(), hashlib.sha256(body).hexdigest())

    def test_the_preamble_states_the_net_hash_pinned_here(self):
        preamble, _ = split_patch(PATCH.read_bytes())
        self.assertIn(NET_SHA256.encode(), preamble)

    def test_the_patch_has_no_carriage_returns(self):
        self.assertNotIn(b"\r", PATCH.read_bytes(), "line endings were converted: the patch would no longer apply")


if __name__ == "__main__":
    unittest.main()
