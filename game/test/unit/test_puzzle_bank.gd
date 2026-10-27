extends GutTest

const TEMP_FILE := "user://test_puzzle_bank.json"


func after_each() -> void:
	if FileAccess.file_exists(TEMP_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FILE))


func _record(id: String, rating: int) -> Dictionary:
	return {"id": id, "fen": "", "moves": [], "rating": rating, "themes": []}


func _bank() -> PuzzleBank:
	var recs := []
	for r in [600, 650, 700, 1200, 1210, 1800]:
		recs.append(_record("p%d" % r, r))
	var strong := [_record("s900", 900), _record("s1500", 1500)]
	return PuzzleBank.from_dict({"version": 1, "puzzles": recs, "strong": strong})


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _write_temp_file(text: String) -> void:
	var file := FileAccess.open(TEMP_FILE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_pick_stays_near_the_rating():
	for p in _bank().pick("puzzles", 650, 3, _rng(1)):
		assert_between(p.rating, 500, 800)


func test_pick_widens_when_the_window_is_thin():
	assert_eq(_bank().pick("puzzles", 1200, 4, _rng(1)).size(), 4)


func test_pick_is_distinct_deterministic_and_respects_exclude():
	var a := _bank().pick("puzzles", 650, 3, _rng(5))
	var b := _bank().pick("puzzles", 650, 3, _rng(5))
	assert_eq_deep(a, b)
	var ids := {}
	for p in a:
		ids[p.id] = true
	assert_eq(ids.size(), 3)
	var excluded := _bank().pick("puzzles", 650, 2, _rng(5), PackedStringArray(["p650"]))
	assert_false(excluded.any(func(p): return p.id == "p650"))


func test_pick_returns_what_exists_when_the_pool_runs_out():
	assert_eq(_bank().pick("puzzles", 1200, 10, _rng(1)).size(), 6)
	assert_eq(_bank().pick("puzzles", 1200, 0, _rng(1)).size(), 0)


func test_pick_reads_the_named_pool():
	var picked := _bank().pick("strong", 1000, 2, _rng(1))
	assert_eq(picked.size(), 2)
	for p in picked:
		assert_true(p.id.begins_with("s"), p.id)


func test_by_id():
	assert_eq(_bank().by_id("p1800").rating, 1800)
	assert_true(_bank().by_id("nope").is_empty())


func test_by_id_also_finds_strong_records():
	assert_eq(_bank().by_id("s1500").rating, 1500)


func test_load_file_reads_a_bank():
	_write_temp_file(JSON.stringify({"version": 1, "puzzles": [_record("a", 1000)], "strong": []}))
	var bank := PuzzleBank.load_file(TEMP_FILE)
	assert_not_null(bank)
	assert_eq(bank.puzzles.size(), 1)
	assert_eq(int(bank.by_id("a").rating), 1000, "JSON numbers load as floats")


func test_load_file_returns_null_for_a_missing_file():
	assert_null(PuzzleBank.load_file("user://no_such_puzzle_bank.json"))


func test_load_file_returns_null_for_bad_json():
	_write_temp_file("{ not json")
	assert_null(PuzzleBank.load_file(TEMP_FILE))
