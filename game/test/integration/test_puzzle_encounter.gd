extends GutTest
const FakeEngine := preload("res://test/support/fake_engine.gd")
const PUZZLE := {"id": "p1", "fen": "5k2/5ppp/8/8/8/8/8/RR4K1 b - - 0 1", "moves": ["f8g8", "a1a8"],
	"rating": 1000, "themes": ["mateIn1", "oneMove", "backRankMate"]}
## The same puzzle with no theme worth naming.
const PLAIN_PUZZLE := {"id": "p2", "fen": "5k2/5ppp/8/8/8/8/8/RR4K1 b - - 0 1", "moves": ["f8g8", "a1a8"],
	"rating": 1000, "themes": ["oneMove", "short"]}
## The position the player faces: the puzzle's FEN after the opponent's first move.
const FACED := "6k1/5ppp/8/8/8/8/8/RR4K1 w - - 1 2"
var fake
var run: RunState
var enc: PuzzleEncounter

func before_each():
	fake = FakeEngine.new(); add_child_autofree(fake)
	run = RunState.create(1, 1200, "italian_game")
	_make(PUZZLE)

func _make(puzzle: Dictionary) -> void:
	enc = PuzzleEncounter.new(puzzle, run, fake); enc.encounter_id = "e1"; enc.enemy_name = "Greedy Pawn"
	enc.opponent_delay_s = 0.0; enc.explain_timeout_s = 0.2
	watch_signals(enc); add_child_autofree(enc)

func _start():
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)

func test_opponent_move_is_played_first():
	await _start()
	assert_eq(get_signal_parameters(enc, "board_changed", 1)[1], "f8g8")

func test_begin_shows_the_start_position_and_a_full_enemy_bar():
	enc.begin()
	assert_signal_emitted_with_parameters(enc, "board_changed", [PUZZLE.fen, ""])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [1.0])
	await wait_for_signal(enc.input_enabled, 2)
	assert_eq(get_signal_parameters(enc, "board_changed", 1), [FACED, "f8g8"])
	assert_signal_emitted_with_parameters(enc, "message", ["Greedy Pawn attacks! Find the best move."])
	assert_signal_emitted_with_parameters(enc, "input_enabled", [true])
	assert_eq(enc.current_fen(), FACED)

func test_the_player_is_the_side_that_moves_after_the_opponent():
	assert_true(enc.player_white())

func test_correct_move_wins_without_damage():
	await _start(); enc.submit_move("a1a8")
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	assert_eq(run.hp, 100); assert_eq(run.battle.outcome, RunState.Outcome.WON)

func test_a_win_shows_the_move_and_empties_the_enemy_bar():
	await _start(); enc.submit_move("a1a8")
	assert_signal_emitted_with_parameters(enc, "board_changed", ["R5k1/5ppp/8/8/8/8/8/1R4K1 b - - 2 2", "a1a8"])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [0.0])
	assert_signal_emitted_with_parameters(enc, "message", ["Correct!"])

func test_any_checkmate_is_accepted():
	await _start(); enc.submit_move("b1b8")
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])

func test_wrong_move_costs_hp_and_shows_the_solution():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	assert_eq(run.hp, 90); assert_signal_emitted_with_parameters(enc, "arrow", ["a1a8"])
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0],
		"Back-rank mate. After Ra7, the best reply is Kf8. The best move was Ra8#.")

func test_a_wrong_move_is_taken_back_and_committed_before_the_search_answers():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	assert_eq(get_signal_parameters(enc, "board_changed"), [FACED, ""])
	assert_eq(enc.outcome, RunState.Outcome.LOST); assert_eq(run.battle.outcome, RunState.Outcome.LOST)
	assert_signal_not_emitted(enc, "finished")
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])

func test_the_explanation_searches_the_position_after_the_wrong_move():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(fake.searches.size(), 1)
	var search: Dictionary = fake.searches[0]
	assert_eq([search.fen, search.moves, search.ms, search.multipv],
		[FACED, PackedStringArray(["a1a7"]), Tuning.EXPLAIN_SEARCH_MS, 1])

func test_the_message_leaves_out_a_theme_the_puzzle_does_not_name():
	_make(PLAIN_PUZZLE)
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0], "After Ra7, the best reply is Kf8. The best move was Ra8#.")

func test_the_message_leaves_out_a_sentence_the_builder_cannot_write():
	fake.replies = [[FakeEngine.line("a8a8", 0)]]
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0], "Back-rank mate. The best move was Ra8#.")

func test_explanation_falls_back_when_the_engine_never_answers():
	fake.available = false
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0], "Back-rank mate. The best move was Ra8#.")
	assert_eq(fake.searches.size(), 0)

func test_explanation_waits_for_a_busy_engine():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); fake.busy_frames = 3; enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0],
		"Back-rank mate. After Ra7, the best reply is Kf8. The best move was Ra8#.")

