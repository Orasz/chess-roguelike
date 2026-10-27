extends GutTest

const MATE_FEN := "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
const FIRST_MOVES := ["a2a3", "a2a4", "b2b3", "b2b4", "c2c3", "c2c4", "d2d3", "d2d4", "e2e3", "e2e4",
	"f2f3", "f2f4", "g2g3", "g2g4", "h2h3", "h2h4", "b1a3", "b1c3", "g1f3", "g1h3"]

var engine: UciEngine


func before_each():
	engine = UciEngine.new()
	add_child_autofree(engine)
	assert_true(engine.start())
	assert_true(await wait_for_signal(engine.ready_ok, 15), "ready_ok")


func after_each():
	if is_instance_valid(engine):
		engine.shutdown()


func test_engine_name_is_stockfish_19():
	assert_true(engine.engine_name.begins_with("Stockfish 19"), engine.engine_name)


func test_bestmove_from_start_is_a_legal_first_move():
	watch_signals(engine)
	assert_true(engine.set_position(UciEngine.START_FEN))
	assert_true(engine.go_movetime(200))
	assert_true(await wait_for_signal(engine.best_move, 10))
	assert_has(FIRST_MOVES, get_signal_parameters(engine, "best_move")[0])
	assert_signal_emitted(engine, "evaluation")


func test_finds_mate_in_one():
	watch_signals(engine)
	engine.set_position(MATE_FEN)
	engine.go_movetime(500)
	await wait_for_signal(engine.best_move, 10)
	assert_eq(get_signal_parameters(engine, "best_move")[0], "a1a8")
	assert_true(engine.last_eval.is_mate)
	assert_eq(engine.last_eval.value, 1)


func test_strength_elo_is_clamped():
	assert_eq(engine.set_strength_elo(800), 1320)
	assert_eq(engine.set_strength_elo(5000), 3190)
	assert_eq(engine.set_strength_elo(1500), 1500)


func test_configuration_is_refused_and_reported_while_searching():
	engine.set_position(UciEngine.START_FEN)
	assert_true(engine.go_movetime(2000))
	assert_eq(engine.set_strength_elo(1500), -1, "nothing applied while searching")
	assert_false(engine.set_full_strength())
	assert_false(engine.new_game())


func test_configuration_is_applied_when_ready():
	assert_true(engine.set_full_strength())
	assert_true(engine.new_game())


func test_go_is_refused_while_searching():
	engine.set_position(UciEngine.START_FEN)
	assert_true(engine.go_movetime(2000))
	assert_false(engine.go_movetime(100), "second go while searching")


func test_invalid_input_is_rejected_and_engine_stays_alive():
	watch_signals(engine)
	assert_false(engine.set_position("not a fen"))
	assert_false(engine.set_position(UciEngine.START_FEN, PackedStringArray(["e2-e4"])))
	assert_true(engine.set_position(UciEngine.START_FEN, PackedStringArray(["e2e4"])))
	engine.go_movetime(100)
	assert_true(await wait_for_signal(engine.best_move, 10), "engine still alive")


func test_positions_stockfish_would_reject_never_reach_it():
	watch_signals(engine)
	# Each of these makes sf_19 call std::exit(1) if it is sent.
	assert_false(engine.set_position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e3 0 1"))
	assert_false(engine.set_position("4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"))
	assert_false(engine.set_position(UciEngine.START_FEN, PackedStringArray(["e2e5"])))
	assert_true(engine.set_position(UciEngine.START_FEN))
	engine.go_movetime(100)
	assert_true(await wait_for_signal(engine.best_move, 10), "engine still alive")


func test_shutdown_from_a_signal_handler_stops_dispatch():
	watch_signals(engine)
	engine.set_process(false)  # let the whole search pile up, then dispatch it in one batch
	engine.set_position(UciEngine.START_FEN)
	engine.go_movetime(200)
	await wait_seconds(1.0)
	engine.evaluation.connect(func(_eval): engine.shutdown(), CONNECT_ONE_SHOT)
	engine._process(0.0)
	assert_signal_not_emitted(engine, "best_move")
	assert_false(engine.is_ready(), "no engine behind it")


func test_free_during_search_then_restart():
	engine.set_position(UciEngine.START_FEN)
	engine.go_movetime(5000)
	var started := Time.get_ticks_msec()
	engine.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(Time.get_ticks_msec() - started, 1000, "freeing must not wait out the 5 s search")
	engine = UciEngine.new()
	add_child_autofree(engine)
	assert_true(engine.start())
	assert_true(await wait_for_signal(engine.ready_ok, 15), "restarted")
