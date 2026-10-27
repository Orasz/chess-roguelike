class_name UciParser
extends RefCounted
## Pure functions for reading UCI engine output and checking the syntax of
## what we send. Stockfish exits the whole process on a malformed command,
## so every FEN and move goes through these checks before it is sent.

const _PIECES := "prnbqkPRNBQK"


## Returns null unless `line` is an `info` line that carries a score.
## `info string` lines are free text, so a word "score" in them means nothing.
static func parse_info(line: String) -> EngineEval:
	var tokens := line.split(" ", false)
	if tokens.size() < 2 or tokens[0] != "info" or tokens[1] == "string" or not tokens.has("score"):
		return null
	var e := EngineEval.new()
	var i := 1
	while i < tokens.size():
		match tokens[i]:
			"depth":
				e.depth = _int_at(tokens, i + 1); i += 2
			"multipv":
				e.multipv = _int_at(tokens, i + 1); i += 2
			"nodes":
				e.nodes = _int_at(tokens, i + 1); i += 2
			"nps":
				e.nps = _int_at(tokens, i + 1); i += 2
			"time":
				e.time_ms = _int_at(tokens, i + 1); i += 2
			"score":
				e.is_mate = i + 1 < tokens.size() and tokens[i + 1] == "mate"
				e.value = _int_at(tokens, i + 2); i += 3
			"wdl":
				i += 4
			"seldepth", "hashfull", "tbhits":
				i += 2
			"pv":
				e.pv = tokens.slice(i + 1); i = tokens.size()
			_:
				i += 1  # lowerbound, upperbound and anything unknown
	return e


## Returns the move, "(none)" when there is no legal move, or "" when `line`
## is not a `bestmove` line.
static func parse_bestmove(line: String) -> String:
	var tokens := line.split(" ", false)
	if tokens.size() < 2 or tokens[0] != "bestmove":
		return ""
	return tokens[1]


## Syntax check only: it does not prove the position is legal.
static func is_valid_fen(fen: String) -> bool:
	var fields := fen.split(" ", false)
	if fields.size() != 6 or fen != " ".join(fields):
		return false
	return (_is_valid_board(fields[0])
			and fields[1] in ["w", "b"]
			and _is_valid_castling(fields[2])
			and _matches(fields[3], "-|[a-h][36]")
			and _matches(fields[4], "\\d+")
			and _matches(fields[5], "[1-9]\\d*"))


static func is_valid_uci_move(move: String) -> bool:
	return _matches(move, "[a-h][1-8][a-h][1-8][qrbn]?")


static func _is_valid_board(board: String) -> bool:
	var ranks := board.split("/")
	if ranks.size() != 8:
		return false
	for rank in ranks:
		var squares := 0
		for c in rank:
			if c >= "1" and c <= "8":
				squares += int(c)
			elif _PIECES.contains(c):
				squares += 1
			else:
				return false
		if squares != 8:
			return false
	return board.count("K") == 1 and board.count("k") == 1


static func _is_valid_castling(castling: String) -> bool:
	return castling == "-" or (castling != "" and _matches(castling, "K?Q?k?q?"))


## True when `pattern` matches the whole of `text`. \A and \z are used
## instead of ^ and $, because $ also matches before a trailing newline.
static func _matches(text: String, pattern: String) -> bool:
	var re := RegEx.create_from_string("\\A(?:" + pattern + ")\\z")
	return re.search(text) != null


static func _int_at(tokens: PackedStringArray, index: int) -> int:
	return int(tokens[index]) if index < tokens.size() else 0
