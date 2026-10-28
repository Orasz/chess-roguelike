# Open-beta release: facts from primary sources

- **Date of research:** 2026-10-28
- **Project:** free, open-source (GPLv3) Android chess roguelike, Godot 4.7.2 + GDScript, Stockfish `sf_19` in a custom
  GDExtension (`native/`, scons + Android NDK). No network in the app, no proprietary SDKs, no analytics, zero budget.
- **Context:** [0001 engine integration](../decisions/0001-engine-integration.md),
  [0002 vertical slice](../decisions/0002-vertical-slice.md).

## How to read this

- Each answer gives the value, the primary-source URL, and the date or version the source states. Google Play Console Help
  pages show **no "last updated" date**; where a date exists it is given.
- **[local]** marks a fact verified on this machine. "Not stated" means the source is silent; nothing was filled in from memory.
- Google's wording is paraphrased with the page and heading named; one short exact fragment appears in Q2.
- Nothing in the repository was changed except this file; no build was run. Read-only tools used: NDK r28b
  `llvm-objdump`/`llvm-readelf`, `aapt2`, `zipalign`, `unzip`, `cmp`. Web pages were fetched as plain text.

---

## Q1. Google Play, new app, new personal developer account (as of 2026-10-28)

### 1.0 Prerequisites outside the question that gate everything

