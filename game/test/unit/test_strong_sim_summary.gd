extends GutTest
## The summary of a strong-enemy simulation: how many positions the hint policy won, how long the
## wins took, and what they cost.


func _result(id: String, outcome: int, player_moves: int, hp_lost: int) -> Dictionary:
	return {"id": id, "outcome": outcome, "player_moves": player_moves, "hp_lost": hp_lost}


func test_summary_counts_wins_and_their_median_length():
	var results := [
		_result("a", RunState.Outcome.WON, 6, 0),
		_result("b", RunState.Outcome.WON, 11, 10),
		_result("c", RunState.Outcome.LOST, 12, 30),
		_result("d", RunState.Outcome.WON, 8, 4),
	]
	var summary := StrongSimSummary.summarize(results)
	assert_eq(summary.count, 4)
	assert_almost_eq(summary.won_share, 0.75, 0.001)
	assert_eq(summary.median_moves_to_win, 8.0)
	assert_almost_eq(summary.mean_hp_lost, 11.0, 0.001)


func test_the_median_of_an_even_count_is_the_mean_of_the_middle_two():
	var results := [_result("a", RunState.Outcome.WON, 6, 0), _result("b", RunState.Outcome.WON, 9, 0)]
	assert_eq(StrongSimSummary.summarize(results).median_moves_to_win, 7.5)


func test_no_results_and_no_wins_give_zeros():
	assert_eq(StrongSimSummary.summarize([]),
		{"count": 0, "won_share": 0.0, "median_moves_to_win": 0.0, "mean_hp_lost": 0.0})
	var summary := StrongSimSummary.summarize([_result("a", RunState.Outcome.DRAWN, 3, 5)])
	assert_eq([summary.won_share, summary.median_moves_to_win, summary.mean_hp_lost], [0.0, 0.0, 5.0])
