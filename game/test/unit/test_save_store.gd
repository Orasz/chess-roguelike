extends GutTest

const PATH := "user://test_run.json"


func after_each():
	for p in [PATH, PATH + ".tmp", PATH + ".corrupt"]:
		DirAccess.remove_absolute(p)


func _write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()


func test_save_then_load():
	var store := SaveStore.new(PATH)
	var r := RunState.create(1, 600, "italian_game")
	r.take_damage(12)
	assert_true(store.save(r))
	assert_true(store.has_save())
	assert_eq(store.load_run().hp, 88)
	assert_false(FileAccess.file_exists(PATH + ".tmp"))


func test_a_second_save_replaces_the_first():
	var store := SaveStore.new(PATH)
	var r := RunState.create(1, 600, "italian_game")
	assert_true(store.save(r))
	r.take_damage(40)
	assert_true(store.save(r))
	assert_eq(store.load_run().hp, 60)
	assert_false(FileAccess.file_exists(PATH + ".tmp"))


func test_save_keeps_a_battle_in_progress():
	var store := SaveStore.new(PATH)
	var r := RunState.create(1, 600, "italian_game")
	r.set_battle({"id": "a", "moves": ["e2e4"]})
	store.save(r)
	assert_eq_deep(store.load_run().battle, {"id": "a", "moves": ["e2e4"]})


func test_save_fails_when_the_file_cannot_be_written():
	var store := SaveStore.new("user://no_such_directory/run.json")
	assert_false(store.save(RunState.create(1, 600, "italian_game")))
	assert_false(store.has_save())


func test_corrupt_or_foreign_saves_load_as_none():
	var store := SaveStore.new(PATH)
	for content in ["{\"version\": 1, \"hp\": ", "garbage", JSON.stringify({"version": 999})]:
		_write(PATH, content)
		assert_null(store.load_run(), content)
	assert_true(FileAccess.file_exists(PATH + ".corrupt"))


func test_every_unloadable_file_is_moved_to_corrupt():
	var store := SaveStore.new(PATH)
	var broken := {
		"empty": "",
		"truncated": "{\"version\": 1, \"hp\": ",
		"root is not a dictionary": "[1, 2, 3]",
		"foreign version": JSON.stringify({"version": 999}),
		"a field is missing": JSON.stringify({"version": 1, "hp": 50}),
	}
	for label in broken:
		_write(PATH, broken[label])
		assert_null(store.load_run(), label)
		assert_false(FileAccess.file_exists(PATH), "%s: moved away" % label)
		assert_eq(FileAccess.get_file_as_string(PATH + ".corrupt"), broken[label], label)


func test_a_foreign_version_leaves_no_save():
	var store := SaveStore.new(PATH)
	_write(PATH, JSON.stringify({"version": 999}))
	assert_false(store.has_save())
	assert_false(FileAccess.file_exists(PATH))
	assert_true(FileAccess.file_exists(PATH + ".corrupt"))


func test_a_newer_corrupt_file_replaces_the_older_one():
	var store := SaveStore.new(PATH)
	_write(PATH + ".corrupt", "older")
	_write(PATH, "newer")
	assert_null(store.load_run())
	assert_eq(FileAccess.get_file_as_string(PATH + ".corrupt"), "newer")


func test_a_missing_file_is_not_corrupt():
	var store := SaveStore.new(PATH)
	assert_null(store.load_run())
	assert_false(store.has_save())
	assert_false(FileAccess.file_exists(PATH + ".corrupt"))


func test_stale_temp_file_is_ignored():
	var store := SaveStore.new(PATH)
	store.save(RunState.create(1, 600, "italian_game"))
	_write(PATH + ".tmp", "half")
	assert_not_null(store.load_run())


func test_stale_temp_file_does_not_break_the_next_save():
	var store := SaveStore.new(PATH)
	_write(PATH + ".tmp", "half")
	assert_true(store.save(RunState.create(1, 600, "italian_game")))
	assert_not_null(store.load_run())
	assert_false(FileAccess.file_exists(PATH + ".tmp"))


func test_clear():
	var store := SaveStore.new(PATH)
	store.save(RunState.create(1, 600, "italian_game"))
	store.clear()
	assert_false(store.has_save())
	assert_null(store.load_run())


func test_clear_with_no_save_is_harmless():
	SaveStore.new(PATH).clear()
	assert_false(FileAccess.file_exists(PATH))
