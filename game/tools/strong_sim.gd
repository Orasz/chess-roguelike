extends SceneTree
## Plays every strong position of the bank against the real engine, the way a player who follows
## the hint would, and prints what it measured (`StrongSimSummary`). It tunes the strong enemy's
## win condition: see docs/research/2026-10-28-strong-tuning.md. It never ships.
##
##   godot --headless --path game -s res://tools/strong_sim.gd -- --rating 1200 --out ../build/strong-sim-1200.json
##
## The enemy plays at `clampi(rating, Tuning.PICKER_MIN_ELO, Tuning.PICKER_MAX_ELO)`, like in a run.
## The player plays the encounter's hint whenever it is a legal move, and otherwise the engine's
## best move from a full-strength search of `_FALLBACK_SEARCH_MS`, MultiPV 1. The engine is the
## script's own: the `ChessEngine` autoload stays stopped, and the encounters and the fallback
## searches share this one engine, which the fallback uses only on the player's turn, while the
## encounter is not searching. Each position has a fixed seed, so the enemy's choices repeat
## from one run to the next as long as the engine's lines do; a timed search can still vary.

const _PUZZLES_PATH := "res://data/puzzles/italian_game.json"
const _FALLBACK_SEARCH_MS := 700
## How long the script waits for the engine to start, or for a search, in seconds.
const _ENGINE_WAIT_S := 60.0
## The seed of the first position's run; the next ones count up from it.
const _FIRST_SEED := 1

var _engine: UciEngine
var _player_turn := false
var _outcome := -1


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if not args.has("rating") or not args.has("out"):
		printerr("usage: -s res://tools/strong_sim.gd -- --rating <elo> --out <file.json>")
		quit(2)
		return
	var rating := int(args["rating"])
	var bank := PuzzleBank.load_file(_PUZZLES_PATH)
	if bank == null or bank.strong.is_empty():
		printerr("strong_sim: no strong positions in %s" % _PUZZLES_PATH)
		quit(1)
		return
	_engine = UciEngine.new()
	root.add_child(_engine)
	if not _engine.start() or not await _wait_until_ready():
		printerr("strong_sim: the engine did not start")
		quit(1)
		return
	var enemy_elo := clampi(rating, Tuning.PICKER_MIN_ELO, Tuning.PICKER_MAX_ELO)
	print("strong_sim: %d positions, rating %d, enemy Elo %d, %s" % [bank.strong.size(), rating, enemy_elo,
		_constants()])
	var results: Array = []
	for i in bank.strong.size():
		var record: Dictionary = bank.strong[i]
		var result := await _play(record, RunState.create(_FIRST_SEED + i, rating, "italian_game"), enemy_elo)
		if result.is_empty():
			printerr("strong_sim: the fallback search failed on %s" % record["id"])
			_engine.shutdown()
			quit(1)
			return
		results.append(result)
		print("[%d/%d] %s: %s after %d moves, %d HP lost" % [i + 1, bank.strong.size(), result["id"],
			RunState.Outcome.keys()[result["outcome"]], result["player_moves"], result["hp_lost"]])
	_engine.shutdown()
	var summary := StrongSimSummary.summarize(results)
	print("strong_sim: summary ", JSON.stringify(summary))
	var report := {"date": Time.get_date_string_from_system(), "rating": rating, "enemy_elo": enemy_elo,
		"constants": _constants(), "summary": summary, "results": results}
	if not _write(String(args["out"]), report):
		quit(1)
		return
	quit(0)


## Plays one strong position to its end and returns `{id, outcome, player_moves, hp_lost}`, or {}
## when a fallback search failed.
func _play(record: Dictionary, run: RunState, enemy_elo: int) -> Dictionary:
	var enc := StrongEncounter.new(record, run, _engine, enemy_elo)
	enc.encounter_id = String(record["id"])
	enc.enemy_name = "Sim"
	enc.engine_wait_s = _ENGINE_WAIT_S
	_player_turn = false
	_outcome = -1
	enc.input_enabled.connect(_on_input_enabled)
	enc.finished.connect(_on_finished)
	root.add_child(enc)
	enc.begin()
	var failed := false
	while _outcome == -1:
		await process_frame
		if not _player_turn:
			continue
		_player_turn = false
		var move := await _player_move(record, enc)
		if move.is_empty():
			failed = true
			break
		enc.submit_move(move)
	var result := {"id": String(record["id"]), "outcome": _outcome, "player_moves": enc.snapshot()["player_moves"],
		"hp_lost": Tuning.MAX_HP - run.hp}
	root.remove_child(enc)
	enc.free()
	return {} if failed else result


## The hint when it is legal, and otherwise the engine's best move. "" when the search failed.
func _player_move(record: Dictionary, enc: StrongEncounter) -> String:
	var hint := String(enc.snapshot()["hint"])
	if ChessRules.inspect(enc.current_fen()).get("legal", PackedStringArray()).has(hint):
		return hint
	if not _engine.is_ready() or not _engine.set_full_strength() or _engine.set_multipv(1) < 0:
		return ""
	if not _engine.set_position(String(record["fen"]), enc.moves) or not _engine.go_movetime(_FALLBACK_SEARCH_MS):
		return ""
	var best := [""]
	var on_best := func(move: String) -> void: best[0] = move
	_engine.best_move.connect(on_best, CONNECT_ONE_SHOT)
	var waited := 0.0
	while best[0].is_empty() and waited < _ENGINE_WAIT_S:
		await process_frame
		waited += root.get_process_delta_time()
	if _engine.best_move.is_connected(on_best):
		_engine.best_move.disconnect(on_best)
	return best[0]


func _on_input_enabled(on: bool) -> void:
	if on:
		_player_turn = true


func _on_finished(outcome: int) -> void:
	_outcome = outcome


func _wait_until_ready() -> bool:
	var waited := 0.0
	while not _engine.is_ready():
		if waited >= _ENGINE_WAIT_S:
			return false
		await process_frame
		waited += root.get_process_delta_time()
	return true


## The tuning numbers the run measured.
func _constants() -> Dictionary:
	return {"DECISIVE_GAIN_CP": Tuning.DECISIVE_GAIN_CP, "DECISIVE_MIN_CP": Tuning.DECISIVE_MIN_CP,
		"DAMAGE_DEADZONE_WP": Tuning.DAMAGE_DEADZONE_WP, "STRONG_MOVE_LIMIT": Tuning.STRONG_MOVE_LIMIT,
		"STRONG_SEARCH_MS": Tuning.STRONG_SEARCH_MS, "STRONG_CANDIDATES": Tuning.STRONG_CANDIDATES}


## Reads `--name value` pairs.
static func _parse_args(user_args: PackedStringArray) -> Dictionary:
	var args := {}
	for i in range(0, user_args.size() - 1):
		if user_args[i].begins_with("--"):
			args[user_args[i].substr(2)] = user_args[i + 1]
	return args


## Writes `report` as JSON to `path`, relative to the project directory, creating its directory.
static func _write(path: String, report: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		printerr("strong_sim: cannot write %s" % absolute)
		return false
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("strong_sim: wrote ", absolute)
	return true
