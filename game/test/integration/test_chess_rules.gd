extends GutTest
const START := UciEngine.START_FEN
const ITALIAN := "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
const CHECKED := "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"  # side not to move is in check


func test_start_position():
	var info := ChessRules.inspect(START)
	assert_eq(info.legal.size(), 20); assert_false(info.in_check); assert_eq(info.fen, START)


func test_moves_are_replayed():
	assert_eq(ChessRules.fen_after(START, PackedStringArray(["e2e4", "e7e5"])),
		"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")


func test_invalid_input_returns_empty_and_never_exits():
	assert_true(ChessRules.inspect("not a fen").is_empty())
	assert_true(ChessRules.inspect(START, PackedStringArray(["e2e5"])).is_empty())
	assert_true(ChessRules.inspect(CHECKED).is_empty())
	assert_true(StockfishEngine.inspect_position(CHECKED, PackedStringArray()).is_empty())
	assert_eq(ChessRules.fen_after(START, PackedStringArray(["e2e4\n"])), "")


func test_status():
	var cases := [
		[ChessRules.Status.CHECKMATE, START, ["e2e4","e7e5","f1c4","b8c6","d1h5","g8f6","h5f7"]],
		[ChessRules.Status.STALEMATE, "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", []],
		[ChessRules.Status.DRAW_FIFTY, "4k3/8/8/8/8/8/8/R3K3 w - - 100 80", []],
		[ChessRules.Status.DRAW_REPETITION, START, ["g1f3","g8f6","f3g1","f6g8","g1f3","g8f6","f3g1","f6g8"]],
		[ChessRules.Status.DRAW_MATERIAL, "4k3/8/8/8/8/8/8/4K1N1 w - - 0 1", []],
		[ChessRules.Status.DRAW_MATERIAL, "4k3/8/8/8/8/8/8/4KB2 w - - 0 1", []],
		[ChessRules.Status.ONGOING, "4k3/8/8/8/8/8/8/R3K3 w - - 0 1", []]]
	for c in cases:
		assert_eq(ChessRules.status(c[1], PackedStringArray(c[2])), c[0], str(c))


func test_san():
	for c in [[START, "e2e4", "e4"], [START, "g1f3", "Nf3"], [ITALIAN, "e1g1", "O-O"],
			["rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "e4d5", "exd5"],
			["8/4P3/8/8/k7/8/8/4K3 w - - 0 1", "e7e8q", "e8=Q+"],
			["6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "a1a8", "Ra8#"],
			["4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1", "b1d2", "Nbd2"],
			["4k3/8/8/R7/8/8/8/R3K3 w - - 0 1", "a1a3", "R1a3"],
			["4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6", "exd6"]]:
		assert_eq(ChessRules.san(c[0], c[1]), c[2], c[1])
	assert_eq(ChessRules.san("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "a1a8", false), "Ra8")
	assert_eq(ChessRules.san(START, "e2e5"), "")


func test_board_helpers():
	assert_eq(ChessRules.piece_at(START, "e1"), "K"); assert_eq(ChessRules.piece_at(START, "e4"), "")
	assert_eq(ChessRules.side_to_move(ITALIAN), "w"); assert_eq(ChessRules.material(START, "b"), 3900)
