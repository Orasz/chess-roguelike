class_name ExplanationBuilder
extends RefCounted
## Turns puzzle themes and the engine's best reply into the short texts the game
## shows after a mistake. Texts are translated with `TranslationServer.translate()`, the
## static twin of `tr()`, from English sources.

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
## How many plies of the engine's line are replayed to see what a mistake costs.
const _REPLAYED_PLIES := 3
## The smallest material drop, in centipawns, that counts as losing a piece.
const _MATERIAL_DROP := 100
## FEN letters of the piece types the mover can lose, most valuable first.
const _LOSABLE_PIECES := "qrbnp"


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
## reply wins one of the mover's pieces (the most valuable one the line takes within
## `_REPLAYED_PLIES` plies), or else just what the best reply is.
## Returns "" when `wrong_uci` is illegal in `fen`, or when the sentence needs the
## reply's first move and the line has none or it is illegal.
static func after_mistake(fen: String, wrong_uci: String, reply: EngineEval) -> String:
	var wrong := ChessRules.san(fen, wrong_uci, false)
	if wrong.is_empty():
		return ""
	if reply.is_mate and reply.value > 1:
		return TranslationServer.translate("After %s, the opponent has mate in %d.") % [wrong, reply.value]
	var best := ""
	if not reply.pv.is_empty():
		best = ChessRules.san(ChessRules.fen_after(fen, PackedStringArray([wrong_uci])), reply.pv[0], false)
	if best.is_empty():
		return ""
	if reply.is_mate and reply.value == 1:
		return TranslationServer.translate("After %s, %s is checkmate.") % [wrong, best]
	var lost := _lost_piece(fen, wrong_uci, reply.pv)
	if not lost.is_empty():
		return TranslationServer.translate("After %s, %s wins your %s.") % [wrong, best, lost]
	return TranslationServer.translate("After %s, the best reply is %s.") % [wrong, best]


## The translated name of the most valuable piece type the mover loses when `wrong_uci`
## is followed by the first plies of `line`, or "" when the mover's material balance
## does not fall by `_MATERIAL_DROP` or none of the mover's piece counts went down
## (the opponent promoted, for instance). The replay stops at the first illegal move.
static func _lost_piece(fen: String, wrong_uci: String, line: PackedStringArray) -> String:
	var mover := ChessRules.side_to_move(fen)
	var opponent := "b" if mover == "w" else "w"
	var moves := PackedStringArray([wrong_uci])
	var last := ChessRules.fen_after(fen, moves)
	for move in line.slice(0, _REPLAYED_PLIES):
		moves.append(move)
		var next := ChessRules.fen_after(fen, moves)
		if next.is_empty():
			break
		last = next
	var before := ChessRules.material(fen, mover) - ChessRules.material(fen, opponent)
	var after := ChessRules.material(last, mover) - ChessRules.material(last, opponent)
	if before - after < _MATERIAL_DROP:
		return ""
	for letter in _LOSABLE_PIECES:
		var piece := letter.to_upper() if mover == "w" else letter
		if _count(last, piece) < _count(fen, piece):
			return _translated_piece(letter)
	return ""


## How many pieces of FEN letter `piece` are on the board of `fen`.
static func _count(fen: String, piece: String) -> int:
	return fen.get_slice(" ", 0).count(piece)


static func _translated_theme(tag: String) -> String:
	match tag:
		"backRankMate": return TranslationServer.translate("Back-rank mate")
		"smotheredMate": return TranslationServer.translate("Smothered mate")
		"mateIn1": return TranslationServer.translate("Mate in one")
		"fork": return TranslationServer.translate("Fork")
		"pin": return TranslationServer.translate("Pin")
		"skewer": return TranslationServer.translate("Skewer")
		"discoveredAttack": return TranslationServer.translate("Discovered attack")
		"doubleCheck": return TranslationServer.translate("Double check")
		"hangingPiece": return TranslationServer.translate("Hanging piece")
		"trappedPiece": return TranslationServer.translate("Trapped piece")
		"attraction": return TranslationServer.translate("Attraction")
		"deflection": return TranslationServer.translate("Deflection")
		"capturingDefender": return TranslationServer.translate("Capturing the defender")
		"interference": return TranslationServer.translate("Interference")
		"clearance": return TranslationServer.translate("Clearance")
		"exposedKing": return TranslationServer.translate("Exposed king")
		"promotion": return TranslationServer.translate("Promotion")
	return ""


static func _translated_piece(letter: String) -> String:
	match letter:
		"q": return TranslationServer.translate("queen")
		"r": return TranslationServer.translate("rook")
		"b": return TranslationServer.translate("bishop")
		"n": return TranslationServer.translate("knight")
		"p": return TranslationServer.translate("pawn")
	return ""
