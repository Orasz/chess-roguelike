extends GutTest
## The theory encounter on the real Italian Game book. The player is White; the enemy answers with
## book moves, and leaving the book is taken back, explained and charged once per position.

const START := UciEngine.START_FEN
var book: OpeningBook
var run: RunState
var enc: TheoryEncounter


func before_each():
	book = OpeningBook.load_file("res://data/openings/italian_game.json")
	run = RunState.create(1, 1200, "italian_game")
	_make()


func after_each():
	TranslationServer.set_locale("en")


func _make() -> void:
	enc = TheoryEncounter.new(book, run); enc.encounter_id = "e1"; enc.enemy_name = "Old Bishop"
	enc.opponent_delay_s = 0.0
	watch_signals(enc); add_child_autofree(enc)


## Plays `uci` and waits until the enemy has answered and the player may move again.
func _play(uci: String):
	enc.submit_move(uci); await wait_for_signal(enc.input_enabled, 2)


## Plays the book's main move at every turn, up to the end of the line.
func _play_the_main_line():
	for i in 12:
		enc.submit_move(book.player_options(enc.moves)[0].move)
		if enc.outcome != -1:
			return
		await wait_for_signal(enc.input_enabled, 2)


func _fen_after(moves: Array) -> String:
	return ChessRules.fen_after(START, PackedStringArray(moves))


func test_begin_shows_the_start_position_the_plans_and_a_full_enemy_bar():
	enc.begin()
	assert_signal_emitted_with_parameters(enc, "board_changed", [START, ""])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [1.0])
	assert_signal_emitted_with_parameters(enc, "message", [book.plans()])
	assert_signal_emitted_with_parameters(enc, "input_enabled", [true])
	assert_eq(enc.current_fen(), START)

func test_the_plans_are_shown_in_the_language_of_the_locale():
	TranslationServer.set_locale("it")
	enc.begin()
	assert_string_starts_with(get_signal_parameters(enc, "message")[0], "La Partita Italiana")

func test_the_player_is_white():
	assert_true(enc.player_white())

func test_begin_commits_the_battle():
	enc.begin()
	assert_eq(run.battle, {"id": "e1", "kind": "theory", "content": "italian_game", "moves": [], "punished": [], "outcome": -1})

func test_moves_are_ignored_until_input_is_enabled():
	enc.submit_move("e2e4")
	assert_eq(enc.moves.size(), 0); assert_signal_not_emitted(enc, "board_changed")

func test_book_moves_complete_the_line_and_win():
	enc.begin()
	await _play_the_main_line()
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	assert_eq(enc.outcome, RunState.Outcome.WON); assert_eq(run.hp, 100)
	assert_true(book.is_complete(enc.moves))

func test_finishing_the_line_empties_the_enemy_bar_and_commits_the_win():
	enc.begin()
	await _play_the_main_line()
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [0.0])
	assert_eq(run.battle.outcome, RunState.Outcome.WON)
	assert_eq(get_signal_parameters(enc, "board_changed")[1], enc.moves[-1])

func test_a_move_after_the_line_is_over_is_ignored():
	enc.restore({"id": "e1", "kind": "theory", "content": "italian_game", "outcome": RunState.Outcome.WON,
		"moves": ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "d2d3", "f8c5", "c2c3", "d7d6", "e1g1"], "punished": []})
	enc.begin(); await wait_for_signal(enc.finished, 2)
	enc.submit_move("a2a3")
	assert_eq(run.hp, 100); assert_signal_emit_count(enc, "finished", 1)

func test_a_book_move_is_shown_and_committed_before_the_enemy_replies():
	enc.begin(); enc.submit_move("e2e4")
	assert_eq(get_signal_parameters(enc, "board_changed"), [_fen_after(["e2e4"]), "e2e4"])
	assert_eq(run.battle.moves, ["e2e4"])
	assert_signal_emitted_with_parameters(enc, "input_enabled", [false])
	assert_signal_emit_count(enc, "board_changed", 2)
	await wait_for_signal(enc.input_enabled, 2)
	assert_eq(get_signal_parameters(enc, "board_changed"), [_fen_after(["e2e4", "e7e5"]), "e7e5"])
	assert_eq(run.battle.moves, ["e2e4", "e7e5"])

