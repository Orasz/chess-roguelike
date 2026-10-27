# Credits

Everything the repository ships that someone else made, with its licence.

## Code

- **Stockfish** (the chess engine, linked into the game as a GDExtension): GPLv3, by the
  Stockfish developers. It is used unmodified, with its embedded NNUE net. The game as a whole is
  GPLv3 for that reason: see [`LICENSE`](LICENSE). Source: <https://github.com/official-stockfish/Stockfish>.

## Data

- **Lichess puzzle database** (CC0, public domain), from <https://database.lichess.org/>.
  The repository ships only a filtered subset, `game/data/puzzles/italian_game.json`: puzzles of
  the Italian Game that white solves, in rating bands from 400 to 2600. It is generated offline
  and is at most 200 KB. To regenerate it, download `lichess_db_puzzle.csv.zst` from
  <https://database.lichess.org/#puzzles> into `build/` (which git ignores), then run:

  ```bash
  zstd -dc build/lichess_db_puzzle.csv.zst | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white > game/data/puzzles/italian_game.json
  ```

  `make puzzles` runs the same command.

## Art

- **Pixel Chess Pieces** by SpicyGame (CC0 1.0), from <https://spicygame.itch.io/chess-pieces>.
  Used in the board view: the twelve `color` pieces, `game/assets/chess_pieces/{white,black}_{pawn,knight,bishop,rook,queen,king}.png`.
  The licence note is in [`game/assets/chess_pieces/LICENSE.md`](game/assets/chess_pieces/LICENSE.md).
