extends GutTest
## Main owns the run: the menu, the switch between the overworld and the battles, the end of the
## run, the autosave and the resume. The engine is a FakeEngine, and the save has a path of its own.

const FakeEngine := preload("res://test/support/fake_engine.gd")
const PATH := "user://test_main_run.json"

## The engine of the latest `_main()`.
var fake
## How many times a test's `quit_app` ran.
var quits := 0
var bank := PuzzleBank.load_file("res://data/puzzles/italian_game.json")
## Every Main of the test. A Main writes its scheduled save when it is freed, and GUT frees what it
## autofrees only after `after_each`, so `after_each` frees them itself before deleting the save.
var mains: Array[Node] = []


func before_each():
	quits = 0
	_delete_saves()


func after_each():
	for main in mains:
		if is_instance_valid(main):
			main.free()
	mains.clear()
	_delete_saves()


func _delete_saves() -> void:
	for p in [PATH, PATH + ".tmp", PATH + ".corrupt"]:
		DirAccess.remove_absolute(p)


## A Main on a new FakeEngine and the test's save path, in the tree.
func _main() -> Main:
	fake = FakeEngine.new()
	add_child_autofree(fake)
	var main: Main = (load("res://main/main.tscn") as PackedScene).instantiate()
	main.engine = fake
	main.save_path = PATH
	add_child_autofree(main)
	mains.append(main)
	return main


## The first encounter of `kind`, in id order.
func _first_of_kind(run: RunState, kind: String) -> String:
	var ids: Array = run.encounters.keys()
	ids.sort()
	for id: String in ids:
		if run.encounters[id]["kind"] == kind:
			return id
	return ""


## The puzzle bank record that encounter `id` of `run` plays.
func _record_of(run: RunState, id: String) -> Dictionary:
	return bank.by_id(run.encounters[id]["content"])


## A legal move of the position on the board that is not `solution` and does not mate.
func _wrong_move(enc: Encounter, solution: String) -> String:
	var fen := enc.current_fen()
	for move in ChessRules.inspect(fen)["legal"]:
		if move != solution and ChessRules.status(fen, PackedStringArray([move])) != ChessRules.Status.CHECKMATE:
			return move
	return ""


func _menu_button(main: Main, button_name: String) -> Button:
	return main.current_screen().get_node("%" + button_name)


func test_menu_offers_continue_only_with_a_save():
	var main := _main()
	assert_true(main.current_screen() is MainMenu)
	assert_false(_menu_button(main, "ContinueButton").visible, "no save, no Continue")
	for preset in ["BeginnerButton", "ClubButton", "StrongButton"]:
		assert_true(_menu_button(main, preset).visible, preset)
	main.start_run(1200, 42)
	await wait_process_frames(1)
	main.show_menu()
	assert_true(main.current_screen() is MainMenu)
	assert_true(_menu_button(main, "ContinueButton").visible)


func test_a_dead_corrupt_or_unbuildable_save_offers_only_a_new_run():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var dead := RunSetup.create(42, 1200, MapAssembler.assemble(MapAssembler.load_chunks(), rng), bank)
	dead.hp = 0
	SaveStore.new(PATH).save(dead)
	var main := _main()
	assert_false(_menu_button(main, "ContinueButton").visible, "a run at 0 HP is over")
	assert_false(main.continue_run())
	assert_false(FileAccess.file_exists(PATH), "and its save is gone")
	var lost := RunState.create(42, 1200, "italian_game")
	lost.chunk_order = PackedStringArray(["start", "nowhere", "gate"])
	SaveStore.new(PATH).save(lost)
	assert_false(main.continue_run(), "a zone that cannot be rebuilt is no save")
	assert_false(FileAccess.file_exists(PATH))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{\"version\": 1, \"hp\":")
	file.close()
	main.show_menu()
	assert_false(_menu_button(main, "ContinueButton").visible, "a truncated save is no save")
	assert_false(main.continue_run())
	assert_true(main.current_screen() is MainMenu)


