# 0004 — Open beta build: the release bundle, checked on the phone

- **Date:** 2026-10-28
- **Status:** accepted, with the open items listed in the Consequences
- **Context:**
  - Plan [`docs/superpowers/plans/2026-10-28-open-beta.md`](../superpowers/plans/2026-10-28-open-beta.md), Task 12
  - Decision [0002 — Vertical slice](0002-vertical-slice.md), whose device check this one repeats
  - Decision [0003 — Engine net](0003-engine-net.md), whose phone numbers this one compares against
  - Release notes [`docs/release.md`](../release.md)

## Context

The open beta goes to Google Play as a closed test first. Before the author uploads anything, the bundle that would
be uploaded has to be installed on a real phone and played: the release build differs from the developer APK in its
id, its signing, its stripped libraries and its edge-to-edge window, and several behaviours of the beta plan (the
Back button, the mistake pause, the safe area, the About screen, Italian) had only been tested headless. This check
also produces the store screenshots, which must show the release build.

## What was built

- **The bundle.** `build/chess-roguelike-0.1.0-1.aab`, **27,945,258 bytes**, built from commit `941f66f` with
  `make aab` (Task 10) and signed with the author's upload key, which is kept outside the repository and was typed
  by the author only.
  - Application id `io.github.orasz.chessroguelike`, named "Chess Roguelike"; `versionCode` 1, `versionName` "0.1.0";
    `minSdk` 24, `targetSdk` 36; `arm64-v8a` only.
  - The engine is Stockfish `sf_19` with the light net `nn-61e7af4bb97d` and its P_hm patch, as adopted in 0003.
  - `make check-aab` on this bundle: **14 PASS, 0 FAIL** (native libraries uncompressed with 16 KB page alignment, the
    release extension present, no other ABI, 16 KB LOAD segments in the three libraries, the id, `versionCode` 1,
    `minSdk` 24, `targetSdk` 36, no permission, `allowBackup="false"`, not debuggable). It was re-run read-only
    during this check, with the same result.
- **How it reached the phone.** `make install-aab` built the APK set for the connected phone with bundletool and
  installed it. That APK set is signed with bundletool's **debug** key, not the upload key (ruling R-localsign: Play
  re-signs everything, so nothing on the phone depends on the upload key). The installed splits are `base`,
  `split_assetPackInstallTime` (the game's files), `split_config.arm64_v8a`, `split_config.en` and
  `split_config.xxhdpi`.
- **Nothing was rebuilt, changed or fixed** during the check. Every failure below is a finding for a later task.

## Measurements

**Device:** the same Nothing Phone (3) as in 0001–0003.
- Model A024, Android 17 (SDK 37), system language en-GB.
- The screen is 1260×2800 (9:20). The game sees it as 720×1600 (scale 1.75).
- The camera hole is at x 595–666, y 50–121. The navigation-bar frame is y 2728–2800 and is hidden while the game
  runs (immersive); the system's bottom gesture zone is y 2704–2800.

**How the checks were run:** as in 0002, from the Mac with `adb` (`input tap`, `swipe`, `keyevent`, `screencap`),
with `adb logcat` running for the whole session. The release build is not debuggable, so `run-as` does not work:
the save was judged by behaviour only, never read. Three runs were played: a Club run (puzzles, theory, strong enemy
7DvIR, escaped), a second Club run (strong enemy JubY0, won) and a Beginner run (the theory opening text only). The
strong enemy's moves were chosen with the desktop build of the same light-net Stockfish (`build/stockfish/stockfish`,
1.5–4 s per move), because the game shows no hint before a mistake.

The screenshots named below are kept in the task's working folder (`.superpowers/sdd/2026-10-28-open-beta/device/`),
which is not committed.

