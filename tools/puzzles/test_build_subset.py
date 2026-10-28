import io
import json
import random
import unittest
from unittest import mock

from engine import uci

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

    def test_puzzles_pool_needs_at_least_two_moves(self):
        result = build(row(id="single", moves="e7e5"))
        self.assertEqual(result["puzzles"], [])

    def test_long_puzzles_keep_only_the_first_two_moves(self):
        result = build(row(id="longer", themes="mateIn2 long", moves="e7e5 g1f3 b8c6 f1c4"))
        self.assertEqual(ids(result["puzzles"]), ["longer"])
        self.assertEqual(result["puzzles"][0]["moves"], ["e7e5", "g1f3"])
        self.assertEqual(result["puzzles"][0]["themes"], ["mateIn2", "long"])

    def test_each_band_caps_mate_in_one(self):
        result = build(
            row(id="m1", popularity=99, themes="mateIn1 oneMove"),
            row(id="m2", popularity=98, themes="mateIn1 oneMove"),
            row(id="m3", popularity=97, themes="mateIn1 oneMove"),
            row(id="other_a", popularity=90, themes="fork short"),
            row(id="other_b", popularity=89, themes="pin short"),
            per_band=3,
            max_mate_share=0.34,
        )
        kept = result["puzzles"]
        self.assertEqual(len(kept), 3)
        self.assertEqual(sorted(ids(kept)), ["m1", "other_a", "other_b"])
        self.assertEqual(sum("mateIn1" in record["themes"] for record in kept), 1)

    def test_mate_in_one_cap_is_per_band(self):
        result = build(
            row(id="low", rating=650, themes="mateIn1 oneMove"),
            row(id="high", rating=1250, themes="mateIn1 oneMove"),
            per_band=3,
            max_mate_share=0.34,
        )
        self.assertEqual(ids(result["puzzles"]), ["low", "high"])

    def test_mate_in_one_cap_can_leave_a_band_short(self):
        result = build(
            row(id="m1", popularity=99, themes="mateIn1 oneMove"),
            row(id="m2", popularity=98, themes="mateIn1 oneMove"),
            per_band=3,
            max_mate_share=0.34,
        )
        self.assertEqual(ids(result["puzzles"]), ["m1"])

    def test_advantage_rows_also_go_to_the_strong_pool(self):
        result = build(
            row(id="adv", themes="advantage long", moves="e7e5 g1f3 b8c6 f1c4"),
        )
        self.assertEqual(ids(result["strong"]), ["adv"])
        self.assertEqual(result["strong"][0]["themes"], ["advantage", "long"])
        self.assertEqual(result["strong"][0]["moves"], ["e7e5", "g1f3", "b8c6", "f1c4"])
        self.assertEqual(ids(result["puzzles"]), ["adv"])
        self.assertEqual(result["puzzles"][0]["moves"], ["e7e5", "g1f3"])

    def test_strong_positions_are_filtered_by_evaluation(self):
        # The rows differ by their first move, so the fake can tell them apart.
        evaluations = {"e7e5": 100, "d7d5": 200, "c7c5": 450}
        calls = []

        def evaluate(fen, first_move):
            calls.append((fen, first_move))
            return evaluations[first_move]

        result = build(
            row(id="low", themes="advantage long", moves="e7e5 g1f3 b8c6 f1c4"),
            row(id="inside", themes="advantage long", moves="d7d5 g1f3 b8c6 f1c4"),
            row(id="high", themes="advantage long", moves="c7c5 g1f3 b8c6 f1c4"),
            evaluate=evaluate,
            strong_min_cp=150,
            strong_max_cp=400,
        )
        self.assertEqual(ids(result["strong"]), ["inside"])
        self.assertEqual(result["strong"][0]["eval"], 200)
        self.assertEqual(len(calls), 3)
        self.assertEqual({fen for fen, _ in calls}, {FEN_BLACK_TO_MOVE})

    def test_strong_band_stops_evaluating_once_full(self):
        calls = []

        def evaluate(fen, first_move):
            calls.append(first_move)
            return 200

        build(
            row(id="a", popularity=99, themes="advantage long", moves="e7e5 g1f3"),
            row(id="b", popularity=98, themes="advantage long", moves="d7d5 g1f3"),
            row(id="c", popularity=97, themes="advantage long", moves="c7c5 g1f3"),
            evaluate=evaluate,
            strong_per_band=2,
        )
        self.assertEqual(calls, ["e7e5", "d7d5"])

    def test_strong_band_goes_down_the_ranking_past_rejected_rows(self):
        evaluations = {"e7e5": 90, "d7d5": 200, "c7c5": 300}
        result = build(
            row(id="a", popularity=99, themes="advantage long", moves="e7e5 g1f3"),
            row(id="b", popularity=98, themes="advantage long", moves="d7d5 g1f3"),
            row(id="c", popularity=97, themes="advantage long", moves="c7c5 g1f3"),
            evaluate=lambda fen, first_move: evaluations[first_move],
            strong_per_band=2,
        )
        self.assertEqual(ids(result["strong"]), ["b", "c"])

    def test_unevaluable_strong_rows_are_skipped(self):
        result = build(
            row(id="adv", themes="advantage long", moves="e7e5 g1f3 b8c6 f1c4"),
            evaluate=lambda fen, first_move: None,
        )
        self.assertEqual(result["strong"], [])

    def test_strong_rows_are_unfiltered_and_unscored_without_evaluate(self):
        result = build(row(id="adv", themes="advantage long", moves="e7e5 g1f3 b8c6 f1c4"))
        self.assertEqual(ids(result["strong"]), ["adv"])
        self.assertNotIn("eval", result["strong"][0])

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

    def test_output_is_still_deterministic(self):
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
                json.dumps(
                    build(
                        *shuffled,
                        per_band=3,
                        strong_per_band=2,
                        evaluate=lambda fen, first_move: 150 + len(first_move) + int(fen[0] == "r"),
                    ),
                    indent=1,
                    sort_keys=True,
                )
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

    def test_engine_flag_filters_the_strong_positions_with_that_engine(self):
        class FakeEngine:
            instances = []

            def __init__(self, path):
                self.path = path
                self.searches = []
                FakeEngine.instances.append(self)

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                pass

            def search(self, fen, moves, depth=None, movetime_ms=None):
                self.searches.append((fen, moves, depth))
                return uci.Result(best="g1f3", cp=200 if moves == ["e7e5"] else None, mate=None)

        stdin = io.StringIO(
            "\n".join(
                [
                    HEADER,
                    row(id="in_reach", themes="advantage long", moves="e7e5 g1f3"),
                    row(id="mate", themes="advantage long", moves="d7d5 g1f3"),
                ]
            )
            + "\n"
        )
        stdout = io.StringIO()
        argv = ["--opening", "Italian_Game", "--side", "white", "--engine", "/fake/stockfish", "--strong-depth", "9"]
        with mock.patch("sys.stdin", stdin), mock.patch("sys.stdout", stdout), mock.patch.object(
            uci, "Engine", FakeEngine
        ):
            status = build_subset.main(argv)
        self.assertEqual(status, 0)
        engine = FakeEngine.instances[0]
        self.assertEqual(engine.path, "/fake/stockfish")
        self.assertEqual([search[1] for search in engine.searches], [["e7e5"], ["d7d5"]])
        self.assertEqual({search[2] for search in engine.searches}, {9})
        result = json.loads(stdout.getvalue())
        self.assertEqual(ids(result["strong"]), ["in_reach"])
        self.assertEqual(result["strong"][0]["eval"], 200)


if __name__ == "__main__":
    unittest.main()
