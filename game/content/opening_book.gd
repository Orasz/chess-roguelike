class_name OpeningBook
extends RefCounted
## An opening as a tree of hand-written lines, read from a file such as
## data/openings/italian_game.json. A player node is `{move, why: {en, it}, replies: [enemy
## nodes]}`; an enemy node is `{move, next: [player nodes]}`. The first player node of a list
## is the main move, and a player node with no replies ends its line.
##
## Lines are written from White's side, so the player moves when the number of moves played
## is even. `side` is kept as data for the encounters that need it.
##
## The theory text is data in both languages, so `text` picks the language itself instead of
## going through `tr()`.

var id := ""
var player_white := true
var start_fen := ""

var _name := {}
var _plans := {}
var _line: Array = []


## Loads the book at `path`. Returns null when the file is missing or is not a JSON object.
static func load_file(path: String) -> OpeningBook:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data)


## Builds a book from the parsed file.
static func from_dict(d: Dictionary) -> OpeningBook:
	var book := OpeningBook.new()
	book.id = d.get("id", "")
	book.player_white = d.get("side", "white") == "white"
	book.start_fen = d.get("start_fen", UciEngine.START_FEN)
	book._name = d.get("name", {})
	book._plans = d.get("plans", {})
	book._line = d.get("line", [])
	return book


## The player nodes on offer after `moves`, main move first. Empty on the enemy's turn, when
## `moves` has left the book, and when the line is complete.
func player_options(moves: PackedStringArray) -> Array:
	return _walk(moves).get("players", [])


## The enemy's book moves after `moves`. Empty on the player's turn, when `moves` has left the
## book, and when the line is complete.
func enemy_replies(moves: PackedStringArray) -> PackedStringArray:
	var replies := PackedStringArray()
	for node: Dictionary in _walk(moves).get("replies", []):
		replies.append(node.move)
	return replies


## True when the last of `moves` was a player node that ends its line.
func is_complete(moves: PackedStringArray) -> bool:
	return _walk(moves).has("complete")


## The text of `field`, a `{en, it}` Dictionary, in the language of the current locale, or in
## English when `field` has none for it.
func text(field: Dictionary) -> String:
	var language := TranslationServer.get_locale().substr(0, 2)
	return field.get(language, field.get("en", ""))


## The name of the opening, in the current language.
func name() -> String:
	return text(_name)


## The ideas of the opening, in the current language.
func plans() -> String:
	return text(_plans)


## Follows `moves` down the tree. Returns `{players}` with the player nodes on offer on the
## player's turn, `{replies}` with the enemy nodes on offer on the enemy's turn, `{complete}`
## after the last move of a line, and `{}` once `moves` has left the book.
func _walk(moves: PackedStringArray) -> Dictionary:
	var players: Array = _line
	for i in range(0, moves.size(), 2):
		var player_node := _find(players, moves[i])
		if player_node.is_empty():
			return {}
		var replies: Array = player_node.get("replies", [])
		if i + 1 == moves.size():
			return {"replies": replies} if not replies.is_empty() else {"complete": true}
		var enemy_node := _find(replies, moves[i + 1])
		if enemy_node.is_empty():
			return {}
		players = enemy_node.get("next", [])
	return {"players": players}


## The node of `nodes` that plays `move`, or an empty Dictionary.
func _find(nodes: Array, move: String) -> Dictionary:
	for node: Dictionary in nodes:
		if node.move == move:
			return node
	return {}
