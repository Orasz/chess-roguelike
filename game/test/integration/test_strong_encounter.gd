extends GutTest
## The strong encounter: a game under way that the player must convert within the move limit. The
## enemy's bar follows the player's advantage, and the player loses HP for the win chance their own
## moves throw away. Most tests script the engine with FakeEngine; one plays against Stockfish.

const FakeEngine := preload("res://test/support/fake_engine.gd")
const OPENING := {"id": "s1", "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "moves": ["e7e5", "g1f3"]}
const ENDGAME := {"id": "s2", "fen": "6k1/4Q3/6K1/8/8/8/8/8 b - - 0 1", "moves": ["g8h8"]}
## After 1.f3 e5 the player, White, can walk into 2.g4 Qh4#.
const FOOLS_MATE := {"id": "s3", "fen": "rnbqkbnr/pppppppp/8/8/8/5P2/PPPPP1PP/RNBQKBNR b KQkq - 0 1", "moves": ["e7e5"]}
## The enemy is White here, so the player is Black.
const PLAYER_BLACK := {"id": "s4", "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "moves": ["e2e4"]}
var fake
var run: RunState
var enc: StrongEncounter
var real_engine: UciEngine


func after_each():
	if is_instance_valid(real_engine):
		real_engine.shutdown()


## Builds the encounter on a fake engine that answers the opening evaluation with `first_reply`,
## without starting it.
func _create(position: Dictionary, first_reply: Array, enemy_elo := 2400) -> void:
	fake = FakeEngine.new(); add_child_autofree(fake); fake.replies = [first_reply]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(position, run, fake, enemy_elo); enc.encounter_id = "g"; enc.enemy_name = "Gatekeeper"
	watch_signals(enc); add_child_autofree(enc)

func _make(position: Dictionary, first_reply: Array) -> void:
	_create(position, first_reply)
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)

func _fen_after(position: Dictionary, moves: Array) -> String:
	return ChessRules.fen_after(position.fen, PackedStringArray(moves))


func test_opening_eval_fills_the_enemy_bar():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [1.0]); assert_eq(enc.snapshot().cp_start, 300)

func test_mistake_costs_hp_from_lost_win_chance():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300), FakeEngine.line("g8f6", 250)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75); assert_eq(enc.moves[-1], "b8c6")
	assert_signal_emitted_with_parameters(enc, "arrow", ["g1f3"])

func test_good_move_lowers_the_enemy_bar_without_damage():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", -550)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 100); assert_almost_eq(get_signal_parameters(enc, "enemy_bar")[0], 0.5, 0.001)

func test_decisive_advantage_wins_before_the_enemy_moves():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", -900)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON]); assert_eq(enc.moves.size(), 2)

func test_checkmate_wins_and_stalemate_draws_without_searching():
	await _make(ENDGAME, [FakeEngine.line("e7e8", 500)])
	enc.submit_move("e7e8"); assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	await _make(ENDGAME, [FakeEngine.line("e7e8", 500)])
	enc.submit_move("e7f7"); assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN])
	assert_eq(fake.searches.size(), 1, "only the opening eval")

func test_move_limit_lets_the_enemy_escape():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)]); enc.move_limit = 1
	fake.replies.append([FakeEngine.line("b8c6", 0)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.finished, 2)
	assert_eq(run.hp, 100 - 13 - Tuning.STRONG_FAIL_DAMAGE)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])

func test_restore_with_enemy_to_move_damages_once():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.replies = [[FakeEngine.line("b8c6", 300)]]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); add_child_autofree(enc)
	enc.restore({"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5", "b1c3"], "cp_start": 300,
		"cp_now": 300, "player_moves": 1, "hint": "g1f3", "outcome": -1})
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75); assert_eq(fake.searches.size(), 1); assert_eq(enc.moves[-1], "b8c6")

func test_waits_for_a_busy_engine():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.busy_frames = 5
	fake.replies = [[FakeEngine.line("g1f3", 300)]]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); add_child_autofree(enc); enc.begin()
	await wait_process_frames(2); assert_eq(fake.searches.size(), 0)
	await wait_for_signal(enc.input_enabled, 2); assert_eq(fake.searches.size(), 1)

func test_ignores_a_search_it_did_not_start():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.search_finished.emit("b8c6", [FakeEngine.line("b8c6", 900)])
	assert_eq(run.hp, 100); assert_eq(enc.moves.size(), 1)

