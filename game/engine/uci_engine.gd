class_name UciEngine
extends Node
## The only GDScript entry point to Stockfish.
##
## Stockfish exits the whole process on a malformed command, so this class
## builds every command from fixed templates and validates the FEN and move
## syntax first. Moves passed to set_position() must also be legal: they must
## come from the engine itself or from a legal-move generator.

signal ready_ok()
signal evaluation(eval: EngineEval)
signal best_move(move: String)

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
## Stockfish silently ignores UCI_Elo values outside this range.
const ELO_MIN := 1320
const ELO_MAX := 3190

enum State { STOPPED, STARTING, READY, SEARCHING }

var engine_name: String = ""
var last_eval: EngineEval = null

var _state := State.STOPPED
var _engine: StockfishEngine = null


func start() -> bool:
	if _state != State.STOPPED:
		return false
	_engine = StockfishEngine.new()
	if not _engine.start():
		_engine = null
		return false
	_state = State.STARTING
	_engine.send("uci")
	return true


## True when the engine is ready and not searching.
func is_ready() -> bool:
	return _state == State.READY


func new_game() -> void:
	if _state != State.READY:
		return
	_state = State.STARTING
	_engine.send("ucinewgame")
	_engine.send("isready")


## Returns the Elo actually applied, clamped to [ELO_MIN, ELO_MAX].
func set_strength_elo(elo: int) -> int:
	var applied := clampi(elo, ELO_MIN, ELO_MAX)
	if _state == State.READY:
		_engine.send("setoption name UCI_LimitStrength value true")
		_engine.send("setoption name UCI_Elo value %d" % applied)
	else:
		push_error("UciEngine: strength can only change while the engine is ready")
	return applied


func set_full_strength() -> void:
	if _state == State.READY:
		_engine.send("setoption name UCI_LimitStrength value false")
	else:
		push_error("UciEngine: strength can only change while the engine is ready")


## Returns false, and sends nothing, if the FEN or any move fails validation.
func set_position(fen: String, moves := PackedStringArray()) -> bool:
	if _state != State.READY or not UciParser.is_valid_fen(fen):
		return false
	for move in moves:
		if not UciParser.is_valid_uci_move(move):
			return false
	var command := "position fen " + fen
	if not moves.is_empty():
		command += " moves " + " ".join(moves)
	_engine.send(command)
	return true


## Returns false if the engine is not ready, for example while it is searching.
func go_movetime(ms: int) -> bool:
	if _state != State.READY or ms <= 0:
		return false
	_state = State.SEARCHING
	_engine.send("go movetime %d" % ms)
	return true


## Stops the engine thread. Safe to call more than once.
func shutdown() -> void:
	if _engine != null:
		_engine.stop()
		_engine = null
	_state = State.STOPPED


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		shutdown()


func _process(_delta: float) -> void:
	if _engine == null:
		return
	for line in _engine.poll_lines():
		_handle_line(line)


func _handle_line(line: String) -> void:
	if line.is_empty():
		return
	if line.begins_with("id name "):
		engine_name = line.substr("id name ".length())
	elif line == "uciok":
		_engine.send("setoption name Threads value 1")
		_engine.send("setoption name Hash value 16")
		_engine.send("isready")
	elif line == "readyok":
		if _state == State.STARTING:
			_state = State.READY
			ready_ok.emit()
	elif line.begins_with("info "):
		var eval := UciParser.parse_info(line)
		if eval != null and eval.multipv == 1:
			last_eval = eval
			evaluation.emit(eval)
	else:
		var move := UciParser.parse_bestmove(line)
		if move != "":
			_state = State.READY
			best_move.emit(move)
