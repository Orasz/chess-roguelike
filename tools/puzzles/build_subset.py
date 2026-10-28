#!/usr/bin/env python3
r"""Builds the game's puzzle subset from the Lichess puzzle database (CC0).

Reads the database's CSV on stdin and writes the subset as JSON on stdout:

    zstd -dc lichess_db_puzzle.csv.zst \
        | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white > out.json

The output has two pools, both limited to one opening and to the puzzles that its
`--side` solves:

* `puzzles`: every puzzle of at least two moves, for the basic enemies. A record keeps only
  the first two moves (the opponent's, then the solution), and each band holds at most a set
  share of mate-in-one rows.
* `strong`: positions with the `advantage` theme, for the strong enemy. When an `evaluate`
  function is given, a position is kept only if its evaluation after the opponent's first move
  lies in a window, and the record stores it as `eval`.

Each pool keeps the most popular rows of every rating band, so the file stays small. Only the
standard library is used.
"""

import argparse
import csv
import inspect
import json
import math
import os
import sys

SOURCE = "Lichess puzzle database (CC0), https://database.lichess.org/"

REQUIRED_COLUMNS = (
    "PuzzleId",
    "FEN",
    "Moves",
    "Rating",
    "RatingDeviation",
    "Popularity",
    "NbPlays",
    "Themes",
    "OpeningTags",
)


def build(
    lines,
    opening,
    side,
    per_band=30,
    strong_per_band=8,
    band_width=200,
    min_rating=400,
    max_rating=2600,
    max_rd=90,
    min_popularity=80,
    min_plays=300,
    max_mate_share=0.34,
    evaluate=None,
    strong_min_cp=150,
    strong_max_cp=400,
):
    """Builds the subset from an iterable of CSV lines, header included.

    A row is kept when its `OpeningTags` has the `opening` token, `side` solves it, and its
    rating deviation, popularity, play count and rating pass the limits. `side` is "white" or
    "black". The solver is the side to move after the first move of `Moves`, so white solves a
    row whose FEN has black to move. Ratings run from `min_rating` (included) to `max_rating`
    (excluded), in bands of `band_width`; each band keeps its `per_band` most popular puzzles
    and its `strong_per_band` most popular strong positions.

    A puzzle needs at least two moves and keeps the first two. Rows with the `mateIn1` theme
    fill at most `floor(per_band * max_mate_share)` places of a band.

    `evaluate(fen, first_move)` returns the solver's evaluation in centipawns after
    `first_move`, or None for a mate or a failure. When it is given, each band walks its strong
    candidates in ranking order until `strong_per_band` have an evaluation from `strong_min_cp`
    to `strong_max_cp` (both included); the record gains `"eval"`. Without it, strong rows are
    kept unfiltered and unscored.

    Raises ValueError when a required column is missing or `side` is unknown.
    """
    if side not in ("white", "black"):
        raise ValueError("side must be 'white' or 'black', not %r" % (side,))
    fen_side_to_move = "b" if side == "white" else "w"

    reader = csv.DictReader(lines)
    missing = [name for name in REQUIRED_COLUMNS if name not in (reader.fieldnames or ())]
    if missing:
        raise ValueError("missing CSV columns: " + ", ".join(missing))

    puzzles = {}
    strong = {}
    for row in reader:
        if opening not in row["OpeningTags"].split():
            continue
        if row["FEN"].split()[1] != fen_side_to_move:
            continue
        rating = int(row["Rating"])
        if not min_rating <= rating < max_rating:
            continue
        if (
            int(row["RatingDeviation"]) > max_rd
            or int(row["Popularity"]) < min_popularity
            or int(row["NbPlays"]) < min_plays
        ):
            continue
        themes = row["Themes"].split()
        moves = row["Moves"].split()
        if len(moves) < 2:
            continue
        record = {
            "id": row["PuzzleId"],
            "fen": row["FEN"],
            "moves": moves,
            "rating": rating,
            "themes": themes,
        }
        # Sorts the most popular first; ties go to the most played, then to the lowest id.
        rank = (-int(row["Popularity"]), -int(row["NbPlays"]), row["PuzzleId"])
        band = (rating - min_rating) // band_width
        puzzles.setdefault(band, []).append((rank, dict(record, moves=moves[:2])))
        if "advantage" in themes:
            strong.setdefault(band, []).append((rank, record))

    mate_cap = math.floor(per_band * max_mate_share)
    return {
        "version": 1,
        "source": SOURCE,
        "opening": opening,
        "side": side,
        "puzzles": _top_puzzles(puzzles, per_band, mate_cap),
        "strong": _top_strong(strong, strong_per_band, evaluate, strong_min_cp, strong_max_cp),
    }