func test_enemy_replies_only_with_book_moves():
	enc.begin(); await _play("e2e4")
	assert_eq(enc.moves.size(), 2)
	assert_true(book.enemy_replies(PackedStringArray(["e2e4"])).has(enc.moves[1]))

func test_the_enemy_picks_its_reply_with_the_run_rng():
	var line := ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"]
	var replies := book.enemy_replies(PackedStringArray(line))
	assert_eq(replies, PackedStringArray(["f8c5", "g8f6"]))
	for seed_value in [1, 2, 3, 4]:
		run = RunState.create(seed_value, 1200, "italian_game"); _make()
		var twin := RandomNumberGenerator.new(); twin.seed = seed_value
		var expected := replies[twin.randi_range(0, replies.size() - 1)]
		enc.restore({"id": "e1", "kind": "theory", "content": "italian_game", "moves": line, "punished": [], "outcome": -1})
		enc.begin(); await wait_for_signal(enc.input_enabled, 2)
		assert_eq(enc.moves[5], expected, "seed %d" % seed_value)
		assert_eq(run.rng.state, twin.state, "one draw per reply")

func test_a_move_while_the_enemy_replies_is_ignored():
	enc.begin(); enc.submit_move("e2e4")
	enc.submit_move("d7d5")
	await wait_for_signal(enc.input_enabled, 2)
	assert_eq(enc.moves, PackedStringArray(["e2e4", "e7e5"])); assert_eq(run.hp, 100)

func test_leaving_the_book_costs_hp_once_and_shows_the_book_move():
	enc.begin()
	enc.submit_move("d2d4")
	assert_eq(run.hp, 95)
	assert_signal_emitted_with_parameters(enc, "arrow", ["e2e4"])
	var why: String = book.player_options(PackedStringArray())[0].why.en
	assert_string_contains(get_signal_parameters(enc, "message")[0], why)
	assert_string_contains(get_signal_parameters(enc, "message")[0], "That leaves the book.")
	enc.submit_move("a2a3")
	assert_eq(run.hp, 95)
	await _play("e2e4")
	assert_eq(enc.moves.size(), 2)

func test_an_off_book_move_is_taken_back_and_the_player_may_move_again():
	enc.begin(); enc.submit_move("d2d4")
	assert_eq(get_signal_parameters(enc, "board_changed"), [START, ""])
	assert_eq(enc.current_fen(), START); assert_eq(enc.moves.size(), 0)
	assert_eq(get_signal_parameters(enc, "input_enabled"), [true])
	assert_eq(enc.outcome, -1); assert_signal_not_emitted(enc, "finished")

func test_an_off_book_move_is_committed_with_its_ply_before_the_player_moves_again():
	enc.begin(); enc.submit_move("d2d4")
	assert_eq(run.battle.punished, [0]); assert_eq(run.battle.moves, [])

func test_every_off_book_move_explains_the_book_move_again():
	enc.begin(); enc.submit_move("d2d4"); enc.submit_move("a2a3")
	assert_signal_emit_count(enc, "message", 3)
	assert_signal_emit_count(enc, "arrow", 2)
	assert_eq(get_signal_parameters(enc, "message", 1), get_signal_parameters(enc, "message", 2))

func test_the_explanation_is_in_the_language_of_the_locale():
	TranslationServer.set_locale("it")
	enc.begin(); enc.submit_move("d2d4")
	var why: String = book.player_options(PackedStringArray())[0].why.it
	assert_string_contains(get_signal_parameters(enc, "message")[0], why)

func test_each_position_is_charged_once_on_its_own():
	enc.begin(); await _play("e2e4")
	enc.submit_move("a2a3"); enc.submit_move("h2h3")
	assert_eq(run.hp, 95); assert_eq(run.battle.punished, [2])
	assert_signal_emitted_with_parameters(enc, "arrow", ["g1f3"])
	await _play("g1f3")
	enc.submit_move("a2a3")
	assert_eq(run.hp, 90); assert_eq(run.battle.punished, [2, 4])

