extends GutTest

## The theme tags and names in the priority order the builder promises.
const THEME_ORDER := [
	["backRankMate", "Back-rank mate"], ["smotheredMate", "Smothered mate"], ["mateIn1", "Mate in one"],
	["fork", "Fork"], ["pin", "Pin"], ["skewer", "Skewer"],
	["discoveredAttack", "Discovered attack"], ["doubleCheck", "Double check"],
	["hangingPiece", "Hanging piece"], ["trappedPiece", "Trapped piece"],
	["attraction", "Attraction"], ["deflection", "Deflection"], ["capturingDefender", "Capturing the defender"],
	["interference", "Interference"], ["clearance", "Clearance"],
	["exposedKing", "Exposed king"], ["promotion", "Promotion"],
]
const MATE_FEN := "6k1/5ppp/8/8/8/8/r4PPP/R5K1 b - - 0 1"
## White knight on b4 attacked by the black pawn on c5.
const HANGING_KNIGHT := "4k3/8/8/2p5/1N6/8/8/4K3 w - - 0 1"
## Black pawns on b5 and d5 attack the white pawn on e4 and the white queen on c4.
const TWO_TARGETS := "4k3/8/8/1p1p4/2Q1P3/8/8/7K w - - 0 1"
## Queens face each other on the open d-file; each one is defended by its own rook.
const QUEEN_TRADE := "r2q2k1/p6p/8/8/8/8/P6P/R2Q2K1 w - - 0 1"
## QUEEN_TRADE without the a7 pawn, so the black rook sees down the a-file.
const OPEN_A_FILE := "r2q2k1/7p/8/8/8/8/P6P/R2Q2K1 w - - 0 1"


func _reply(mate: bool, value: int, pv: Array) -> EngineEval:
	var e := EngineEval.new(); e.is_mate = mate; e.value = value; e.pv = PackedStringArray(pv); return e


func test_theme_name_follows_priority_and_skips_generic_tags():
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["opening", "oneMove", "fork", "short"])), "Fork")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["mateIn1", "backRankMate"])), "Back-rank mate")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["oneMove"])), "")


func test_theme_name_is_empty_without_themes():
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray()), "")


func test_every_theme_outranks_the_ones_after_it():
	for i in THEME_ORDER.size():
		var remaining := PackedStringArray()
		for j in range(THEME_ORDER.size() - 1, i - 1, -1):
			remaining.append(THEME_ORDER[j][0])
		assert_eq(ExplanationBuilder.theme_name(remaining), THEME_ORDER[i][1], "from %s" % THEME_ORDER[i][0])


func test_a_piece_taken_by_the_immediate_reply_names_that_move():
	assert_eq(ExplanationBuilder.after_mistake("4k3/8/4p3/8/1N6/8/8/4K3 w - - 0 1", "b4d5",
		_reply(false, 300, ["e6d5"])), "After Nd5, exd5 wins your knight.")


func test_mate_in_one_and_longer_mates():
	var fen := MATE_FEN
	assert_eq(ExplanationBuilder.after_mistake(fen, "a2b2", _reply(true, 1, ["a1a8"])),
		"After Rb2, Ra8 is checkmate.")
	assert_eq(ExplanationBuilder.after_mistake(fen, "a2b2", _reply(true, 3, ["a1a8"])),
		"After Rb2, the opponent has mate in 3.")


func test_generic_sentence_without_material_change():
	assert_eq(ExplanationBuilder.after_mistake(UciEngine.START_FEN, "a2a3", _reply(false, 30, ["e7e5"])),
		"After a3, the best reply is e5.")


func test_material_lost_a_few_plies_later_does_not_name_the_capture():
	# The knight on b4 falls on the opponent's second move, which is not their next move yet.
	var pv := ["e8d8", "d1e1", "c5b4"]
	assert_eq(ExplanationBuilder.after_mistake(HANGING_KNIGHT, "e1d1", _reply(false, 300, pv)),
		"After Kd1, the opponent can win your knight.")


func test_a_queen_taken_on_the_third_ply_is_a_threat_not_a_move():
	# h6 h3 Qxd1+ Kh2: the queen falls on the opponent's second move, and nothing takes it back.
	var pv := ["h7h6", "h2h3", "d8d1", "g1h2"]
	assert_eq(ExplanationBuilder.after_mistake(QUEEN_TRADE, "a2a3", _reply(false, 900, pv)),
		"After a3, the opponent can win your queen.")

