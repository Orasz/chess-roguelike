extends GutTest

var scene


func before_each():
	scene = load("res://spike/engine_spike.tscn").instantiate()
	add_child_autofree(scene)


func after_each():
	if is_instance_valid(scene):
		scene.engine.shutdown()


func test_buttons_disabled_until_ready():
	for b in ["%PlayButton", "%MateCheckButton", "%QgaCheckButton", "%NewGameButton"]:
		assert_true(scene.get_node(b).disabled, b)
	await wait_for_signal(scene.engine.ready_ok, 15)
	await get_tree().process_frame
	assert_false(scene.get_node("%PlayButton").disabled)


func test_play_button_appends_engine_move():
	await wait_for_signal(scene.engine.ready_ok, 15)
	watch_signals(scene.engine)
	scene.get_node("%PlayButton").pressed.emit()
	await wait_for_signal(scene.engine.best_move, 10)
	await get_tree().process_frame
	var move: String = get_signal_parameters(scene.engine, "best_move")[0]
	assert_string_contains(scene.get_node("%MovesLabel").text, move)


func test_mate_check_reports_success():
	await wait_for_signal(scene.engine.ready_ok, 15)
	scene.get_node("%MateCheckButton").pressed.emit()
	await wait_for_signal(scene.engine.best_move, 10)
	await get_tree().process_frame
	assert_string_contains(scene.get_node("%CheckLabel").text, "✓ a1a8")
