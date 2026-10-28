import tempfile
import unittest

from . import uci
from .fake_engine import reply, write_fake_engine

START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


class EngineTest(unittest.TestCase):
    def engine(self, **kwargs):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path, log = write_fake_engine(directory.name, **kwargs)
        engine = uci.Engine(path)
        self.addCleanup(engine.close)
        return engine, log

    def test_search_returns_the_best_move_and_score(self):
        engine, _ = self.engine(default=reply(cp=34, best="e2e4"))

        self.assertEqual(engine.search(START, [], movetime_ms=100), uci.Result("e2e4", 34, None))

    def test_mate_scores_are_reported_as_mate(self):
        engine, _ = self.engine(default=reply(mate=-2, best="g1f3"))

        result = engine.search(START, ["e2e4"], depth=5)

        self.assertEqual(result.mate, -2)
        self.assertIsNone(result.cp)

    def test_bench_nodes_reads_the_total(self):
        engine, _ = self.engine(nodes=2793281)

        self.assertEqual(engine.bench_nodes(), 2793281)

    def test_commands_are_built_from_fixed_templates(self):
        engine, log = self.engine()

        engine.search(START, ["e2e4", "e7e5"], movetime_ms=300)
        engine.close()

        with open(log) as f:
            sent = f.read().splitlines()
        self.assertEqual(sent[:4], ["uci", "setoption name Threads value 1", "setoption name Hash value 16", "isready"])
        self.assertIn("position fen {} moves e2e4 e7e5".format(START), sent)
        self.assertIn("go movetime 300", sent)

    def test_text_that_is_not_a_fen_or_a_move_is_refused(self):
        engine, _ = self.engine()

        with self.assertRaises(ValueError):
            engine.search(START + "\nquit", [], depth=1)
        with self.assertRaises(ValueError):
            engine.search(START, ["e2e4\nquit"], depth=1)

    def test_a_search_needs_exactly_one_limit(self):
        engine, _ = self.engine()

        with self.assertRaises(ValueError):
            engine.search(START, [])
        with self.assertRaises(ValueError):
            engine.search(START, [], movetime_ms=10, depth=2)


if __name__ == "__main__":
    unittest.main()
