extends GutTest
## The battle screen renders an encounter's signals and forwards the player's moves. A stub
## encounter stands in for the real ones: it emits what the test tells it to, and records the moves.

const FakeEngine := preload("res://test/support/fake_engine.gd")
const START := UciEngine.START_FEN
const AFTER_E4 := "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

class StubEncounter extends Encounter:
	var began := false
	var moves: Array[String] = []

	func begin() -> void:
		began = true

	func submit_move(uci: String) -> void:
		moves.append(uci)

	func _on_player_move(_uci: String) -> void:
		pass

	func _kind() -> String:
		return "puzzle"

## Stands in for the window: the screen's anchors make it fill this control, as they fill the window.
var window: Control
var screen: BattleScreen
var fake: StubEncounter
var run: RunState

func before_each():
	run = RunState.create(1, 1200, "italian_game")
	fake = StubEncounter.new()
	fake.encounter_id = "3_41"
	fake.enemy_name = "Greedy Pawn"
	fake.run = run
	window = Control.new()
	window.size = Vector2(720, 1280)
	add_child_autofree(window)
	screen = load("res://battle/battle_screen.tscn").instantiate()
	window.add_child(screen)
	screen.open(fake, run)
	watch_signals(screen)

func _board() -> BoardView:
	return screen.get_node("%Board")

func _bar(node_name: String) -> ProgressBar:
	return screen.get_node("%" + node_name)

func test_open_shows_the_enemy_and_begins_the_encounter():
	assert_eq(screen.encounter, fake)
	assert_eq(fake.get_parent(), screen)
	assert_true(fake.began)
	assert_eq((screen.get_node("%EnemyName") as Label).text, "Greedy Pawn")
	assert_not_null((screen.get_node("%EnemySprite") as TextureRect).texture)
	assert_eq((screen.get_node("%PlayerHpLabel") as Label).text, "HP 100/100")
	assert_eq(_bar("PlayerHp").max_value, float(Tuning.MAX_HP))
	assert_eq(_bar("PlayerHp").value, float(Tuning.MAX_HP))
	assert_eq((screen.get_node("%PotionButton") as Button).text, "Potion ×1")
	assert_false((screen.get_node("%ContinueButton") as Button).visible)

func test_board_is_square_and_fits_from_9_16_to_9_20():
	for window_size in [Vector2(720, 1280), Vector2(720, 1600)]:
		window.size = window_size
		await wait_process_frames(2)
		var board := _board()
		var dialogue: Control = screen.get_node("%Dialogue")
		assert_eq(screen.size, window_size, "the screen fills the window at %s" % window_size)
		assert_eq(board.size.x, board.size.y, "square at %s" % window_size)
		assert_eq(board.size.x, 640.0, "the largest multiple of 128 px that fits at %s" % window_size)
		assert_true(board.size.x <= 720 - 32, "fits the gutters at %s" % window_size)
		assert_almost_eq(board.global_position.x + board.size.x / 2.0, window_size.x / 2.0, 0.5, "centred at %s" % window_size)
		assert_true(board.get_global_rect().end.y <= dialogue.get_global_rect().position.y, "board above dialogue at %s" % window_size)
		assert_true(dialogue.get_global_rect().end.y <= window_size.y, "dialogue inside the screen at %s" % window_size)

func test_board_fits_a_3_by_4_window():
	window.size = Vector2(720, 960)
	await wait_process_frames(2)
	var board := _board()
	var dialogue: Control = screen.get_node("%Dialogue")
	assert_eq(board.size.x, board.size.y, "square")
	assert_gte(board.size.x, float(Tuning.BOARD_MIN_SIDE))
	assert_eq(fmod(board.size.x, 128.0), 0.0, "a multiple of 128 px")
	assert_true(dialogue.get_global_rect().end.y <= 960.0, "the dialogue ends inside the window")
	assert_gte(dialogue.get_parent().size.y, float(Tuning.DIALOGUE_MIN_HEIGHT), "the dialogue box keeps its least height")
	assert_true(board.get_global_rect().end.y <= dialogue.get_global_rect().position.y, "board above dialogue")
	window.size = Vector2(720, 1280)
	await wait_process_frames(2)
	assert_eq(_board().size.x, 640.0, "taller windows get the full board back")

