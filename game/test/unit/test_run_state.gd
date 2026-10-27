extends GutTest


func _run() -> RunState:
	return RunState.create(42, 1200, "italian_game")


func _two_encounters(r: RunState) -> void:
	r.encounters = {
		"a": {"kind": "strong", "content": "x", "mandatory": true, "resolved": false},
		"b": {"kind": "puzzle", "content": "y", "mandatory": false, "resolved": false},
	}


## A run that went through JSON, as a save file does.
func _through_json(r: RunState) -> Variant:
	return JSON.parse_string(JSON.stringify(r.to_dict()))


func test_new_run():
	var r := _run()
	assert_eq([r.hp, r.potions], [Tuning.MAX_HP, Tuning.START_POTIONS])
	assert_eq([r.seed, r.rating, r.opening_id], [42, 1200, "italian_game"])
	assert_true(r.battle.is_empty())


func test_new_run_seeds_the_rng_with_the_seed():
	var expected := RandomNumberGenerator.new()
	expected.seed = 42
	assert_eq(_run().rng.randi(), expected.randi())


func test_damage_floors_at_zero_and_dies_once():
	var r := _run()
	watch_signals(r)
	r.take_damage(70)
	r.take_damage(70)
	r.take_damage(5)
	assert_eq(r.hp, 0)
	assert_signal_emit_count(r, "died", 1)


func test_damage_that_leaves_hp_does_not_kill():
	var r := _run()
	watch_signals(r)
	r.take_damage(99)
	assert_eq(r.hp, 1)
	assert_signal_not_emitted(r, "died")


func test_negative_damage_does_not_heal():
	var r := _run()
	r.take_damage(20)
	r.take_damage(-50)
	assert_eq(r.hp, Tuning.MAX_HP - 20)


func test_potion_rules():
	var r := _run()
	assert_false(r.use_potion(), "refused at full HP")
	r.take_damage(10)
	assert_true(r.use_potion())
	assert_eq([r.hp, r.potions], [Tuning.MAX_HP, 0])
	assert_false(r.use_potion(), "none left")
	for i in Tuning.POTION_MAX:
		r.add_potion()
	assert_false(r.add_potion())
	assert_eq(r.potions, Tuning.POTION_MAX)


func test_a_dead_run_cannot_drink():
	var r := _run()
	watch_signals(r)
	r.take_damage(Tuning.MAX_HP)
	assert_eq(r.potions, Tuning.START_POTIONS, "the run dies holding a potion")
	assert_false(r.use_potion())
	assert_eq([r.hp, r.potions], [0, Tuning.START_POTIONS])
	r.take_damage(Tuning.MAX_HP)
	assert_signal_emit_count(r, "died", 1)


func test_potion_heals_by_its_amount_and_stops_at_the_maximum():
	var r := _run()
	r.take_damage(50)
	r.use_potion()
	assert_eq(r.hp, Tuning.MAX_HP - 50 + Tuning.POTION_HEAL)
	r.add_potion()
	r.use_potion()
	assert_eq(r.hp, Tuning.MAX_HP, "healing is capped at the maximum")


func test_changed_fires_on_every_mutation_and_only_on_those():
	var r := _run()
	_two_encounters(r)
	watch_signals(r)
	r.take_damage(10)
	assert_signal_emit_count(r, "changed", 1)
	r.use_potion()
	assert_signal_emit_count(r, "changed", 2)
	r.add_potion()
	assert_signal_emit_count(r, "changed", 3)
	r.set_player_tile(Vector2i(1, 2))
	assert_signal_emit_count(r, "changed", 4)
	r.set_battle({"id": "a"})
	assert_signal_emit_count(r, "changed", 5)
	r.resolve_encounter("a", RunState.Outcome.LOST)
	assert_signal_emit_count(r, "changed", 6)
	assert_eq(r.hp, Tuning.MAX_HP)
	assert_false(r.use_potion(), "refused at full HP")
	r.potions = Tuning.POTION_MAX
	assert_false(r.add_potion(), "refused at the cap")
	r.take_damage(0)
	assert_signal_emit_count(r, "changed", 6)


func test_resolve_encounter():
	var r := _run()
	_two_encounters(r)
	r.set_battle({"id": "a"})
	assert_eq(r.resolve_encounter("a", RunState.Outcome.WON), 1)
	assert_true(r.encounters.a.resolved)
	assert_true(r.battle.is_empty())
	assert_eq(r.resolve_encounter("b", RunState.Outcome.LOST), 0)


func test_resolve_emits_changed_once_even_when_it_adds_a_potion():
	var r := _run()
	_two_encounters(r)
	watch_signals(r)
	assert_eq(r.resolve_encounter("a", RunState.Outcome.WON), 1)
	assert_eq(r.potions, Tuning.START_POTIONS + 1)
	assert_signal_emit_count(r, "changed", 1)


func test_only_a_win_drops_a_potion():
	var r := _run()
	_two_encounters(r)
	r.encounters.a.resolved = false
	for outcome in [RunState.Outcome.LOST, RunState.Outcome.DRAWN]:
		assert_eq(r.resolve_encounter("a", outcome), 0)
	assert_eq(r.potions, Tuning.START_POTIONS)
	assert_true(r.encounters.a.resolved, "a loss or a draw still resolves it")