func test_an_off_book_move_that_kills_the_run_still_shows_the_book_move():
	run.hp = 5; watch_signals(run)
	enc.begin(); enc.submit_move("d2d4")
	assert_eq(run.hp, 0); assert_signal_emit_count(run, "died", 1)
	assert_signal_emitted_with_parameters(enc, "arrow", ["e2e4"])
	assert_eq(run.battle.punished, [0])

func test_restore_continues_mid_line():
	enc.restore({"id": "e1", "kind": "theory", "content": "italian_game", "moves": ["e2e4", "e7e5"], "punished": [], "outcome": -1})
	enc.begin()
	assert_eq(get_signal_parameters(enc, "board_changed"), [ChessRules.fen_after(START, PackedStringArray(["e2e4", "e7e5"])), "e7e5"])
	assert_signal_emitted_with_parameters(enc, "input_enabled", [true])
	assert_signal_not_emitted(enc, "message")
	assert_eq(enc.current_fen(), _fen_after(["e2e4", "e7e5"]))

func test_restore_on_the_enemys_turn_plays_its_reply():
	enc.restore({"id": "e1", "kind": "theory", "content": "italian_game", "moves": ["e2e4"], "punished": [], "outcome": -1})
	enc.begin()
	assert_signal_not_emitted(enc, "input_enabled")
	await wait_for_signal(enc.input_enabled, 2)
	assert_eq(enc.moves, PackedStringArray(["e2e4", "e7e5"]))
	assert_eq(get_signal_parameters(enc, "board_changed"), [_fen_after(["e2e4", "e7e5"]), "e7e5"])
	assert_eq(run.battle.moves, ["e2e4", "e7e5"])

func test_restore_keeps_the_positions_already_charged():
	enc.restore({"id": "e1", "kind": "theory", "content": "italian_game", "moves": ["e2e4", "e7e5"], "punished": [2], "outcome": -1})
	enc.begin(); enc.submit_move("a2a3")
	assert_eq(run.hp, 100)
	enc.submit_move("h2h3")
	assert_eq(run.hp, 100)

func test_snapshot_is_json_safe_and_restores_exactly():
	enc.begin(); await _play("e2e4"); enc.submit_move("a2a3")
	var saved := enc.snapshot()
	assert_eq(saved, {"id": "e1", "kind": "theory", "content": "italian_game", "moves": ["e2e4", "e7e5"], "punished": [2], "outcome": -1})
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(run.battle))
	assert_eq(through_json, {"id": "e1", "kind": "theory", "content": "italian_game", "moves": ["e2e4", "e7e5"], "punished": [2.0], "outcome": -1.0})
	run = RunState.create(1, 1200, "italian_game"); _make()
	enc.restore(through_json)
	assert_eq(enc.snapshot(), saved)
	assert_eq(typeof(enc.snapshot().punished[0]), TYPE_INT)
	enc.begin(); enc.submit_move("a2a3")
	assert_eq(run.hp, 100, "the position was already charged")

func test_restored_finished_encounter_shows_the_last_position_and_finishes_a_frame_later():
	var line := ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "d2d3", "f8c5", "c2c3", "d7d6", "e1g1"]
	enc.restore({"id": "e1", "kind": "theory", "content": "italian_game", "moves": line, "punished": [], "outcome": float(RunState.Outcome.WON)})
	enc.begin()
	assert_signal_emitted_with_parameters(enc, "board_changed", [_fen_after(line), "e1g1"])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [0.0])
	assert_signal_not_emitted(enc, "finished")
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	assert_signal_not_emitted(enc, "input_enabled"); assert_signal_not_emitted(enc, "message")

func test_the_enemy_does_not_reply_once_the_encounter_left_the_tree():
	enc.opponent_delay_s = 0.05
	enc.begin(); enc.submit_move("e2e4")
	remove_child(enc)
	await wait_seconds(0.2)
	assert_eq(enc.moves, PackedStringArray(["e2e4"]))
	assert_eq(run.battle.moves, ["e2e4"])
	enc.free()