| # | Check | Result |
|---|---|---|
| 1 | Cold start | ⚠️ The menu shows. First frame (`am start -W`, force-stopped first): **163, 140, 166 ms**. The time until the engine is ready **cannot be read from a release build**: the bridge copies Stockfish's `info string` lines to logcat only when `DEBUG_ENABLED` is defined (`native/bridge/sf_bridge.cpp`, `mirror`), so neither `Using 1 thread` nor the `NNUE evaluation using` line appears. Indirectly, every battle opened with a working engine (`check-01-menu-cold.png`, `cold1..3.txt`) |
| 2 | Italian | ❌ **Not shown on the device.** The per-app locale was set with `cmd locale set-app-locales … --locales it-IT` (and `it`), and the process configuration read `[it_IT,en_GB]`, but after a force-stop and relaunch every screen stayed English (`check-02-it-menu-2.png`, `-3.png`). Godot reads `Locale.getDefault()` (`GodotIO.getLocale`, read with `javap`). The likely cause, **not verified**: the bundle has Italian Android resources, but the APK set installed only the `en` language split, and Android picks the default locale among the languages the installed resources support. The phone's system language was not changed, by instruction. The catalog itself is shipped (`assets/locale/it.po`, 4,713 bytes, in the asset-pack split) |
| 3 | Edge to edge | ⚠️ **Camera hole: clear** on every screen. The battle's enemy plate starts at y 205, the About title at y 253, the menu's title near y 900, and the overworld shows only map tiles under the hole. **Bottom: content reaches into the hidden navigation bar.** The overworld HUD plate ends at y 2772 and its Potion button spans y 2643–2754; the battle's dialogue box ends at y 2772 and its last line of text, scrolled to the end, reaches y 2737; the About screen's Back button ends at y 2758. All of that is below 2728 (the navigation-bar frame) and 2704 (the gesture zone). The bar is not drawn while the game runs, and taps there worked, but a swipe up from those buttons is the system's gesture (`check-03-overworld-start.png`, `check-E-dialog-after-drag.png`, `check-09-licences-texts-heading.png`) | **Fixed in wave D, re-checked:** every screen now ends above y 2704. The overworld HUD plate spans y 2527–2673 and its Potion button y 2544–2656, the battle dialogue box ends at y 2673 (its last text line at y 2656), the menu ends at y 2075 and the About screen's Back button is at y 1410–1550. A tap on the Potion button and on Back reacted at the first tap (see "Re-check after the fix wave")
| 4 | Back | ✅ Battle → menu with Continue, and Continue restored the same battle (same position, HP 60, moves left 7, same text). Overworld → menu. The new-run confirmation closed on Back, with the menu still there. Menu → the app left (Godot terminated). About → menu. The process stayed alive on every Back except the last (`check-04-*.png`) |
| 5 | Strong enemy | ✅ "Moves left: n" counts down from 12 with every move (12, 11, 10, … 1). A costly mistake showed the arrow and the sentence on the position it refers to, then the reply replaced them: in a burst of captures after a3, the arrow and "After a3, Nxc2 wins your pawn." were on screen at 1.48 s and 2.15 s after the move, and the reply Nd4 was on the board, with no arrow, at 2.82 s (`check-05-burst-a3-0..5.png`). **Escape:** 7DvIR, after three mistakes made on purpose, ended "Gatekeeper Rook escapes!" with 15 HP charged (`check-05-escape.png`). **Win:** JubY0 (start +192 in the record) was won on the 7th move, "Decisive advantage! Gatekeeper Rook is beaten.", with 0 HP lost, by playing the desktop engine's first choice every move (`check-05-run2-m7.png`) | **Fixed in wave D, re-checked:** a capture that is the opponent's immediate reply is named ("After Re5, fxe5 wins your rook."), and a mistake whose best reply is not a capture now reads "After Qf3, the best reply is Be6." instead of naming a later capture as if it were immediate. The counter still counts down (12 to 1) and the Continue button shows at the end. The "can win your" sentence was not reproduced (see "Re-check after the fix wave")
| 6 | Puzzles | ⚠️ The first six puzzles dealt, identified in the bank by position and first move: OpRED (`mateIn2`), zNA1H (`discoveredAttack`), n2DiN (`mateIn1`), 0ZnJr (`fork`), p8aRr (`mateIn3`), OMDUW (`mateIn1`). Four of six are not mate in one. A wrong answer (h3 in OpRED) cost 10 HP and explained itself: "After h3, Rxe2 wins your queen. The best move was Qxe8+.", with the arrow (`check-06-puzzle1-wrong.png`). **In Italian: not tested** (see 2) |
| 7 | Theory | ✅ Each book move showed its own note (e4, Nf3, Bc4, d3, c3), and completing the line showed "Line complete! You played the Italian Game to the end." (`check-07-theory-*.png`). As the code intends (`TheoryEncounter._play_book_move`), the last move's own note (castling) is never shown: the completion line replaces it |
| 8 | Kill in the mistake pause | ⚠️ After the mistake Rb1 (HP 68), Recents was opened 1.0 s after the move and the app swiped away 0.7 s later. Godot stopped its loop at +2.11 s and ActivityManager killed it ("remove task", signal 9) at +2.22 s. After relaunch and Continue: the reply Bxc2 was on the board, **HP 60** (8 HP, a single charge of this mistake), and the dialogue repeated "After Rb1, Bxc2 wins your pawn." (`check-08-continue-restored.png`). The kill was **inside the pause by timing only**: the pause ends about 2.2–2.3 s after the move (0.7 s search plus 1.5 s), so the margin was about 0.1–0.2 s, and the moment itself was not captured. A first attempt (Bxf5) missed: the reply was already shown in the Recents card (`check-08-recents-during-pause.png`) |
| 9 | About | ⚠️ Source code and Send feedback opened the browser on `github.com/Orasz/chess-roguelike` and `…/issues`. Privacy policy opened the browser on `…/blob/main/PRIVACY.md`, which **answered 404**: `PRIVACY.md` is not on the public `main` yet (`origin/main` is at `3a64272`). Licences opened inside the screen **1.2–1.7 s** after the first press (between two captures), scrolled with a finger drag, and "Licence texts" is followed by "Apache-2.0" and the Apache License text (`check-09-*.png`) |
| 10 | logcat, meminfo, size | ✅ No `FATAL`, no `SCRIPT ERROR`, no `ERROR:` and no error line from Godot in 169,431 lines. Every signal 9 of the app's processes comes from a kill made on purpose: the Recents swipe, the quit from the menu, and three force-stops for the locale. Memory and sizes are below |