func test_a_piece_taken_on_the_first_ply_of_a_longer_line_names_that_move():
	# Qxd1+ is the opponent's next move, whatever follows it.
	var pv := ["d8d1", "g1h2", "h7h6", "h2g3"]
	assert_eq(ExplanationBuilder.after_mistake("r2q2k1/p6p/8/8/8/8/P6P/3Q2K1 w - - 0 1", "a2a3", _reply(false, 900, pv)),
		"After a3, Qxd1 wins your queen.")


func test_an_even_trade_is_not_a_lost_piece():
	# h6 h3 Qxd1+ Rxd1: the mover's fourth-ply recapture evens the queens out.
	var pv := ["h7h6", "h2h3", "d8d1", "a1d1"]
	assert_eq(ExplanationBuilder.after_mistake(QUEEN_TRADE, "a2a3", _reply(false, 30, pv)),
		"After a3, the best reply is h6.")


func test_the_window_ends_on_the_fourth_ply_of_the_line():
	# The recapture on the fourth ply counts; Rxa3 on the fifth, which wins a pawn, does not.
	var pv := ["h7h6", "h2h3", "d8d1", "a1d1", "a8a3"]
	assert_eq(ExplanationBuilder.after_mistake(OPEN_A_FILE, "a2a3", _reply(false, 100, pv)),
		"After a3, the best reply is h6.")


func test_only_four_plies_of_the_line_are_replayed():
	var pv := ["e8d8", "d1e1", "d8e8", "e1d1", "c5b4"]
	assert_eq(ExplanationBuilder.after_mistake(HANGING_KNIGHT, "e1d1", _reply(false, 300, pv)),
		"After Kd1, the best reply is Kd8.")


func test_replay_stops_at_the_first_illegal_move_of_the_line():
	for bad_move in ["e1e5", "zzzz"]:
		var pv := ["e8d8", bad_move, "c5b4"]
		assert_eq(ExplanationBuilder.after_mistake(HANGING_KNIGHT, "e1d1", _reply(false, 300, pv)),
			"After Kd1, the best reply is Kd8.", bad_move)


func test_the_most_valuable_lost_piece_is_named_even_when_a_cheaper_one_falls_first():
	# dxe4 takes a pawn first, the immediate reply; bxc4, two plies later, takes the queen, so the
	# sentence names no move.
	var pv := ["d5e4", "h2g3", "b5c4"]
	assert_eq(ExplanationBuilder.after_mistake(TWO_TARGETS, "h1h2", _reply(false, 900, pv)),
		"After Kh2, the opponent can win your queen.")


func test_black_is_the_mover_when_it_is_black_to_move():
	var fen := "4k3/8/8/8/1n6/2P5/8/4K3 b - - 0 1"
	assert_eq(ExplanationBuilder.after_mistake(fen, "e8d8", _reply(false, 300, ["c3b4"])),
		"After Kd8, cxb4 wins your knight.")


func test_material_the_opponent_gains_without_a_loss_for_the_mover_falls_through():
	# The opponent promotes: the balance drops by 800 but none of the mover's pieces is taken.
	assert_eq(ExplanationBuilder.after_mistake("4k3/8/8/8/8/8/p7/6K1 w - - 0 1", "g1h1", _reply(false, -800, ["a2a1q"])),
		"After Kh1, the best reply is a1=Q.")


func test_a_mate_longer_than_one_needs_no_reply_move():
	assert_eq(ExplanationBuilder.after_mistake(MATE_FEN, "a2b2", _reply(true, 2, [])),
		"After Rb2, the opponent has mate in 2.")


func test_sentence_is_empty_when_the_reply_move_is_missing_or_illegal():
	for pv in [[], ["a1c3"], ["zzzz"]]:
		assert_eq(ExplanationBuilder.after_mistake(MATE_FEN, "a2b2", _reply(true, 1, pv)), "", "mate in 1, %s" % [pv])
		assert_eq(ExplanationBuilder.after_mistake(MATE_FEN, "a2b2", _reply(false, 40, pv)), "", "plain, %s" % [pv])
		assert_eq(ExplanationBuilder.after_mistake(HANGING_KNIGHT, "e1d1", _reply(false, 300, pv)), "", "hanging, %s" % [pv])


func test_sentence_is_empty_when_the_wrong_move_is_illegal():
	assert_eq(ExplanationBuilder.after_mistake(UciEngine.START_FEN, "a2a5", _reply(false, 30, ["e7e5"])), "")
	assert_eq(ExplanationBuilder.after_mistake(UciEngine.START_FEN, "a2a5", _reply(true, 3, ["e7e5"])), "")
	assert_eq(ExplanationBuilder.after_mistake("not a fen", "a2a3", _reply(false, 30, ["e7e5"])), "")
