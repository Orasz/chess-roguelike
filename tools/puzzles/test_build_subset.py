import io
import json
import random
import unittest
from unittest import mock

from . import build_subset

HEADER = "PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags"

# After 1.e4, Black to move: Moves[0] is Black's move and White solves, so the solver is white.
FEN_BLACK_TO_MOVE = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
# After 1.e4 e5, White to move: Moves[0] is White's move and Black solves.
FEN_WHITE_TO_MOVE = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"


def row(**overrides):
    """One CSV line, with the defaults of a puzzle that the builder keeps."""
    fields = {
        "id": "p0001",
        "fen": FEN_BLACK_TO_MOVE,
        "moves": "e7e5 g1f3",
        "rating": 1200,
        "rd": 75,
        "popularity": 90,
        "plays": 1000,
        "themes": "oneMove short",
        "tags": "Italian_Game Italian_Game_Classical_Variation",
    }
    fields.update(overrides)
    return ",".join(
        str(value)
        for value in (
            fields["id"],
            fields["fen"],
            fields["moves"],
            fields["rating"],
            fields["rd"],
            fields["popularity"],
            fields["plays"],
            fields["themes"],
            "https://lichess.org/" + fields["id"],
            fields["tags"],
        )
    )


def build(*rows, **kwargs):
    return build_subset.build([HEADER, *rows], "Italian_Game", "white", **kwargs)


def ids(records):
    return [record["id"] for record in records]


class BuildTest(unittest.TestCase):
    def test_keeps_one_move_puzzles_for_the_opening_and_side(self):
        result = build(row(id="keep"))
        self.assertEqual(result["version"], 1)
        self.assertEqual(result["opening"], "Italian_Game")
        self.assertEqual(result["side"], "white")
        self.assertEqual(result["strong"], [])
        self.assertEqual(
            result["puzzles"],
            [
                {
                    "id": "keep",
                    "fen": FEN_BLACK_TO_MOVE,
                    "moves": ["e7e5", "g1f3"],
                    "rating": 1200,
                    "themes": ["oneMove", "short"],
                }
            ],
        )

    def test_drops_other_openings_wrong_side_and_unreliable_rows(self):
        result = build(
            row(id="keep"),
            row(id="other_opening", tags="Sicilian_Defense"),
            row(id="longer_tag_only", tags="Italian_Game_Classical_Variation"),
            row(id="wrong_side", fen=FEN_WHITE_TO_MOVE),
            row(id="unreliable", rd=120),
            row(id="unpopular", popularity=50),
            row(id="rarely_played", plays=100),
        )
        self.assertEqual(ids(result["puzzles"]), ["keep"])

    def test_black_side_keeps_the_rows_that_black_solves(self):
        lines = [
            HEADER,
            row(id="white_solves"),
            row(id="black_solves", fen=FEN_WHITE_TO_MOVE, moves="g1f3 b8c6"),
        ]
        result = build_subset.build(lines, "Italian_Game", "black")
        self.assertEqual(ids(result["puzzles"]), ["black_solves"])

    def test_unknown_side_is_an_error(self):
        with self.assertRaises(ValueError):
            build_subset.build([HEADER], "Italian_Game", "White")

    def test_puzzles_pool_needs_exactly_two_moves(self):
        result = build(row(id="longer", moves="e7e5 g1f3 b8c6 f1c4"))
        self.assertEqual(result["puzzles"], [])

    def test_advantage_rows_go_to_the_strong_pool(self):
        result = build(
            row(id="adv", themes="advantage long", moves="e7e5 g1f3 b8c6 f1c4"),
        )
        self.assertEqual(result["puzzles"], [])
        self.assertEqual(ids(result["strong"]), ["adv"])
        self.assertEqual(result["strong"][0]["themes"], ["advantage", "long"])

    def test_rating_range_is_half_open(self):
        result = build(
            row(id="low_edge", rating=400),
            row(id="below", rating=399),
            row(id="high_edge", rating=2599),
            row(id="above", rating=2600),
        )
        self.assertEqual(ids(result["puzzles"]), ["low_edge", "high_edge"])

    def test_each_band_keeps_the_most_popular(self):
        result = build(
            row(id="p85", popularity=85),
            row(id="p95", popularity=95),
            row(id="p90", popularity=90),
            per_band=2,
        )
        self.assertEqual(sorted(ids(result["puzzles"])), ["p90", "p95"])

    def test_popularity_ties_fall_back_to_plays_then_id(self):
        result = build(
            row(id="b", popularity=90, plays=500),
            row(id="a", popularity=90, plays=500),
            row(id="most_played", popularity=90, plays=900),
            per_band=2,
        )
        self.assertEqual(sorted(ids(result["puzzles"])), ["a", "most_played"])

    def test_bands_are_filled_independently(self):
        result = build(
            row(id="low_1", rating=650, popularity=99),
            row(id="low_2", rating=651, popularity=98),
            row(id="high_1", rating=1250, popularity=80),
            per_band=1,
        )
        self.assertEqual(ids(result["puzzles"]), ["low_1", "high_1"])

    def test_output_is_sorted_and_deterministic(self):
        rows = []
        for n in range(60):
            rows.append(
                row(
                    id="p%03d" % n,
                    rating=400 + (n * 37) % 2200,
                    popularity=80 + n % 5,
                    plays=300 + n % 3,
                    themes="advantage long" if n % 4 == 0 else "oneMove short",
                    moves="e7e5 g1f3 b8c6 f1c4" if n % 4 == 0 else "e7e5 g1f3",
                )
            )
        outputs = []
        for seed in (1, 2):
            shuffled = rows[:]
            random.Random(seed).shuffle(shuffled)
            outputs.append(
                json.dumps(build(*shuffled, per_band=3, strong_per_band=2), indent=1, sort_keys=True)
            )
        self.assertEqual(outputs[0], outputs[1])
        result = json.loads(outputs[0])
        for pool in ("puzzles", "strong"):
            keys = [(record["rating"], record["id"]) for record in result[pool]]
            self.assertEqual(keys, sorted(keys))
            self.assertTrue(keys)

    def test_missing_column_is_an_error(self):
        header = HEADER.replace("Popularity,", "")
        with self.assertRaises(ValueError):
            build_subset.build([header, row()], "Italian_Game", "white")


class MainTest(unittest.TestCase):
    def test_flags_reach_build_and_stdout_gets_the_json(self):
        stdin = io.StringIO("\n".join([HEADER, row(id="a"), row(id="b", popularity=95)]) + "\n")
        stdout = io.StringIO()
        with mock.patch("sys.stdin", stdin), mock.patch("sys.stdout", stdout):
            status = build_subset.main(["--opening", "Italian_Game", "--side", "white", "--per-band", "1"])
        self.assertEqual(status, 0)
        result = json.loads(stdout.getvalue())
        self.assertEqual(ids(result["puzzles"]), ["b"])


if __name__ == "__main__":
    unittest.main()
