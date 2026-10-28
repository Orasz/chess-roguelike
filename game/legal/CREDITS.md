# Credits

Everything the repository ships that someone else made, with its licence.

## Code

- **Stockfish** (the chess engine, linked into the game as a GDExtension): GPLv3, by the
  Stockfish developers. The build is Stockfish `sf_19` plus the light-net patch below, with the
  light net below. The game as a whole is GPLv3 for that reason: see [`LICENSE`](LICENSE).
  Source: <https://github.com/official-stockfish/Stockfish>.

- **Light-net patch for Stockfish** (`native/patches/sf19-light-net.patch`, applied to a copy of
  Stockfish at build time): GPLv3, as part of Stockfish. Written by sscg13 ("simple mirrored piece
  square features": the P_hm feature set, 768 inputs), rebased onto `sf_19` by Niklas Fiekas. It is the
  patch that Lichess uses for its light Stockfish. Source:
  <https://github.com/niklasf/Stockfish/commit/81348d3fb4f68bda5c442e7459de78ab00acbc55>
  (the file is the commit's `.patch`, with a comment preamble on top that `git apply` ignores).
  Why it is used: [`docs/decisions/0003-engine-net.md`](docs/decisions/0003-engine-net.md).

- **Godot Engine** (the engine the game runs on, exported into the APK): MIT, by Juan Linietsky,
  Ariel Manzur and the Godot Engine contributors. Licence: <https://godotengine.org/license>.
  The engine bundles third-party components under their own licences. `Engine.get_copyright_info()`
  lists them, `Engine.get_license_info()` holds their licence texts, and the engine's
  `COPYRIGHT.txt` lists them too; `Engine.get_license_text()` returns Godot's own licence.

- **godot-cpp** (the C++ bindings of the GDExtension, compiled into it): MIT, by the Godot Engine
  contributors. Source: <https://github.com/godotengine/godot-cpp>.

- Development only: **GUT** (the unit test framework, vendored in `game/addons/gut/`): MIT, by
  Tom "Butch" Wesley. Its licence is in [`game/addons/gut/LICENSE.md`](game/addons/gut/LICENSE.md).
  The export excludes it, so the APK does not ship it.

## Engine net

- **Stockfish light net `nn-61e7af4bb97d.nnue`** (1,166,381 bytes, `native/nn-61e7af4bb97d.nnue`,
  embedded in the extension): a net of the Stockfish project, under CC0 by the fishtest upload
  terms. Fishtest, the project's testing server, serves it
  (<https://tests.stockfishchess.org/api/nn/nn-61e7af4bb97d.nnue>), and its upload page says: "By
  uploading, you license your network under a CC0 license." (source:
  `server/fishtest/templates/nn_upload.html.j2` in <https://github.com/official-stockfish/fishtest>).
  The file was taken from the copy that Lichess vendors:
  <https://raw.githubusercontent.com/lichess-org/dart-multistockfish/main/pkgs/multistockfish_light/ios/multistockfish_light/Sources/multistockfish_light/nnue/nn-61e7af4bb97d.nnue>.
  Its SHA-256 is `61e7af4bb97d51eeeb25d322916f86513b5cd3a827ce189c98c6e31946f99e5b`. Stockfish's README
  adds that its nets are trained on Leela Chess Zero data under the ODbL.
  **To re-check before the public launch:** the net's own fishtest page (uploader, date) could not be
  read, because it sits behind a browser check, so the CC0 licence rests on the upload terms alone.
  See [`docs/decisions/0003-engine-net.md`](docs/decisions/0003-engine-net.md).

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
  The white knight is also the game's icon, see below.

- **Ninja Adventure Asset Pack** by pixel-boy (CC0 1.0), from <https://pixel-boy.itch.io/ninja-adventure-asset-pack>.
  Used for the portraits on the battle screen: six of the pack's `Faceset.png` images (38x38 px),
  renamed, in `game/assets/ninja_adventure/`. The overworld map shows the enemies' portraits at half
  size, and adds four tilesets and one walking sheet, copied unchanged and renamed. The pack's
  licence text is next to them, in
  [`game/assets/ninja_adventure/LICENSE.txt`](game/assets/ninja_adventure/LICENSE.txt).
  - `monsters/gold_racoon.png`, from `Actor/Monster/GoldRacoon/Faceset.png`: Greedy Pawn.
  - `monsters/kappa_green.png`, from `Actor/Monster/KappaGreen/Faceset.png`: Sneaky Bishop.
  - `monsters/bear.png`, from `Actor/Monster/Bear/Faceset.png`: Knight of the Centre.
  - `characters/old_man_3.png`, from `Actor/Character/OldMan3/Faceset.png`: Opening Scholar.
  - `bosses/demon_cyclop.png`, from `Actor/Boss/DemonCyclop/Faceset.png`: Gatekeeper Rook.
  - `characters/boy.png`, from `Actor/Character/Boy/Faceset.png`: the player.
  - `characters/boy_walk.png`, from `Actor/Character/Boy/SeparateAnim/Walk.png`: the player's
    walking sheet on the map, four directions of four 16 px frames.
  - `tilesets/floor.png`, from `Backgrounds/Tilesets/TilesetFloor.png`: the grass and path tiles.
  - `tilesets/nature.png`, from `Backgrounds/Tilesets/TilesetNature.png`: the trees and tall grass.
  - `tilesets/water.png`, from `Backgrounds/Tilesets/TilesetWater.png`: the water and the bridge planks.
  - `tilesets/house.png`, from `Backgrounds/Tilesets/TilesetHouse.png`: the door of the gate.

- **The game's icon** (`game/assets/icon/` and `store/graphics/icon_512.png`): drawn by
  `game/tools/make_icons.gd` from two of the pieces above, so it carries the same licences (CC0 1.0): the
  white knight of Pixel Chess Pieces (`white_knight.png`), over grass tiles of the Ninja Adventure pack
  (`tilesets/floor.png`, the plain grass and the two with blades). Both are scaled by an integer factor.
  The adaptive icon's monochrome layer for Android 13+ themed icons (`adaptive_mono_432.png`) is the same knight
  as a white silhouette, so it is CC0 1.0 as well.
