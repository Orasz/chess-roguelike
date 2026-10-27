extends GutTest

const FakeEngine := preload("res://test/support/fake_engine.gd")


func test_scripted_reply_arrives_next_frame():
	var fake := FakeEngine.new(); add_child_autofree(fake); watch_signals(fake)
	fake.replies = [[FakeEngine.line("e2e4", 30), FakeEngine.line("d2d4", 20)]]
	assert_true(fake.set_position(UciEngine.START_FEN)); assert_true(fake.go_movetime(700))
	assert_signal_not_emitted(fake, "search_finished")
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(fake, "best_move", ["e2e4"])
	assert_eq(fake.searches[0].ms, 700)


func test_default_reply_lists_legal_moves():
	var fake := FakeEngine.new(); add_child_autofree(fake); watch_signals(fake)
	fake.set_position(UciEngine.START_FEN); fake.go_movetime(1)
	await wait_for_signal(fake.search_finished, 1)
	assert_eq(get_signal_parameters(fake, "search_finished")[1].size(), 20)


func _fake_with_position() -> Variant:
	var fake := FakeEngine.new(); add_child_autofree(fake); watch_signals(fake)
	fake.set_position(UciEngine.START_FEN)
	return fake


func test_best_move_is_the_first_line_and_lines_are_numbered_in_reply_order():
	var fake = _fake_with_position()
	fake.replies = [[FakeEngine.line("d2d4", 20, false, PackedStringArray(["d7d5"])), FakeEngine.line("e2e4", 10)]]
	fake.go_movetime(100)
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(fake, "best_move", ["d2d4"])
	var lines: Array = get_signal_parameters(fake, "search_finished")[1]
	assert_eq(lines.map(func(l): return l.multipv), [1, 2])
	assert_eq(lines[0].pv, PackedStringArray(["d2d4", "d7d5"]))


func test_not_ready_while_a_search_is_pending_and_refuses_everything():
	var fake = _fake_with_position()
	assert_true(fake.is_ready())
	assert_true(fake.go_movetime(100))
	assert_false(fake.is_ready())
	assert_false(fake.go_movetime(100)); assert_false(fake.set_position(UciEngine.START_FEN))
	assert_false(fake.new_game()); assert_false(fake.set_full_strength())
	assert_eq(fake.set_strength_elo(1500), -1); assert_eq(fake.set_multipv(3), -1)
	await wait_process_frames(2)
	assert_true(fake.is_ready())
	assert_eq(fake.searches.size(), 1)


func test_configuration_is_applied_and_clamped_when_ready():
	var fake = _fake_with_position()
	assert_true(fake.new_game()); assert_true(fake.set_full_strength())
	assert_eq(fake.set_strength_elo(800), UciEngine.ELO_MIN)
	assert_eq(fake.set_multipv(0), 1); assert_eq(fake.set_multipv(99), UciEngine.MULTIPV_MAX)


func test_each_search_records_the_position_the_time_and_the_multipv():
	var fake = _fake_with_position()
	fake.go_movetime(100)
	await wait_process_frames(2)
	fake.set_multipv(4)
	fake.set_position(UciEngine.START_FEN, PackedStringArray(["e2e4"]))
	fake.go_movetime(250)
	assert_eq(fake.searches, [
		{"fen": UciEngine.START_FEN, "moves": PackedStringArray(), "ms": 100, "multipv": 1},
		{"fen": UciEngine.START_FEN, "moves": PackedStringArray(["e2e4"]), "ms": 250, "multipv": 4},
	])


func test_default_reply_follows_the_last_position_and_ignores_multipv():
	var fake = _fake_with_position()
	fake.set_multipv(2)
	fake.set_position(UciEngine.START_FEN, PackedStringArray(["e2e4"]))
	fake.go_movetime(100)
	await wait_process_frames(2)
	var lines: Array = get_signal_parameters(fake, "search_finished")[1]
	assert_eq(lines.size(), 20)
	assert_true(lines.all(func(l): return l.value == 0 and not l.is_mate and l.pv.size() == 1))
	assert_eq(get_signal_parameters(fake, "best_move")[0], lines[0].pv[0])


func test_checkmated_position_answers_none():
	var fake = _fake_with_position()
	fake.set_position("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")  # stalemate: no legal move
	fake.go_movetime(100)
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(fake, "best_move", ["(none)"])
	assert_eq(get_signal_parameters(fake, "search_finished")[1], [])


func test_set_position_rejects_what_chess_rules_rejects():
	var fake = _fake_with_position()
	assert_false(fake.set_position("not a fen"))
	assert_false(fake.set_position(UciEngine.START_FEN, PackedStringArray(["e2e5"])))
	assert_false(fake.set_position("4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"))
	assert_true(fake.set_position(UciEngine.START_FEN, PackedStringArray(["e2e4"])))


func test_busy_frames_keep_the_engine_not_ready_one_frame_at_a_time():
	var fake := FakeEngine.new(); add_child_autofree(fake)
	fake.set_process(false)  # drive the frames by hand
	fake.busy_frames = 2
	assert_false(fake.is_ready()); assert_false(fake.go_movetime(100)); assert_false(fake.set_position(UciEngine.START_FEN))
	fake._process(0.0)
	assert_false(fake.is_ready())
	fake._process(0.0)
	assert_true(fake.is_ready())
	assert_eq(fake.searches.size(), 0)


func test_busy_engine_becomes_ready_on_its_own():
	var fake := FakeEngine.new(); add_child_autofree(fake)
	fake.busy_frames = 3
	assert_true(await wait_until(fake.is_ready, 1))


func test_unavailable_engine_never_becomes_ready():
	var fake := FakeEngine.new(); add_child_autofree(fake)
	fake.available = false
	await wait_process_frames(3)
	assert_false(fake.is_ready()); assert_false(fake.go_movetime(100)); assert_false(fake.start())


func test_a_best_move_handler_can_start_the_next_search():
	var fake = _fake_with_position()
	fake.replies = [[FakeEngine.line("e2e4", 30)], [FakeEngine.line("d2d4", 20)]]
	fake.best_move.connect(func(_move): fake.go_movetime(50), CONNECT_ONE_SHOT)
	fake.go_movetime(100)
	await wait_process_frames(4)
	assert_eq(fake.searches.size(), 2)
	assert_signal_emit_count(fake, "search_finished", 2)


func test_shutdown_makes_it_not_ready_and_start_brings_it_back():
	var fake = _fake_with_position()
	fake.shutdown()
	assert_false(fake.is_ready())
	assert_true(fake.start())
	assert_true(fake.is_ready())


func test_results_never_arrive_in_the_frame_of_the_go():
	var fake = _fake_with_position()
	fake.set_process(false)  # drive the frames by hand
	fake.go_movetime(100)
	fake._process(0.0)
	assert_signal_not_emitted(fake, "best_move")
	await wait_process_frames(1)
	fake._process(0.0)
	assert_signal_emitted(fake, "best_move")
