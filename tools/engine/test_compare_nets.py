import contextlib
import io
import json
import os
import tempfile
import unittest

from . import compare_nets
from .fake_engine import reply, write_fake_engine

FEN_A = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"
FEN_B = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
FEN_C = "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1"
FEN_P = "rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq - 0 1"
LINE = ["a7a6", "a2a3", "b7b6", "b2b3"]

# Three strong positions, each with the opponent's first move in `moves`.
STRONG = [
    {"fen": FEN_A, "id": "A", "moves": LINE},
    {"fen": FEN_B, "id": "B", "moves": LINE},
    {"fen": FEN_C, "id": "C", "moves": LINE},
]


def data(puzzles=(), strong=()):
    return {"puzzles": list(puzzles), "strong": list(strong)}


class CompareNetsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = directory.name

    def engines(self, full, light, nodes_full=2793281, nodes_light=2793281):
        full_path, self.full_log = write_fake_engine(
            self.directory, "full", replies=full, nodes=nodes_full)
        light_path, self.light_log = write_fake_engine(
            self.directory, "light", replies=light, nodes=nodes_light)
        return full_path, light_path

    def test_agreement_and_median_difference(self):
        # The searched position is the one after the opponent's first move, `moves[0]`.
        full = {FEN_A: reply(cp=100, best="a2a3"),
                FEN_B: reply(cp=100, best="a2a3"),
                FEN_C: reply(cp=100, best="a2a3")}
        light = {FEN_A: reply(cp=110, best="a2a3"),
                 FEN_B: reply(cp=130, best="a2a3"),
                 FEN_C: reply(cp=150, best="h2h3")}
        full_path, light_path = self.engines(full, light, nodes_light=2793000)

        report = compare_nets.compare(full_path, light_path, data(strong=STRONG))

        self.assertAlmostEqual(report["strong_agreement"], 2 / 3)
        self.assertEqual(report["strong_median_abs_diff_cp"], 30)
        self.assertEqual(report["nodes_full"], 2793281)
        self.assertEqual(report["nodes_light"], 2793000)

    def test_a_mate_in_one_counts_as_solved(self):
        puzzle = {"fen": FEN_P, "id": "P", "moves": ["a7a6", "a2a3"]}
        full = {FEN_P: reply(cp=500, best="a2a3")}
        light = {FEN_P: reply(mate=1, best="d1h5")}
        full_path, light_path = self.engines(full, light)

        report = compare_nets.compare(full_path, light_path, data(puzzles=[puzzle]))

        self.assertEqual(report["puzzles_solved_full"], 1)
        self.assertEqual(report["puzzles_solved_light"], 1)

    def test_a_different_move_without_mate_is_not_solved(self):
        puzzle = {"fen": FEN_P, "id": "P", "moves": ["a7a6", "a2a3"]}
        full = {FEN_P: reply(cp=500, best="a2a3")}
        light = {FEN_P: reply(cp=500, best="h2h3")}
        full_path, light_path = self.engines(full, light)

        report = compare_nets.compare(full_path, light_path, data(puzzles=[puzzle]))

        self.assertEqual((report["puzzles_solved_full"], report["puzzles_solved_light"]), (1, 0))

    def test_puzzles_are_searched_at_300_ms_and_strong_positions_at_700_ms(self):
        puzzle = {"fen": FEN_P, "id": "P", "moves": ["a7a6", "a2a3"]}
        full_path, light_path = self.engines({}, {})

        compare_nets.compare(full_path, light_path, data(puzzles=[puzzle], strong=STRONG[:1]))

        with open(self.full_log) as f:
            sent = f.read().splitlines()
        self.assertEqual([c for c in sent if c.startswith("go")], ["go movetime 300", "go movetime 700"])
        self.assertIn("position fen {} moves a7a6".format(FEN_P), sent)

    def test_positions_with_a_mate_score_are_left_out_of_the_median(self):
        full = {FEN_A: reply(cp=100, best="a2a3"),
                FEN_B: reply(mate=3, best="a2a3")}
        light = {FEN_A: reply(cp=140, best="a2a3"),
                 FEN_B: reply(cp=900, best="a2a3")}
        full_path, light_path = self.engines(full, light)

        report = compare_nets.compare(full_path, light_path, data(strong=STRONG[:2]))

        self.assertEqual(report["strong_agreement"], 1.0)
        self.assertEqual(report["strong_median_abs_diff_cp"], 40)

    def test_the_command_line_prints_a_json_report(self):
        full_path, light_path = self.engines({}, {})
        data_path = os.path.join(self.directory, "data.json")
        with open(data_path, "w") as f:
            json.dump(data(strong=STRONG[:1]), f)

        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            compare_nets.main(["--full", full_path, "--light", light_path, "--data", data_path])

        report = json.loads(out.getvalue())
        self.assertEqual(report["strong_agreement"], 1.0)
        self.assertEqual(sorted(report), sorted([
            "strong_agreement", "strong_median_abs_diff_cp", "puzzles_solved_full",
            "puzzles_solved_light", "nodes_full", "nodes_light"]))


if __name__ == "__main__":
    unittest.main()