func test_engine_that_never_answers_ends_in_a_draw():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.available = false
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); enc.engine_wait_s = 0.2
	watch_signals(enc); add_child_autofree(enc); enc.begin()
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN]); assert_eq(run.hp, 100)

func test_real_engine_plays_a_reply():
	real_engine = UciEngine.new(); add_child_autofree(real_engine)
	assert_true(real_engine.start())
	assert_true(await wait_for_signal(real_engine.ready_ok, 15), "ready_ok")
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, real_engine, 2400); enc.encounter_id = "g"; enc.enemy_name = "Gatekeeper"
	watch_signals(enc); add_child_autofree(enc)
	enc.begin(); assert_true(await wait_for_signal(enc.input_enabled, 15), "the opening eval")
	enc.submit_move("g1f3")
	# The begin, the player's move, then the reply: wait for the one that carries the reply.
	var replied := func() -> bool: return get_signal_parameters(enc, "board_changed")[1] != "g1f3"
	assert_true(await wait_until(replied, 15), "the reply")
	var reply: String = get_signal_parameters(enc, "board_changed")[1]
	assert_has(ChessRules.inspect(OPENING.fen, PackedStringArray(["e7e5", "g1f3"])).legal, reply)
	assert_true(run.hp <= 100)
	assert_signal_emit_count(enc, "board_changed", 3)


func test_begin_shows_the_board_and_announces_the_enemy_before_the_opening_eval():
	_create(OPENING, [FakeEngine.line("g1f3", 300)])
	enc.begin()
	assert_eq(get_signal_parameters(enc, "board_changed", 0), [_fen_after(OPENING, ["e7e5"]), "e7e5"])
	assert_signal_emitted_with_parameters(enc, "message",
		["Gatekeeper blocks the way! Convert your advantage within 12 moves."])
	assert_signal_not_emitted(enc, "input_enabled"); assert_signal_not_emitted(enc, "enemy_bar")
	assert_eq(enc.current_fen(), _fen_after(OPENING, ["e7e5"]))
	await wait_for_signal(enc.input_enabled, 2)

func test_begin_commits_the_battle_before_the_opening_eval():
	_create(OPENING, [FakeEngine.line("g1f3", 300)])
	enc.begin()
	assert_eq(run.battle, {"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5"], "cp_start": null,
		"cp_now": 0, "player_moves": 0, "hint": "", "outcome": -1})
	await wait_for_signal(enc.input_enabled, 2)

func test_the_opening_eval_is_a_full_strength_search_of_the_player_to_move_position():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	assert_eq(fake.searches.size(), 1)
	var search: Dictionary = fake.searches[0]
	assert_eq([search.fen, search.moves, search.ms, search.multipv],
		[OPENING.fen, PackedStringArray(["e7e5"]), Tuning.STRONG_SEARCH_MS, Tuning.STRONG_CANDIDATES])

func test_the_opening_eval_is_committed_with_its_hint():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	assert_eq(run.battle, {"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5"], "cp_start": 300,
		"cp_now": 300, "player_moves": 0, "hint": "g1f3", "outcome": -1})

func test_the_player_is_the_side_that_moves_after_the_enemy():
	_create(OPENING, [])
	assert_true(enc.player_white())
	_create(PLAYER_BLACK, [])
	assert_false(enc.player_white())

func test_moves_are_ignored_until_the_opening_eval_is_done():
	_create(OPENING, [FakeEngine.line("g1f3", 300)])
	enc.begin(); enc.submit_move("g1f3")
	assert_eq(enc.moves.size(), 1)
	await wait_for_signal(enc.input_enabled, 2)

func test_a_player_move_is_shown_and_committed_before_the_search_answers():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300)])
	enc.submit_move("b1c3")
	assert_eq(get_signal_parameters(enc, "board_changed"), [_fen_after(OPENING, ["e7e5", "b1c3"]), "b1c3"])
	assert_eq(run.battle.moves, ["e7e5", "b1c3"]); assert_eq(run.battle.player_moves, 1)
	assert_eq(run.battle.cp_now, 300, "the old evaluation"); assert_eq(run.hp, 100)
	await wait_for_signal(enc.input_enabled, 2)

func test_the_search_after_a_player_move_covers_the_whole_line():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	var search: Dictionary = fake.searches[1]
	assert_eq([search.fen, search.moves, search.ms, search.multipv],
		[OPENING.fen, PackedStringArray(["e7e5", "b1c3"]), Tuning.STRONG_SEARCH_MS, Tuning.STRONG_CANDIDATES])

