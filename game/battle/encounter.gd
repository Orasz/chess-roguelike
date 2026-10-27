@abstract
class_name Encounter
extends Node
## The shared shell of a battle encounter: pure logic with no UI. A battle screen renders its
## signals and forwards the player's moves to `submit_move()`. A subclass says what a move means
## (`_on_player_move()`), how it starts (`begin()`) and what it saves (`_kind()`, `snapshot()`).
##
## Two rules keep a resume after a kill exact. An encounter calls `_commit()` after each
## committed step and before anything asynchronous (a timer, an engine search), so the saved
## state is never behind what the player saw. And it restores from a snapshot with `restore()`
## before `begin()`, which picks up from there.

## The position on the board changed. `last_move` is the move that led to it, or "" for none
## (the start, or a move taken back).
signal board_changed(fen: String, last_move: String)
signal message(text: String)
## Shows the move `uci` as an arrow. "" clears it.
signal arrow(uci: String)
## The enemy's bar, from 1.0 (full) to 0.0 (empty).
signal enemy_bar(fraction: float)
## Whether the player may move now.
signal input_enabled(on: bool)
## The encounter is over. Also emitted by a restored encounter that was already over, one frame
## after `begin()`, so a caller can connect first.
signal finished(outcome: int)

var encounter_id := ""
var enemy_name := ""
var run: RunState
## The engine the encounter searches with. Null for an encounter that never searches.
var engine: UciEngine
## A `RunState.Outcome`, or -1 while the encounter is not over.
var outcome := -1
## How long a search waits for the engine to be ready, in seconds of foreground time (see
## `advance_wait()`). Tests shorten it.
var engine_wait_s := Tuning.ENGINE_WAIT_S

## Which side the player has, for a subclass to set once it knows.
var _player_white := true
## The position on the board now: the last one `_show()` put there.
var _fen := ""
var _input_on := false
## True from the moment `_run_search()` starts a search until its result or its timeout.
var _awaiting_search := false
var _search_lines: Array = []


## Starts the encounter, or resumes it after `restore()`. A subclass emits `board_changed` for
## the position it starts from.
@abstract func begin() -> void


## The player's move, in UCI. It is ignored while input is not enabled, once the encounter is
## over, and when the move is not legal in `current_fen()`. Otherwise input is switched off and
## `_on_player_move()` takes over.
func submit_move(uci: String) -> void:
	if not _input_on or _is_finished() or not _is_legal(uci):
		return
	_set_input(false)
	_on_player_move(uci)


func player_white() -> bool:
	return _player_white


## The position on the board now.
func current_fen() -> String:
	return _fen


## What a save needs to resume the encounter: JSON-safe data (strings, numbers, booleans, arrays
## and dictionaries only) that always has `"id"`, `"kind"` and `"outcome"`. A subclass adds its
## own fields to the result of `super()`.
func snapshot() -> Dictionary:
	return {"id": encounter_id, "kind": _kind(), "outcome": outcome}


## Loads what `snapshot()` returned, before `begin()`. The snapshot may have gone through JSON,
## so numbers are converted with `int()`: a number there is a float.
func restore(saved: Dictionary) -> void:
	outcome = int(saved.get("outcome", -1))


## A subclass that overrides this must call `super()`.
func _exit_tree() -> void:
	_awaiting_search = false
	if is_instance_valid(engine) and engine.search_finished.is_connected(_on_search_finished):
		engine.search_finished.disconnect(_on_search_finished)


## What the player's accepted move means. It is a coroutine when the answer takes a search.
@abstract func _on_player_move(uci: String) -> void


## The encounter's kind: "puzzle", "theory" or "strong".
@abstract func _kind() -> String


## Stores the snapshot in the run.
func _commit() -> void:
	run.set_battle(snapshot())


## Puts `fen` on the board and tells the screen.
func _show(fen: String, last_move: String) -> void:
	_fen = fen
	board_changed.emit(fen, last_move)


func _set_input(on: bool) -> void:
	_input_on = on
	input_enabled.emit(on)


func _is_finished() -> bool:
	return outcome != -1


func _is_legal(uci: String) -> bool:
	return ChessRules.inspect(_fen).get("legal", PackedStringArray()).has(uci)


## The foreground time a wait has counted after one more frame: `waited` plus the frame's process
## time `delta`, of which at most `Tuning.MAX_WAIT_STEP_S` counts. The main loop stops while the
## app is in the background, and the first frame back has a `delta` that covers the whole time
## away; counted as one short step, it cannot time out a wait whose result is about to be polled.
static func advance_wait(waited: float, delta: float) -> float:
	return waited + minf(delta, Tuning.MAX_WAIT_STEP_S)


## Polls `engine.is_ready()` once per frame, for at most `timeout_s` seconds of foreground time
## (see `advance_wait()`). Returns whether the engine is ready, and false when the encounter left
## the tree meanwhile.
func _wait_for_engine(timeout_s: float) -> bool:
	var waited := 0.0
	while not engine.is_ready():
		if not is_inside_tree() or waited >= timeout_s:
			return false
		await get_tree().process_frame
		waited = advance_wait(waited, get_process_delta_time())
	return true


## Runs the search on the position the caller has just set, for `ms` milliseconds, and returns its
## lines (`EngineEval`s, best first). Only a result that arrives while this search is awaited
## counts. Returns [] when the engine refuses the search, when the result is still missing
## `timeout_s` seconds after the search time (both in foreground time, see `advance_wait()`), and
## when the encounter left the tree meanwhile.
func _run_search(ms: int, timeout_s: float) -> Array:
	if not engine.search_finished.is_connected(_on_search_finished):
		engine.search_finished.connect(_on_search_finished)
	_search_lines = []
	_awaiting_search = true
	if not engine.go_movetime(ms):
		_awaiting_search = false
		return []
	var limit := ms / 1000.0 + timeout_s
	var waited := 0.0
	while _awaiting_search:
		if not is_inside_tree() or waited >= limit:
			_awaiting_search = false
			return []
		await get_tree().process_frame
		waited = advance_wait(waited, get_process_delta_time())
	return _search_lines


func _on_search_finished(_move: String, lines: Array) -> void:
	if not _awaiting_search:
		return
	_awaiting_search = false
	_search_lines = lines
