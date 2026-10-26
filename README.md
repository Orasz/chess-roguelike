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
| `make apk` | Exports `build/spike.apk` (debug) |
| `make install` | Installs it on the USB-connected phone |
| `make logcat` | Follows Godot's log on the phone |
