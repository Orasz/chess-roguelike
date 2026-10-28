class_name ExplanationBuilder
extends RefCounted
## Turns puzzle themes and the engine's best reply into the short texts the game
## shows after a mistake. Every text goes through `tr()` with an English source.

## Lichess theme tags in the order that decides which one names a puzzle: the
## first tag in this list that a puzzle carries wins. Tags that are not listed
## ("opening", "oneMove", "short", ...) describe a puzzle without naming an idea.
const _THEME_PRIORITY: Array[String] = [
	"backRankMate", "smotheredMate", "mateIn1",
	"fork", "pin", "skewer",
	"discoveredAttack", "doubleCheck",
	"hangingPiece", "trappedPiece",
	"attraction", "deflection", "capturingDefender", "interference", "clearance",
	"exposedKing", "promotion",
]
## How many plies of the engine's line are replayed to see what a mistake costs. An even
## number, so the window ends on the mover's recapture when the line has one.
const _REPLAYED_PLIES := 4
## The smallest material drop, in centipawns, that counts as losing a piece.
const _MATERIAL_DROP := 100
## FEN letters of the piece types the mover can lose, most valuable first.
const _LOSABLE_PIECES := "qrbnp"

## `tr()` is an instance method, so the static functions below call it on this object.
static var _translator := RefCounted.new()


## The name of the first of `themes` that is worth showing, in the priority order of
## `_THEME_PRIORITY`, or "" when none is.
static func theme_name(themes: PackedStringArray) -> String:
	for tag in _THEME_PRIORITY:
		if themes.has(tag):
			return _translated_theme(tag)
	return ""


## One sentence on why `wrong_uci` was a mistake in `fen`, built from `reply`: the
## engine's best line in the position after the wrong move, from the opponent's point
## of view. Moves are written in SAN without check or mate suffixes. In order, it
## says that the reply is checkmate, that the opponent has a longer mate, that the
## line wins one of the mover's pieces (see `_lost_piece`), naming the opponent's move that
## takes it when that is their very next move and otherwise only that they can, or else
## just what the best reply is.
## Returns "" when `wrong_uci` is illegal in `fen`, or when the sentence needs the
## reply's first move and the line has none or it is illegal.
static func after_mistake(fen: String, wrong_uci: String, reply: EngineEval) -> String:
	var wrong := ChessRules.san(fen, wrong_uci, false)
	if wrong.is_empty():
		return ""
	if reply.is_mate and reply.value > 1:
		return _translator.tr("After %s, the opponent has mate in %d.") % [Notation.display(wrong), reply.value]
	var best := ""
	if not reply.pv.is_empty():
		best = ChessRules.san(ChessRules.fen_after(fen, PackedStringArray([wrong_uci])), reply.pv[0], false)
	if best.is_empty():
		return ""
	wrong = Notation.display(wrong)
	best = Notation.display(best)
	if reply.is_mate and reply.value == 1:
		return _translator.tr("After %s, %s is checkmate.") % [wrong, best]
	var lost := _lost_piece(fen, wrong_uci, reply.pv)
	if not lost.is_empty():
		# A capture further down the line is not the opponent's next move, and a move that cannot be
		# played yet is not named: the board still shows the pieces before it.
		if lost.ply == 0:
			return _translator.tr("After %s, %s wins your %s.") % [wrong, Notation.display(lost.move), lost.piece]
		return _translator.tr("After %s, the opponent can win your %s.") % [wrong, lost.piece]
	return _translator.tr("After %s, the best reply is %s.") % [wrong, best]


## What the mover loses when `wrong_uci` is followed by the first `_REPLAYED_PLIES` plies
## of `line`, as {piece: the translated name of the most valuable piece type whose count
## went down, move: the SAN, without suffix, of the first opponent move in the window
## that took a piece of that type, ply: that move's index in `line`, 0 for the immediate
## reply}. Returns {} when the mover's material balance at the
## end of the window has not fallen by `_MATERIAL_DROP`, or when no opponent move took
## a piece of a type whose count went down (the opponent promoted, for instance).
## The replay stops at the first illegal move. `wrong_uci` and the first move of `line`
## must be legal.
static func _lost_piece(fen: String, wrong_uci: String, line: PackedStringArray) -> Dictionary:
	var mover := ChessRules.side_to_move(fen)
	var opponent := "b" if mover == "w" else "w"
	var moves := PackedStringArray([wrong_uci])
	# positions[i] is the position before line[i]; the opponent plays the even plies.
	var positions: Array[String] = [ChessRules.fen_after(fen, moves)]
	for move in line.slice(0, _REPLAYED_PLIES):
		moves.append(move)
		var next := ChessRules.fen_after(fen, moves)
		if next.is_empty():
			break
		positions.append(next)
	var last: String = positions.back()
	var before := ChessRules.material(fen, mover) - ChessRules.material(fen, opponent)
	var after := ChessRules.material(last, mover) - ChessRules.material(last, opponent)
	if before - after < _MATERIAL_DROP:
		return {}
	for letter in _LOSABLE_PIECES:
		var piece := letter.to_upper() if mover == "w" else letter
		if _count(last, piece) >= _count(fen, piece):
			continue
		for ply in range(0, positions.size() - 1, 2):
			if _count(positions[ply + 1], piece) < _count(positions[ply], piece):
				return {"piece": _translated_piece(letter), "move": ChessRules.san(positions[ply], line[ply], false), "ply": ply}
	return {}


## How many pieces of FEN letter `piece` are on the board of `fen`.
static func _count(fen: String, piece: String) -> int:
	return fen.get_slice(" ", 0).count(piece)


static func _translated_theme(tag: String) -> String:
	match tag:
		"backRankMate": return _translator.tr("Back-rank mate")
		"smotheredMate": return _translator.tr("Smothered mate")
		"mateIn1": return _translator.tr("Mate in one")
		"fork": return _translator.tr("Fork")
		"pin": return _translator.tr("Pin")
		"skewer": return _translator.tr("Skewer")
		"discoveredAttack": return _translator.tr("Discovered attack")
		"doubleCheck": return _translator.tr("Double check")
		"hangingPiece": return _translator.tr("Hanging piece")
		"trappedPiece": return _translator.tr("Trapped piece")
		"attraction": return _translator.tr("Attraction")
		"deflection": return _translator.tr("Deflection")
		"capturingDefender": return _translator.tr("Capturing the defender")
		"interference": return _translator.tr("Interference")
		"clearance": return _translator.tr("Clearance")
		"exposedKing": return _translator.tr("Exposed king")
		"promotion": return _translator.tr("Promotion")
	return ""


static func _translated_piece(letter: String) -> String:
	match letter:
		"q": return _translator.tr("queen", "lost piece")
		"r": return _translator.tr("rook", "lost piece")
		"b": return _translator.tr("bishop", "lost piece")
		"n": return _translator.tr("knight", "lost piece")
		"p": return _translator.tr("pawn", "lost piece")
	return ""
