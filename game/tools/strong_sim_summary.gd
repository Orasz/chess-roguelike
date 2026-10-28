class_name StrongSimSummary
extends RefCounted
## What a strong-enemy simulation (`strong_sim.gd`) measured, in four numbers. The tuning acceptance
## reads `won_share` and `median_moves_to_win`.


## Sums up `results`, one `{id, outcome, player_moves, hp_lost}` per position played, where
## `outcome` is a `RunState.Outcome`. Returns `{count, won_share, median_moves_to_win, mean_hp_lost}`:
## the median counts the player's moves of the won positions only, and is 0 when none was won.
static func summarize(results: Array) -> Dictionary:
	var won_moves: Array[int] = []
	var hp_lost := 0
	for result: Dictionary in results:
		if int(result["outcome"]) == RunState.Outcome.WON:
			won_moves.append(int(result["player_moves"]))
		hp_lost += int(result["hp_lost"])
	var count := results.size()
	return {
		"count": count,
		"won_share": float(won_moves.size()) / count if count > 0 else 0.0,
		"median_moves_to_win": _median(won_moves),
		"mean_hp_lost": float(hp_lost) / count if count > 0 else 0.0,
	}


## The median of `values`, the mean of the middle two for an even count, and 0 for none.
static func _median(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	var middle := values.size() / 2
	if values.size() % 2 == 1:
		return float(values[middle])
	return (values[middle - 1] + values[middle]) / 2.0
