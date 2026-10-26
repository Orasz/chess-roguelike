# Chess Roguelike

A free, open-source mobile roguelike with a Pokémon-style 2D overworld, in which every battle is a
chess position. It is built with Godot 4, and Android is the first platform.

The full design is in
[`docs/superpowers/specs/2026-10-26-chess-roguelike-design.md`](docs/superpowers/specs/2026-10-26-chess-roguelike-design.md).

**Current milestone:** the engine spike. It shows that Stockfish runs inside the game on a real
Android phone. The plan is in
[`docs/superpowers/plans/2026-10-26-engine-spike.md`](docs/superpowers/plans/2026-10-26-engine-spike.md).

## Licence

GPLv3. The game ships Stockfish, which is GPLv3.

## Development

You need Godot 4.7.2. Install it with `brew install --cask --appdir="$HOME/Applications" godot`,
or set `GODOT` to point at your Godot binary.

To run the test suite headless, use:

```bash
make test
```

`make test` fails when a test fails, when a test script cannot be loaded, or when nothing ran.