func test_board_fits_the_viewport_of_a_3_by_4_window():
	# Stretch expand turns a 3:4 window into a 960x1280 viewport.
	window.size = Vector2(960, 1280)
	await wait_process_frames(2)
	var board := _board()
	var panel: Control = screen.get_node("%Dialogue").get_parent()
	assert_eq(board.size, Vector2(640, 640))
	assert_almost_eq(board.global_position.x + board.size.x / 2.0, 480.0, 0.5, "centred")
	assert_gte(panel.size.y, float(Tuning.DIALOGUE_MIN_HEIGHT), "the dialogue box keeps its least height")
	assert_true(panel.get_global_rect().end.y <= 1280.0, "the dialogue ends inside the window")

func test_a_narrower_screen_gets_a_smaller_multiple_of_128():
	window.size = Vector2(600, 1200)
	await wait_process_frames(2)
	assert_eq(_board().size, Vector2(512, 512))

func test_encounter_signals_drive_the_ui():
	fake.enemy_bar.emit(0.5)
	await wait_seconds(Tuning.BAR_TWEEN_S + 0.1)
	assert_eq(_bar("EnemyHp").value, 50.0)
	fake.message.emit("Hi")
	assert_eq((screen.get_node("%Dialogue") as RichTextLabel).text, "Hi")
	fake.board_changed.emit(START, "")
	assert_eq(_board().fen(), START)
	_board().move_chosen.emit("e2e4")
	assert_eq(fake.moves, ["e2e4"] as Array[String])

func test_a_drag_scrolls_a_long_message():
	fake.message.emit("A long message that does not fit the box. ".repeat(60))
	await wait_process_frames(2)
	var dialogue: RichTextLabel = screen.get_node("%Dialogue")
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(0, -40)
	dialogue.gui_input.emit(drag)
	assert_eq(dialogue.get_v_scroll_bar().value, 40.0)
	drag.relative = Vector2(0, 100)
	dialogue.gui_input.emit(drag)
	assert_eq(dialogue.get_v_scroll_bar().value, 0.0, "it stops at the top")

func test_a_new_message_starts_at_the_top():
	fake.message.emit("A long message that does not fit the box. ".repeat(60))
	await wait_process_frames(2)
	var dialogue: RichTextLabel = screen.get_node("%Dialogue")
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(0, -80)
	dialogue.gui_input.emit(drag)
	assert_gt(dialogue.get_v_scroll_bar().value, 0.0)
	fake.message.emit("Another long message that does not fit the box. ".repeat(60))
	await wait_process_frames(2)
	assert_eq(dialogue.get_v_scroll_bar().value, 0.0)

func test_board_changed_orients_the_board_to_the_player_and_marks_the_last_move():
	await wait_process_frames(2)
	fake.board_changed.emit(AFTER_E4, "e2e4")
	assert_eq(_board().square_at(Vector2(1, 1)), "a8")
	assert_eq(_board().last_move(), "e2e4")
	fake._player_white = false
	fake.board_changed.emit(AFTER_E4, "")
	assert_eq(_board().square_at(Vector2(1, 1)), "h1")
	assert_eq(_board().last_move(), "")

func test_the_arrow_stays_through_a_new_position_and_goes_when_the_player_moves():
	fake.arrow.emit("e2e4")
	assert_eq(_board().arrow(), "e2e4")
	fake.board_changed.emit(START, "")
	assert_eq(_board().arrow(), "e2e4")
	_board().move_chosen.emit("d2d4")
	assert_eq(_board().arrow(), "")
	assert_eq(fake.moves, ["d2d4"] as Array[String])

func test_input_enabled_makes_the_board_interactive_until_the_encounter_finishes():
	fake.board_changed.emit(START, "")
	_board().tap_square("e2")
	assert_eq(_board().selected_square(), "", "no taps before the encounter allows input")
	fake.input_enabled.emit(true)
	_board().tap_square("e2")
	assert_eq(_board().selected_square(), "e2")
	fake.input_enabled.emit(false)
	assert_eq(_board().selected_square(), "")
	_board().tap_square("e2")
	assert_eq(_board().selected_square(), "")
	fake.input_enabled.emit(true)
	fake.finished.emit(RunState.Outcome.LOST)
	fake.input_enabled.emit(true)
	_board().tap_square("e2")
	assert_eq(_board().selected_square(), "", "a finished encounter never gives the board back")

func test_finish_shows_continue_and_close_reports_the_outcome():
	var button: Button = screen.get_node("%ContinueButton")
	fake.board_changed.emit(START, "")
	fake.input_enabled.emit(true)
	fake.finished.emit(RunState.Outcome.WON)
	assert_true(button.visible)
	_board().tap_square("e2")
	assert_eq(_board().selected_square(), "")
	button.pressed.emit()
	assert_signal_emitted_with_parameters(screen, "closed", [RunState.Outcome.WON])

