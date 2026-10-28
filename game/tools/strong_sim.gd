extends SceneTree
## Plays every strong position of the bank against the real engine, the way a player who follows
## the hint would, and prints what it measured (`StrongSimSummary`). It tunes the strong enemy's
## win condition: see docs/research/2026-10-28-strong-tuning.md. It never ships.
##
##   godot --headless --path game -s res://tools/strong_sim.gd -- --rating 1200 --out ../build/strong-sim-1200.json
##
## Two options: `--player-elo N` swaps the hint policy for a human proxy (below), and `--limit N`
## plays only the first N positions, for a smoke run.
##
## The enemy plays at `clampi(rating, Tuning.PICKER_MIN_ELO, Tuning.PICKER_MAX_ELO)`, like in a run.
## The player plays the encounter's hint whenever it is a legal move, and otherwise the engine's
## best move from a full-strength search of `_FALLBACK_SEARCH_MS`, MultiPV 1. The engine is the
## script's own: the `ChessEngine` autoload stays stopped, and the encounters and the fallback
## searches share this one engine, which the fallback uses only on the player's turn, while the
## encounter is not searching.
##
## With `--player-elo N` the player never sees the hint. Whenever it moves it searches the position
## at full strength, MultiPV `Tuning.STRONG_CANDIDATES`, `_FALLBACK_SEARCH_MS`, and plays the line
## `MovePicker.choose(lines, N, rng)` picks: a human of that Elo as the game's own enemy model sees
## one, not a real person. The picks come from a generator seeded with the position's index.
##
## Each position has a fixed seed, so the enemy's choices and the picks repeat from one run to the
## next as long as the engine's lines do; a timed search can still vary.

const _PUZZLES_PATH := "res://data/puzzles/italian_game.json"
const _FALLBACK_SEARCH_MS := 700
## How long the script waits for the engine to start, or for a search, in seconds.
const _ENGINE_WAIT_S := 60.0
## The seed of the first position's run; the next ones count up from it.
const _FIRST_SEED := 1

var _engine: UciEngine
var _player_turn := false
var _outcome := -1
## The Elo of the human proxy, or 0 for the hint policy.
var _player_elo := 0
## Draws the human proxy's picks; reseeded for each position.
var _pick_rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if not args.has("rating") or not args.has("out"):
		printerr("usage: -s res://tools/strong_sim.gd -- --rating <elo> --out <file.json>")
		quit(2)
		return
	var rating := int(args["rating"])
	_player_elo = int(args.get("player-elo", 0))
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
	var total := bank.strong.size()
	if args.has("limit"):
		total = mini(total, int(args["limit"]))
	print("strong_sim: %d positions, rating %d, enemy Elo %d, player %s, %s" % [total, rating, enemy_elo,
		"Elo %d" % _player_elo if _player_elo > 0 else "follows the hint", _constants()])
	var results: Array = []
	for i in total:
		var record: Dictionary = bank.strong[i]
		_pick_rng.seed = i
		var result := await _play(record, RunState.create(_FIRST_SEED + i, rating, "italian_game"), enemy_elo)
		if result.is_empty():
			printerr("strong_sim: the player's search failed on %s" % record["id"])
			_engine.shutdown()
			quit(1)
			return
		results.append(result)
		print("[%d/%d] %s: %s after %d moves, %d HP lost" % [i + 1, total, result["id"],
			RunState.Outcome.keys()[result["outcome"]], result["player_moves"], result["hp_lost"]])
	_engine.shutdown()
	var summary := StrongSimSummary.summarize(results)
	print("strong_sim: summary ", JSON.stringify(summary))
	var report := {"date": Time.get_date_string_from_system(), "rating": rating, "enemy_elo": enemy_elo,
		"player_elo": _player_elo, "constants": _constants(), "summary": summary, "results": results}
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
	enc.mistake_pause_s = 0.0
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


## The player's move: the human proxy's pick when `_player_elo` is set, and otherwise the hint when
## it is legal, and the engine's best move when it is not. "" when a search failed.
func _player_move(record: Dictionary, enc: StrongEncounter) -> String:
	if _player_elo > 0:
		return await _human_move(record, enc)
	var hint := String(enc.snapshot()["hint"])
	if ChessRules.inspect(enc.current_fen()).get("legal", PackedStringArray()).has(hint):
		return hint
	return String((await _search(record, enc, 1))["move"])


## The line of the engine's `Tuning.STRONG_CANDIDATES` best that `MovePicker` picks at the proxy's Elo.
func _human_move(record: Dictionary, enc: StrongEncounter) -> String:
	var lines: Array = (await _search(record, enc, Tuning.STRONG_CANDIDATES))["lines"]
	if lines.is_empty():
		return ""
	var pick: EngineEval = lines[MovePicker.choose(lines, _player_elo, _pick_rng)]
	return pick.pv[0] if not pick.pv.is_empty() else ""


## Searches the encounter's current position at full strength with `multipv` lines, and returns them
## ordered by index, and the engine's best move, as `{move, lines}`; both are empty when the search failed.
func _search(record: Dictionary, enc: StrongEncounter, multipv: int) -> Dictionary:
	var failed := {"move": "", "lines": []}
	if not _engine.is_ready() or not _engine.set_full_strength() or _engine.set_multipv(multipv) < 0:
		return failed
	if not _engine.set_position(String(record["fen"]), enc.moves) or not _engine.go_movetime(_FALLBACK_SEARCH_MS):
		return failed
	var found := [failed, false]
	var on_done := func(move: String, lines: Array) -> void:
		found[0] = {"move": move, "lines": lines}
		found[1] = true
	_engine.search_finished.connect(on_done, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not found[1] and waited < _ENGINE_WAIT_S:
		await process_frame
		waited += root.get_process_delta_time()
	if _engine.search_finished.is_connected(on_done):
		_engine.search_finished.disconnect(on_done)
	return found[0]


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
