extends GutTest
## Main owns the run: the menu, the switch between the overworld and the battles, the end of the
## run, the autosave and the resume. The engine is a FakeEngine, and the save has a path of its own.

const FakeEngine := preload("res://test/support/fake_engine.gd")
const PATH := "user://test_main_run.json"

## The engine of the latest `_main()`.
var fake
var bank := PuzzleBank.load_file("res://data/puzzles/italian_game.json")
## Every Main of the test. A Main writes its scheduled save when it is freed, and GUT frees what it
## autofrees only after `after_each`, so `after_each` frees them itself before deleting the save.
var mains: Array[Node] = []


func before_each():
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
