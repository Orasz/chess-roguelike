extends Control
## Engine spike check screen. It runs on desktop and on the phone, and
## exercises start-up, strength settings, engine moves and evaluation.

const MATE_FEN := "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
const QGA_FEN := "rnbqkbnr/p3pppp/8/1p6/2pP4/4P3/1P3PPP/RNBQKBNR w KQkq - 0 6"

enum Request { NONE, PLAY, MATE_CHECK, QGA_CHECK }

var engine: UciEngine
var moves := PackedStringArray()

var _request := Request.NONE

@onready var _buttons: Array[Button] = [%PlayButton, %MateCheckButton, %QgaCheckButton, %NewGameButton]


func _ready() -> void:
	engine = UciEngine.new()
	add_child(engine)
	engine.ready_ok.connect(_refresh)
	engine.best_move.connect(_on_best_move)
	%PlayButton.pressed.connect(_on_play)
	%MateCheckButton.pressed.connect(_on_check.bind(Request.MATE_CHECK))
	%QgaCheckButton.pressed.connect(_on_check.bind(Request.QGA_CHECK))
	%NewGameButton.pressed.connect(_on_new_game)
	_refresh()
	if not engine.start():
		%Status.text = "Engine failed to start"


func _on_play() -> void:
	if %FullStrength.button_pressed:
		engine.set_full_strength()
	else:
		engine.set_strength_elo(int(%EloSpin.value))
	if engine.set_position(UciEngine.START_FEN, moves) and engine.go_movetime(1000):
		_request = Request.PLAY
	_refresh()


func _on_check(request: Request) -> void:
	# Checks always run at full strength; Play re-applies its own setting.
	engine.set_full_strength()
	var fen := MATE_FEN if request == Request.MATE_CHECK else QGA_FEN
	var ms := 500 if request == Request.MATE_CHECK else 1000
	if engine.set_position(fen) and engine.go_movetime(ms):
		_request = request
	_refresh()


func _on_new_game() -> void:
	if not engine.new_game():
		return
	moves.clear()
	%MovesLabel.text = ""
	%BestMoveLabel.text = ""
	_refresh()


func _on_best_move(move: String) -> void:
	match _request:
		Request.PLAY:
			if move == "(none)":
				%BestMoveLabel.text = "Game over"
			else:
				moves.append(move)
				%MovesLabel.text = "Moves: " + " ".join(moves)
				%BestMoveLabel.text = "Best move: " + move
		Request.MATE_CHECK:
			%CheckLabel.text = "Mate-in-1: ✓ a1a8" if move == "a1a8" else "Mate-in-1: ✗ got %s" % move
		Request.QGA_CHECK:
			%CheckLabel.text = ("QGA trap: ✓ d1f3" if move == "d1f3"
					else "QGA trap: – got %s (theory says d1f3)" % move)
	_show_eval()
	_request = Request.NONE
	_refresh()


func _show_eval() -> void:
	var e := engine.last_eval
	if e == null:
		return
	if e.is_mate:
		%EvalLabel.text = "Eval: mate %d" % e.value
	else:
		%EvalLabel.text = "Eval: %+.2f (depth %d, side to move)" % [e.value / 100.0, e.depth]
	%SpeedLabel.text = "Speed: %d knps, %d ms" % [e.nps / 1000, e.time_ms]


func _refresh() -> void:
	var ready := engine.is_ready()
	for button in _buttons:
		button.disabled = not ready
	if ready:
		%Status.text = "Ready"
	elif _request != Request.NONE:
		%Status.text = "Searching…"
	else:
		%Status.text = "Starting…"
