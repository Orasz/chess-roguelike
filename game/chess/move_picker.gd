class_name MovePicker
extends RefCounted
## Chooses which of the engine's MultiPV lines the opponent plays, so that its
## strength follows an Elo at any level, including below Stockfish's UCI_Elo floor.
## The search always runs at full strength; weakness comes from picking among
## the lines with a softmax over their centipawn loss against the best line.


## Returns the index in `lines` (an Array of EngineEval, never empty) of the line to play.
## A line `loss` centipawns worse than the best has weight exp(-loss / T). T falls
## linearly from `Tuning.PICKER_TEMP_AT_MIN` at `Tuning.PICKER_MIN_ELO` to
## `Tuning.PICKER_TEMP_AT_MAX` at `Tuning.PICKER_MAX_ELO`, with `elo` clamped to
## that range. At `Tuning.PICKER_MAX_ELO` and above it plays the best line and
## draws nothing from `rng`. All lines are from the same side to move, so their
## values compare directly. Among equal best lines the first one wins.
static func choose(lines: Array, elo: int, rng: RandomNumberGenerator) -> int:
	var values: Array[int] = []
	for line: EngineEval in lines:
		values.append(HpModel.eval_to_cp(line))
	var best := 0
	for i in values.size():
		if values[i] > values[best]:
			best = i
	if elo >= Tuning.PICKER_MAX_ELO:
		return best
	var temperature := _temperature(elo)
	var weights: Array[float] = []
	var total := 0.0
	for value in values:
		var weight := exp(-float(values[best] - value) / temperature)
		weights.append(weight)
		total += weight
	var target := rng.randf() * total
	var cumulative := 0.0
	for i in weights.size():
		cumulative += weights[i]
		if target < cumulative:
			return i
	return best


## The softmax temperature at `elo`, interpolated linearly over the picker's Elo range.
static func _temperature(elo: int) -> float:
	var span := float(Tuning.PICKER_MAX_ELO - Tuning.PICKER_MIN_ELO)
	var t := clampf(float(elo - Tuning.PICKER_MIN_ELO) / span, 0.0, 1.0)
	return lerpf(Tuning.PICKER_TEMP_AT_MIN, Tuning.PICKER_TEMP_AT_MAX, t)
