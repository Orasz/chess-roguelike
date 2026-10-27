extends GutTest

const LOSSES := [0, 40, 80, 150, 300]


func _lines() -> Array:
	var out := []
	for loss in LOSSES:
		var e := EngineEval.new()
		e.value = 100 - loss
		e.pv = PackedStringArray(["a2a3"])
		out.append(e)
	return out


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _mean_loss(elo: int) -> float:
	var rng := _rng(7)
	var total := 0.0
	for i in 2000:
		total += LOSSES[MovePicker.choose(_lines(), elo, rng)]
	return total / 2000.0


func test_strongest_level_always_plays_the_best_line():
	var rng := _rng(1)
	for i in 200:
		assert_eq(MovePicker.choose(_lines(), 2400, rng), 0)


func test_beginner_often_plays_inferior_lines():
	var rng := _rng(2)
	var inferior := 0
	for i in 1000:
		if MovePicker.choose(_lines(), 400, rng) != 0:
			inferior += 1
	assert_gt(inferior, 400)


func test_lower_elo_loses_more():
	assert_gt(_mean_loss(800), _mean_loss(1600))
	assert_gt(_mean_loss(400), _mean_loss(800))


func test_one_line_and_determinism():
	assert_eq(MovePicker.choose(_lines().slice(0, 1), 400, _rng(3)), 0)
	assert_eq(MovePicker.choose(_lines(), 900, _rng(4)), MovePicker.choose(_lines(), 900, _rng(4)))
