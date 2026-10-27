extends GutTest

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const QGA_FEN := "rnbqkbnr/p3pppp/8/1p6/2pP4/4P3/1P3PPP/RNBQKBNR w KQkq - 0 6"


func test_parse_info_cp():
	var e := UciParser.parse_info("info depth 12 seldepth 18 multipv 1 score cp 34 nodes 1000 nps 100000 hashfull 1 tbhits 0 time 10 pv e2e4 e7e5")
	assert_eq([e.depth, e.multipv, e.is_mate, e.value, e.nodes, e.nps, e.time_ms], [12, 1, false, 34, 1000, 100000, 10])
	assert_eq(e.pv, PackedStringArray(["e2e4", "e7e5"]))


func test_parse_info_negative_mate():
	var e := UciParser.parse_info("info depth 5 seldepth 5 multipv 1 score mate -2 nodes 50 nps 5000 time 1 pv g8h8 a1a8")
	assert_true(e.is_mate)
	assert_eq(e.value, -2)


func test_parse_info_skips_bound_and_wdl():
	var e := UciParser.parse_info("info depth 10 multipv 2 score cp -15 upperbound wdl 100 800 100 nodes 9 nps 9 time 1 pv d2d4")
	assert_eq([e.multipv, e.value], [2, -15])
	assert_eq(e.pv, PackedStringArray(["d2d4"]))


func test_parse_info_mate_zero_without_pv():
	var e := UciParser.parse_info("info depth 0 score mate 0")
	assert_true(e.is_mate)
	assert_eq(e.value, 0)
	assert_eq(e.pv.size(), 0)
	assert_eq(e.multipv, 1)


func test_parse_info_ignores_lines_without_score():
	assert_null(UciParser.parse_info("info depth 10 currmove e2e4 currmovenumber 1"))
	assert_null(UciParser.parse_info("info string NNUE evaluation using nn-1a298aa575a0.nnue"))
	assert_null(UciParser.parse_info("readyok"))


func test_parse_bestmove():
	assert_eq(UciParser.parse_bestmove("bestmove e7e8q ponder d1d8"), "e7e8q")
	assert_eq(UciParser.parse_bestmove("bestmove (none)"), "(none)")
	assert_eq(UciParser.parse_bestmove("readyok"), "")


func test_valid_fens():
	assert_true(UciParser.is_valid_fen(START_FEN))
	assert_true(UciParser.is_valid_fen(QGA_FEN))
	assert_true(UciParser.is_valid_fen("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"))


func test_invalid_fens():
	for fen in ["", "not a fen",
			"8/8/8/8/8/8/8/8 w - - 0 1",                                  # no kings
			"rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",  # 9 files
			"rnbqkbnr/pppppppp/8/8/8/8/RNBQKBNR w KQkq - 0 1",            # 7 ranks
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",   # side
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KX - 0 1",     # castling
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e5 0 1",  # en passant rank
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 -1"]: # move number
		assert_false(UciParser.is_valid_fen(fen), fen)


func test_uci_move_syntax():
	for m in ["e2e4", "e7e8q", "a7a8n"]:
		assert_true(UciParser.is_valid_uci_move(m), m)
	for m in ["", "e7e8k", "e9e4", "e2-e4", "e2e4 ", "E2E4"]:
		assert_false(UciParser.is_valid_uci_move(m), m)


func test_trailing_line_break_is_rejected():
	assert_false(UciParser.is_valid_uci_move("e2e4\n"))
	assert_false(UciParser.is_valid_fen(START_FEN + "\n"))
	assert_false(UciParser.is_valid_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w \n - 0 1"))
