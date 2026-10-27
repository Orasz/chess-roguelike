class_name BoardView
extends Control
## A chessboard the player moves on by tapping: a piece, then a target. It shows the position it
## is given and emits the move the player chose, in the UCI form Stockfish accepts (castling as
## the king's two-square move, en passant as the pawn's diagonal step, promotion with a letter).
## It never changes the position itself: the screen that owns it calls `show_position()` with
## the position that follows.
##
## The board is a square of side `min(size.x, size.y)` drawn from the control's top-left corner.
## The squares and marks are drawn in `_draw()`; the pieces are 16x16 pixel-art textures, drawn
## with nearest filtering.

## The player chose `uci`, a legal move of the position shown.
signal move_chosen(uci: String)

const _LIGHT := Color("f0d9b5")
const _DARK := Color("b58863")
const _LAST_MOVE := Color(0.96, 0.84, 0.2, 0.5)
const _SELECTED := Color(0.4, 0.8, 0.4, 0.6)
const _TARGET := Color(0.1, 0.1, 0.1, 0.4)
const _ARROW := Color(0.9, 0.35, 0.15, 0.85)
const _DIM := Color(0, 0, 0, 0.4)
## FEN letter (lowercase) to the name of the piece in the art folder.
const _PIECE_NAMES := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}
## The promotion choices, in the order of the picker's buttons.
const _PROMOTIONS := ["q", "r", "b", "n"]

var _fen := ""
var _white_at_bottom := true
var _interactive := false
## Square name to FEN letter, for the position shown.
var _pieces := {}
## The legal moves of the position shown, in UCI.
var _legal := PackedStringArray()
var _selected := ""
var _targets := PackedStringArray()
## The "from" and "to" squares of a promotion that waits for the player's choice, or "" for none.
var _promotion_from := ""
var _promotion_to := ""
var _last_move := ""
var _arrow := ""
var _textures := {}

@onready var _picker: Control = %PromotionPicker


func _ready() -> void:
	for i in _PROMOTIONS.size():
		(_picker.get_child(i) as Button).pressed.connect(choose_promotion.bind(_PROMOTIONS[i]))
	_layout_picker()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_picker()
		queue_redraw()


## Shows `fen`, with white's side at the bottom when `white_at_bottom` is set. It clears the
## selection, the last-move mark, the target dots and the promotion picker, but not the arrow:
## that changes only through `show_arrow()`.
func show_position(fen: String, white_at_bottom: bool) -> void:
	_fen = fen
	_white_at_bottom = white_at_bottom
	_pieces = {}
	for file in 8:
		for rank in 8:
			var square := char(97 + file) + str(rank + 1)
			var piece := ChessRules.piece_at(fen, square)
			if piece != "":
				_pieces[square] = piece
	_legal = ChessRules.inspect(fen).get("legal", PackedStringArray())
	_last_move = ""
	_clear_selection()


## The position shown.
func fen() -> String:
	return _fen


## Whether the player may select pieces and move. Switching it off clears the selection and
## closes the promotion picker.
func set_interactive(on: bool) -> void:
	_interactive = on
	if not on:
		_clear_selection()


## Marks the squares of `uci` as the last move played. "" (or anything that is not a move) clears
## the mark.
func mark_last_move(uci: String) -> void:
	_last_move = uci if UciParser.is_valid_uci_move(uci) else ""
	queue_redraw()


## The move marked as the last one played, or "".
func last_move() -> String:
	return _last_move


## Draws `uci` as an arrow from the centre of its first square to the centre of its second.
## "" (or anything that is not a move) clears it.
func show_arrow(uci: String) -> void:
	_arrow = uci if UciParser.is_valid_uci_move(uci) else ""
	queue_redraw()


## The move the arrow shows, or "".
func arrow() -> String:
	return _arrow


## What a tap on `square` does: a target of the selected piece moves there; a piece of the side to
## move is selected; anything else deselects. `""` is a tap outside the board. Nothing happens
## while the board is not interactive. A tap that is not on a target also cancels a promotion
## that waits for its piece, since a selection change closes the picker.
func tap_square(square: String) -> void:
	if not _interactive:
		return
	if _selected != "" and _targets.has(square):
		_move_to(square)
	elif square != _selected and _is_selectable(square):
		_select(square)
	else:
		_clear_selection()


## Completes the waiting promotion with `piece` ("q", "r", "b" or "n") and emits the move.
## Ignored when no promotion is waiting.
func choose_promotion(piece: String) -> void:
	if not _interactive or _promotion_from == "" or not _PROMOTIONS.has(piece):
		return
	var uci := _promotion_from + _promotion_to + piece
	if not _legal.has(uci):
		return
	_clear_selection()
	move_chosen.emit(uci)


## The square under `local` (a point in this control's coordinates, for example "e4"), or "" when
## the point is outside the board.
func square_at(local: Vector2) -> String:
	var side := _square_size() * 8.0
	if side <= 0.0 or local.x < 0.0 or local.y < 0.0 or local.x >= side or local.y >= side:
		return ""
	var col := int(local.x / _square_size())
	var row := int(local.y / _square_size())
	var file := col if _white_at_bottom else 7 - col
	var rank := 7 - row if _white_at_bottom else row
	return char(97 + file) + str(rank + 1)


## The selected square, or "".
func selected_square() -> String:
	return _selected


