extends GutTest

const PATH := "res://data/openings/italian_game.json"


func test_italian_book_is_legal_complete_and_bilingual():
	var book := OpeningBook.load_file(PATH)
	assert_not_null(book)
	assert_true(book.player_white)
	var leaves := _walk(book, PackedStringArray())
	assert_gt(leaves, 2, "at least the three lines")


func test_the_book_is_named_and_explained_in_both_languages():
	var book := OpeningBook.load_file(PATH)
	assert_eq(book.id, "italian_game")
	for locale in ["en", "it"]:
		TranslationServer.set_locale(locale)
		assert_ne(book.name(), "", locale)
		assert_ne(book.plans(), "", locale)
	TranslationServer.set_locale("en")


func test_the_three_lines_are_present():
	var book := OpeningBook.load_file(PATH)
	var prefix := PackedStringArray(["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"])
	assert_eq(book.enemy_replies(prefix), PackedStringArray(["f8c5", "g8f6"]), "Giuoco Piano and Two Knights")
	var bishop_lines := book.player_options(prefix + PackedStringArray(["f8c5"]))
	assert_eq(bishop_lines.map(func(n): return n.move), ["c2c3", "d2d3"], "line A is the main move, line B the alternative")
	var after_cxd4 := prefix + PackedStringArray(["f8c5", "c2c3", "g8f6", "d2d4", "e5d4", "c3d4", "c5b4"])
	assert_eq(book.player_options(after_cxd4).map(func(n): return n.move), ["c1d2", "b1c3"], "Bd2 is main, Nc3 the alternative")
	assert_true(book.is_complete(after_cxd4 + PackedStringArray(["c1d2"])))
	assert_true(book.is_complete(after_cxd4 + PackedStringArray(["b1c3"])))
	var two_knights := prefix + PackedStringArray(["g8f6", "d2d3", "f8c5", "c2c3", "d7d6", "e1g1"])
	assert_true(book.is_complete(two_knights), "line C")
	var quiet_bishop := prefix + PackedStringArray(["f8c5", "d2d3", "g8f6", "c2c3", "d7d6", "e1g1"])
	assert_true(book.is_complete(quiet_bishop), "line B")


func _walk(book: OpeningBook, moves: PackedStringArray) -> int:
	assert_false(ChessRules.inspect(book.start_fen, moves).is_empty(), " ".join(moves))
	if book.is_complete(moves):
		return 1
	var count := 0
	for node in book.player_options(moves):
		assert_ne(node.why.get("en", ""), "", "English note after " + " ".join(moves))
		assert_ne(node.why.get("it", ""), "", "Italian note after " + " ".join(moves))
		count += _walk(book, moves + PackedStringArray([node.move]))
	for reply in book.enemy_replies(moves):
		count += _walk(book, moves + PackedStringArray([reply]))
	return count