The checks that the earlier reviews asked for:

| # | Check | Result |
|---|---|---|
| E-themed | The launcher icon | ✅ With themed icons on, the home screen shows a white knight on the dark plate. App info shows the full-colour icon (the knight on a lime circle), the name "Chess Roguelike" and "No permissions requested". The old developer app shows Godot's glyph next to it (`check-E-home.png`, `check-E-icon-appinfo.png`) |
| E-confirm | The new-run confirmation | ✅ Centred over the dimmed menu, well inside the safe area (`check-04-confirm-open.png`) |
| E-legal | The shipped files | ✅ `assets/legal/CREDITS.md`, `assets/legal/GPL-3.0.txt` and `assets/locale/it.po` are in `split_assetPackInstallTime.apk`. The base APK holds no game files at all in a bundle install. None of the five installed APKs has a `test/`, `addons/` (so no GUT), `tools/`, `spike/` or `.gutconfig.json` entry |
| E-dialog | A long text in the dialogue | ✅ The opening plans at the start of the theory fight overflow the box, show a scroll bar, and scroll with a finger drag to their last line; the board does not move. This closes 0002's E2 (`check-E-dialog-before.png`, `check-E-dialog-after-drag.png`) |
| E-language | Enemy names in Italian | ❌ Not tested, for the reason of check 2 |

