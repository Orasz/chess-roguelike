# 0003 — Engine net: the light net, adopted by the author against the plan's rule

- **Date:** 2026-10-28
- **Status:** accepted
- **Context:**
  - Plan [`docs/superpowers/plans/2026-10-28-open-beta.md`](../superpowers/plans/2026-10-28-open-beta.md), Task 1
  - Decision [0001 — Engine integration](0001-engine-integration.md), Consequences
  - Decision [0002 — Vertical slice](0002-vertical-slice.md), Consequences
  - Research [`docs/research/2026-10-28-open-beta-release.md`](../research/2026-10-28-open-beta-release.md), Q4

## Context

0001 and 0002 measured the embedded full net (`nn-1a298aa575a0.nnue`, 93.95 MiB): a 128 MB debug
APK and about 450 MiB of memory. Both are heavy for a Play beta. Lichess ships a 1.1 MB net with a
patched Stockfish, and 0001 named it as the alternative to evaluate. Adopting it means carrying a
fork patch on every Stockfish update, so it had to earn its place against a rule written before
the measurement.

## What was measured

- **The light build.** Stockfish `sf_19` with the patch of
  [niklasf/Stockfish commit 81348d3](https://github.com/niklasf/Stockfish/commit/81348d3fb4f68bda5c442e7459de78ab00acbc55)
  (simple mirrored piece-square features, authored by sscg13) and the net `nn-61e7af4bb97d.nnue`.
  Both were taken from the files Lichess vendors, and both were downloaded into `build/` only.
  - Patch: `https://github.com/niklasf/Stockfish/commit/81348d3fb4f68bda5c442e7459de78ab00acbc55.patch`,
    105,794 bytes, SHA-256 `37a59c2ba8b615077f1d0f321e541bd317c6ab8d6af1d75099a7093f101d65d9`.
  - Net: `https://raw.githubusercontent.com/lichess-org/dart-multistockfish/main/pkgs/multistockfish_light/ios/multistockfish_light/Sources/multistockfish_light/nnue/nn-61e7af4bb97d.nnue`,
    1,166,381 bytes, SHA-256 `61e7af4bb97d51eeeb25d322916f86513b5cd3a827ce189c98c6e31946f99e5b`, which matches
    the name and the hash that Lichess pins in its Android build.
  - The patch was applied with `git apply` to a copy of the submodule (`build/stockfish-light/`). The submodule
    itself was never touched.
- **Desktop comparison.** `tools/engine/compare_nets.py` ran a desktop build of each tree
  (`make stockfish-cli`, `ARCH=apple-silicon`, 1 thread, 16 MB hash) on `game/data/puzzles/italian_game.json`:
  the 240 puzzles at 300 ms, and the 80 strong positions at 700 ms, searched after the opponent's first move.
  A puzzle counts as solved when the best move is the second move of the line, or when it is scored as mate
  in one.
- **Phone.** The same Nothing Phone (3) as in 0001 and 0002, driven from the Mac with `adb`. The extension was
  built with `scons ... sf_dir=../build/stockfish-light/src net=nn-61e7af4bb97d.nnue`, exported as the developer
  APK (package `io.github.chessroguelike.slice`) and installed. A Strong run was played: two puzzle battles and
  the strong enemy (Gatekeeper Rook), where two moves were played (Bxc6+ and Bxa8). logcat confirmed
  `NNUE evaluation using nn-61e7af4bb97d.nnue (1MiB, ...)`. `dumpsys meminfo` was read in that battle.
  The full-net APK was then rebuilt, reinstalled, and measured the same way as a baseline: the resumed strong
  battle, after one more move.
- **Engine ready time**, as in 0002: the time from `am start` to the `info string Using 1 thread` line in
  logcat, on the device clock, from a cold start (force-stopped), three runs each.
- **Licence of the net.** Read from the official sources:
  - Fishtest, the Stockfish project's testing server, serves this net
    (`https://tests.stockfishchess.org/api/nn/nn-61e7af4bb97d.nnue` redirects to `data.stockfishchess.org`).
    Its upload page, in the fishtest source (`server/fishtest/templates/nn_upload.html.j2`), says: "By uploading,
    you license your network under a CC0 license." and its checkbox reads: "You are the author of this network or
    have obtained the network with a CC0 license."
  - The `official-stockfish/networks` repository states: "All networks in this repository were uploaded by the
    authors under the CC0 license." Its `LICENSE` is CC0 1.0 Universal. That repository does not list
    `nn-61e7af4bb97d`, so this statement is evidence of the project's practice, not of this file.
  - The `lichess-org/dart-multistockfish` repository is GPLv3 as a whole and says nothing particular about the net.
  - Stockfish's README adds that its nets are trained on Leela Chess Zero data under the ODbL.
  - The fishtest listing of the net (uploader, date) could not be read: the page sits behind a browser check,
    which was not bypassed.

## Measurements

| | Full net (0002 and today) | Light net |
|---|---|---|
| `bench` nodes | 2,497,913 | **2,793,281** (the number of the patch's own commit) |
| Puzzles solved, of 240 | 240 | 240 |
| Strong positions, same best move | | 80 of 80 (1.00) |
| Strong positions, median score gap | | **83.5 cp** (72.5 cp on a second run) |
| Debug APK | 127,967,184 bytes (128.0 MB) | **30,535,632 bytes** (30.5 MB) |
| Extension library for arm64 | 99.5 MB | 2.0 MB |
| TOTAL PSS after a strong battle | 461,860 KB (451 MiB) | **249,735 KB** (244 MiB) |
| Native heap | 223,556 KB | 108,120 KB |
| Engine ready, cold start, 3 runs | 1.30, 1.36, 1.32 s | 1.35, 1.19, 1.17 s |
| First frame (`am start -W`) | 253, 279, 258 ms | 318, 296, 266 ms |

The full net's memory figures match 0002 (460,565 KB and 222,516 KB), and so does its APK size to the byte.

The score gap is systematic, not noise. Over the 80 strong positions the light net's score is lower than or equal to the
full net's in 78, and 82 cp lower on average. The median score is +501 cp for the light net against +590 cp for the
full net: the light net is as sure about the best move, but reads the advantage about 14 % smaller.

## Decision rule and result

The rule of the plan: adopt the light net only if every condition holds.

| # | Condition | Measured | Result |
|---|---|---|---|
| 1 | `bench` matches (2,793,281 nodes on the patched tree) | 2,793,281 | pass |
| 2 | `puzzles_solved_light` ≥ 0.95 × `puzzles_solved_full` (≥ 228) | 240 against 240 | pass |
| 3 | `strong_agreement` ≥ 0.70 | 1.00 | pass |
| 4 | `strong_median_abs_diff_cp` ≤ 60 | 83.5 | **fail** |
| 5 | TOTAL PSS ≤ 300 MB | 249,735 KB (244 MiB, 256 MB) | pass |
| 6 | APK ≤ 50 MB | 30,535,632 bytes (30.5 MB) | pass |
| 7 | Licence compatible with GPLv3 redistribution | CC0 by the fishtest upload terms | pass, with the caveat above |

## Decision

**Adopt the light net (`nn-61e7af4bb97d`) with the vendored P_hm patch.** This is the author's decision, and it
**departs from the rule of the plan**: the rule says "adopt only if every condition holds, otherwise keep the full
net", and condition 4 failed (83.5 cp against a limit of 60). The rule's answer was "keep the full net". The author
chose otherwise, for these reasons:

- Everything else favours the light net, by a wide margin:
  - agreement on the strong positions: 80 of 80;
  - puzzles solved: 240 of 240, as many as the full net;
  - memory: 244 MiB against 451 MiB;
  - debug APK: 30.5 MB against 128 MB.
- The failed condition measures a **systematic scale**, not a strength problem. The light net picks the same moves
  but reads advantages about 14 % smaller (median +501 cp against +590 cp). A scale is a constant that the game
  can absorb by tuning its thresholds in the light net's own centipawns. A weaker engine could not be fixed that way.
- **Not measured:** the strength of the light net against the full net in games. The evidence of strength is the
  agreement on 80 positions and the Elo that the patch reports against `sf18-15mb` (+9.75 +/- 2.7 over 20,000
  games, not ours), nothing more.

## Consequences

- **Task 2 vendors the patch and the net.** It adds the patched Stockfish tree and the net to the build and wires
  `SF_TREE` and `NET` (the `sf_dir` and `net` arguments of `native/SConstruct`, and `make stockfish-cli`) to them.
  Until then the repository builds the full net, as before.
- **No manual rescale.** The thresholds are not multiplied by a factor. Task 3 computes the evaluations of the strong
  positions, and Task 4 runs its simulation, with the game's own light engine, so the start window [+150, +400], the
  win at `max(cp_start + 250, 500)` and the damage are tuned in the light net's centipawns.
- **A fork patch to carry.** The patch must be re-applied on every Stockfish update. The check is the `bench` of the
  patched tree: 2,793,281 nodes for the `sf_19` rebase, which is the number in the patch's own commit message. The
  patch is written against a development snapshot, so it has to be rebased onto each release tag.
- **Licence to re-check before the public launch.** The net's CC0 licence rests on the fishtest upload terms,
  because the net's own page could not be read (it sits behind a browser check). The upload page says: "By
  uploading, you license your network under a CC0 license." and its checkbox reads: "You are the author of this
  network or have obtained the network with a CC0 license." Before the launch, read the net's fishtest page
  (uploader and date) and record the result in `CREDITS.md`.
- **Start-up time.** The cold start of the engine is about 1.2 s with either net (1.2 to 1.35 s against 1.3 to 1.36 s),
  so the net does not change what the player waits for.
- **Memory and size.** The beta's budget moves from about 450 MiB and a 128 MB debug APK to about 250 MiB (244 MiB
  measured) and a 30.5 MB one. The size of the release bundle is for the release task to measure.
- **What was built stays.** `tools/engine/` (the UCI driver and the comparison), `make stockfish-cli`, and the scons
  arguments `sf_dir` and `net` repeat this spike on any Stockfish checkout, for example after an update. The bridge
  includes Stockfish's headers by name (`-iquote` on the tree being built), so that `sf_dir` really selects the tree it
  builds against. Applying the patch needs `git apply` on a copy of the tree that is a git repository of its own:
  `git apply` inside a subdirectory of another repository silently ignores the paths, and `patch -p1` does not follow
  the renames.
- **The bridge needed nothing else.** The patch is source-compatible with it: the extension built with the light tree
  loaded on the phone, and the engine played.