func test_the_damage_is_committed_with_the_enemy_reply():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300, false, PackedStringArray(["d2d4"]))])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75)
	assert_eq(run.battle, {"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5", "b1c3", "b8c6"],
		"cp_start": 300, "cp_now": -300, "player_moves": 1, "hint": "d2d4", "outcome": -1})
	assert_eq(get_signal_parameters(enc, "board_changed"), [_fen_after(OPENING, ["e7e5", "b1c3", "b8c6"]), "b8c6"])
	assert_signal_emit_count(enc, "board_changed", 3)

func test_a_mistake_is_explained_from_the_enemy_best_line():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("g8f6", 250), FakeEngine.line("b8c6", 300)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(get_signal_parameters(enc, "message")[0], "After Nc3, the best reply is Nc6.")

func test_a_small_loss_costs_hp_without_an_arrow_or_an_explanation():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", -200)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 96)
	assert_signal_not_emitted(enc, "arrow"); assert_signal_emit_count(enc, "message", 1)

func test_a_mistake_without_a_hint_draws_no_arrow():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.replies = [[FakeEngine.line("b8c6", 300)]]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); watch_signals(enc); add_child_autofree(enc)
	enc.restore({"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5", "b1c3"], "cp_start": 300,
		"cp_now": 300, "player_moves": 1, "hint": "", "outcome": -1})
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75); assert_signal_not_emitted(enc, "arrow")
	assert_eq(get_signal_parameters(enc, "message")[0], "After Nc3, the best reply is Nc6.")

func test_the_enemy_plays_the_line_the_picker_chooses_with_the_run_rng():
	var lines := [FakeEngine.line("b8c6", 0), FakeEngine.line("g8f6", 0), FakeEngine.line("d7d6", 0)]
	for seed_value in [1, 2, 3, 4]:
		_create(OPENING, [FakeEngine.line("g1f3", 0)], 400)
		run.rng.seed = seed_value
		var twin := RandomNumberGenerator.new(); twin.seed = seed_value
		var expected: String = lines[MovePicker.choose(lines, 400, twin)].pv[0]
		enc.begin(); await wait_for_signal(enc.input_enabled, 2)
		fake.replies.append(lines)
		enc.submit_move("g1f3"); await wait_for_signal(enc.input_enabled, 2)
		assert_eq(enc.moves[-1], expected, "seed %d" % seed_value)
		assert_eq(run.rng.state, twin.state, "one draw for the reply")

func test_being_mated_loses():
	await _make(FOOLS_MATE, [FakeEngine.line("d2d4", 0)])
	fake.replies.append([FakeEngine.line("d8h4", 1, true)])
	enc.submit_move("g2g4"); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])
	assert_eq(enc.moves[-1], "d8h4"); assert_eq(run.hp, 75, "an even game thrown away is 50 points")
	assert_signal_emitted_with_parameters(enc, "message", ["After g4, Qh4 is checkmate."])
	assert_eq(run.battle.outcome, RunState.Outcome.LOST)

func test_a_win_by_mate_empties_the_enemy_bar_and_is_committed():
	await _make(ENDGAME, [FakeEngine.line("e7e8", 500)])
	enc.submit_move("e7e8")
	assert_eq(get_signal_parameters(enc, "enemy_bar")[0], 0.0)
	assert_eq(run.battle.outcome, RunState.Outcome.WON); assert_eq(run.battle.moves, ["g8h8", "e7e8"])

func test_the_escape_message_names_the_enemy():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)]); enc.move_limit = 1
	fake.replies.append([FakeEngine.line("b8c6", -300)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "message", ["Gatekeeper escapes!"])
	assert_eq(enc.moves.size(), 2, "the enemy does not move"); assert_eq(run.battle.outcome, RunState.Outcome.LOST)

func test_a_search_without_lines_makes_the_opponent_withdraw():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([])
	enc.submit_move("b1c3"); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN])
	assert_signal_emitted_with_parameters(enc, "message", ["The opponent hesitates and withdraws."])
	assert_eq(run.hp, 100); assert_eq(run.battle.outcome, RunState.Outcome.DRAWN)

## A line the engine sent without a pv.
func _line_without_pv(value: int) -> EngineEval:
	var e := EngineEval.new(); e.value = value; return e

func test_a_search_whose_only_line_has_no_pv_makes_the_opponent_withdraw():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([_line_without_pv(300)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN])
	assert_signal_emitted_with_parameters(enc, "message", ["The opponent hesitates and withdraws."])
	assert_eq(run.hp, 100, "no damage without a move"); assert_eq(enc.moves.size(), 2)
	assert_eq(run.battle.outcome, RunState.Outcome.DRAWN)

