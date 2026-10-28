# Strong enemy: tuning the win condition

- **Date of the runs:** 2026-10-28
- **What is tuned:** the strong enemy's win condition. A strong enemy is beaten when the player's evaluation reaches
  `max(cp_start + DECISIVE_GAIN_CP, DECISIVE_MIN_CP)`, or by mate (`HpModel.decisive_cp()`). `cp_start` is the battle's
  opening evaluation.
- **Acceptance:**
  - The plan's bar is that, at Club (rating 1200), the hint policy wins **at least 80 %** of the strong positions, with a
    median of **at most 10** player moves.
  - The controller ruled that the bar is met only by the **mean `won_share` of three runs** with the same constants.
    Each of those runs must also have a median of at most 10 moves.
- **The order of the search:**
  1. The gain drops by 50 cp per attempt, down to a floor of 150.
  2. Then `DECISIVE_MIN_CP` drops by 50 cp per three-run set, down to a floor of 400.
  3. `STRONG_MOVE_LIMIT` stays at 12.
- **Result:** `DECISIVE_GAIN_CP = 150` and `DECISIVE_MIN_CP = 500` are accepted. The mean of three runs is **0.853**,
  and the medians are 5.5, 6 and 6 moves.

The simulated player is the engine following its own hint. So 0.80 is a ceiling for human play, not an estimate of it.
The [human-proxy runs](#human-proxy-runs) at the end measure one step closer to a person.

## How the runs were made

`make strong-sim RATING=<rating>` runs `game/tools/strong_sim.gd` headless. It writes every position's result to
`build/strong-sim-<rating>.json`, and copies of the runs below are in [`data/`](data/). With `PLAYER_ELO=<elo>` the
file is `build/strong-sim-<rating>-player<elo>.json`.

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
| `DAMAGE_DEADZONE_WP` | 5.0 |
| `STRONG_MOVE_LIMIT` | 12 |
| `STRONG_SEARCH_MS` | 700 |
| `STRONG_CANDIDATES` | 5 |

## Runs

Each run takes 7 to 10 minutes on an Apple-silicon Mac. The won count is in brackets.

| # | Date | Rating | `DECISIVE_GAIN_CP` | `DECISIVE_MIN_CP` | count | won_share | median_moves_to_win | mean_hp_lost | Data |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-28 | 1200 | 250 | 500 | 75 | 0.760 (57) | 8.0 | 3.60 | [run 1](data/strong-sim-run1-1200.json) |
| 2 | 2026-10-28 | 1200 | 200 | 500 | 75 | 0.787 (59) | 7.0 | 3.28 | [run 2](data/strong-sim-run2-1200.json) |
| 3 | 2026-10-28 | 1200 | 150 | 500 | 75 | 0.800 (60) | 5.5 | 3.00 | [run 3](data/strong-sim-run3-1200.json) |
| 4 | 2026-10-28 | 1800 | 150 | 500 | 75 | 0.600 (45) | 8.0 | 6.00 | [run 4](data/strong-sim-run4-1800.json) |
| 5 | 2026-10-28 | 1200 | 150 | 500 | 75 | 0.893 (67) | 6.0 | 1.68 | [run 5](data/strong-sim-run5-1200.json) |
| 6 | 2026-10-28 | 1200 | 150 | 500 | 75 | 0.867 (65) | 6.0 | 2.00 | [run 6](data/strong-sim-run6-1200.json) |

### Verdicts

- **Runs 1 and 2 fail.** Their single `won_share` is under 0.80. They were judged before the three-run rule, and with
  the noise shown below, one run each does not settle them either way.
- **Runs 3, 5 and 6 are accepted.** They are a three-run set at a gain of 150 and a minimum of 500.
  - Their mean `won_share` is (60 + 67 + 65) / 225 = **0.853**, at or above 0.80.
  - Their medians are 5.5, 6.0 and 6.0, each at most 10.
  - `DECISIVE_MIN_CP` therefore did not need to move.
- **Run 4 is for the record.** It is played at 1800, where the plan sets no target.

## What the runs show

- **Every position that was not won was an escape.** The move limit ran out on every one of them. No run had a mate
  against the player, a draw, or a withdrawal.
- **The HP lost comes from the escape, with two exceptions.** An escape costs `STRONG_FAIL_DAMAGE` = 15 HP, and
  every won position cost 0 HP. In all six runs only two escapes cost more: one in run 2 and one in run 5 cost 21 HP,
  the 15 HP of the escape plus 6 HP of move damage earlier in the same battle. With the 5-point dead zone, a player
  who follows the hint is never charged for engine noise.
- **Runs are noisy, more than one run can resolve.**
  - The three runs at the same constants won 60, 67 and 65 positions.
  - 22 different positions escaped at least once, and only 4 escaped in all three runs.
  - The timed searches are the only source of difference between those runs. The cause of run 3's lower count was not
    isolated: other work on the machine may have slowed its searches, but that was not measured.
- **The gain controls little here.**
  - At a gain of 150, the target is the 500 cp floor for every start up to 350 cp, which covers 48 of the 75 stored
    evaluations.
  - The 0.760, 0.787 and 0.800 of runs 1 to 3 are within the noise above, so they show no trend.
  - If the strong enemy needs retuning, `DECISIVE_MIN_CP` or `STRONG_MOVE_LIMIT` is the lever that binds.
- **At 1800 the enemy is markedly harder.** 30 of the 75 positions escape.

## Tests that pin the boundary

The tests fix the boundary at the accepted constants. In `game/test/integration/test_strong_encounter.gd`, a battle opens
at +300 cp, so its target is the 500 cp floor:

- an evaluation of +499 after the player's move plays on (`test_one_centipawn_short_of_the_target_plays_on`);
- +500 wins before the enemy moves (`test_reaching_the_target_wins`).

`game/test/unit/test_hp_model.gd` checks `decisive_cp`, `enemy_fraction` and `is_decisive` with the same constants.

## Human-proxy runs

The runs above let the engine play the player, with the hint. These two do not.

- **What the simulated player is.** A `MovePicker` at the player's Elo over the engine's 5 best lines (MultiPV 5, 700 ms,
  full strength), the same softmax that makes the enemy weak. It is a model of a human of that Elo, **not a real
  person**.
- **What it does not get.** It never sees the hint. Each of its moves is a fresh pick, with a random generator seeded
  with the position's index so the picks repeat.
- **What the numbers are.** Indications for the closed test, **not acceptance criteria**. No `Tuning` constant changed
  after them, and the plan's 0.80 bar still belongs to the hint-policy runs above.

`make strong-sim RATING=1200 PLAYER_ELO=1200` and `make strong-sim RATING=800 PLAYER_ELO=800` ran at the constants in
the table above, `DECISIVE_GAIN_CP = 150` and `DECISIVE_MIN_CP = 500`. The enemy plays at the rating, like in a run: a
Club-preset player (1200) meets an enemy at 1200. The 800 run is a weaker proxy, not a preset: the presets are
Beginner 600, Club 1200 and Strong 1800 (`Tuning.RATING_PRESETS`), so no preset is at 800.

| # | Date | Rating (enemy Elo) | Player Elo | count | won_share | median_moves_to_win | mean_hp_lost | Escapes | Mates or draws | Data |
|---|---|---|---|---|---|---|---|---|---|---|
| 7 | 2026-10-28 | 1200 | 1200 | 75 | 0.613 (46) | 5.5 | 8.36 | 29 | 0 | [run 7](data/strong-sim-run7-1200-player1200.json) |
| 8 | 2026-10-28 | 800 | 800 | 75 | 0.640 (48) | 5.0 | 9.08 | 27 | 0 | [run 8](data/strong-sim-run8-800-player800.json) |

For comparison, the hint policy at 1200 won 0.853 of the positions over runs 3, 5 and 6, with a mean of 1.68 to 3.00 HP
lost.

### What they suggest

- **The 1200 proxy wins about six battles out of ten.** Run 7 won 46 of 75. The 800 proxy of run 8 won 48 of 75. This
  is a statement about the model, not about real players: the proxy never plays outside the engine's five best lines,
  so it plays no blunder worse than the fifth-best move, and real players can do worse. The difference between the two is two positions, inside the noise that the earlier runs showed.
- **Almost every battle that is not won is an escape.** All 29 and 27 of them ran out of the 12 moves; there was no
  mate against the player and no draw. When the player does win, it is quick: the median is 5.5 and 5.0 moves, and
  the slowest win took all 12.
- **The cost is the escape.** An escape costs 15 HP, and the lost battles lost 20.6 HP (run 7) and 23.6 HP (run 8) on
  average, so the extra over 15 is move damage taken before the enemy got away. A won battle cost 0.63 and 0.90 HP on
  average. The worst single battle cost 50 HP (run 7) and 55 HP (run 8) of the 100, so none ended the run alone.
  - The mean over all positions is 8.4 and 9.1 HP per strong battle, against 1.7 to 3.0 for the hint policy.
- **Below the hint policy, as expected.** The hint policy is the engine's own best move every turn, and a human of 1200
  or 800 is not. What the closed test can tell is whether real players behave nearer 0.61 or nearer 0.85.
- **Noise.** A first pass of the same two commands, made before the tool wrote `player_elo` into its report and so not
  kept as data, gave 0.587 and 0.653: about two positions away from runs 7 and 8.

For the testers, the open questions are how often the enemy escaped and whether the "Moves left" counter was enough to
see it coming. The closed-test plan asks them (Task 14, Step 2).
