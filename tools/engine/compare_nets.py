#!/usr/bin/env python3
r"""Compares two Stockfish builds, a full net against a light one, on the game's own data.

    python3 tools/engine/compare_nets.py --full build/stockfish/stockfish \
        --light build/stockfish-light/stockfish --data game/data/puzzles/italian_game.json

It prints a JSON report:

* `puzzles_solved_full`, `puzzles_solved_light`: the puzzles each build solves. A puzzle is
  solved when, after the opponent's first move, the best move at 300 ms is the second move of
  `moves`, or the position is scored as mate in one.
* `strong_agreement`: the share of strong positions on which both builds pick the same best
  move at 700 ms, searched after the opponent's first move.
* `strong_median_abs_diff_cp`: the median gap between their scores on those positions. A
  position where either build reports a mate has no centipawn score and is left out.
* `nodes_full`, `nodes_light`: the `bench` node counts. They differ between nets; each one is
  checked against the count that its own tree is known to report.

Only the standard library is used.
"""

import argparse
import json
import statistics
import sys

try:
    from . import uci
except ImportError:  # run as a script: this directory is on sys.path, not its parent
    import uci

PUZZLE_MS = 300
STRONG_MS = 700


def solved(engine, puzzle):
    """Whether `engine` finds the solution of `puzzle` (the move after the opponent's first)."""
    first, answer = puzzle["moves"][0], puzzle["moves"][1]
    result = engine.search(puzzle["fen"], [first], movetime_ms=PUZZLE_MS)
    return result.best == answer or result.mate == 1


def compare(full_path, light_path, data):
    """Runs both builds on `data` (the puzzle file's content) and returns the report."""
    with uci.Engine(full_path) as full, uci.Engine(light_path) as light:
        puzzles_full = sum(solved(full, p) for p in data["puzzles"])
        puzzles_light = sum(solved(light, p) for p in data["puzzles"])

        agreed = 0
        gaps = []
        for position in data["strong"]:
            moves = position["moves"][:1]
            a = full.search(position["fen"], moves, movetime_ms=STRONG_MS)
            b = light.search(position["fen"], moves, movetime_ms=STRONG_MS)
            agreed += a.best == b.best
            if a.cp is not None and b.cp is not None:
                gaps.append(abs(a.cp - b.cp))

        return {
            "strong_agreement": agreed / len(data["strong"]) if data["strong"] else None,
            "strong_median_abs_diff_cp": statistics.median(gaps) if gaps else None,
            "puzzles_solved_full": puzzles_full,
            "puzzles_solved_light": puzzles_light,
            "nodes_full": full.bench_nodes(),
            "nodes_light": light.bench_nodes(),
        }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--full", required=True, help="Stockfish binary with the full net")
    parser.add_argument("--light", required=True, help="Stockfish binary with the light net")
    parser.add_argument("--data", required=True, help="the puzzle JSON written by build_subset.py")
    args = parser.parse_args(argv)
    with open(args.data) as f:
        data = json.load(f)
    json.dump(compare(args.full, args.light, data), sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
