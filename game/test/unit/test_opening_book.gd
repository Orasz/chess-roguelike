extends GutTest
## A tiny inline book: 1.e4 (main) or 1.d4. After 1.e4 e5, 2.Nf3 ends the line.

const TEMP_FILE := "user://test_opening_book.json"


func after_each() -> void:
	TranslationServer.set_locale("en")
	if FileAccess.file_exists(TEMP_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FILE))


func _dict() -> Dictionary:
	var why := {"en": "Because.", "it": "Perché."}
	return {"version": 1, "id": "t", "side": "white", "name": why, "plans": why,
		"start_fen": UciEngine.START_FEN, "line": [
			{"move": "e2e4", "why": why, "replies": [{"move": "e7e5", "next": [{"move": "g1f3", "why": why, "replies": []}]}]},
			{"move": "d2d4", "why": why, "replies": []}]}


func _book() -> OpeningBook:
	return OpeningBook.from_dict(_dict())


func test_navigation():
	var b := _book()
	assert_eq(b.player_options(PackedStringArray()).map(func(n): return n.move), ["e2e4", "d2d4"])
	assert_eq(b.enemy_replies(PackedStringArray(["e2e4"])), PackedStringArray(["e7e5"]))
	assert_true(b.player_options(PackedStringArray(["e2e4"])).is_empty(), "enemy's turn")
	assert_true(b.player_options(PackedStringArray(["a2a3"])).is_empty(), "out of book")
	assert_true(b.is_complete(PackedStringArray(["e2e4", "e7e5", "g1f3"])))
	assert_false(b.is_complete(PackedStringArray(["e2e4"])))


func test_enemy_replies_are_empty_on_the_players_turn_and_out_of_book():
	var b := _book()
	assert_true(b.enemy_replies(PackedStringArray()).is_empty(), "player's turn")
	assert_true(b.enemy_replies(PackedStringArray(["e2e4", "e7e5"])).is_empty(), "player's turn")
	assert_true(b.enemy_replies(PackedStringArray(["a2a3"])).is_empty(), "out of book")
	assert_true(b.enemy_replies(PackedStringArray(["d2d4"])).is_empty(), "line complete")


func test_a_finished_line_offers_nothing_more():
	var b := _book()
	assert_true(b.is_complete(PackedStringArray(["d2d4"])), "a leaf on the first move")
	assert_true(b.player_options(PackedStringArray(["e2e4", "e7e5", "g1f3"])).is_empty())
	assert_true(b.enemy_replies(PackedStringArray(["d2d4"])).is_empty())
	assert_false(b.is_complete(PackedStringArray(["e2e4", "e7e5", "g1f3", "b8c6"])), "past the end is out of book")
	assert_false(b.is_complete(PackedStringArray(["a2a3"])), "out of book is not complete")
	assert_false(b.is_complete(PackedStringArray()), "the empty line is not complete")


func test_an_enemy_move_outside_the_book_leaves_it():
	var b := _book()
	assert_true(b.player_options(PackedStringArray(["e2e4", "c7c5"])).is_empty())
	assert_false(b.is_complete(PackedStringArray(["e2e4", "c7c5"])))


func test_player_options_return_the_node_with_its_why():
	var node: Dictionary = _book().player_options(PackedStringArray())[0]
	assert_eq(node.move, "e2e4")
	assert_eq(node.why.en, "Because.")


func test_from_dict_reads_the_header():
	var b := _book()
	assert_eq(b.id, "t")
	assert_true(b.player_white)
	assert_eq(b.start_fen, UciEngine.START_FEN)
	assert_false(OpeningBook.from_dict(_dict().merged({"side": "black"}, true)).player_white)


func test_text_falls_back_to_english():
	TranslationServer.set_locale("fr")
	assert_eq(_book().text({"en": "Hi", "it": "Ciao"}), "Hi")
	TranslationServer.set_locale("it")
	assert_eq(_book().text({"en": "Hi", "it": "Ciao"}), "Ciao")
	TranslationServer.set_locale("it_IT")
	assert_eq(_book().text({"en": "Hi", "it": "Ciao"}), "Ciao", "only the language counts")


func test_name_and_plans_follow_the_locale():
	var b := OpeningBook.from_dict(_dict().merged({"name": {"en": "Name", "it": "Nome"}, "plans": {"en": "Plans", "it": "Piani"}}, true))
	assert_eq(b.name(), "Name")
	assert_eq(b.plans(), "Plans")
	TranslationServer.set_locale("it")
	assert_eq(b.name(), "Nome")
	assert_eq(b.plans(), "Piani")


func test_load_file_reads_a_book_and_returns_null_on_failure():
	var file := FileAccess.open(TEMP_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(_dict()))
	file.close()
	var b := OpeningBook.load_file(TEMP_FILE)
	assert_not_null(b)
	assert_eq(b.id, "t")
	assert_null(OpeningBook.load_file("user://no_such_book.json"), "missing file")
	file = FileAccess.open(TEMP_FILE, FileAccess.WRITE)
	file.store_string("[1, 2")
	file.close()
	assert_null(OpeningBook.load_file(TEMP_FILE), "malformed JSON")
	file = FileAccess.open(TEMP_FILE, FileAccess.WRITE)
	file.store_string("[1, 2]")
	file.close()
	assert_null(OpeningBook.load_file(TEMP_FILE), "not an object")
