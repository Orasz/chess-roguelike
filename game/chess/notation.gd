class_name Notation
extends RefCounted
## How a move written in SAN (see `ChessRules.san`) is shown to the player. SAN's piece letters are
## the English ones; the catalog of the current language maps each to its own (in Italian K, Q, R, B
## and N become R, D, T, A and C). Only the first character and the letter after `=` of a promotion
## are piece letters. File letters, castling and the capture and check signs stay as they are.

## `tr()` is an instance method, so the static functions below call it on this object.
static var _translator := RefCounted.new()


## `san` with its piece letters in the language of the current locale. "" stays "".
static func display(san: String) -> String:
	if san.is_empty():
		return san
	var shown := _piece_letter(san[0]) + san.substr(1)
	var promotion := shown.find("=")
	if promotion >= 0 and promotion + 1 < shown.length():
		shown = shown.substr(0, promotion + 1) + _piece_letter(shown[promotion + 1]) + shown.substr(promotion + 2)
	return shown


## The letter that stands for the piece `letter` in the current language, or `letter` itself when it
## is not an upper-case piece letter. The calls are literal so that the extractor sees them.
static func _piece_letter(letter: String) -> String:
	match letter:
		"K": return _translator.tr("K", "piece letter")
		"Q": return _translator.tr("Q", "piece letter")
		"R": return _translator.tr("R", "piece letter")
		"B": return _translator.tr("B", "piece letter")
		"N": return _translator.tr("N", "piece letter")
	return letter
