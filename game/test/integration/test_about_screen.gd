extends GutTest
## The About screen: the version, the free-software notice, the links to the published pages and the
## licences of everything the app ships.

var about: AboutScreen


func before_each():
	about = (load("res://main/about_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(about)


func _licences() -> RichTextLabel:
	return about.get_node("%Licences")


func _show_licences() -> String:
	(about.get_node("%LicencesButton") as Button).pressed.emit()
	return _licences().text


func test_links_open_the_published_pages():
	var opened := []
	about.open_url = func(u: String) -> void: opened.append(u)
	for b in ["%SourceButton", "%PrivacyButton", "%FeedbackButton"]:
		about.get_node(b).pressed.emit()
	assert_eq(opened, [AboutScreen.SOURCE_URL, AboutScreen.PRIVACY_URL, AboutScreen.FEEDBACK_URL])


func test_the_urls_are_the_published_ones():
	assert_eq(AboutScreen.SOURCE_URL, "https://github.com/Orasz/chess-roguelike")
	assert_eq(AboutScreen.PRIVACY_URL, "https://github.com/Orasz/chess-roguelike/blob/main/PRIVACY.md")
	assert_eq(AboutScreen.FEEDBACK_URL, "https://github.com/Orasz/chess-roguelike/issues")


func test_the_default_opener_is_the_browser():
	assert_eq(about.open_url, Callable(OS, "shell_open"))


func test_shows_the_version_and_the_free_software_notice():
	var version: String = ProjectSettings.get_setting("application/config/version")
	assert_eq(version, "0.1.0")
	assert_string_contains((about.get_node("%Version") as Label).text, version)
	assert_string_contains((about.get_node("%Notice") as Label).text, "GNU General Public License")
	assert_string_contains((about.get_node("%Notice") as Label).text, "version 3")


func test_back_closes_the_screen():
	watch_signals(about)
	(about.get_node("%BackButton") as Button).pressed.emit()
	assert_signal_emitted(about, "closed")


func test_licences_are_hidden_and_not_built_until_asked_for():
	assert_false(_licences().visible)
	assert_eq(_licences().text, "", "the large text is built on demand")
	_show_licences()
	assert_true(_licences().visible)


func test_licences_name_every_engine_component():
	var text := _show_licences()
	var components: Array = Engine.get_copyright_info()
	assert_gt(components.size(), 0)
	for component: Dictionary in components:
		assert_string_contains(text, component["name"])


func test_licences_hold_the_licence_texts_of_the_engine():
	var text := _show_licences()
	var licences: Dictionary = Engine.get_license_info()
	assert_gt(licences.size(), 0)
	for licence_name: String in licences:
		assert_string_contains(text, licence_name)
	assert_string_contains(text, String(licences.values()[0]).strip_edges().left(200))


func test_licences_come_in_order():
	var text := _show_licences()
	var notice := text.find("GNU General Public License")
	var gpl := text.find(FileAccess.get_file_as_string("res://legal/GPL-3.0.txt").strip_edges().left(200))
	var credits := text.find(FileAccess.get_file_as_string("res://legal/CREDITS.md").strip_edges().left(200))
	var component := text.find(String((Engine.get_copyright_info()[0] as Dictionary)["name"]))
	var licence_text := text.rfind(String(Engine.get_license_info().values()[0]).strip_edges().left(200))
	assert_between(notice, 0, gpl - 1, "the notice comes first")
	assert_between(gpl, notice, credits - 1, "then the GPLv3")
	assert_between(credits, gpl, component - 1, "then the credits")
	assert_between(component, credits, licence_text - 1, "then the engine's components")
	assert_gt(licence_text, component, "then their licence texts")


func test_pressing_the_licences_twice_builds_them_once():
	var first := _show_licences()
	assert_eq(_show_licences(), first)


func test_a_drag_scrolls_the_licences():
	_show_licences()
	await wait_process_frames(2)
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(0, -40)
	_licences().gui_input.emit(drag)
	assert_eq(_licences().get_v_scroll_bar().value, 40.0)
	drag.relative = Vector2(0, 100)
	_licences().gui_input.emit(drag)
	assert_eq(_licences().get_v_scroll_bar().value, 0.0, "it stops at the top")


func test_the_content_sits_inside_the_safe_area():
	assert_true(about.get_node("Safe") is SafeMarginContainer)
