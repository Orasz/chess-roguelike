#!/usr/bin/env python3
r"""Builds the game's puzzle subset from the Lichess puzzle database (CC0).

Reads the database's CSV on stdin and writes the subset as JSON on stdout:

    zstd -dc lichess_db_puzzle.csv.zst \
        | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white > out.json

The output has two pools, both limited to one opening and to the puzzles that its
`--side` solves:

* `puzzles`: one-move puzzles (the `oneMove` theme, exactly two moves), for the basic enemies.
* `strong`: positions with the `advantage` theme, for the strong enemy.

Each pool keeps the most popular rows of every rating band, so the file stays small. Only the
standard library is used.
"""

import argparse
import csv
import inspect
import json
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
):
    """Builds the subset from an iterable of CSV lines, header included.

    A row is kept when its `OpeningTags` has the `opening` token, `side` solves it, and its
    rating deviation, popularity, play count and rating pass the limits. `side` is "white" or
    "black". The solver is the side to move after the first move of `Moves`, so white solves a
    row whose FEN has black to move. Ratings run from `min_rating` (included) to `max_rating`
    (excluded), in bands of `band_width`; each band keeps its `per_band` most popular puzzles
    and its `strong_per_band` most popular strong positions.

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
        if "oneMove" in themes and len(moves) == 2:
            puzzles.setdefault(band, []).append((rank, record))
        if "advantage" in themes:
            strong.setdefault(band, []).append((rank, record))

    return {
        "version": 1,
        "source": SOURCE,
        "opening": opening,
        "side": side,
        "puzzles": _top_of_each_band(puzzles, per_band),
        "strong": _top_of_each_band(strong, strong_per_band),
    }


def _top_of_each_band(bands, per_band):
    """Keeps the first `per_band` ranked records of every band, sorted by rating and then id."""
    kept = []
    for ranked in bands.values():
        ranked.sort(key=lambda item: item[0])
        kept.extend(record for _, record in ranked[:per_band])
    kept.sort(key=lambda record: (record["rating"], record["id"]))
    return kept


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
}


def _parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Builds the puzzle subset from the Lichess CSV on stdin; writes JSON on stdout."
    )
    parser.add_argument("--opening", required=True, help="OpeningTags token, e.g. Italian_Game")
    parser.add_argument("--side", required=True, choices=("white", "black"), help="the side that solves")
    defaults = inspect.signature(build).parameters
    for name, description in _INT_OPTIONS.items():
        parser.add_argument(
            "--" + name.replace("_", "-"),
            dest=name,
            type=int,
            default=defaults[name].default,
            help=description + " (default: %(default)s)",
        )
    return parser.parse_args(argv)


def main(argv=None):
    options = vars(_parse_args(argv))
    subset = build(sys.stdin, **options)
    sys.stdout.write(json.dumps(subset, indent=1, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