func test_new_run_opens_the_overworld_and_saves():
	var main := _main()
	_menu_button(main, "ClubButton").pressed.emit()
	assert_true(main.current_screen() is Overworld)
	assert_eq(main.run.rating, Tuning.RATING_PRESETS["Club"])
	await wait_process_frames(1)
	var saved := SaveStore.new(PATH).load_run()
	assert_not_null(saved)
	if saved != null:
		assert_eq(saved.to_dict(), main.run.to_dict())


## A Main whose menu offers to continue the run of `start_run(1200, 42)`, already saved.
func _main_with_a_saved_run() -> Main:
	var main := _main()
	main.start_run(1200, 42)
	await wait_process_frames(1)
	main.show_menu()
	return main


func test_with_a_save_a_preset_asks_before_starting_a_run():
	var main: Main = await _main_with_a_saved_run()
	var saved := FileAccess.get_file_as_string(PATH)
	var confirm: Control = main.current_screen().get_node("%ConfirmNewRun")
	assert_false(confirm.visible, "nothing to confirm yet")
	_menu_button(main, "BeginnerButton").pressed.emit()
	assert_true(main.current_screen() is MainMenu, "no run starts")
	assert_null(main.run)
	assert_true(confirm.visible, "the menu asks first")
	await wait_process_frames(1)
	assert_eq(FileAccess.get_file_as_string(PATH), saved, "the save is unchanged")


func test_confirming_starts_the_new_run_over_the_save():
	var main: Main = await _main_with_a_saved_run()
	_menu_button(main, "StrongButton").pressed.emit()
	_menu_button(main, "StartNewRunButton").pressed.emit()
	assert_true(main.current_screen() is Overworld)
	assert_eq(main.run.rating, Tuning.RATING_PRESETS["Strong"])
	await wait_process_frames(1)
	assert_eq(SaveStore.new(PATH).load_run().rating, Tuning.RATING_PRESETS["Strong"])


func test_cancelling_keeps_the_save_and_the_menu():
	var main: Main = await _main_with_a_saved_run()
	var saved := FileAccess.get_file_as_string(PATH)
	_menu_button(main, "ClubButton").pressed.emit()
	_menu_button(main, "CancelButton").pressed.emit()
	assert_true(main.current_screen() is MainMenu)
	assert_false((main.current_screen().get_node("%ConfirmNewRun") as Control).visible)
	assert_true(_menu_button(main, "ContinueButton").visible, "Continue is still offered")
	await wait_process_frames(1)
	assert_eq(FileAccess.get_file_as_string(PATH), saved, "the save is unchanged")
	_menu_button(main, "ContinueButton").pressed.emit()
	assert_true(main.current_screen() is Overworld)
	assert_eq(main.run.rating, 1200, "the saved run resumes")


func test_continue_restores_a_battle_in_progress():
	var main := _main()
	main.start_run(1200, 42)
	var id := _first_of_kind(main.run, "strong")
	var record := _record_of(main.run, id)
	var start := ChessRules.fen_after(record["fen"], PackedStringArray(record["moves"]).slice(0, 1))
	# The opening evaluation gives the player +300 cp. The fake answers the player's move with 0 cp,
	# so the move costs HP.
	fake.replies = [[FakeEngine.line(ChessRules.inspect(start)["legal"][0], 300)]]
	main.open_encounter(id)
	var enc: StrongEncounter = main.current_screen().encounter
	assert_true(await wait_for_signal(enc.input_enabled, 5), "the opening evaluation")
	enc.submit_move(ChessRules.inspect(enc.current_fen())["legal"][0])
	assert_true(await wait_for_signal(enc.input_enabled, 5), "the enemy answered")
	var hp := main.run.hp
	var moves := enc.moves.duplicate()
	assert_lt(hp, Tuning.MAX_HP, "the player's move cost HP")
	main.free()
	var resumed := _main()
	assert_true(resumed.continue_run())
	var screen: Node = resumed.current_screen()
	assert_true(screen is BattleScreen)
	if screen is BattleScreen:
		assert_eq((screen as BattleScreen).encounter.moves, moves)
	assert_eq(resumed.run.hp, hp)
	await wait_process_frames(2)
	assert_eq(fake.searches, [], "no damage is recomputed while the player is to move")


