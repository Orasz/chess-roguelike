class_name Main
extends Node
## The game. It owns the run and shows one screen at a time: the menu, the overworld or a battle on
## top of it, and the end of the run. Every change of the run is saved, once per frame however many
## changes the frame makes, and a pause, a close or the back button save at once, so the app resumes
## where the player left it, in the middle of a battle too.
##
## `engine` and `save_path` can be set before the node enters the tree. A null engine becomes the
## `ChessEngine` autoload.

const _MENU_SCENE := preload("res://main/main_menu.tscn")
const _OVERWORLD_SCENE := preload("res://overworld/overworld.tscn")
const _BATTLE_SCENE := preload("res://battle/battle_screen.tscn")
const _RUN_END_SCENE := preload("res://main/run_end.tscn")
const _ABOUT_SCENE := preload("res://main/about_screen.tscn")
const _PUZZLES_PATH := "res://data/puzzles/italian_game.json"
const _BOOK_PATH := "res://data/openings/italian_game.json"

## The engine the battles search with.
var engine: UciEngine
## Where the run is saved.
var save_path := "user://run.json"
## The run under way, or null outside one.
var run: RunState
## What the Back button does on the menu. Tests replace it.
var quit_app: Callable = _quit

var _store: SaveStore
var _bank: PuzzleBank
var _book: OpeningBook
var _chunks := {}
## The zone of the run under way.
var _layout: ZoneLayout
## The overworld of the run under way, or null.
var _overworld: Overworld
## The battle on top of the overworld, or null.
var _battle: BattleScreen
var _screen: Node
## True when a save is scheduled for the end of the frame.
var _save_pending := false


## Starts the engine and loads the content. When the puzzles, the opening or the chunks of a zone
## cannot be loaded, it shows an error instead of the menu.
func _ready() -> void:
	_fit_window()
	get_tree().root.size_changed.connect(_fit_window)
	if engine == null:
		engine = get_node("/root/ChessEngine") as UciEngine
	# False when the engine already runs, which is fine.
	engine.start()
	_store = SaveStore.new(save_path)
	_bank = PuzzleBank.load_file(_PUZZLES_PATH)
	_book = OpeningBook.load_file(_BOOK_PATH)
	_chunks = MapAssembler.load_chunks()
	# Every zone is a start, two middles and an exit, so if one assembles, every seed does.
	if _bank == null or _book == null or MapAssembler.assemble(_chunks, RandomNumberGenerator.new()) == null:
		_show_error()
		return
	show_menu()


## The screen shown now.
func current_screen() -> Node:
	return _screen


## Shows the menu, with "Continue" when a run is saved. A run under way is saved and left.
func show_menu() -> void:
	_leave_run()
	var menu: MainMenu = _MENU_SCENE.instantiate()
	menu.can_continue = _saved_run() != null
	menu.continue_requested.connect(_on_continue_requested)
	menu.new_run_requested.connect(_on_new_run_requested)
	menu.about_requested.connect(_show_about)
	_show_screen(menu)