func test_lines_without_a_pv_are_dropped_from_the_search():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	# Kept, the line without a pv would be the enemy's best one, so the one it charges and plays.
	fake.replies.append([_line_without_pv(900), FakeEngine.line("b8c6", 300)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75); assert_eq(enc.moves[-1], "b8c6")
	assert_eq(enc.outcome, -1, "the battle goes on"); assert_signal_not_emitted(enc, "finished")

func test_an_opening_eval_without_a_pv_makes_the_opponent_withdraw():
	_create(OPENING, [_line_without_pv(300)])
	enc.begin(); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN])
	assert_eq(run.battle.cp_start, null, "no opening evaluation")

func test_a_search_the_engine_never_answers_makes_the_opponent_withdraw():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)]); enc.engine_wait_s = 0.2
	fake.replies.append([FakeEngine.line("b8c6", 300)])
	enc.submit_move("b1c3"); fake.shutdown()
	assert_eq(fake.searches.size(), 2, "the engine accepted the search")
	await wait_process_frames(3)
	assert_signal_not_emitted(enc, "finished")
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN])
	assert_signal_emitted_with_parameters(enc, "message", ["The opponent hesitates and withdraws."])
	assert_eq(run.hp, 100); assert_eq(run.battle.outcome, RunState.Outcome.DRAWN)

func test_a_move_while_the_enemy_thinks_is_ignored():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", -300)])
	enc.submit_move("g1f3"); enc.submit_move("d2d4")
	await wait_for_signal(enc.input_enabled, 2)
	assert_eq(enc.moves, PackedStringArray(["e7e5", "g1f3", "b8c6"]))

func test_a_snapshot_survives_json():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300, false, PackedStringArray(["d2d4"]))])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(run.battle))
	var restored := StrongEncounter.new(OPENING, run, fake, 2400); restored.encounter_id = "g"; autofree(restored)
	restored.restore(through_json)
	var saved := restored.snapshot()
	assert_eq(saved, run.battle)
	assert_eq([typeof(saved.cp_start), typeof(saved.cp_now), typeof(saved.player_moves), typeof(saved.outcome)],
		[TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT])

func test_a_battle_saved_before_the_opening_eval_evaluates_it_on_resume():
	_create(OPENING, [FakeEngine.line("g1f3", 300)])
	enc.restore(JSON.parse_string(JSON.stringify({"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5"],
		"cp_start": null, "cp_now": 0, "player_moves": 0, "hint": "", "outcome": -1})))
	assert_eq(enc.snapshot().cp_start, null)
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(fake.searches.size(), 1); assert_eq(enc.snapshot().cp_start, 300)
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [1.0])

func test_restore_on_the_player_turn_shows_the_bar_and_waits_for_the_player():
	_create(OPENING, [])
	enc.restore({"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5", "g1f3", "b8c6"], "cp_start": 300.0,
		"cp_now": 550.0, "player_moves": 1.0, "hint": "", "outcome": -1.0})
	enc.begin()
	assert_eq(get_signal_parameters(enc, "board_changed", 0), [_fen_after(OPENING, ["e7e5", "g1f3", "b8c6"]), "b8c6"])
	assert_almost_eq(get_signal_parameters(enc, "enemy_bar")[0], 0.5, 0.001)
	assert_signal_emitted_with_parameters(enc, "input_enabled", [true])
	assert_signal_not_emitted(enc, "message"); assert_eq(fake.searches.size(), 0)

func test_a_restored_finished_battle_finishes_a_frame_later():
	_create(OPENING, [])
	enc.restore({"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5", "g1f3"], "cp_start": 300,
		"cp_now": 900, "player_moves": 1, "hint": "", "outcome": float(RunState.Outcome.WON)})
	enc.begin()
	assert_signal_emitted_with_parameters(enc, "board_changed", [_fen_after(OPENING, ["e7e5", "g1f3"]), "g1f3"])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [0.0])
	assert_signal_not_emitted(enc, "finished")
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	assert_signal_not_emitted(enc, "input_enabled"); assert_eq(fake.searches.size(), 0)

func test_leaving_the_tree_during_the_search_changes_nothing():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300)])
	enc.submit_move("b1c3"); remove_child(enc)
	await wait_process_frames(3)
	assert_eq(run.hp, 100); assert_eq(run.battle.moves, ["e7e5", "b1c3"]); assert_eq(run.battle.outcome, -1)
	assert_signal_not_emitted(enc, "finished")
	enc.free()
