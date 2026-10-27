class_name ChessRules
extends RefCounted
## Chess rules for the game, as static functions. The move generator is
## Stockfish's own, reached through the bridge; this class adds what the engine
## does not report: SAN, insufficient material and a few board readers.
##
## Every function that takes a position accepts only what Stockfish itself would
## accept, and returns an empty result otherwise. Stockfish exits the whole
## process on invalid input, so nothing reaches the native call unchecked.

enum Status { ONGOING, CHECKMATE, STALEMATE, DRAW_FIFTY, DRAW_REPETITION, DRAW_MATERIAL }

## Material values in centipawns, keyed by lowercase piece letter. Kings have none.
const _VALUES := {"p": 100, "n": 300, "b": 300, "r": 500, "q": 900}


## Replays `moves` from `fen` and returns Stockfish's view of the result:
## {fen: String, legal: PackedStringArray, in_check: bool, rule50: int, threefold: bool}.
## `legal` holds UCI moves, with castling as the king's two-square move (e1g1).
## Returns {} when the FEN or any move is invalid, or when the side not to move
## is in check.
static func inspect(fen: String, moves := PackedStringArray()) -> Dictionary:
	if not UciParser.is_valid_fen(fen):
		return {}
	for move in moves:
		if not UciParser.is_valid_uci_move(move):
			return {}
	return StockfishEngine.inspect_position(fen, moves)


## The FEN after `moves`, or "" when the input is invalid.
static func fen_after(fen: String, moves: PackedStringArray) -> String:
	return inspect(fen, moves).get("fen", "")


## How the game stands after `moves`. Checkmate and stalemate come first, then the
## fifty-move rule, threefold repetition and insufficient material (only K v K,
## K+N v K and K+B v K). Invalid input counts as ONGOING.
static func status(fen: String, moves := PackedStringArray()) -> Status:
	var info := inspect(fen, moves)
	if info.is_empty():
		return Status.ONGOING
	if info.legal.is_empty():
		return Status.CHECKMATE if info.in_check else Status.STALEMATE
	if info.rule50 >= 100:
		return Status.DRAW_FIFTY
	if info.threefold:
		return Status.DRAW_REPETITION
	if _is_insufficient_material(info.fen):
		return Status.DRAW_MATERIAL
	return Status.ONGOING


## Standard algebraic notation of the legal move `uci` in `fen`, with a `+` or `#`
## suffix when `suffix` is set. Returns "" for an illegal move.
static func san(fen: String, uci: String, suffix := true) -> String:
	var info := inspect(fen)
	if info.is_empty() or not info.legal.has(uci):
		return ""
	var from := uci.substr(0, 2)
	var to := uci.substr(2, 2)
	var piece := piece_at(fen, from)
	var kind := piece.to_upper()
	var text := ""
	var file_step := to.unicode_at(0) - from.unicode_at(0)
	if kind == "K" and absi(file_step) == 2:
		text = "O-O" if file_step > 0 else "O-O-O"
	elif kind == "P":
		# A legal pawn move that changes file is a capture, en passant included.
		if from[0] != to[0]:
			text = from[0] + "x"
		text += to
		if uci.length() == 5:
			text += "=" + uci[4].to_upper()
	else:
		var capture := piece_at(fen, to) != ""
		text = kind + _disambiguation(fen, info.legal, piece, from, to) + ("x" if capture else "") + to
	if suffix:
		var after := inspect(fen, PackedStringArray([uci]))
		if after.in_check:
			text += "#" if after.legal.is_empty() else "+"
	return text


## The FEN letter of the piece on `square` (for example "e1"), or "" when the
## square is empty or is not a square.
static func piece_at(fen: String, square: String) -> String:
	if square.length() != 2:
		return ""
	var file := square.unicode_at(0) - "a".unicode_at(0)
	var rank := square.unicode_at(1) - "1".unicode_at(0)
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return ""
	var rows := fen.get_slice(" ", 0).split("/")
	if rows.size() != 8:
		return ""
	var column := 0
	for c in rows[7 - rank]:
		if c >= "1" and c <= "8":
			column += int(c)
			if column > file:
				return ""
		else:
			if column == file:
				return c
			column += 1
	return ""


## "w" or "b", or "" when the FEN does not say.
static func side_to_move(fen: String) -> String:
	var side := fen.get_slice(" ", 1)
	return side if side == "w" or side == "b" else ""


## The material `color` ("w" or "b") has on the board: pawn 100, knight 300,
## bishop 300, rook 500, queen 900, and no value for the king.
static func material(fen: String, color: String) -> int:
	if color != "w" and color != "b":
		return 0
	var total := 0
	for c in fen.get_slice(" ", 0):
		var is_white := c == c.to_upper()
		if is_white == (color == "w"):
			total += _VALUES.get(c.to_lower(), 0)
	return total


## The coordinates that tell apart the pieces of the same kind that could also
## move to `to`: the file when that is enough, else the rank, else both.
static func _disambiguation(fen: String, legal: PackedStringArray, piece: String, from: String, to: String) -> String:
	var same_file := false
	var same_rank := false
	var ambiguous := false
	for move in legal:
		var other := move.substr(0, 2)
		if other == from or move.substr(2, 2) != to or piece_at(fen, other) != piece:
			continue
		ambiguous = true
		same_file = same_file or other[0] == from[0]
		same_rank = same_rank or other[1] == from[1]
	if not ambiguous:
		return ""
	if not same_file:
		return from[0]
	if not same_rank:
		return from[1]
	return from


## K v K, K+N v K or K+B v K: no side can ever mate.
static func _is_insufficient_material(fen: String) -> bool:
	var minors := 0
	for c in fen.get_slice(" ", 0):
		match c.to_lower():
			"n", "b":
				minors += 1
			"p", "r", "q":
				return false
	return minors <= 1