| Item | Value | Source |
|---|---|---|
| Registration fee | **US$25**, one time. Prepaid cards not accepted. | [Get started with Play Console](https://support.google.com/googleplay/android-developer/answer/6112435) |
| Identity | Owner 18+. A government ID and a credit/debit card in the legal name may be requested; an invalid ID forfeits the fee. | same page |
| Device verification | Personal accounts verify a real, non-rooted Android 10+ phone with the Play Console mobile app before publishing. | [Device verification](https://support.google.com/googleplay/android-developer/answer/14316361) |
| Package name | Unique and **permanent**; cannot be deleted or reused. The slice uses `io.github.chessroguelike.slice`; 0002 leaves the final id open. | [Create and set up your app](https://support.google.com/googleplay/android-developer/answer/9859152) |
| Package registration | From 2026-09-30 every Play package must be registered (Android developer verification) or it is removed. Google auto-registers by signing key; manual registration is a small signed APK carrying a Play snippet. | [Registering Play package names](https://support.google.com/googleplay/android-developer/answer/16984799) |

**The fee conflicts with the zero budget.** No source read offers a waiver for a personal Play account.

### 1.1 Target API level

- **New apps and updates must target Android 16 (API 36) or higher, in effect since 2026-08-31.** Existing apps need API 35
  to stay visible to new users; an extension to 2026-11-01 can be requested (the page does not say for whom; moot for a new app).
- Sources, in agreement: [Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
  (no date shown) and [developer.android.com/google/play/requirements/target-sdk](https://developer.android.com/google/play/requirements/target-sdk)
  (last updated 2026-10-16 UTC).
- **[local]** Godot 4.7.2 defaults to target SDK 36 (Q3); `aapt2 dump badging build/slice.apk` reports
  `targetSdkVersion='36'`, `minSdkVersion='24'`. Nothing to change.
- Effect of targeting 36 ([Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16),
  last updated 2026-10-23 UTC): no edge-to-edge opt-out, and on displays of 600 dp smallest width or more, orientation,
  resizability and aspect-ratio restrictions are ignored. The portrait lock (`window/handheld/orientation=1`) does not hold on tablets.

### 1.2 16 KB memory page size for native code

- **Who:** apps that contain native code. [developer.android.com/guide/practices/page-sizes](https://developer.android.com/guide/practices/page-sizes)
  (last updated 2026-10-16 UTC): apps targeting API 35+ must support 16 KB pages on 64-bit devices on Google Play.
  Java/Kotlin-only apps already comply. The [technical quality requirements](https://support.google.com/googleplay/android-developer/answer/17492799)
  page (no date shown) adds that native-code apps must support 64-bit-only architectures, so `arm64-v8a` only is compliant.
- **Since when (ambiguous):** the Android guide says updates that do not support 16 KB cannot be released **from 2027-02-01**.
  The Android Developers Blog of 2025-05-08 said 2025-11-01 and has no update banner; the current guide supersedes it. The
  technical-quality page says new app bundles must support 16 KB but dates only TV (2026-08-01) and Wear OS (2026-09-15).
  Not stated: whether a **new** phone app is blocked before 2027-02-01. Plan as if it is.
- **Toolchain rule:** NDK r28+ links 16 KB-aligned by default; r27 and older need
  `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384`. AGP 8.5.1+ with **uncompressed** libraries aligns the zip.
- **Exact checks** (from the guide):
  - ELF, per `.so` (every LOAD line must show `align 2**14` or more):
    `<NDK>/toolchains/llvm/prebuilt/<host>/bin/llvm-objdump -p libX.so | grep LOAD`
  - APK zip alignment (last line "Verification successful"): `<SDK>/build-tools/<35.0.0+>/zipalign -v -c -P 16 4 app.apk`
  - AAB: `bundletool dump config --bundle=app.aab | grep alignment` must print `PAGE_ALIGNMENT_16K` (`4K` means unaligned
    zip). Then unzip the `.aab` (libraries are under `base/lib/arm64-v8a/`) and run the `llvm-objdump` check.
  - RELRO: `llvm-readelf -Wl libX.so | grep 'RELRO\|Type'`; `(VirtAddr + MemSiz) % 0x4000` should be 0 unless GNU_RELRO has its own LOAD.
- **[local] Our result: compliant** (NDK `28.1.13356709` = r28b).
  - `game/bin/android/libstockfish_gd.android.template_debug.arm64.so`: all four LOAD segments Align `0x4000`. GNU_RELRO is
    its own LOAD (`0x5ee23d0 + 0x2c30 = 0x5ee5000`, remainder `0x1000`); the next writable LOAD starts at `0x5ee8e70`, past
    `0x5ee8000`: the case the guide calls compliant.
  - In `build/slice.apk`, `libc++_shared.so`, `libgodot_android.so` and `libstockfish_gd...so` all show `align 2**14`; the
    extracted `libstockfish_gd` is byte-identical (`cmp`) to the file in `game/bin/android/`.
  - `zipalign -c -P 16 -v 4 build/slice.apk` (build-tools 36.1.0): **Verification successful**.
  - Only a **debug** `.so` exists; no release `.so` has been built (Q3.5).

### 1.3 Is AAB mandatory for new apps?

- **Yes**, since August 2021 ([About Android App Bundles](https://developer.android.com/guide/app-bundle), last updated 2026-06-24 UTC).
  Release help allows APKs only for apps created before August 2021 ([Prepare and roll out a release](https://support.google.com/googleplay/android-developer/answer/9859348)).
- Limits are on compressed download size: base module 500 MB, all modules plus install-time asset packs 4 GB
  ([size limits](https://support.google.com/googleplay/android-developer/answer/9859372)). The 127.7 MB debug APK is far below.
- `versionCode` must rise on every upload; maximum 2,100,000,000 (Create and set up your app page).
- The current `make apk` output is a debug APK: fine for GitHub sideloading, not uploadable to Play.

### 1.4 Testing before production (new personal accounts)

- Source: [App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
  (no date shown); applies to personal accounts created after **2023-11-13**.
- **Rule:** a **closed test** with **at least 12 testers opted in continuously for at least 14 days**, then apply for production
  access on the Dashboard. Production and Pre-registration stay disabled until then. Review usually takes up to 7 days; Google may
  ask for more testing (fewer than 12 testers, weak engagement). A tester who opts out early does not count, and a re-opt-in
  must again cover consecutive days. The application asks about the test, the app and production readiness.
- **It also gates open testing:** open testing becomes available only after production access.
- Tracks ([Set up an open, closed, or internal test](https://support.google.com/googleplay/android-developer/answer/9845334)):

| Track | Needs | Notes |
|---|---|---|
| Internal | Nothing; works before app setup is complete | Up to 100 testers by email. An internal tester is **not eligible** for closed or open tests. |
| Closed | App setup complete | Email lists or Google Groups: up to 200 lists of 2,000, 50 lists per track. |
| Open | Production access | Listing must be ready for public view. |
| Production | The 12 x 14-day closed test, then approval | |

- Consequence: the 12 closed testers must not also be internal testers.

### 1.5 Privacy policy and Data safety with no data collected

- **A privacy policy is required even if the app collects nothing and does not target children.** It must be linked on the listing
  **and inside the app**, on a public `http(s)` URL with a valid certificate, readable worldwide without login, as a normal web
  page (not a PDF), specific to the app. Source: [Prepare your app for review](https://support.google.com/googleplay/android-developer/answer/9859455).
- **The Data safety form is required** on closed, open and production tracks, also with zero collection; it must link the policy and
  may state that nothing is collected or shared. Internal-only apps are exempt. "Collect" means sending data off the device;
  on-device processing is out of scope. Source: [Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469).
- Other App content declarations: Ads (No), app access instructions, target audience, content rating, high-risk permissions (none).
- **[local, Godot source]** `OS.shell_open` starts an `ACTION_VIEW` intent
  ([GodotIO.java, 4.7.2-stable](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/GodotIO.java)),
  so an in-app privacy-policy link needs no INTERNET permission.

### 1.6 Content rating and target audience (staying out of Families)

- **Content rating:** an IARC questionnaire in Play Console (App content, category, questions, submit). It returns ratings from
  several authorities (ESRB, PEGI and others), varying by region; required for new apps and for updates that change content;
  wrong answers can lead to removal. The outcome depends on the answers. Source: [Content rating requirements](https://support.google.com/googleplay/android-developer/answer/9859655).
- **Target audience** ([Manage target audience and app content settings](https://support.google.com/googleplay/android-developer/answer/9285070)):
  - Groups: 5 and under, 6-8, 9-12 (children in most locales), 13-15 and 16-17 (may be children in some locales), 18 and over.
  - An app with **at least one** group that includes children must follow the Families policy (including self-certified ad SDKs).
  - The page does **not** say whether 13-15 or 16-17 triggers Families. The only unambiguous way out is **"18 and over" only**.
    Anyone targeting under-21s must check local child law.
  - Child-oriented store art (youthful animation, young characters) can get an app rejected even outside Families.
  - "Restrict Minor Access" (18+ only) blocks Google-determined minors from finding or installing the app; optional.

### 1.7 Store-listing assets

Sources: [Add preview assets](https://support.google.com/googleplay/android-developer/answer/9866151), [Create and set up your app](https://support.google.com/googleplay/android-developer/answer/9859152).

| Asset | Value |
|---|---|
| App name / short / full description | **30 / 80 / 4,000** characters. Short description: no calls to action, rankings, price claims, emoji or symbols |
| App icon | 32-bit PNG with alpha, **512 x 512 px**, max **1024 KB** (separate from the launcher icon) |
| Feature graphic | **1024 x 500 px**, JPEG or 24-bit PNG, **no alpha**; required to publish |
| Phone screenshots | Max **8** per device type; to publish, the page asks for a minimum of two across device types (read here as two in total) |
| Screenshot format | JPEG or 24-bit PNG, no alpha; each side 320 to 3840 px; the long side at most **2x** the short side |
| Screenshot file size | Not stated for phones (8 MB is stated only for Android XR) |
| Game promotion eligibility | At least 3 screenshots, 16:9 or 9:16, at least 1920 x 1080 or 1080 x 1920 |
| Preview video / alt text | Optional YouTube URL / alt text of 140 characters or fewer recommended |

- **[local, arithmetic]** the test phone's screen is 1260 x 2800 (0002), 2.22:1, which breaks the 2x rule: raw `screencap` images
  must be cropped or scaled (for example 1080 x 1920).

---

## Q2. Payments policy and a donation link (GitHub Sponsors, Ko-fi)

Sources: [Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738) and
[Understanding Google Play's Payments policy (FAQ)](https://support.google.com/googleplay/android-developer/answer/10281818); neither shows a date.

- **Scope of the billing rule:** Play apps that *require or accept payment for access to in-app features or services* (items,
  subscriptions, ad removal, new functionality). A free app with no paid feature is outside that trigger (my reading).
- **Carve-outs:** the policy lists cases where Play billing must **not** be used, among them, in its words,
  "peer-to-peer payments, online auctions, and tax exempt donations".
- **The link rule:** apart from those carve-outs and the EEA/US programs, an app may not lead users to a payment method other than
  Play billing. Four routes are named: the app's Play listing; in-app promotions of purchasable content; in-app webviews, buttons,
  links, messages, ads or other calls to action; and in-app flows such as sign-up.
- **The FAQ answers the donation case** (entry on direct tips and contributions from user to creator): Play billing is not required
  when **100 %** of the tip goes to the creator **and** the payment grants no digital content or service (stickers, badges, special
  emoji, and so on); it is then a peer-to-peer payment. If either condition fails, Play billing applies.
- **Reading for us:**
  - A no-perks link to GitHub Sponsors or Ko-fi fits the FAQ's peer-to-peer case.
  - "Tax exempt donations" does not fit a personal Sponsors or Ko-fi page; do not rely on it.
  - Not defined: whether platform or processor fees break "100 %". GitHub's and Ko-fi's fee terms were not read.
  - The policy text does not exempt donation links from the link ban in so many words; the FAQ is the clarifying text. The Play
    listing and the app are the exposed surfaces; a link only in the README or on the project site is on no surface the policy names.
- The policy points to numbered sections 3, 8 and 9 as exceptions; the numbering is not visible in the text read, so the mapping to
  clauses above is my reading of the list order.

---

## Q3. Godot 4.7 Android export for Play

Sources: Godot docs branch `4.7` (via Context7 `/godotengine/godot-docs/__branch__4.7`) and Godot source at tag `4.7.2-stable`
(`platform/android/export/export_plugin.cpp`, `editor/export/*`, `platform/android/java/app/config.gradle`). Docs show no dates.

### 3.1 Exporting an AAB (Gradle build)

- Docs ([android_gradle_build.rst](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/export/android_gradle_build.rst),
  [exporting_for_android.rst](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/export/exporting_for_android.rst)): AAB needs the
  Gradle build. **Project > Install Android Build Template...**, enable **Gradle Build** in the Android preset, set the export format to AAB.
- **What lands in the project** (`export_template_manager.cpp`): `game/android/build/` (unzipped Gradle project: `build.gradle`,
  `config.gradle`, `settings.gradle`, `gradlew`, `src/`, `libs/`, `res/`, `assetPackInstallTime/`, plus an empty `.gdignore`) and
  `game/android/.build_version` (template identifier; builds refuse to run on a mismatch). Movable with `gradle_build/gradle_build_directory`.
- **[local] Size:** `~/Library/Application Support/Godot/export_templates/4.7.2.stable/android_source.zip` is 214,418,211 bytes
  (161 files, 216,152,616 unzipped), almost all in two prebuilt AARs: `libs/debug/godot-lib.template_debug.aar` 112.7 MB and
  `libs/release/godot-lib.template_release.aar` 103.3 MB. The zip has no `.gitignore`.
- **Commit versus ignore:** the docs say the files need no editing unless the project must be modified, and give no version-control rule.
  My recommendation: **ignore `game/android/build/`** (about 216 MB, regenerable); commit only a deliberate customisation, ideally via
  `gradle_build/android_source_template`. `.build_version` is tiny and regenerated. `game/android/` is **not** in the current `.gitignore`.
- **Preset keys:** `gradle_build/use_gradle_build=true`; `gradle_build/export_format` enum (`Export APK`=0, `Export AAB`=1, default APK);
  the output path must end in `.aab`. `--export-release` runs Gradle `bundleRelease`; `--export-debug` runs `bundleDebug`.
- **Toolchain (discrepancy):** docs list build-tools 35.0.1, platform 35, CMake 3.10.2.4988404, NDK r28b, JDK 17. The 4.7.2-stable
  `config.gradle` says AGP 8.6.1, compileSdk 36, buildTools 36.1.0, Kotlin 2.1.21, `ndkVersion` 29.0.14206865; Gradle wrapper 8.11.1; Java 17.
  **[local]** installed: build-tools 36.1.0 and NDK 28.1.13356709 only. Whether Gradle wants NDK 29 is not stated; the first run will show.

### 3.2 Export-preset keys and 4.7.2 defaults

| Key | Default | Notes |
|---|---|---|
| `gradle_build/min_sdk` | empty = **24** | Gradle build only; cannot be below 24 (Vulkan default 29 is irrelevant: GL Compatibility) |
| `gradle_build/target_sdk` | empty = **36** | Gradle build only; at least `min_sdk` |
| `version/code` | **1** | Docs: must rise on every Play release |
| `version/name` | empty | Falls back to `application/config/version`. **[local]** debug APK: `versionName='1.0.0'`, `versionCode='1'` with neither set |
| `package/unique_name` | `com.example.$genname` | Ours: `io.github.chessroguelike.slice` |
| `architectures/arm64-v8a` | true (the only default ABI) | Ours: arm64 only |
| `gradle_build/compress_native_libraries` | false | Docs advise false for Play |
| `user_data_backup/allow` | false | Manifest `allowBackup=false` **[local]** |

Our `game/export_presets.cfg` sets only `use_gradle_build=false`, the architectures, `package/unique_name` and `package/name`.

### 3.3 Release signing and Play App Signing

- **Keys:** `keystore/release` (path), `keystore/release_user` (alias), `keystore/release_password`. Docs: keystore and key
  password must be equal; avoid special characters.
- **Environment variables** (docs table "Android export environment variables"; constants in `export_plugin.h`):
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`
  (plus the `..._DEBUG_*` trio). In `EditorExportPreset::get_or_env` a **non-empty environment variable wins over the preset value**.
- The keys are secret options, so the editor stores them in `res://.godot/export_credentials.cfg`, not in `export_presets.cfg`;
  `.godot/` is already ignored here. The Makefile exports only the `DEBUG` trio.
- Godot passes them to Gradle as `-Prelease_keystore_file/alias/password`; a missing keystore file aborts the export.
- **Play App Signing** ([page](https://support.google.com/googleplay/android-developer/answer/9842756), no date): for a new app Google
  generates the app signing key and enrols the app on first upload. You make an **upload key** (Android Studio or `keytool`), sign the
  AAB with it and register its certificate; a lost or leaked upload key can be reset. Google advises different upload and signing keys.
  The signing key can be changed only before the first open-test or production rollout.

### 3.4 Permissions

- All `permissions/*` boxes default to **false**; `permissions/custom_permissions` is empty. The template manifests declare no
  `uses-permission`. `INTERNET` is added only for debug runs with remote debug or the dumb-client flag (`p_give_internet`), not for a
  normal `--export-debug` or `--export-release`.
- **[local]** `aapt2 dump permissions build/slice.apk` lists **none**. The manifest has `uses-feature` entries (GLES 3.0,
  `screen.portrait`, implied `faketouch`); these are features, not permissions.
- **To export with none:** leave every box unticked and `custom_permissions` empty; do not use "Deploy with Remote Debug". Check with
  `aapt2 dump permissions <apk>`, or `bundletool dump manifest --bundle=app.aab` for an AAB (`bundletool` is **not installed** here).

### 3.5 How GDExtension `.so` files are packaged in a Gradle build

- `copy_gradle_so` copies each library the `.gdextension` selects for the export features to
  `android/build/libs/<debug|release>/<abi>/<file>`; the Gradle module maps `jniLibs.srcDirs` there. The file name must start with
  `lib` and the entry needs an ABI tag (`arm64`) or the export fails.
- `debug` or `release` in that path follows the export type, so `--export-release` needs an `android.release.arm64` library
  (entries match by feature tags, first match wins: [gdextension_file.rst](https://github.com/godotengine/godot-docs/blob/4.7/engine_details/engine_api/gdextension/gdextension_file.rst)).
- **[local]** `game/bin/stockfish_gd.gdextension` already lists `android.release.arm64 = .../libstockfish_gd.android.template_release.arm64.so`,
  but that file does not exist: `make native-android` builds only `target=template_debug`.
- With `compress_native_libraries=false` and AGP 8.6.1 (8.5.1+ needed) libraries are stored uncompressed and 16 KB zip-aligned: read from
  the template config and the flag Godot passes, **not yet checked on a built AAB**.
- Our `.so` lists `libc++_shared.so` as NEEDED; Godot's template supplies it (**[local]** 1,374,336 bytes, 16 KB-aligned).

### 3.6 Launcher icon settings

Keys in the Android preset (docs [exporting_for_android.rst](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/export/exporting_for_android.rst), class reference `EditorExportPlatformAndroid`):

| Key | Minimum | Used on |
|---|---|---|
| `launcher_icons/main_192x192` | 192 x 192 | Android below 8 |
| `launcher_icons/adaptive_foreground_432x432` | 432 x 432 | Android 8+ |
| `launcher_icons/adaptive_background_432x432` | 432 x 432 | Android 8+ |
| `launcher_icons/adaptive_monochrome_432x432` | 432 x 432 | Android 13+ themed icon, optional |

- Safe zone: centred 66 dp circle (264 px at xxxhdpi). Fallbacks when empty: main = project icon (`application/config/icon`) then Godot
  default; foreground = main, then project icon, then default; background = Godot default only; monochrome has none. The slice has
  no icon (0002), so Godot's shows. This is separate from the 512 x 512 Play listing icon (Q1.7).

### 3.7 Our native build (`native/SConstruct`, godot-cpp)

- godot-cpp is `10.0.0-stable`, `api_version=4.7`. `tools/android.py` defaults: `ndk_version=28.1.13356709` (r28b),
  `android_api_level=24` (forced up from lower), `ANDROID_HOME`-based path, toolchain `darwin-x86_64`.
- **Compile flags (arm64):** `--target=aarch64-linux-android24 -march=armv8-a -fPIC`; Stockfish adds `-O3 -funroll-loops`, `IS_64BIT`,
  `USE_POPCNT`, `USE_NEON=8` (no dotprod on Android); `-fno-exceptions` comes from godot-cpp's `disable_exceptions=True`.
- **Link flags:** `-shared --target=aarch64-linux-android24 -march=armv8-a` and `-llog`. There is **no** `-Wl,-z,max-page-size`:
  16 KB alignment comes from NDK r28b's default. LTO defaults to off on Android.
- **[local]** `.comment`: clang 19.0.0, LLD 19.0.0 (r28b). The alignment depends on the NDK: keep r28+, or add the two flags on r27 or older.

---

## Q4. Stockfish net options for the phone build

### 4.1 What `sf_19` contains **[local]** (`native/thirdparty/Stockfish`, HEAD `edb0d9d`, tag `sf_19`)

- **There is no small net in `sf_19`.** `evaluate.h` defines one name, `EvalFileDefaultName` = `nn-1a298aa575a0.nnue`; there is no
  `EvalFileSmall`, no second `Network`, and no small-net path in `evaluate.cpp`. The [Stockfish 19 release post](https://stockfishchess.org/blog/2026/stockfish-19/)
  (2026-09-05) introduces the SFNNv16 architecture and says the secondary net introduced in 16.1 was **retired**. The premise "default
  big and small net names" does not apply to this version.
- **The one net:** `native/nn-1a298aa575a0.nnue` is **98,511,183 bytes (93.95 MiB)**; its SHA-256 starts `1a298aa575a0`, as named.
  Lichess's notes give the same size. The runtime reports 109 MiB in memory (0001).
- **`EvalFile`** (`engine.cpp`): string option, default the name above. Setting it calls `load_network(path)`: the default name loads the
  embedded copy; any other value is read with `ifstream` from the working directory, the binary directory, or the given path. The net
  must match the compiled architecture hash. `export_net <file>` writes the embedded net out (used by `tests/instrumented.py`).
- **Hazard:** `Engine::go`, `Engine::perft` and the eval trace call `verify_network()`, which prints an error and calls
  **`exit(EXIT_FAILURE)`** if the selected net did not load. In our process that ends the app, the same class as 0001's `std::exit`
  note; `validate_position` does not cover a missing or wrong net.
- **Small net only?** **No option and no build flag** in `sf_19` selects a smaller net. Related: `-DNNUE_EMBEDDING_OFF` (below) and
  loading another architecture-compatible file via `EvalFile`; no smaller official net of this architecture is named in the source.
- **What embedding does** (`nnue/network.cpp`): `INCBIN(EmbeddedNNUE, EvalFileDefaultName)` assembles the file into the library as
  read-only data and `load_internal` parses it from memory. `-DNNUE_EMBEDDING_OFF` swaps it for a 1-byte stub (upstream's WebAssembly
  build uses it), after which only `EvalFile` can supply a net. **[local]** our `.so`'s first read-only LOAD is `0x5e3fc50` bytes
  (94.2 MiB), mostly that blob. Our `SConstruct` embeds it.

### 4.2 Lichess mobile and `multistockfish` "light"

- **Repo:** [lichess-org/dart-multistockfish](https://github.com/lichess-org/dart-multistockfish), `multistockfish` 0.6.x: Stockfish 19 with
  a small embedded net (about 1 MB), Stockfish 19 with no embedded net, and Fairy-Stockfish. `StockfishFlavor.light` is the default.
- **Light net:** `nn-61e7af4bb97d.nnue`, **1,166,381 bytes (1.11 MiB)** (HTTP `Content-Length` of the repo file), SHA-256
  `61e7af4bb97d51eeeb25d322916f86513b5cd3a827ce189c98c6e31946f99e5b` (`android/CMakeLists.txt`). Source:
  [multistockfish_light/UPDATING.md](https://github.com/lichess-org/dart-multistockfish/blob/main/pkgs/multistockfish_light/UPDATING.md).
- **The patch:** the vendored engine carries three changes beyond upstream `sf_19`: a private-I/O patch (like our stream swap), a
  namespace rename, and the **small-net feature-set patch**, which replaces `half_ka_v2_hm` + `full_threats` + `pp_3wide` with one tiny
  set `P_hm` (12 piece types x 64 squares = 768 inputs, mirrored by king side) and points `EvalFileDefaultName` at the matching net.
  - Origin: [niklasf/Stockfish commit 81348d3](https://github.com/niklasf/Stockfish/commit/81348d3fb4f68bda5c442e7459de78ab00acbc55)
    by sscg13, rebased by Niklas Fiekas; **not an upstream commit**. Diffstat from its `.patch`: 19 files, +215 / -1,594; it deletes the
    threat and pawn-pair code and edits `position.cpp`, `search.cpp`, `types.h` and the accumulator. `L1` stays 1024 in the diff context,
    so the net is small mainly because the input layer shrinks (my inference).
  - Strength per its message: **+9.75 +/- 2.7 Elo over 20,000 games against `sf18-15mb`** (a 15 MB Stockfish 18 build). Not stated in
    any source read: strength against the 94 MiB `sf_19` net.
  - Check recipe: `bench` must report 2,793,281 nodes for the `sf_19` rebase (the commit's `Bench:` line).
  - Lichess web ships the same idea as `sf_19_smallnet` in [stockfish-web v0.5.0](https://github.com/lichess-org/stockfish-web/releases) (2026-09-05).
- Their Android CMake build uses `-DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -O3` and an explicit `-Wl,-z,max-page-size=16384`.
- **What the Lichess app ships** ([engine_spec.dart](https://github.com/lichess-org/mobile/blob/main/lib/src/model/engine/engine_spec.dart);
  `pubspec.yaml` v0.31.1 pins `multistockfish ^0.6.0`): `light` (embedded net), `latest` (no-embedded-net flavor, net loaded from disk by
  path) and `fairy` (Fairy-Stockfish, used for variants and, per the code comment, for the weakest opponent levels, which need negative
  skill values). The last bears on 0001's open item about opponents below Elo 1320.

### 4.3 What each option changes, as far as the sources say

| | Embedded full net (now) | `EvalFile` from `user://` (`NNUE_EMBEDDING_OFF`) | Light net + P_hm patch |
|---|---|---|---|
| Net file | 98,511,183 B | same file, outside the `.so` | 1,166,381 B (84x smaller) |
| `.so` | 99,474,032 B, **stored uncompressed** in the APK **[local]** | about 1 MB (arithmetic: 99,474,032 - 98,511,183) | about 2 MB (same, plus the small net) |
| Debug APK | 127,967,184 B measured | about 29.5 MB if the net is not in the APK (arithmetic) | about 30.6 MB (arithmetic: 127,967,184 - 98,511,183 + 1,166,381) |
| In-memory net | 109 MiB | 109 MiB | not measured; the 768-input first layer is about 1.5 MiB of `int16` weights (arithmetic, excludes layer stacks) |
| Process memory | PSS 451 to 460 MB, native heap 214 to 222 MB (0001, 0002) | **not measured**; drops the file-backed blob pages but not the heap copy (inference) | **not measured** |
| Engine fidelity | unmodified `sf_19` | unmodified `sf_19` | `sf_19` plus a fork patch |
| New hazard | none | missing or corrupt file at `go` calls `exit(EXIT_FAILURE)` | patch must be re-applied on every Stockfish update |
| Strength | full net | full net | +9.75 +/- 2.7 Elo vs `sf18-15mb`; vs full net not stated |

- **`EvalFile` from `user://` saves no installed size under this project's constraints.** The net must reach the phone: bundled in the AAB
  (no saving; my reasoning: `ifstream` cannot open a `res://` path, so the file would be copied to `user://` and stored twice) or
  downloaded (the app has no network). Play Asset Delivery is a Play library, not checked here, and conflicts with "no proprietary SDKs".
- The light net is the only option in the sources that shrinks both APK and net memory; the cost is a fork patch and a different net lineage.

---

## Open points

1. **US$25 fee versus zero budget**, plus government ID, a non-prepaid card and an Android 10+ phone (Q1.0). No waiver found. GitHub-only
   distribution has a parallel rule: Android Developer Console registration is $25 for full distribution, free for a limited account with
   up to 20 devices ([Understanding Android developer verification](https://support.google.com/android-developer-console/answer/16561738), no date shown);
   enforcement began 2026-09-30 in Brazil, Indonesia, Singapore and Thailand and goes global in 2027, with an "advanced flow" for unverified apps.
2. **Closed-test lead time:** 12 testers x 14 continuous days, then up to about 7 days of review; open testing only after approval.
3. **16 KB and release build:** the date is 2027-02-01 (current guide) versus 2025-11-01 (2025 blog). The debug `.so` passes, but no release `.so`
   exists (`make native-android` builds `template_debug` only; the `.gdextension` release entry points at a missing file) and no AAB has been
   built, so the AAB check (`bundletool`, not installed) is still to do. Needs `scons ... target=template_release` and a Makefile target.
4. **SDK/NDK mismatch inside Godot's own sources** (docs: build-tools 35.0.1, NDK r28b; template: 36.1.0, NDK 29.0.14206865). Confirm on the first Gradle run.
5. **No small net in `sf_19`:** the "small net only" option does not exist upstream. The 1.1 MB route means a fork patch with unmeasured strength
   against the full net; the "not measured" memory cells need a `dumpsys meminfo` run.
6. **Donation link:** the FAQ supports a no-perks tip link, but fee handling versus "100 %" is undefined and the policy does not name donations in
   the link ban. Lowest exposure: README and project site, not the listing or the app.
7. **Target audience:** only "18 and over" is unambiguously outside Families; whether 13-15 or 16-17 pulls it in is not stated. Avoid child-oriented store art.
8. **Target 36 behaviour:** edge-to-edge is mandatory and the portrait lock is ignored at 600 dp and above; 0002's safe-area finding (E1) is live.
9. **Signing channels (inference):** Google signs Play installs with its own key, so a GitHub APK signed with another key cannot update a Play
   install and vice versa. Decide: one key supplied to Play, or two channels.
10. **Fixed once chosen:** the package id (permanent) and a public privacy-policy URL linked on the listing and in the app.
