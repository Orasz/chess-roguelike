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


func test_enemy_fraction():
	assert_eq(HpModel.enemy_fraction(300, 300), 1.0)
	assert_almost_eq(HpModel.enemy_fraction(550, 300), 0.5, 0.001)
	assert_eq(HpModel.enemy_fraction(800, 300), 0.0)
	assert_eq(HpModel.enemy_fraction(100, 300), 1.0, "losing ground refills, never above full")
	assert_almost_eq(HpModel.enemy_fraction(700, 750), 0.5, 0.001, "start capped below decisive")


func test_is_decisive():
	assert_true(HpModel.is_decisive(800))
	assert_false(HpModel.is_decisive(799))
