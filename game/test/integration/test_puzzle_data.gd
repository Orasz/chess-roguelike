extends GutTest

const PATH := "res://data/puzzles/italian_game.json"


func test_file_loads_within_budget():
	var bank := PuzzleBank.load_file(PATH)
	assert_not_null(bank)
	assert_gt(bank.puzzles.size(), 199)
	assert_gt(bank.strong.size(), 49)
	assert_lt(FileAccess.open(PATH, FileAccess.READ).get_length(), 200_000)


func test_every_record_is_legal_and_white_solves():
	var bank := PuzzleBank.load_file(PATH)
	for p in bank.puzzles + bank.strong:
		assert_false(ChessRules.inspect(p.fen, PackedStringArray(p.moves)).is_empty(), p.id)
		var after_first := ChessRules.fen_after(p.fen, PackedStringArray([p.moves[0]]))
		assert_eq(ChessRules.side_to_move(after_first), "w", p.id)


func test_every_rating_preset_is_served():
	var bank := PuzzleBank.load_file(PATH)
	var rng := RandomNumberGenerator.new()
	for rating in [600, 1200, 1800]:
		var picked := bank.pick("puzzles", rating, 8, rng)
		assert_eq(picked.size(), 8)
		for p in picked:
			assert_between(int(p.rating), rating - 300, rating + 300, p.id)
		var strong := bank.pick("strong", rating, 1, rng)
		assert_eq(strong.size(), 1)
		assert_between(int(strong[0].rating), rating - 500, rating + 500)


func test_mate_in_one_is_not_most_of_the_bank():
	var bank := PuzzleBank.load_file(PATH)
	var mates := 0
	for p in bank.puzzles:
		if "mateIn1" in p.themes:
			mates += 1
	assert_lt(float(mates) / bank.puzzles.size(), 0.40)


func test_every_strong_position_starts_in_reach():
	for p in PuzzleBank.load_file(PATH).strong:
		assert_between(int(p.eval), 150, 400, p.id)
