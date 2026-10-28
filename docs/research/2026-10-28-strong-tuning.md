# Strong enemy: tuning the win condition

- **Date of the runs:** 2026-10-28
- **What is tuned:** `Tuning.DECISIVE_GAIN_CP`. A strong enemy is beaten when the player's evaluation reaches
  `max(cp_start + DECISIVE_GAIN_CP, DECISIVE_MIN_CP)`, or by mate. `cp_start` is the battle's opening evaluation
  (`HpModel.decisive_cp()`).
- **Acceptance (open-beta plan):** at Club (rating 1200), the hint policy wins **at least 80 %** of the strong
  positions, with a median of **at most 10** player moves. If it does not, the gain drops by 50 cp per retry, down to a
  floor of 150.
- **Result:** **`DECISIVE_GAIN_CP = 150`**, the floor. It passes at exactly 80 % (60 of 75).

## How the runs were made

`make strong-sim RATING=<rating>` runs `game/tools/strong_sim.gd` headless. It writes every position's result to
`build/strong-sim-<rating>.json`.

- **Engine.** The game's own engine: the light-net build of decision
  [0003](../decisions/0003-engine-net.md), as a macOS GDExtension, on one thread with a 16 MB hash. Its centipawns read
  about 14 % smaller than the full net's, so every threshold here is in the light net's centipawns.
- **Positions.** The 75 `strong` records of `game/data/puzzles/italian_game.json`. Each record's stored evaluation, after
  the opponent's first move, is in [157, 400] cp from the player's side, with a median of 321. It was computed at depth 14
  with the same engine.
- **Enemy.** A real `StrongEncounter` at enemy Elo `clampi(rating, 400, 2400)`. It runs a 700 ms search with 5 MultiPV
  lines, and `MovePicker` chooses among them.
- **Player.** The player plays the encounter's hint whenever it is a legal move. Otherwise it plays the best move of a
  700 ms MultiPV 1 search on the same engine.
- **Seeds.** Every position has its own fixed seed, from 1 to 75. The enemy's random choices repeat between runs, but
  the timed searches do not: the same constants can give a different game.

The other constants were the same in every run:

| Constant | Value |
|---|---|
| `DECISIVE_MIN_CP` | 500 |
| `DAMAGE_DEADZONE_WP` | 5.0 |
| `STRONG_MOVE_LIMIT` | 12 |
| `STRONG_SEARCH_MS` | 700 |
| `STRONG_CANDIDATES` | 5 |

## Runs

Each run takes 8 to 10 minutes on an Apple-silicon Mac.

| # | Date | Rating | `DECISIVE_GAIN_CP` | count | won_share | median_moves_to_win | mean_hp_lost | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-28 | 1200 | 250 | 75 | 0.760 (57) | 8.0 | 3.60 | fails: won_share < 0.80 |
| 2 | 2026-10-28 | 1200 | 200 | 75 | 0.787 (59) | 7.0 | 3.28 | fails: won_share < 0.80 |
| 3 | 2026-10-28 | 1200 | 150 | 75 | 0.800 (60) | 5.5 | 3.00 | **passes**, at the boundary |
| 4 | 2026-10-28 | 1800 | 150 | 75 | 0.600 (45) | 8.0 | 6.00 | for the record (no acceptance) |

## What the runs show

- **Every position that was not won was an escape.** The move limit ran out on every one of them. No run had a mate
  against the player, a draw, or a withdrawal.
- **The HP lost comes from the escape alone.** Every escape costs `STRONG_FAIL_DAMAGE` = 15 HP, and every won position
  cost 0 HP. With the 5-point dead zone, a player who follows the hint is never charged for engine noise.
- **Lowering the gain buys little.** Going from 250 to 150 cp raised the wins from 57 to 60, and shortened the median
  win from 8 to 5.5 moves.
  - The escapes are positions where following the hint does not grow the advantage within 12 moves, so a lower target
    reaches only a few more of them.
  - At a gain of 150, the target is the 500 cp floor for every start up to 350 cp. Starts at or below 300 cp won 24 of
    32, and starts above 300 cp won 36 of 43.
- **Runs are noisy.** Runs 1 and 2 had 18 and 16 escapes, and only 9 of those positions escaped in both runs. A rerun
  with the same constants can move `won_share` by a few positions, which is ±0.03 to 0.04.
  - Run 3 passes on 60 of 75, the least number of wins that passes. A rerun could well land at 0.787.
- **At 1800 the enemy is markedly harder.** 30 of the 75 positions escape. The plan sets no target at that rating.

## If the margin is wanted

The floor of 150 is reached, so the gain has no room left. A rerun that falls below 0.80 means another constant must
move. The likely candidates are these:

- `STRONG_MOVE_LIMIT`: every failure is an escape on the last move;
- `DECISIVE_MIN_CP`: it is the binding target for every start below 350 cp, and those starts win no more often than the
  higher ones.

This choice is not this document's to make.