func test_drop_chance_follows_the_kind():
	# 200 won puzzles: at 25% the count is far from 0 and far from 200.
	var r := _run()
	var drops := 0
	for i in 200:
		r.encounters = {"p": {"kind": "puzzle", "content": "", "mandatory": false, "resolved": false}}
		r.potions = 0
		drops += r.resolve_encounter("p", RunState.Outcome.WON)
	assert_between(drops, 20, 80)
	for kind in ["theory", "strong"]:
		for i in 50:
			r.encounters = {"e": {"kind": kind, "content": "", "mandatory": true, "resolved": false}}
			r.potions = 0
			assert_eq(r.resolve_encounter("e", RunState.Outcome.WON), 1, kind)


func test_a_win_at_the_potion_cap_gains_nothing():
	var r := _run()
	_two_encounters(r)
	r.potions = Tuning.POTION_MAX
	assert_eq(r.resolve_encounter("a", RunState.Outcome.WON), 0)
	assert_eq(r.potions, Tuning.POTION_MAX)


func test_round_trip_keeps_everything():
	var r := _run()
	r.take_damage(30)
	r.chunk_order = PackedStringArray(["start", "bridge"])
	r.set_player_tile(Vector2i(7, 70))
	r.set_battle({"id": "a", "moves": ["e2e4"]})
	r.rng.randi()
	var copy := RunState.from_dict(_through_json(r))
	assert_eq_deep(copy.to_dict(), r.to_dict())
	assert_eq(copy.rng.randi(), r.rng.randi())


func test_round_trip_keeps_the_typed_fields():
	var r := _run()
	r.chunk_order = PackedStringArray(["start", "bridge"])
	r.set_player_tile(Vector2i(7, 70))
	_two_encounters(r)
	var copy := RunState.from_dict(_through_json(r))
	assert_eq(copy.player_tile, Vector2i(7, 70))
	assert_eq(copy.chunk_order, PackedStringArray(["start", "bridge"]))
	assert_eq([copy.rating, copy.hp, copy.potions], [1200, Tuning.MAX_HP, Tuning.START_POTIONS])
	assert_eq(copy.opening_id, "italian_game")
	assert_eq_deep(copy.encounters, r.encounters)


func test_large_rng_state_survives_json():
	var r := RunState.create(9_000_000_000_000_000_001, 1200, "italian_game")
	var copy := RunState.from_dict(_through_json(r))
	assert_eq(copy.seed, r.seed)
	assert_eq(copy.rng.state, r.rng.state)


func test_negative_seed_survives_json():
	var r := RunState.create(-7, 1200, "italian_game")
	r.rng.randi()
	var copy := RunState.from_dict(_through_json(r))
	assert_eq(copy.seed, -7)
	assert_eq(copy.rng.randi(), r.rng.randi())


func test_to_dict_stores_the_64_bit_values_as_strings():
	var d := RunState.create(9_000_000_000_000_000_001, 1200, "italian_game").to_dict()
	assert_typeof(d.seed, TYPE_STRING)
	assert_typeof(d.rng_state, TYPE_STRING)
	assert_eq(d.seed, "9000000000000000001")


func test_from_dict_rejects_bad_input():
	assert_null(RunState.from_dict({}))
	assert_null(RunState.from_dict({"version": 99}))


func test_from_dict_rejects_a_missing_field():
	for field in _run().to_dict().keys():
		var d := _run().to_dict()
		d.erase(field)
		assert_null(RunState.from_dict(d), "without %s" % field)


func test_from_dict_rejects_a_wrong_type():
	var wrong := {
		"version": "1",
		"seed": 42,
		"rng_state": 42,
		"rating": "1200",
		"opening_id": 5,
		"hp": null,
		"potions": [1],
		"chunk_order": "start",
		"player_tile": [1],
		"encounters": [],
		"battle": "none",
	}
	for field in wrong:
		var d := _run().to_dict()
		d[field] = wrong[field]
		assert_null(RunState.from_dict(d), "bad %s" % field)


func test_from_dict_rejects_values_that_are_not_what_they_look_like():
	var bad_seed := _run().to_dict()
	bad_seed.seed = "not a number"
	assert_null(RunState.from_dict(bad_seed), "a seed that is not a decimal string")
	var bad_tile := _run().to_dict()
	bad_tile.player_tile = [1, "2"]
	assert_null(RunState.from_dict(bad_tile), "a tile with a text coordinate")
	var bad_chunks := _run().to_dict()
	bad_chunks.chunk_order = ["start", 3]
	assert_null(RunState.from_dict(bad_chunks), "a chunk id that is not a string")


func test_from_dict_does_not_fire_died_for_a_dead_run():
	var r := _run()
	r.take_damage(Tuning.MAX_HP)
	var copy := RunState.from_dict(_through_json(r))
	watch_signals(copy)
	copy.take_damage(5)
	assert_eq(copy.hp, 0)
	assert_signal_not_emitted(copy, "died")