func test_a_wrong_answer_that_kills_the_run_still_finishes():
	run.hp = 5; watch_signals(run)
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(run.hp, 0); assert_signal_emit_count(run, "died", 1)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])

func test_moves_are_ignored_until_input_is_enabled():
	enc.begin(); enc.submit_move("f8g8")
	assert_eq(run.hp, 100); assert_eq(enc.outcome, -1); assert_signal_not_emitted(enc, "finished")
	await wait_for_signal(enc.input_enabled, 2)

func test_an_illegal_move_is_ignored():
	await _start(); enc.submit_move("a1a9"); enc.submit_move("g1g8"); enc.submit_move("a8a1")
	assert_signal_not_emitted(enc, "finished"); assert_eq(run.hp, 100)
	assert_signal_emit_count(enc, "board_changed", 2)
	enc.submit_move("a1a8")
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])

func test_a_move_after_the_puzzle_is_over_is_ignored():
	await _start(); enc.submit_move("a1a8"); enc.submit_move("a1a7")
	assert_eq(run.hp, 100); assert_signal_emit_count(enc, "finished", 1)

func test_a_second_move_while_the_explanation_runs_is_ignored():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7"); enc.submit_move("b1b7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(run.hp, 90); assert_signal_emit_count(enc, "finished", 1)

func test_input_is_switched_off_when_a_move_is_accepted():
	await _start(); enc.submit_move("a1a8")
	assert_signal_emitted_with_parameters(enc, "input_enabled", [false])

func test_snapshot_is_json_safe():
	await _start()
	assert_eq(enc.snapshot(), {"id": "e1", "kind": "puzzle", "content": "p1", "outcome": -1,
		"message": "Greedy Pawn attacks! Find the best move."})
	enc.submit_move("a1a8")
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(run.battle))
	assert_eq([through_json.id, through_json.kind, through_json.content], ["e1", "puzzle", "p1"])
	assert_eq(int(through_json.outcome), RunState.Outcome.WON)

func test_begin_commits_the_battle_before_the_opponent_moves():
	enc.begin()
	assert_eq(run.battle, {"id": "e1", "kind": "puzzle", "content": "p1", "outcome": -1, "message": ""})
	await wait_for_signal(enc.input_enabled, 2)

func test_restored_finished_puzzle_does_not_damage_again():
	enc.restore({"id": "e1", "kind": "puzzle", "content": "p1", "outcome": RunState.Outcome.LOST})
	enc.begin(); await wait_for_signal(enc.finished, 2)
	assert_eq(run.hp, 100); assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])

func test_a_restored_finished_puzzle_shows_the_solved_position_and_finishes_a_frame_later():
	enc.restore({"id": "e1", "kind": "puzzle", "content": "p1", "outcome": float(RunState.Outcome.WON)})
	enc.begin()
	assert_signal_emitted_with_parameters(enc, "board_changed", ["R5k1/5ppp/8/8/8/8/8/1R4K1 b - - 2 2", "a1a8"])
	assert_signal_not_emitted(enc, "finished")
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	assert_signal_not_emitted(enc, "input_enabled")

func test_a_restored_finished_puzzle_ignores_moves():
	enc.restore({"id": "e1", "kind": "puzzle", "content": "p1", "outcome": RunState.Outcome.WON})
	enc.begin(); await wait_for_signal(enc.finished, 2)
	enc.submit_move("a1a7")
	assert_eq(run.hp, 100)

func test_leaving_the_tree_disconnects_from_the_engine():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(fake.search_finished.get_connections().size(), 1)
	remove_child(enc)
	assert_eq(fake.search_finished.get_connections().size(), 0)
	enc.free()

func test_a_search_result_nobody_asked_for_is_ignored():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	fake.search_finished.emit("a8a8", [FakeEngine.line("a8a8", 0)])
	assert_eq(enc._search_lines[0].pv[0], "g8f8")

func test_restored_finished_puzzle_repeats_its_verdict():
	enc.restore({"id": "e1", "kind": "puzzle", "content": "p1", "outcome": RunState.Outcome.LOST, "message": "M"})
	enc.begin()
	assert_signal_emitted_with_parameters(enc, "message", ["M"]); assert_signal_emit_count(enc, "message", 1)
	await wait_for_signal(enc.finished, 2)

func test_the_verdict_is_saved_with_the_outcome():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(run.battle.message, get_signal_parameters(enc, "message")[0])
	assert_string_contains(run.battle.message, "The best move was")

func test_a_win_is_saved_with_its_message():
	await _start(); enc.submit_move("a1a8")
	assert_eq(run.battle.message, "Correct!")

func test_a_kill_during_the_explanation_does_not_repeat_the_attack_message():
	await _start(); enc.submit_move("a1a7")
	assert_eq(run.battle.outcome, RunState.Outcome.LOST); assert_eq(run.battle.message, "")
	await wait_for_signal(enc.finished, 2)
