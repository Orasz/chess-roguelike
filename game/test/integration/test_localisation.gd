extends GutTest
## The Italian catalog: it translates every string of the template, keeps its placeholders, drives the
## explanations and the notation, and every other language shows English.

const POT := "res://locale/messages.pot"
const CATALOG := "res://locale/it.po"
## White knight on b4 attacked by the black pawn on e6 once it lands on d5.
const KNIGHT_FEN := "4k3/8/4p3/8/1N6/8/8/4K3 w - - 0 1"
const _PLACEHOLDER := "%[sd]"


func after_each():
	TranslationServer.set_locale("en")


func _reply(mate: bool, value: int, pv: Array) -> EngineEval:
	var e := EngineEval.new(); e.is_mate = mate; e.value = value; e.pv = PackedStringArray(pv); return e


## The entries of the template as [{ctx, id}], read from its msgctxt and msgid lines.
func _pot_entries(path: String) -> Array:
	var entries := []
	var ctx := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("msgctxt "):
			ctx = _quoted(line.trim_prefix("msgctxt "))
		elif line.begins_with("msgid "):
			var id := _quoted(line.trim_prefix("msgid "))
			if not id.is_empty():
				entries.append({"ctx": ctx, "id": id})
			ctx = ""
	return entries


func _quoted(literal: String) -> String:
	return literal.substr(1, literal.length() - 2).c_unescape()


func _placeholders(text: String) -> Array:
	var found := []
	var regex := RegEx.create_from_string(_PLACEHOLDER)
	for m in regex.search_all(text):
		found.append(m.get_string())
	return found


func test_the_template_lists_every_string():
	# Guards the parser of this file: the template has the strings of the scenes and of the scripts.
	var ids := _pot_entries(POT).map(func(e): return e.id)
	assert_true(ids.has("Chess Roguelike"))
	assert_true(ids.has("After %s, %s wins your %s."))
	assert_true(ids.has("K"))


func test_every_string_has_an_italian_translation():
	var it := load(CATALOG) as Translation
	assert_not_null(it)
	for e in _pot_entries(POT):
		assert_ne(it.get_message(e.id, e.ctx), "", e.id)


func test_translations_keep_the_placeholders_of_their_source():
	var it := load(CATALOG) as Translation
	for e in _pot_entries(POT):
		assert_eq(_placeholders(it.get_message(e.id, e.ctx)), _placeholders(e.id), e.id)


func test_explanations_read_in_italian():
	TranslationServer.set_locale("it")
	assert_eq(ExplanationBuilder.after_mistake(KNIGHT_FEN, "b4d5", _reply(false, 300, ["e6d5"])),
		"Dopo Cd5, exd5 ti prende il cavallo.")


func test_themes_and_enemy_names_read_in_italian():
	TranslationServer.set_locale("it")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["fork"])), "Forchetta")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["pin"])), "Inchiodatura")
	assert_eq(EnemyRoster.for_encounter("strong", "x").name, tr("Gatekeeper Rook"))
	assert_ne(EnemyRoster.for_encounter("strong", "x").name, "Gatekeeper Rook")


func test_other_languages_fall_back_to_english():
	TranslationServer.set_locale("fr")
	assert_eq(ExplanationBuilder.after_mistake(KNIGHT_FEN, "b4d5", _reply(false, 300, ["e6d5"])),
		"After Nd5, exd5 wins your knight.")
	assert_eq(Notation.display("Qxe7+"), "Qxe7+")


func test_a_regional_italian_locale_is_italian():
	TranslationServer.set_locale("it_CH")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["fork"])), "Forchetta")


func test_notation_follows_the_language():
	TranslationServer.set_locale("it")
	assert_eq(Notation.display("Qxe7+"), "Dxe7+")
	assert_eq(Notation.display("Nbd7"), "Cbd7")
	assert_eq(Notation.display("Kf1"), "Rf1")
	assert_eq(Notation.display("Rxa8#"), "Txa8#")
	assert_eq(Notation.display("Bb5"), "Ab5")
	assert_eq(Notation.display("exd5"), "exd5", "a file letter is not a piece")
	assert_eq(Notation.display("bxc3"), "bxc3", "a file letter is not a piece")
	assert_eq(Notation.display("e8=Q+"), "e8=D+")
	assert_eq(Notation.display("bxa8=N"), "bxa8=C")
	assert_eq(Notation.display("O-O"), "O-O")
	assert_eq(Notation.display("O-O-O+"), "O-O-O+")
	assert_eq(Notation.display(""), "")
	TranslationServer.set_locale("en")
	assert_eq(Notation.display("Qxe7+"), "Qxe7+")
	assert_eq(Notation.display("e8=Q+"), "e8=Q+")


func test_the_licences_open_with_the_notice_in_the_language_of_the_player():
	TranslationServer.set_locale("it")
	var about := (load("res://main/about_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(about)
	(about.get_node("%LicencesButton") as Button).pressed.emit()
	assert_true((about.get_node("%Licences") as RichTextLabel).text.begins_with("Chess Roguelike è software libero"))