## Focus 1 of the review: the app is killed while the enemy searches. The save of the player's move
## is on disk, the damage of that move is not; on resume, the search reruns and charges it once.
func test_a_kill_during_the_enemy_search_charges_the_move_once_on_resume():
	var main := _main()
	main.start_run(1200, 42)
	var id := _first_of_kind(main.run, "strong")
	var record := _record_of(main.run, id)
	var start := ChessRules.fen_after(record["fen"], PackedStringArray(record["moves"]).slice(0, 1))
	# The opening evaluation gives the player +300 cp.
	fake.replies = [[FakeEngine.line(ChessRules.inspect(start)["legal"][0], 300)]]
	main.open_encounter(id)
	var enc: StrongEncounter = main.current_screen().encounter
	assert_true(await wait_for_signal(enc.input_enabled, 5), "the opening evaluation")
	enc.submit_move(ChessRules.inspect(enc.current_fen())["legal"][0])
	var played := enc.moves.duplicate()
	var reply: String = ChessRules.inspect(enc.current_fen())["legal"][0]
	await wait_process_frames(1)
	var copy := FileAccess.get_file_as_bytes(PATH)
	var on_disk := SaveStore.new(PATH).load_run()
	assert_eq(PackedStringArray(on_disk.battle["moves"]), played, "the save holds the player's move")
	assert_eq(on_disk.hp, Tuning.MAX_HP, "but not its damage: the search was still pending")
	# The kill. Out of the tree, the pending search ends without effect before Main is freed; what
	# Main writes on its way out is replaced by the copy, as if the process had died at the copy.
	remove_child(main)
	await wait_process_frames(2)
	main.free()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_buffer(copy)
	file.close()
	var resumed := _main()
	# The rerun search scores the enemy's reply +300 cp for the enemy: the move drops the player
	# from +300 to -300 cp.
	fake.replies = [[FakeEngine.line(reply, 300)]]
	var cost := HpModel.player_damage(300, -300)
	assert_gt(cost, 0)
	assert_true(resumed.continue_run())
	var resumed_enc: StrongEncounter = resumed.current_screen().encounter
	assert_true(await wait_for_signal(resumed_enc.input_enabled, 5), "the enemy answered")
	assert_eq(fake.searches.size(), 1, "exactly one search on resume")
	if fake.searches.size() == 1:
		assert_eq(fake.searches[0]["moves"], played, "the search of the player's move")
	assert_eq(resumed.run.hp, Tuning.MAX_HP - cost, "the move is charged once")
	var expected := played.duplicate()
	expected.append(reply)
	assert_eq(resumed_enc.moves, expected, "the enemy's reply is appended")
	await wait_process_frames(2)
	assert_eq(resumed.run.hp, Tuning.MAX_HP - cost, "and nothing charges it again")
	assert_eq(SaveStore.new(PATH).load_run().hp, Tuning.MAX_HP - cost, "the damage is saved with the reply")


func test_finishing_a_battle_returns_to_the_overworld_with_the_enemy_gone():
	var main := _main()
	main.start_run(1200, 42)
	var world: Overworld = main.current_screen()
	var id := _first_of_kind(main.run, "puzzle")
	main.open_encounter(id)
	var screen: BattleScreen = main.current_screen()
	assert_false(world.visible, "the overworld is hidden during the battle")
	assert_true(is_instance_valid(world), "but kept")
	var enc: PuzzleEncounter = screen.encounter
	assert_true(await wait_for_signal(enc.input_enabled, 5))
	enc.submit_move(_record_of(main.run, id)["moves"][1])
	(screen.get_node("%ContinueButton") as Button).pressed.emit()
	assert_eq(main.current_screen(), world)
	assert_true(world.visible)
	assert_true(main.run.encounters[id]["resolved"])
	assert_eq(main.run.battle, {})
	assert_false(world.get_node("Enemies").has_node(id), "the enemy is gone from the map")
	await wait_process_frames(1)
	assert_true(SaveStore.new(PATH).load_run().encounters[id]["resolved"], "and from the save")


