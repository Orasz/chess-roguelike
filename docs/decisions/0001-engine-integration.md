# 0001 — Engine integration: Stockfish in-process through a GDExtension

- **Date:** 2026-10-27
- **Status:** accepted
- **Context:**
  - Spec §10, "Biggest technical risk"
  - Spec §14, step 1
  - Plan [`docs/superpowers/plans/2026-10-26-engine-spike.md`](../superpowers/plans/2026-10-26-engine-spike.md), Task 6

## Context

The game needs a chess engine on the phone for strong enemies, the final boss and HP as
advantage. Android 10 and later block running a bundled executable, so the usual desktop approach
(launching Stockfish as a separate process) is not available. No maintained Stockfish plugin for
Godot 4 on Android existed. The spike had to prove that Stockfish can run inside the game on a real
arm64 phone, play a move at a chosen strength, and report its evaluation.

## What was built

The work is in Tasks 1–5 of the plan, plus the fixes from the final review.

- **The extension.** The C++ GDExtension (`native/`) compiles **unmodified Stockfish `sf_19`**,
  together with its embedded NNUE net, into one shared library. Stockfish's UCI loop runs on a
  background thread with an 8 MB stack.
- **How it talks to the game.** `std::cin` and `std::cout` are swapped for in-memory stream
  buffers, and only complete lines reach GDScript.
- **Exit-proof validation.** `validate_position` runs Stockfish's own `Position::set` and the same
  legal-move lookup on a scratch position. Any FEN or move that would make Stockfish call
  `std::exit` is rejected before it is sent.
- **Logging.** The engine's last messages, and on Android every `info string` and `std::cerr`
  line, are mirrored to logcat.
- **GDScript side.** `UciEngine` (`game/engine/uci_engine.gd`) is the only entry point. It clamps
  `UCI_Elo` to 1320–3190 and refuses commands while a search is running.
- **Tests.** 31 GUT tests run headless on macOS.

## Measurements

**Device:** Nothing Phone (3), model A024, codename Metroid.
- Android 17 (SDK 37) on a Snapdragon SM8735, `arm64-v8a`.
- The CPU supports dotprod (`asimddp`). The build does not use it yet.
- 11 GB RAM, 4 KB pages.

**Build:**
- Debug APK: **127.7 MB** (127,735,063 bytes).
- The `libstockfish_gd` arm64 library inside it: 99.5 MB, of which about 94 MiB is the embedded net.

**How the checks were run:** from the Mac with `adb`, using `input tap`, `keyevent` and `swipe`
gestures, with screenshots taken through `screencap`. The only manual step was enabling USB
debugging on the phone.

| # | Check | Result |
|---|---|---|
| 1 | Cold start until the status reads `Ready` | ✅ The first frame appears 378 ms after launch (`am start -W`). `Ready` shows in ≤ 2.4 s on first launch and ≤ 1.8 s on relaunch; both figures include screenshot latency |
| 2 | Ten Play presses at Elo 1320 | ✅ Ten legal moves: `c2c4 d7d6 e2e3 e7e5 b1c3 g7g6 d2d4 f8g7 d4e5 g7e5`. The evaluation updated each time, ending at −0.29 at depth 15 |
| 3 | Full strength, then Play | ✅ It played `g1e2 b8c6 b2b3`, reaching depth 18 within 1 s |
| 4 | Mate check | ✅ `a1a8` was found as mate 1, in 13 ms |
| 5 | QGA check | ✅ `d1f3` at +5.52, depth 17. The engine agrees with opening theory |
| 6 | Speed at full strength, 1 thread, 1000 ms | 224–250 knps, depth 17–18 |
| 7 | Home during a search, wait 10 s, return | ✅ The same process (pid 9277) survived. The background search's move (`c8f5`) was applied, and the next Play worked |
| 8 | Swipe the app away from Recents, then relaunch | ✅ ActivityManager killed it with `remove task`. On relaunch it was `Ready` within 1.8 s |
| 9 | logcat for the whole session | ✅ No `FATAL`, no `signal 11` or `SIGABRT`, no unexpected process exit. Stockfish's `info string` lines appear under the `stockfish` tag |

**Memory after a session** (`dumpsys meminfo`): TOTAL PSS **451 MB**, native heap 214 MB.
Stockfish reports that its net uses 109 MiB in memory, and that the "Shared memory [is] not
supported by the OS", so it falls back to a local allocation.

## Decision

**The GDExtension route is confirmed.** Stockfish runs in-process on a current Android phone,
starts in under 2.5 s, plays at a chosen strength, reports its evaluation, and survives being sent
to the background and being killed. We will not use the fallbacks from spec §10: a Godot Android
plugin calling Stockfish through JNI, or an engine of our own.

## Consequences

These are inputs to the vertical-slice plan.

- **Net strategy before the open beta.** The embedded full net makes the APK 127.7 MB and uses
  about 451 MB of memory in total. Two alternatives need evaluating:
  - The **1.1 MB light net** that Lichess uses. It needs a small Stockfish patch, but it would cut
    both numbers drastically and is still far stronger than any player the game targets.
  - **`EvalFile` loaded from `user://`.** This keeps the APK small, but not the memory use.
- **Opponents below Elo 1320.** `UCI_Elo` cannot go lower than 1320, so beginner opponents need
  a weakening approach of their own (spec §10).
- **The `std::exit` hazard is contained.** Every position and move now goes through Stockfish's
  own validation before it is sent. The vertical slice must keep sending engine commands only
  through `UciEngine`.
- **Screen shape.** The 720×1280 (9:16) base shows black bars on a 9:20 phone. The slice should
  use the `expand` stretch aspect, or design for taller screens.
- **dotprod.** This phone supports it, but the Android build targets plain `armv8` for
  compatibility. A runtime-dispatched build is a later optimisation, not a blocker.
- **Lifecycle.** A paused search finishes in the background, and its move arrives on resume. The
  slice decides whether a backgrounded battle pauses its clock (spec §7) or cancels the search.