## Starts a new run at `rating` on the zone of `seed`, on the overworld, and saves it over the save
## of any earlier run at the end of the frame.
@warning_ignore("shadowed_global_identifier")
func start_run(rating: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var layout := MapAssembler.assemble(_chunks, rng)
	_begin(RunSetup.create(seed, rating, layout, _bank), layout)
	_request_save()


## Resumes the saved run where it was left: on the overworld, or in the battle it was in. Returns
## false, and leaves the screen as it is, when no run can be resumed. A saved run that is over (at
## 0 HP) or whose zone the chunks cannot rebuild is deleted.
func continue_run() -> bool:
	var saved := _saved_run()
	if saved == null:
		return false
	var layout := MapAssembler.rebuild(_chunks, saved.chunk_order)
	if layout == null:
		_store.clear()
		return false
	_begin(saved, layout)
	if not run.battle.is_empty():
		open_encounter(String(run.battle.get("id", "")))
	return true


## Opens the battle of encounter `id` on top of the overworld, which is hidden but kept. When the
## run holds that encounter's battle in progress, the battle resumes from it. An encounter that
## cannot be built is reported, and the overworld stays.
func open_encounter(id: String) -> void:
	var encounter := EncounterFactory.create(id, run, engine, _bank, _book)
	if encounter == null:
		push_error("Main: cannot build encounter '%s'" % id)
		return
	_overworld.hide()
	_battle = _BATTLE_SCENE.instantiate()
	add_child(_battle)
	_screen = _battle
	_battle.closed.connect(_on_battle_closed.bind(id))
	_battle.open(encounter, run)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_save_now()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_save_now()
			_go_back()


## Expands the layout on tall windows and pillarboxes wide ones, see `ScreenFit`.
func _fit_window() -> void:
	var root := get_tree().root
	root.content_scale_aspect = ScreenFit.aspect_for(root.size)


## The Back button goes back one screen: from the overworld, a battle, the end of a run or the About
## screen to the menu, with the run kept, and from the menu out of the app, unless the menu has a question open
## to close first. It never leaves the app from a battle.
func _go_back() -> void:
	if _screen is MainMenu:
		if not (_screen as MainMenu).handle_back():
			quit_app.call()
	elif _screen is Overworld or _screen is BattleScreen or _screen is RunEnd or _screen is AboutScreen:
		show_menu()
	else:
		quit_app.call()


func _quit() -> void:
	get_tree().quit()


## A save still scheduled is written now, since the deferred call never comes once the node is freed.
func _exit_tree() -> void:
	if _save_pending:
		_save_now()


## Makes `new_run` the run under way, on the overworld of `layout`.
func _begin(new_run: RunState, layout: ZoneLayout) -> void:
	_leave_run()
	run = new_run
	_layout = layout
	run.changed.connect(_request_save)
	run.died.connect(_on_run_died)
	var world: Overworld = _OVERWORLD_SCENE.instantiate()
	world.encounter_requested.connect(open_encounter)
	world.zone_cleared.connect(_on_zone_cleared)
	_show_screen(world)
	_overworld = world
	_overworld.setup(run, _layout)


## Writes what is still to save of the run under way, and lets it go.
func _leave_run() -> void:
	if run == null:
		return
	if _save_pending:
		_save_now()
	_release_run()


## Lets the run under way go, unsaved: nothing it does reaches Main any more.
func _release_run() -> void:
	run.changed.disconnect(_request_save)
	run.died.disconnect(_on_run_died)
	run = null


## The run is over. Nothing may save it again (neither the scheduled save of the change that ended
## it, nor a commit of the battle still running), and then its save is deleted. The end screen comes
## at the end of the frame, since the battle or the overworld that ended the run is still running.
func _end_run(won: bool) -> void:
	if run == null:
		return
	_save_pending = false
	_release_run()
	_store.clear()
	_show_run_end.call_deferred(won)


## The saved run, or null when no save loads. A saved run at 0 HP is over, and its save is deleted.
func _saved_run() -> RunState:
	var saved := _store.load_run()
	if saved != null and saved.hp <= 0:
		_store.clear()
		return null
	return saved


## Replaces the screens with `screen`. The old ones are queued for deletion rather than freed,
## because the call may come from one of their own signals.
func _show_screen(screen: Node) -> void:
	for child in get_children():
		child.queue_free()
	_overworld = null
	_battle = null
	add_child(screen)
	_screen = screen


func _show_run_end(won: bool) -> void:
	var screen: RunEnd = _RUN_END_SCENE.instantiate()
	screen.won = won
	screen.back_requested.connect(show_menu)
	_show_screen(screen)


func _show_about() -> void:
	var screen: AboutScreen = _ABOUT_SCENE.instantiate()
	screen.closed.connect(show_menu)
	_show_screen(screen)


## The plain message shown when the game's content cannot be loaded.
func _show_error() -> void:
	var label := Label.new()
	label.text = tr("The game data could not be loaded.")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_show_screen(label)


## Schedules one save for the end of the frame, which covers every change made until then.
func _request_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	_flush_save.call_deferred()


## Writes the scheduled save, unless it was written or dropped meanwhile.
func _flush_save() -> void:
	if _save_pending:
		_save_now()


func _save_now() -> void:
	_save_pending = false
	if run != null and not _store.save(run):
		push_error("Main: the run could not be saved to '%s'" % save_path)


func _on_continue_requested() -> void:
	# The save may have gone since the menu was shown: the menu then shows it is gone.
	if not continue_run():
		show_menu()


func _on_new_run_requested(rating: int) -> void:
	start_run(rating, randi())


## The player pressed Continue after the battle: the encounter is resolved, and the overworld comes
## back without its enemy.
func _on_battle_closed(outcome: int, id: String) -> void:
	# Queued: the screen is still emitting `closed`.
	_battle.queue_free()
	_battle = null
	run.resolve_encounter(id, outcome)
	_overworld.setup(run, _layout)
	_overworld.show()
	_screen = _overworld


func _on_run_died() -> void:
	_end_run(false)


func _on_zone_cleared() -> void:
	_end_run(true)