def _by_rating_then_id(kept):
    kept.sort(key=lambda record: (record["rating"], record["id"]))
    return kept


def _top_puzzles(bands, per_band, mate_cap):
    """Keeps the first `per_band` ranked puzzles of every band, with at most `mate_cap` mate-in-one."""
    kept = []
    for ranked in bands.values():
        ranked.sort(key=lambda item: item[0])
        mates = 0
        in_band = 0
        for _, record in ranked:
            if in_band == per_band:
                break
            if "mateIn1" in record["themes"]:
                if mates == mate_cap:
                    continue
                mates += 1
            kept.append(record)
            in_band += 1
    return _by_rating_then_id(kept)


def _top_strong(bands, per_band, evaluate, min_cp, max_cp):
    """Keeps the first `per_band` ranked strong positions of every band that pass `evaluate`."""
    kept = []
    for ranked in bands.values():
        ranked.sort(key=lambda item: item[0])
        if evaluate is None:
            kept.extend(record for _, record in ranked[:per_band])
            continue
        in_band = 0
        for _, record in ranked:
            if in_band == per_band:
                break
            score = evaluate(record["fen"], record["moves"][0])
            if score is None or not min_cp <= score <= max_cp:
                continue
            kept.append(dict(record, eval=score))
            in_band += 1
    return _by_rating_then_id(kept)


# Help text of the numeric flags. Each flag is the name of a `build` parameter, in kebab-case,
# and takes that parameter's default.
_INT_OPTIONS = {
    "per_band": "puzzles kept per rating band",
    "strong_per_band": "strong positions kept per rating band",
    "band_width": "width of a rating band",
    "min_rating": "lowest rating, included",
    "max_rating": "highest rating, excluded",
    "max_rd": "highest RatingDeviation",
    "min_popularity": "lowest Popularity",
    "min_plays": "lowest NbPlays",
    "strong_min_cp": "lowest evaluation of a strong position, in centipawns",
    "strong_max_cp": "highest evaluation of a strong position, in centipawns",
}


def _parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Builds the puzzle subset from the Lichess CSV on stdin; writes JSON on stdout."
    )
    parser.add_argument("--opening", required=True, help="OpeningTags token, e.g. Italian_Game")
    parser.add_argument("--side", required=True, choices=("white", "black"), help="the side that solves")
    defaults = inspect.signature(build).parameters
    parser.add_argument(
        "--max-mate-share",
        type=float,
        default=defaults["max_mate_share"].default,
        help="share of a band that mate-in-one puzzles may fill (default: %(default)s)",
    )
    parser.add_argument(
        "--engine",
        help="UCI engine binary that evaluates the strong positions; without it they are not filtered",
    )
    parser.add_argument(
        "--strong-depth",
        type=int,
        default=14,
        help="search depth of the strong-position evaluation (default: %(default)s)",
    )
    for name, description in _INT_OPTIONS.items():
        parser.add_argument(
            "--" + name.replace("_", "-"),
            dest=name,
            type=int,
            default=defaults[name].default,
            help=description + " (default: %(default)s)",
        )
    return parser.parse_args(argv)


def _engine_evaluator(engine, depth):
    """Returns `evaluate(fen, first_move)` for `build`, searching to `depth` with `engine`."""

    def evaluate(fen, first_move):
        # After the first move the solver is the side to move, so its score is the engine's.
        # Only a row the engine refuses (an illegal FEN or move) is skipped: a dead engine
        # (EOFError, OSError) must stop the run, or the pool would silently come out short.
        try:
            return engine.search(fen, [first_move], depth=depth).cp
        except ValueError:
            return None

    return evaluate


def main(argv=None):
    options = vars(_parse_args(argv))
    engine_path = options.pop("engine")
    depth = options.pop("strong_depth")
    if engine_path is None:
        subset = build(sys.stdin, **options)
    else:
        # The engine driver lives next to this package; a script run puts only this directory on the path.
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from engine import uci

        try:
            with uci.Engine(engine_path) as engine:
                subset = build(sys.stdin, evaluate=_engine_evaluator(engine, depth), **options)
        except (EOFError, OSError) as error:
            sys.stderr.write("build_subset: the engine %s failed: %s\n" % (engine_path, error or type(error).__name__))
            return 1
    sys.stdout.write(json.dumps(subset, indent=1, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
