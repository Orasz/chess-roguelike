# Chess Roguelike

A free, open-source mobile roguelike with a Pokémon-style 2D overworld, in which every battle is a
chess position. It is built with Godot 4, and Android is the first platform.

The full design is in
[`docs/superpowers/specs/2026-10-26-chess-roguelike-design.md`](docs/superpowers/specs/2026-10-26-chess-roguelike-design.md).

**Current milestone:** the vertical slice. It is one playable zone: a map assembled from
hand-made chunks, Lichess one-move puzzles, a theory encounter for the Italian Game, a strong
enemy with HP as advantage, run HP and a potion, and a save that resumes even in the middle of a
battle. The plan is in
[`docs/superpowers/plans/2026-10-27-vertical-slice.md`](docs/superpowers/plans/2026-10-27-vertical-slice.md).
The engine spike that came before it
([`docs/superpowers/plans/2026-10-26-engine-spike.md`](docs/superpowers/plans/2026-10-26-engine-spike.md))
stays in the project as a developer scene, `res://spike/engine_spike.tscn`.

## Licence

GPLv3. The game ships Stockfish, which is GPLv3.

## Development

You need Godot 4.7.2 and SCons. Install them with
`brew install --cask --appdir="$HOME/Applications" godot` and `brew install scons`, or set
`GODOT` to point at your Godot binary.

After cloning, fetch the submodules (godot-cpp and Stockfish):

```bash
git submodule update --init
```

The engine is Stockfish `sf_19` with the light net `nn-61e7af4bb97d` (1.1 MB), which needs a patch:
[`native/patches/sf19-light-net.patch`](native/patches/sf19-light-net.patch). Both are committed, and
`make` applies the patch to a copy of the submodule in `build/stockfish-light/`, so the submodule stays
untouched. Why the game uses this net and not Stockfish's 94 MiB one is in
[decision 0003](docs/decisions/0003-engine-net.md). The first `make test` builds that copy and the
native extension, which takes a few minutes. `make check-engine` builds the desktop engine and checks
that its `bench` reports 2793281 nodes. The Makefile says how to build the full net instead.

To run the test suite headless, use:

```bash
make test
```

`make test` fails when a test fails, when a test script cannot be loaded, or when nothing ran.

`make test-tools` runs only the Python tests of the offline tools in `tools/`, and `make puzzles`
rebuilds the puzzle subset in `game/data/puzzles/` from the Lichess dump (see
[`CREDITS.md`](CREDITS.md) for where to get it).

## Android setup

The commands below set up the Android build on macOS (Apple Silicon). Homebrew installs avoid
`sudo`.

1. Install the tools: `brew install openjdk@17 android-commandlinetools scons`.
2. Install the SDK packages into `~/Library/Android/sdk`:

   ```bash
   export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
   sdkmanager --sdk_root="$ANDROID_HOME" "cmdline-tools;latest" "platform-tools" "build-tools;36.1.0" "platforms;android-36" "ndk;28.1.13356709"
   ```

   **Behind a TLS-inspecting proxy** (`PKIX path building failed`), add
   `export SDKMANAGER_OPTS="-Djavax.net.ssl.trustStoreType=KeychainStore"`. Java then uses the
   certificates that macOS already trusts.
3. Create the debug keystore at `~/Library/Application Support/Godot/keystores/debug.keystore`.
   Use alias `androiddebugkey` and password `android`. Godot's editor creates it on first run.
4. Install the Godot 4.7.2 Android export templates. Copy `android_debug.apk`,
   `android_release.apk`, `android_source.zip` and `version.txt` into
   `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`. Take them from the
   editor's Manage Export Templates dialog, or from the official `.tpz`.

Then use these `make` targets:

| Target | What it does |
|---|---|
| `make native-android` | Builds the arm64 GDExtension |
| `make apk` | Exports `build/slice.apk` (debug) |
| `make install` | Installs it on the USB-connected phone |
| `make logcat` | Follows Godot's log on the phone |