func test_hp_zero_ends_the_run_and_deletes_the_save():
	var main := _main()
	main.start_run(1200, 42)
	var run := main.run
	run.take_damage(Tuning.MAX_HP - Tuning.PUZZLE_DAMAGE)
	await wait_process_frames(1)
	assert_true(FileAccess.file_exists(PATH), "the run is saved before it ends")
	var id := _first_of_kind(run, "puzzle")
	main.open_encounter(id)
	var enc: PuzzleEncounter = main.current_screen().encounter
	assert_true(await wait_for_signal(enc.input_enabled, 5))
	enc.submit_move(_wrong_move(enc, _record_of(run, id)["moves"][1]))
	assert_eq(run.hp, 0)
	await wait_process_frames(5)
	var screen: Node = main.current_screen()
	assert_true(screen is RunEnd, "the defeat screen")
	if screen is RunEnd:
		assert_false((screen as RunEnd).won)
	assert_false(FileAccess.file_exists(PATH), "nothing saved the dead run again")
	(screen.get_node("%BackButton") as Button).pressed.emit()
	assert_true(main.current_screen() is MainMenu)
	assert_false(_menu_button(main, "ContinueButton").visible)


func test_clearing_the_zone_ends_the_run_with_a_victory():
	var main := _main()
	main.start_run(1200, 42)
	await wait_process_frames(1)
	assert_true(FileAccess.file_exists(PATH))
	main.run.set_player_tile(main.run.player_tile + Vector2i.UP)
	(main.current_screen() as Overworld).zone_cleared.emit()
	await wait_process_frames(3)
	var screen: Node = main.current_screen()
	assert_true(screen is RunEnd, "the victory screen")
	if screen is RunEnd:
		assert_true((screen as RunEnd).won)
	assert_false(FileAccess.file_exists(PATH), "the step onto the exit saved nothing")
	(screen.get_node("%BackButton") as Button).pressed.emit()
	assert_true(main.current_screen() is MainMenu)


## An encounter charges damage and commits its next step in one block: both must land in one save.
func test_the_changes_of_one_frame_are_saved_together_at_its_end():
	var main := _main()
	main.start_run(1200, 42)
	await wait_process_frames(1)
	main.run.take_damage(10)
	main.run.set_battle({"id": "a", "step": 1})
	assert_eq(SaveStore.new(PATH).load_run().hp, Tuning.MAX_HP, "nothing is written in the middle of the frame")
	await wait_process_frames(1)
	var saved := SaveStore.new(PATH).load_run()
	assert_eq(saved.hp, Tuning.MAX_HP - 10)
	assert_eq(saved.battle, {"id": "a", "step": 1.0})


func test_pause_saves_immediately():
	var main := _main()
	main.start_run(1200, 42)
	main.run.take_damage(50)
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(SaveStore.new(PATH).load_run().hp, 50)


func test_freeing_main_writes_the_save_still_scheduled():
	var main := _main()
	main.start_run(1200, 42)
	await wait_process_frames(1)
	main.run.take_damage(30)
	main.free()
	assert_eq(SaveStore.new(PATH).load_run().hp, 70)


func test_closing_the_window_or_going_back_saves_immediately():
	var main := _main()
	main.start_run(1200, 42)
	main.run.take_damage(10)
	main._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(SaveStore.new(PATH).load_run().hp, 90)
	main.run.take_damage(10)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(SaveStore.new(PATH).load_run().hp, 80)


## The Main of a test, with a `quit_app` that counts instead of quitting.
func _main_that_counts_quits() -> Main:
	var main := _main()
	main.quit_app = func() -> void: quits += 1
	return main


func test_the_window_aspect_follows_its_shape():
	var main := _main()
	var root := main.get_tree().root
	assert_eq(root.content_scale_aspect, ScreenFit.aspect_for(root.size))


func test_back_on_the_menu_quits():
	var main := _main_that_counts_quits()
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(quits, 1)


