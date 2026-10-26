extends GutTest

var engines: Array = []


func _new_engine() -> StockfishEngine:
	var e := StockfishEngine.new()
	engines.append(e)
	return e


func after_each():
	for e in engines:
		e.stop()
	engines.clear()


func _collect_until(e: StockfishEngine, prefix: String, timeout_s := 10.0) -> PackedStringArray:
	var out := PackedStringArray()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		for line in e.poll_lines():
			out.append(line)
			if line.begins_with(prefix):
				return out
		await get_tree().process_frame
	return out


func test_uci_handshake():
	var e := _new_engine()
	assert_true(e.start())
	e.send("uci")
	var lines := await _collect_until(e, "uciok")
	assert_eq(lines[-1], "uciok")
	assert_true(Array(lines).any(func(l): return l.begins_with("id name Stockfish 19")))


func test_readyok_after_isready():
	var e := _new_engine()
	e.start()
	e.send("isready")
	assert_eq((await _collect_until(e, "readyok"))[-1], "readyok")


func test_every_polled_line_is_complete_uci():
	var e := _new_engine()
	e.start()
	for c in ["uci", "isready", "position startpos", "go depth 12"]:
		e.send(c)
	var lines := await _collect_until(e, "bestmove", 30.0)
	assert_true(lines[-1].begins_with("bestmove "))
	for l in lines:
		if l.is_empty():
			continue  # Stockfish's `uci` reply contains intentional blank lines
		assert_has(["id", "option", "uciok", "readyok", "info", "bestmove"], l.get_slice(" ", 0), l)
		if l.begins_with("info depth") and l.contains(" score "):
			assert_not_null(UciParser.parse_info(l), l)


func test_second_instance_cannot_start():
	var a := _new_engine()
	var b := _new_engine()
	assert_true(a.start())
	assert_false(b.start())
	a.send("isready")
	assert_eq((await _collect_until(a, "readyok"))[-1], "readyok")


func test_restart_after_stop():
	var e := _new_engine()
	e.start()
	e.stop()
	assert_false(e.is_running())
	assert_true(e.start())
	e.send("isready")
	assert_eq((await _collect_until(e, "readyok"))[-1], "readyok")
