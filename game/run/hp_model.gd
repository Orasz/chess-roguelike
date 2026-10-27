class_name HpModel
extends RefCounted
## The "HP as advantage" maths: how a move's evaluation becomes damage to the
## player, and how the enemy's bar follows the evaluation. Evaluations are in
## centipawns from the player's point of view, except where a function says otherwise.

## Lichess's published win-chance formula is 50 + 50 * (2 / (1 + e^(-K * cp)) - 1).
const _WIN_CHANCE_K := 0.00368208


## Win chance for the player, from 0 to 100, at an evaluation of `cp` centipawns.
static func win_chance(cp: int) -> float:
	return 50.0 + 50.0 * (2.0 / (1.0 + exp(-_WIN_CHANCE_K * cp)) - 1.0)


## Converts an engine evaluation to centipawns, from the side to move's point of view.
## A mate the side to move delivers is `Tuning.MATE_CP`; a mate against it, or
## `mate 0`, is `-Tuning.MATE_CP`.
static func eval_to_cp(e: EngineEval) -> int:
	if not e.is_mate:
		return e.value
	return Tuning.MATE_CP if e.value > 0 else -Tuning.MATE_CP


## HP the player loses when a move takes the evaluation from `cp_before` to `cp_after`.
## Losses under the dead zone are engine noise, and a better position never heals.
static func player_damage(cp_before: int, cp_after: int) -> int:
	var loss := win_chance(cp_before) - win_chance(cp_after)
	if loss < Tuning.DAMAGE_DEADZONE_WP:
		return 0
	return mini(roundi(loss * Tuning.DAMAGE_PER_WP), Tuning.MAX_MOVE_DAMAGE)


## How full the enemy's bar is at `cp`, from 0 to 1. The bar starts full at the
## battle's opening evaluation `cp_start`, and empties linearly to the decisive
## threshold. The start is capped so that at least `Tuning.MIN_BAR_RANGE_CP` remains.
static func enemy_fraction(cp: int, cp_start: int) -> float:
	var bar_start := mini(cp_start, Tuning.DECISIVE_CP - Tuning.MIN_BAR_RANGE_CP)
	var remaining := float(Tuning.DECISIVE_CP - cp)
	return clampf(remaining / float(Tuning.DECISIVE_CP - bar_start), 0.0, 1.0)


## True when `cp` reaches the decisive threshold, which wins the battle.
static func is_decisive(cp: int) -> bool:
	return cp >= Tuning.DECISIVE_CP