func test_back_closes_the_new_run_confirmation_first():
	var main: Main = await _main_with_a_saved_run()
	main.quit_app = func() -> void: quits += 1
	var saved := FileAccess.get_file_as_string(PATH)
	_menu_button(main, "ClubButton").pressed.emit()
	var confirm: Control = main.current_screen().get_node("%ConfirmNewRun")
	assert_true(confirm.visible)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(confirm.visible, "the question closes")
	assert_eq(quits, 0, "and the app stays")
	assert_true(main.current_screen() is MainMenu)
	await wait_process_frames(1)
	assert_eq(FileAccess.get_file_as_string(PATH), saved, "the save is unchanged")
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(quits, 1, "with nothing left to close, back quits")


func test_back_on_the_overworld_and_the_end_screen_goes_to_the_menu():
	var main := _main_that_counts_quits()
	main.start_run(1200, 42)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(main.current_screen() is MainMenu)
	assert_null(main.run)
	assert_eq(quits, 0)
	await wait_process_frames(1)
	assert_true(_menu_button(main, "ContinueButton").visible, "the run is kept")
	main.continue_run()
	main.run.take_damage(Tuning.MAX_HP)
	await wait_process_frames(5)
	assert_true(main.current_screen() is RunEnd)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(main.current_screen() is MainMenu)
	assert_eq(quits, 0)


func test_back_in_battle_returns_to_the_menu_and_keeps_the_run():
	var main := _main_that_counts_quits()
	main.start_run(1200, 42)
	var id := _first_of_kind(main.run, "puzzle")
	main.open_encounter(id)
	var enc: PuzzleEncounter = main.current_screen().encounter
	assert_true(await wait_for_signal(enc.input_enabled, 5))
	main.run.take_damage(10)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(main.current_screen() is MainMenu)
	assert_eq(quits, 0, "back never quits from a battle")
	assert_null(main.run)
	await wait_process_frames(2)
	var saved := SaveStore.new(PATH).load_run()
	assert_eq(saved.hp, Tuning.MAX_HP - 10, "the run is saved")
	assert_eq(saved.battle["id"], id, "in its battle")
	_menu_button(main, "ContinueButton").pressed.emit()
	var screen: Node = main.current_screen()
	assert_true(screen is BattleScreen, "Continue restores the battle")
	if screen is BattleScreen:
		assert_eq((screen as BattleScreen).encounter.encounter_id, id)
	assert_eq(main.run.hp, Tuning.MAX_HP - 10)


## The player's move is saved, its damage is not, and the app goes back to the menu while the enemy
## searches. The search ends with the screen. On Continue the encounter runs the search again, once.
func test_back_during_the_enemy_search_keeps_the_move():
	var main := _main_that_counts_quits()
	main.start_run(1200, 42)
	var id := _first_of_kind(main.run, "strong")
	var record := _record_of(main.run, id)
	var start := ChessRules.fen_after(record["fen"], PackedStringArray(record["moves"]).slice(0, 1))
	fake.replies = [[FakeEngine.line(ChessRules.inspect(start)["legal"][0], 300)]]
	main.open_encounter(id)
	var enc: StrongEncounter = main.current_screen().encounter
	assert_true(await wait_for_signal(enc.input_enabled, 5), "the opening evaluation")
	enc.submit_move(ChessRules.inspect(enc.current_fen())["legal"][0])
	var played := enc.moves.duplicate()
	var reply: String = ChessRules.inspect(enc.current_fen())["legal"][0]
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(main.current_screen() is MainMenu)
	assert_eq(quits, 0)
	await wait_process_frames(3)
	var on_disk := SaveStore.new(PATH).load_run()
	assert_eq(PackedStringArray(on_disk.battle["moves"]), played, "the save holds the player's move")
	assert_eq(on_disk.hp, Tuning.MAX_HP, "its damage is still to be charged")
	main.free()
	var resumed := _main()
	fake.replies = [[FakeEngine.line(reply, 300)]]
	assert_true(resumed.continue_run())
	var resumed_enc: StrongEncounter = resumed.current_screen().encounter
	assert_true(await wait_for_signal(resumed_enc.input_enabled, 5), "the enemy answered")
	assert_eq(fake.searches.size(), 1, "exactly one search on the new engine")
	assert_eq(resumed_enc.moves.size(), played.size() + 1, "and the enemy's reply is appended")
