extends UciEngine
## A scripted stand-in for the engine, for tests that must never touch Stockfish.
## It sends nothing to it, and it is ready from construction: start() only undoes
## shutdown(). Like the real engine, it is not ready while a search is running,
## and then it refuses configuration and new searches.
##
## Tests set `replies` before a search; each go_movetime() pops one.

## One entry per search to come. Each entry is an Array of EngineEval, best line first.
## When none is left, a search answers with every legal move of the last position
## set, each at 0 cp, whatever the MultiPV setting.
var replies: Array = []
## One {fen, moves, ms, multipv} per search: the last position set, the `ms` given
## to go_movetime(), and the MultiPV applied at that time.
var searches: Array = []
## When false the engine never becomes ready.
var available := true
## is_ready() stays false for this many more process frames.
var busy_frames := 0

var _stopped := false
var _fen := START_FEN
var _moves := PackedStringArray()
var _multipv := 1
var _searching := false
var _pending: Array = []
var _go_frame := 0


## Builds a line whose `pv` is `[move] + tail`.
static func line(move: String, value: int, mate := false, tail := PackedStringArray()) -> EngineEval:
	var e := EngineEval.new()
	e.is_mate = mate
	e.value = value
	e.pv = PackedStringArray([move])
	e.pv.append_array(tail)
	return e


## Returns `available`.
func start() -> bool:
	_stopped = false
	return available


func is_ready() -> bool:
	return available and not _stopped and busy_frames <= 0 and not _searching


func new_game() -> bool:
	return is_ready()


func set_full_strength() -> bool:
	return is_ready()


func set_strength_elo(elo: int) -> int:
	if not is_ready():
		return -1
	return clampi(elo, ELO_MIN, ELO_MAX)


func set_multipv(n: int) -> int:
	if not is_ready():
		return -1
	_multipv = clampi(n, 1, MULTIPV_MAX)
	return _multipv


## Returns false when the engine is not ready or ChessRules rejects the position.
func set_position(fen: String, moves := PackedStringArray()) -> bool:
	if not is_ready() or ChessRules.inspect(fen, moves).is_empty():
		return false
	_fen = fen
	# A copy: the caller's array is shared, not copied, and it may grow before the search is read.
	_moves = moves.duplicate()
	return true


## Pops the next scripted reply and delivers it, as best_move then search_finished,
## on the next process frame.
func go_movetime(ms: int) -> bool:
	if not is_ready() or ms <= 0:
		return false
	searches.append({"fen": _fen, "moves": _moves, "ms": ms, "multipv": _multipv})
	_pending = replies.pop_front() if not replies.is_empty() else _every_legal_move()
	for i in _pending.size():
		_pending[i].multipv = i + 1
	_searching = true
	_go_frame = Engine.get_process_frames()
	return true


func shutdown() -> void:
	_stopped = true
	_searching = false
	_pending = []


func _process(_delta: float) -> void:
	if busy_frames > 0:
		busy_frames -= 1
	if not _searching or Engine.get_process_frames() <= _go_frame:
		return
	var lines := _pending
	_pending = []
	_searching = false
	var move := "(none)"
	if not lines.is_empty() and not lines[0].pv.is_empty():
		move = lines[0].pv[0]
	best_move.emit(move)
	search_finished.emit(move, lines)


func _every_legal_move() -> Array:
	var lines: Array = []
	for move in ChessRules.inspect(_fen, _moves).get("legal", PackedStringArray()):
		lines.append(line(move, 0))
	return lines