## The squares the selected piece can move to, sorted.
func target_squares() -> PackedStringArray:
	return _targets


func _gui_input(event: InputEvent) -> void:
	# Godot turns a touch into a mouse press too, flagged with this device id. Handling both
	# would tap twice for one touch.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch and event.pressed:
		tap_square(square_at(event.position))
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap_square(square_at(event.position))
		accept_event()


func _draw() -> void:
	var square_size := _square_size()
	if square_size <= 0.0:
		return
	for row in 8:
		for col in 8:
			var rect := Rect2(col * square_size, row * square_size, square_size, square_size)
			draw_rect(rect, _LIGHT if (col + row) % 2 == 0 else _DARK)
	if _last_move != "":
		draw_rect(_square_rect(_last_move.substr(0, 2)), _LAST_MOVE)
		draw_rect(_square_rect(_last_move.substr(2, 2)), _LAST_MOVE)
	if _selected != "":
		draw_rect(_square_rect(_selected), _SELECTED)
	for square in _pieces:
		draw_texture_rect(_texture_for(_pieces[square]), _square_rect(square), false)
	for square in _targets:
		_draw_target(square)
	if _arrow != "":
		_draw_arrow(_square_rect(_arrow.substr(0, 2)).get_center(), _square_rect(_arrow.substr(2, 2)).get_center())
	if _promotion_from != "":
		draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * square_size * 8.0), _DIM)


## A square dot on an empty target, a square outline on one that holds a piece to capture.
func _draw_target(square: String) -> void:
	var rect := _square_rect(square)
	if _pieces.has(square):
		draw_rect(rect.grow(-rect.size.x * 0.06), _TARGET, false, rect.size.x * 0.08)
	else:
		var dot := rect.size.x * 0.25
		draw_rect(Rect2(rect.get_center() - Vector2.ONE * dot / 2.0, Vector2.ONE * dot), _TARGET)


## A thick line from `from` to `to` that ends in a triangular head at `to`.
func _draw_arrow(from: Vector2, to: Vector2) -> void:
	if from.is_equal_approx(to):
		return
	var unit := _square_size()
	var direction := (to - from).normalized()
	var base := to - direction * unit * 0.45
	var across := direction.orthogonal() * unit * 0.3
	draw_line(from, base, _ARROW, unit * 0.2)
	draw_colored_polygon(PackedVector2Array([to, base + across, base - across]), _ARROW)


func _select(square: String) -> void:
	_close_picker()
	_selected = square
	_targets = PackedStringArray()
	for move in _legal:
		var target := move.substr(2, 2)
		if move.begins_with(square) and not _targets.has(target):
			_targets.append(target)
	_targets.sort()
	queue_redraw()


## Emits the move from the selected square to `target`, or asks for a promotion piece when there
## are several moves between the two.
func _move_to(target: String) -> void:
	var prefix := _selected + target
	var moves := PackedStringArray()
	for move in _legal:
		if move.begins_with(prefix):
			moves.append(move)
	if moves.size() == 1:
		_clear_selection()
		move_chosen.emit(moves[0])
	elif moves.size() > 1:
		_open_picker(_selected, target)


func _open_picker(from: String, to: String) -> void:
	_promotion_from = from
	_promotion_to = to
	var white := ChessRules.side_to_move(_fen) == "w"
	for i in _PROMOTIONS.size():
		var letter: String = _PROMOTIONS[i]
		(_picker.get_child(i) as Button).icon = _texture_for(letter.to_upper() if white else letter)
	_layout_picker()
	_picker.show()
	queue_redraw()


func _close_picker() -> void:
	_promotion_from = ""
	_promotion_to = ""
	_picker.hide()
	queue_redraw()


## Drops the selection, its dots and the promotion picker.
func _clear_selection() -> void:
	_selected = ""
	_targets = PackedStringArray()
	_close_picker()


## Whether `square` holds a piece of the side to move, and the board is interactive.
func _is_selectable(square: String) -> bool:
	var piece: String = _pieces.get(square, "")
	var side := ChessRules.side_to_move(_fen)
	if not _interactive or piece == "" or side == "":
		return false
	return (piece == piece.to_upper()) == (side == "w")


## Four squares wide and one tall, across the middle of the board.
func _layout_picker() -> void:
	if _picker == null:
		return
	var square_size := _square_size()
	for button in _picker.get_children():
		(button as Control).custom_minimum_size = Vector2.ONE * square_size
	_picker.position = Vector2(2.0, 3.5) * square_size
	_picker.size = Vector2(4.0, 1.0) * square_size


func _square_size() -> float:
	return minf(size.x, size.y) / 8.0


## The area of `square` (for example "e4") in this control's coordinates.
func _square_rect(square: String) -> Rect2:
	var file := square.unicode_at(0) - 97
	var rank := square.unicode_at(1) - 49
	var col := file if _white_at_bottom else 7 - file
	var row := 7 - rank if _white_at_bottom else rank
	var square_size := _square_size()
	return Rect2(col * square_size, row * square_size, square_size, square_size)


## The texture of the piece with FEN letter `letter` (uppercase is white).
func _texture_for(letter: String) -> Texture2D:
	if not _textures.has(letter):
		var color := "white" if letter == letter.to_upper() else "black"
		_textures[letter] = load("res://assets/chess_pieces/%s_%s.png" % [color, _PIECE_NAMES[letter.to_lower()]])
	return _textures[letter]
