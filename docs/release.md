# Releasing to Google Play

This is the author's checklist for building the signed Android App Bundle (AAB) that goes to Google Play,
checking it, and trying it on a phone. The bundle is `build/chess-roguelike-<version name>-<version code>.aab`
and its application id is `io.github.orasz.chessroguelike`. The developer APK (`make apk`) has its own id,
`io.github.orasz.chessroguelike.dev`, so the two never collide on a phone.

## Tools, once

Everything in the Android setup of the [README](../README.md#android-setup) applies: JDK 17, the Android SDK
(build-tools 36.1.0, platform 36, NDK r28b) and the Godot 4.7.2 export templates, `android_source.zip` included.

- **bundletool** checks the bundle and builds the APKs that `make install-aab` puts on the phone. It needs a JDK
  of 11 or later, and the JDK 17 of the Makefile does. Download `bundletool-all-1.18.3.jar` (32,520,401 bytes)
  from <https://github.com/google/bundletool/releases/tag/1.18.3> and save it as `build/tools/bundletool.jar`
  (`build/` is not tracked). GitHub lists its SHA-256 as
  `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`; check it with `shasum -a 256`.
  Another location is possible: `make check-aab BUNDLETOOL=/path/to/bundletool.jar`.
- **Godot's Gradle build template** is installed by `make android-template` (it runs inside `make aab`). It lands
  in `game/android/`, which git ignores: it is about 216 MB and regenerable. Godot has no command that only
  installs it, so the target uses the `--install-android-build-template` flag together with an export that is made
  to fail before it builds anything. Delete `game/android/` to force a reinstall; the target also does it by
  itself when the template's version differs from the Godot in use.
- **The first `make aab`** is a Gradle build. Gradle downloads its own distribution and the Android Gradle plugin's
  dependencies, so it needs the network the first time. Godot's template names NDK 29.0.14206865
  (`ndkVersion` in `game/android/build/config.gradle`) while the setup installs r28b. The native libraries are
  prebuilt, not compiled by Gradle, but Gradle may still want that NDK to strip them. If the build complains,
  install it with `sdkmanager --sdk_root="$ANDROID_HOME" "ndk;29.0.14206865"` (about 1.05 GB to download).

## The upload key, once

Google Play signs what users install with a key that Google holds (Play App Signing). You sign each upload with
a separate **upload key**, so Google can verify who uploaded. If the upload key is lost or leaked, Google resets
it from your account; a lost app-signing key would end the app. That is why the bundle is signed with an upload
key and never with the key that users' phones check.

Create it in your own terminal, with the keystore outside the repository:

```bash
mkdir -p ~/keys
keytool -genkeypair -v -keystore ~/keys/chess-roguelike-upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000
```

- Use the **same password** for the keystore and for the key (Godot needs it), and no special characters in it.
- Keep a **backup** of the `.jks` file and of the password outside this repository and outside this computer (a
  password manager, an encrypted drive). Never commit them, paste them in a chat or a log, or write them in a
  Makefile or a file.
- Nothing in the repository reads or stores the password. `make aab` reads it from three environment variables
  of your shell, and it is the only target that uses the upload key:

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/keys/chess-roguelike-upload.jks"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
read -rs "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD?Upload key password: "; export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

The `read` is for zsh; it keeps the password out of the shell history and of the screen. In bash, use
`read -rs -p "Upload key password: " GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. The variables last as long as the
terminal window does.

## Building, checking, trying

```bash
make aab                 # builds, imports, installs the template, exports and signs the bundle
make check-aab           # checks build/chess-roguelike-<version>.aab; pass AAB=<file> to check another one
make install-aab         # builds the APKs for the USB phone, signed with the debug key, and installs them
```

`make aab` stops at once, with a message, when one of the three variables is missing or the keystore file does not
exist. It builds the release engine library (`make native-android-release`) first.

`make check-aab` prints one PASS or FAIL line per condition and exits with 1 when any fails. It requires:

1. `bundletool dump config` shows `PAGE_ALIGNMENT_16K`;
2. `libstockfish_gd.android.template_release.arm64.so` is in the bundle;
3. every `base/lib/arm64-v8a/*.so` has only LOAD segments with `align 2**14` (16 KB), read with the NDK's
   `llvm-objdump -p`;
4. every one of those libraries is stored in the zip, not deflated (the 16 KB zip alignment depends on it);
5. the manifest has the Play id, the `versionCode` of the preset, `targetSdkVersion` 36 and no `uses-permission`.

`make install-aab` asks bundletool for the APKs of the connected phone and installs them: the same split APKs
a download from Play gives, unlike `make install`. They are signed with bundletool's default **debug key**,
`~/.android/debug.keystore` (the target creates it with the public debug values, password `android`, when it is
missing), so the upload key and its password never reach bundletool. For that reason this install cannot update
a copy that came from Play, nor be updated by it: uninstall one before installing the other. Launch the app,
play a move against the engine, and watch `make logcat` for `FATAL`.

## Uploading

Play Console, your app, **Test and release**, then the track (closed testing for the beta), **Create new
release**: upload the `.aab` and accept Play App Signing when it asks (the first upload enrolls the app). The
upload key's certificate is registered from that first upload. The application id is permanent from then on.

## The next release

Play refuses an upload whose `versionCode` is not higher than every earlier one. In `game/export_presets.cfg`,
section `[preset.1.options]` of the "Android Play" preset:

- raise `version/code` by at least one;
- change `version/name` when the user-visible version changes.

The bundle's file name, the build and `make check-aab` all read these two values from the preset, so nothing else
needs editing. The preset's `export_path` is only the default of Godot's editor; update it too if you export from
the editor. Run `make aab` and `make check-aab` again before each upload.