func test_continue_reports_the_outcome_once():
	var button: Button = screen.get_node("%ContinueButton")
	fake.finished.emit(RunState.Outcome.LOST)
	button.pressed.emit()
	assert_true(button.disabled)
	assert_signal_emit_count(screen, "closed", 1)

func test_potion_button_follows_the_rules():
	var button: Button = screen.get_node("%PotionButton")
	assert_true(button.disabled, "disabled at full HP")
	run.take_damage(50)
	assert_false(button.disabled)
	assert_eq((screen.get_node("%PlayerHpLabel") as Label).text, "HP 50/100")
	button.pressed.emit()
	assert_eq(run.hp, 80)
	assert_eq(run.potions, 0)
	assert_true(button.disabled, "disabled without potions")
	assert_eq(button.text, "Potion ×0")
	assert_eq((screen.get_node("%PlayerHpLabel") as Label).text, "HP 80/100")

func test_potion_button_is_disabled_once_the_run_is_dead():
	run.take_damage(Tuning.MAX_HP)
	assert_true((screen.get_node("%PotionButton") as Button).disabled)

func test_the_player_bar_tweens_to_the_new_hp():
	run.take_damage(40)
	await wait_seconds(Tuning.BAR_TWEEN_S + 0.1)
	assert_eq(_bar("PlayerHp").value, 60.0)
	run.set_player_tile(Vector2i(1, 1))
	assert_eq(_bar("PlayerHp").value, 60.0, "a change that is not HP leaves the bar alone")

func _strong_screen() -> StrongEncounter:
	var engine := FakeEngine.new()
	add_child_autofree(engine)
	engine.replies = [[FakeEngine.line("g1f3", 300)]]
	var strong := StrongEncounter.new({"id": "s1", "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
		"moves": ["e7e5", "g1f3"]}, run, engine, 2400)
	strong.encounter_id = "s1"
	strong.enemy_name = "Gatekeeper"
	return strong

func test_the_moves_left_label_is_hidden_unless_the_encounter_counts_moves():
	assert_false((screen.get_node("%MovesLeft") as Label).visible, "a puzzle encounter never shows it")

func test_a_strong_encounter_shows_the_moves_left():
	var strong := _strong_screen()
	var other := load("res://battle/battle_screen.tscn").instantiate() as BattleScreen
	window.add_child(other)
	other.open(strong, run)
	await wait_process_frames(2)
	var label: Label = other.get_node("%MovesLeft")
	assert_true(label.visible)
	assert_eq(label.text, "Moves left: %d" % Tuning.STRONG_MOVE_LIMIT)
	strong.moves_left.emit(7)
	assert_eq(label.text, "Moves left: 7")
	strong.finished.emit(RunState.Outcome.WON)
	assert_false(label.visible, "the Continue button takes its room")

func test_roster_is_deterministic():
	var first := EnemyRoster.for_encounter("puzzle", "3_41")
	assert_eq(EnemyRoster.for_encounter("puzzle", "3_41"), first)
	assert_true(ResourceLoader.exists(first["sprite"]))

func test_roster_names_the_puzzle_enemies_and_every_sprite_exists():
	var names := {}
	for i in 60:
		var enemy := EnemyRoster.for_encounter("puzzle", "puzzle_%d" % i)
		names[enemy["name"]] = enemy["sprite"]
		assert_true(ResourceLoader.exists(enemy["sprite"]), enemy["sprite"])
	assert_eq(names.keys().size(), 3)
	assert_has(names, "Greedy Pawn")
	assert_has(names, "Sneaky Bishop")
	assert_has(names, "Knight of the Centre")
	assert_eq(names.values().size(), 3)

func test_roster_has_one_enemy_for_theory_and_one_for_strong():
	for kind in ["theory", "strong"]:
		assert_eq(EnemyRoster.for_encounter(kind, "a"), EnemyRoster.for_encounter(kind, "b"))
		assert_true(ResourceLoader.exists(EnemyRoster.for_encounter(kind, "a")["sprite"]))
	assert_eq(EnemyRoster.for_encounter("theory", "a")["name"], "Opening Scholar")
	assert_eq(EnemyRoster.for_encounter("strong", "a")["name"], "Gatekeeper Rook")