**Memory in a strong battle** (`dumpsys meminfo`, read right after the second player move of 7DvIR, with the
enemy's reply on the board): TOTAL PSS **242,389 KB**, native heap **102,918 KB** (the Pss Total column). 0003
measured 249,735 KB and 108,120 KB with the light net on the developer build. A second reading at the same point
of JubY0 gave 234,548 KB and 99,897 KB.

**Sizes:**
- AAB: **27,945,258 bytes**.
- Estimated download for this phone (`bundletool get-size total` on the installed APK set): 27,897,910 bytes.
- Installed APKs (`pm path`, then `adb pull`): base 5,230,930; asset pack 428,060; `arm64_v8a` 74,560,038 (the native
  libraries are stored uncompressed, `libgodot_android.so` alone is 71,114,944); `en` 8,538; `xxhdpi` 13,140. Total
  **80,240,706 bytes**. App info reports 81.20 MB in internal storage.

**Seen on the way, not part of a check:**
- **The explanation can name a capture that is not the next move.** "After a3, Nxc2 wins your pawn." was shown with
  the knight on c6: the engine's line was Nd4 and then Nxc2. `ExplanationBuilder._lost_piece` names the first
  capture within its window of plies, as documented, but the sentence reads as if it were immediate.
- **The strong battle's dialogue goes stale.** After a neutral move, the text of the last mistake stays in the box
  until the next mistake or the end.
- **Recents does not pause the game on this launcher.** Godot's `OnPause` came only with the swipe, not when Recents
  opened, so the mistake pause keeps running behind the Recents screen.
- **A system overlay sits on the left edge.** Nothing OS treats the app as a game and draws its game-mode handle
  (window `GAME_ENTRY`, a dark tab at x 0–25, y about 380–700). It is in every capture, the store screenshots too.
- **The last button tapped keeps a lighter colour** on the menu after the confirmation is cancelled.
- **The licences text is plain.** The GPL's hard line breaks give ragged lines when the label wraps them, and
  `CREDITS.md` shows its Markdown (backticks, dashes) as typed.

**Store screenshots.** Four English ones, from the release build in its default locale on this phone, cropped from
1260×2800 to 1260×2240 (9:16) and scaled to 1080×1920 with `sips`, saved as 24-bit RGB PNG without alpha (IHDR colour
type 2, checked). The crops do not remove equal strips: a centred crop would cut the top of the enemy plate (y 205)
and the whole overworld HUD (y 2625–2772). Each keeps what the screen is about and drops the camera hole:

| File | Source capture | Rows kept |
|---|---|---|
| `store/screenshots/en-US/01-menu.png` | `check-08-relaunch-menu.png` (the menu with Continue) | 280–2520 (equal strips) |
| `store/screenshots/en-US/02-overworld.png` | `check-03-ow-2.png` | 532–2772 (to the HUD's bottom edge) |
| `store/screenshots/en-US/03-battle-explanation.png` | `check-05-burst-a3-1.png` (arrow and sentence during the pause) | 160–2400 (both plates, the item bar, the sentence) |
| `store/screenshots/en-US/04-theory-note.png` | `check-07-theory-bc4.png` (the note of Bc4) | 160–2400 |

**No Italian screenshots were taken**, for the reason of check 2: `store/screenshots/it-IT/` stays empty.
`make test-tools` passes with the four English screenshots (121 tests).

## What could not be tested, and why

- **Italian on the device** (checks 2 and 6, E-language, the four Italian screenshots): the game did not follow the
  per-app locale, and the system language was not to be changed.
- **The engine-ready time** (check 1): the release bridge logs no `info string` line.
- **Reading the save** (check 8): the release build is not debuggable, so `run-as` is refused. Resume was judged by
  what the screen showed.
- **The privacy page's content** (check 9): the link is right, but the page does not exist on `main` yet.
- **Signing with the upload key on the phone**: the installed APKs carry the debug key by design (R-localsign).

## Decision

**The release bundle runs on the phone and is the build for the closed test, once the privacy page is published
and Italian is confirmed.** It installs from the bundle, starts in about 150 ms to its first frame, uses about
237 MiB in a strong battle, plays every encounter, saves and resumes through Back, a swipe from Recents and the
mistake pause, and holds no test or tooling file. The two open items block the store listing, not the build:
- `PRIVACY.md` must be on `main` of the public repository before the listing links to it, or the in-app link and
  the listing's link both show a 404.
- Italian must be shown once on a device before the Italian listing is published, with the Italian screenshots taken
  from it.

## Consequences

These are inputs for the closed test.

- **Before the closed test starts:**
  - Merge to `main` and push, so that `https://github.com/Orasz/chess-roguelike/blob/main/PRIVACY.md` answers.
  - Confirm Italian on a device with an installation that carries the `it` language split: a phone whose system
    language is Italian installing from Play's internal or closed track, or a local APK set built with Italian in its
    device spec. Then take the four Italian screenshots, with the same crops as the English ones.
  - Decide whether the game should follow Android's per-app language. If so, the manifest needs a `localeConfig`,
    and the default-locale behaviour above has to be confirmed first.
- **What to ask the testers:**
  - **The strong enemy.** Is converting the advantage within 12 moves fair, too easy or too hard? Did the escape
    feel deserved? The win rate behind the tuning is a simulation: a human-like proxy (MovePicker at the player's
    Elo) won about **61 %** of the strong battles at Club, against 85 % for a player who always plays the engine's
    move. Ask for the moves left when they won, and whether they used a potion.
  - **The "Moves left: n" counter.** Did they see it before the enemy escaped?
  - **The mistake pause.** Did the arrow and the sentence read as "you should have played this", and was 1.5 s
    enough to read them? Did they notice a sentence naming a capture that comes later in the line (the a3 / Nxc2 case
    above)?
  - **Italian wording**, from native speakers, with Task 8's list of candidate changes in hand (for example "Re
    esposto", "Matto in una mossa", "Cavallo del Centro").
  - **The hero.** The player's character is the pack's young "Boy" sprite, and it is in the store screenshots
    (`02-overworld`, and the portrait in `03` and `04`). The audience is set to 18 and over. The author accepted this
    risk (ruling R-hero); the closed test is where Google or a tester may object.
- **Known risks:**
  - **The hero sprite** against the 18+ audience, as above.
  - **The proxy-measured win rate**, about 61 % at Club, is a simulation, not a measurement of people. Retune only
    from the testers' results.
  - **Building behind a TLS-intercepting proxy.** On the author's company network Gradle needs a truststore with the
    proxy's certificates (`docs/release.md`, "Building behind a TLS-intercepting proxy"). Every `make aab` for a later
    `versionCode` has to be run the same way, or from another network.
  - **The bottom of the screen.** The HUD, the dialogue box and the About screen's Back button reach into the hidden
    navigation bar and the system's gesture zone. Testers on phones with a visible three-button bar or a different
    inset may see them covered. A bottom margin from the navigation-bar inset would clear them.
  - **The store screenshots carry Nothing OS's game-mode handle** on their left edge. Retake them on another phone,
    or leave them as they are: it is a thin dark tab outside the game.
  - **The engine-ready time is no longer measured.** A later device check needs a debug build, or a release log line
    of its own, to compare with 0002 and 0003.

## Re-check after the fix wave (2026-10-28)

The release bundle rebuilt from `6741b34` (installed 22:42:57, `dumpsys package` `lastUpdateTime`) was played again on the same
Nothing Phone (3), with the same method as above (`adb` input, `screencap`, `logcat` running for the whole session). The
evidence is in `.superpowers/sdd/2026-10-28-open-beta/device/` (not committed), files `recheck-*.png` and `recheck-logcat.txt`.
Every input was sent through a guard that refused unless the game had focus. Measurements are the lowest y of readable or
tappable content, in physical pixels (the gesture zone starts at y 2704).

| # | Check | Result |
|---|---|---|
| (a) | Bottom margin | ✅ Menu: lowest content (About button) y 2075 (`recheck-01-menu.png`). Overworld: HUD plate y 2527–2673, Potion button y 2544–2656 (`recheck-05-overworld.png`, `recheck-17-ow-6.png`); was 2772 and 2643–2754. Battle: dialogue box ends y 2673, its last text line y 2656 on the long theory text (`recheck-39-theory-open.png`, `recheck-19-strong-open.png`); was 2772 / 2737. About: Back button y 1410–1550 (`recheck-02-about.png`); was 2758 (the screen now lays out from the top). The closest content is 31 px above the gesture zone (the plate and the box) and 127 px above the bottom edge. **Taps:** the Potion button (HP 90, tapped at y 2601) restored HP 100/100 and showed "Potion x0" at the first tap (`recheck-10-potion-tapped.png`); Back on the About screen returned to the menu at the first tap (`recheck-03-after-about-back.png`) |
| (b) | Explanation sentence | ⚠️ Three sentences seen, all read sensibly: "After h3, the best reply is Qxd1. The best move was Qxd3." (puzzle wrong answer, `recheck-08-puzzle-wrong.png`); "After Qf3, the best reply is Be6." (strong battle, HP -30, `recheck-20-qf3-a.png`); "After Re5, fxe5 wins your rook." (strong battle, immediate capture, `recheck-27-re5-a.png`). The old confusing sentence, a later capture named as the next move, did **not** appear. The new "After <move>, the opponent can win your <piece>." was **not reproduced**: the position of that battle was lost after the first mistake, and the moves tried (Qd3, Nd5, a3, h3, Bd2, Bc3, a4) were small mistakes that showed no sentence. Its unit tests cover it, the device does not |
| (c) | Counter and end of battle | ✅ "Moves left: n" counted down 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 with every move (`recheck-19`, `-20`, `-21` to `-31`). After the last move the battle ended with "Gatekeeper Rook escapes!", 15 HP charged (62 to 47), the counter hidden and the Continue button shown at y 1781–1890 (`recheck-31-end-b.png`). Continue returned to the overworld (`recheck-32-ow-after-strong.png`) |
| (d) | Regression | ✅ Back from a puzzle battle to the menu, then Continue: the same position and HP 47/100 (`recheck-34-back-menu.png`, `recheck-35-continue.png`). Back from the overworld to the menu worked; a new run replaced the save through the confirmation. `logcat` of the whole session (60,525 lines from 22:53): no `FATAL`, no `SCRIPT ERROR`, no Godot error line; the only process death is the force-stop made on purpose before the cold launch. The first 10 minutes of the session (a first logcat, overwritten when the capture was restarted) held a cold launch, a force-stop and no input |

Seen on the way, not part of a check:
- **The dialogue still goes stale** after a move that is not a mistake: "After Qf3, the best reply is Be6." stayed in the box through the next five moves (known, see above).
- **The explanation appears only for a costly mistake.** Moves that lose a few centipawns (HP -3, -5, or none) show no sentence at all, so a lost position gives few sentences.
- The phone was in use by the author during the first minutes of the session; the check started again after the author released it.

**The four English store screenshots were retaken** from this build. Crop: 30 physical px removed from both the left and the right edge
(the game-mode tab is gone), width 1200, height 2133, then `sips -z 1920 1080`; 24-bit RGB, IHDR colour type 2, checked on all four.
The camera hole (y 50–121) is outside every crop.

| File | Source capture | Rows kept |
|---|---|---|
| `01-menu.png` | `recheck-01-menu.png` (menu with Continue) | 380–2513 (the content, y 817–2075, centred) |
| `02-overworld.png` | `recheck-06-ow-walk.png` (new Club run, HP 100, Potion x1, the hero on the road) | 545–2678 (down to the bottom of the HUD plate, y 2673) |
| `03-battle-explanation.png` | `recheck-27-re5-a.png` (the arrow and "After Re5, fxe5 wins your rook.", moves left 4) | 170–2303 (both plates, the item bar, the sentence) |
| `04-theory-note.png` | `recheck-42-t-bc4.png` (the note of Bc4) | 170–2303 |

The overworld's HUD plate loses 2 px of its side border to the 30 px crop. No Italian screenshots were taken: the Italian listing
falls back to the English set, because the author declined to switch the phone language. `make test-tools` passes (121 tests).
