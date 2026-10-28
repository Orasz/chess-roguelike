extends GutTest


func _eval(mate: bool, value: int) -> EngineEval:
	var e := EngineEval.new()
	e.is_mate = mate
	e.value = value
	return e


func test_win_chance():
	assert_almost_eq(HpModel.win_chance(0), 50.0, 0.001)
	assert_almost_eq(HpModel.win_chance(300), 75.11, 0.01)
	assert_almost_eq(HpModel.win_chance(-300) + HpModel.win_chance(300), 100.0, 0.001)


func test_eval_to_cp():
	assert_eq(HpModel.eval_to_cp(_eval(false, 42)), 42)
	assert_eq(HpModel.eval_to_cp(_eval(true, 3)), Tuning.MATE_CP)
	assert_eq(HpModel.eval_to_cp(_eval(true, -2)), -Tuning.MATE_CP)
	assert_eq(HpModel.eval_to_cp(_eval(true, 0)), -Tuning.MATE_CP)


func test_player_damage():
	assert_eq(HpModel.player_damage(0, -10), 0, "engine noise")
	assert_eq(HpModel.player_damage(0, -100), 5)
	assert_eq(HpModel.player_damage(300, -300), 25)
	assert_eq(HpModel.player_damage(300, 0), 13)
	assert_eq(HpModel.player_damage(-200, 300), 0, "a better position never heals or hurts")
	assert_eq(HpModel.player_damage(Tuning.MATE_CP, -Tuning.MATE_CP), Tuning.MAX_MOVE_DAMAGE)
	assert_eq(HpModel.player_damage(0, -40), 0, "3.7 points: inside the new dead zone")
	assert_eq(HpModel.player_damage(0, -60), 3, "5.5 points")


## The numbers below follow `Tuning.DECISIVE_GAIN_CP` = 150 and `Tuning.DECISIVE_MIN_CP` = 500.
func test_decisive_target_rises_with_the_start():
	assert_eq(HpModel.decisive_cp(400), 550); assert_eq(HpModel.decisive_cp(434), 584)
	assert_eq(HpModel.decisive_cp(300), 500, "never below DECISIVE_MIN_CP")
	assert_eq(HpModel.decisive_cp(100), 500, "never below DECISIVE_MIN_CP")


func test_enemy_fraction():
	assert_eq(HpModel.enemy_fraction(400, 400), 1.0)
	assert_almost_eq(HpModel.enemy_fraction(475, 400), 0.5, 0.001)
	assert_eq(HpModel.enemy_fraction(550, 400), 0.0)
	assert_eq(HpModel.enemy_fraction(100, 400), 1.0, "losing ground refills, never above full")
	assert_almost_eq(HpModel.enemy_fraction(300, 100), 0.5, 0.001)


func test_is_decisive():
	assert_true(HpModel.is_decisive(550, 400)); assert_false(HpModel.is_decisive(549, 400))
	assert_true(HpModel.is_decisive(Tuning.MATE_CP, 400))
	assert_true(HpModel.is_decisive(Tuning.MATE_CP, Tuning.MATE_CP), "a mate wins even from a mating start")
