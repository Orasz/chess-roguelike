extends GutTest
## Board is 640 px wide, so a square is 80 px: with white at the bottom, a1 is centred on (40, 600).
const BLACK_PROMOTION := "4k3/8/8/8/8/8/p7/4K3 b - - 0 1"
var board: BoardView

func before_each():
	board = load("res://battle/board_view.tscn").instantiate(); add_child_autofree(board)
	board.size = Vector2(640, 640); board.set_interactive(true); watch_signals(board)

func _moves() -> Array:
	var moves := []
	for i in get_signal_emit_count(board, "move_chosen"):
		moves.append(get_signal_parameters(board, "move_chosen", i)[0])
	return moves

func _touch(position: Vector2, pressed := true) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new(); event.position = position; event.pressed = pressed
	return event

func _click(position: Vector2, pressed := true, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new(); event.position = position; event.pressed = pressed
	event.button_index = button
	return event

func test_tap_own_piece_shows_its_targets_then_moves():
	board.show_position(UciEngine.START_FEN, true); board.tap_square("g1")
	assert_eq(board.target_squares(), PackedStringArray(["f3", "h3"]))
	board.tap_square("f3"); assert_signal_emitted_with_parameters(board, "move_chosen", ["g1f3"])

func test_opponent_pieces_and_inactive_board_ignore_taps():
	board.show_position(UciEngine.START_FEN, true); board.tap_square("g8"); assert_eq(board.selected_square(), "")
	board.set_interactive(false); board.tap_square("g1"); assert_eq(board.selected_square(), "")

func test_castling_en_passant_and_promotion_emit_stockfish_uci():
	board.show_position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", true); board.tap_square("e1"); board.tap_square("g1")
	board.show_position("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", true); board.tap_square("e5"); board.tap_square("d6")
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7"); board.tap_square("e8")
	assert_true(board.get_node("%PromotionPicker").visible); assert_signal_emit_count(board, "move_chosen", 2)
	board.choose_promotion("n")
	assert_eq([get_signal_parameters(board, "move_chosen", 0)[0], get_signal_parameters(board, "move_chosen", 1)[0],
		get_signal_parameters(board, "move_chosen", 2)[0]], ["e1g1", "e5d6", "e7e8n"])

func test_square_at_respects_orientation():
	board.show_position(UciEngine.START_FEN, true); assert_eq(board.square_at(Vector2(1, 1)), "a8")
	board.show_position(UciEngine.START_FEN, false); assert_eq(board.square_at(Vector2(1, 1)), "h1")
	assert_eq(board.square_at(Vector2(700, 1)), "")

func test_square_at_covers_the_whole_board_and_nothing_else():
	board.show_position(UciEngine.START_FEN, true)
	assert_eq(board.square_at(Vector2(639, 639)), "h1")
	assert_eq(board.square_at(Vector2(320, 320)), "e4")
	assert_eq(board.square_at(Vector2(-1, 10)), "")
	assert_eq(board.square_at(Vector2(10, 640)), "")
	board.show_position(UciEngine.START_FEN, false)
	assert_eq(board.square_at(Vector2(639, 639)), "a8")

func test_the_board_is_a_square_drawn_from_the_top_left_of_a_wider_control():
	board.size = Vector2(800, 640)
	board.show_position(UciEngine.START_FEN, true)
	assert_eq(board.square_at(Vector2(639, 639)), "h1")
	assert_eq(board.square_at(Vector2(641, 10)), "")
	board.size = Vector2(640, 400)
	assert_eq(board.square_at(Vector2(399, 399)), "h1")
	assert_eq(board.square_at(Vector2(10, 401)), "")

func test_fen_returns_the_position_shown():
	board.show_position(UciEngine.START_FEN, true)
	assert_eq(board.fen(), UciEngine.START_FEN)

func test_targets_are_empty_until_a_piece_is_selected():
	board.show_position(UciEngine.START_FEN, true)
	assert_eq(board.selected_square(), ""); assert_eq(board.target_squares(), PackedStringArray())
	board.tap_square("e2")
	assert_eq(board.selected_square(), "e2"); assert_eq(board.target_squares(), PackedStringArray(["e3", "e4"]))

func test_tapping_another_own_piece_reselects_and_anything_else_deselects():
	board.show_position(UciEngine.START_FEN, true)
	board.tap_square("g1"); board.tap_square("b1")
	assert_eq(board.selected_square(), "b1"); assert_eq(board.target_squares(), PackedStringArray(["a3", "c3"]))
	board.tap_square("b1")
	assert_eq(board.selected_square(), "", "tapping the selected piece again deselects it")
	board.tap_square("b1"); board.tap_square("e5")
	assert_eq(board.selected_square(), "", "an empty square that is no target deselects")
	board.tap_square("b1"); board.tap_square("")
	assert_eq(board.selected_square(), "", "a tap outside the board deselects")
	board.tap_square("b1"); board.tap_square("g8")
	assert_eq(board.selected_square(), "", "an opponent piece that is no target deselects")
	assert_signal_not_emitted(board, "move_chosen")

func test_a_capture_target_emits_the_capture():
	board.show_position("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1", true)
	board.tap_square("e4"); board.tap_square("d5")
	assert_eq(_moves(), ["e4d5"])

func test_the_move_is_handed_over_and_the_selection_cleared():
	board.show_position(UciEngine.START_FEN, true); board.tap_square("e2"); board.tap_square("e4")
	assert_eq(board.selected_square(), ""); assert_eq(board.target_squares(), PackedStringArray())
	assert_eq(board.fen(), UciEngine.START_FEN, "the board changes only when the screen shows the new position")

func test_black_moves_on_a_flipped_board():
	board.show_position("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", false)
	board.tap_square("e2"); assert_eq(board.selected_square(), "", "white pieces are not selectable on black's turn")
	board.tap_square("e7"); board.tap_square("e5")
	assert_eq(_moves(), ["e7e5"])

func test_show_position_clears_selection_marks_and_picker_but_not_the_arrow():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true)
	board.mark_last_move("a5a4"); board.show_arrow("e1e2")
	board.tap_square("e7"); board.tap_square("e8")
	assert_true(board.get_node("%PromotionPicker").visible)
	assert_eq(board.selected_square(), "e7"); assert_eq(board.last_move(), "a5a4")
	board.show_position(UciEngine.START_FEN, true)
	assert_eq(board.selected_square(), ""); assert_eq(board.target_squares(), PackedStringArray())
	assert_eq(board.last_move(), "")
	assert_false(board.get_node("%PromotionPicker").visible)
	assert_eq(board.arrow(), "e1e2", "the arrow changes only through show_arrow")
	board.show_arrow(""); assert_eq(board.arrow(), "")

func test_mark_last_move_and_show_arrow_are_remembered():
	board.show_position(UciEngine.START_FEN, true)
	board.mark_last_move("e2e4"); board.show_arrow("g1f3")
	assert_eq(board.last_move(), "e2e4"); assert_eq(board.arrow(), "g1f3")
	board.mark_last_move(""); assert_eq(board.last_move(), "")

func test_promotion_picker_offers_the_side_to_moves_pieces_and_a_button_chooses():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7"); board.tap_square("e8")
	var picker: Control = board.get_node("%PromotionPicker")
	assert_true(picker.visible); assert_eq(picker.get_child_count(), 4)
	var white := ["white_queen", "white_rook", "white_bishop", "white_knight"]
	for i in 4:
		var button: Button = picker.get_child(i)
		assert_eq(button.icon, load("res://assets/chess_pieces/%s.png" % white[i]), "button %d" % i)
	(picker.get_child(1) as Button).pressed.emit()
	assert_eq(_moves(), ["e7e8r"]); assert_false(picker.visible)
	assert_eq(board.selected_square(), "")

func test_promotion_picker_uses_black_pieces_for_black():
	board.show_position(BLACK_PROMOTION, true); board.tap_square("a2"); board.tap_square("a1")
	var picker: Control = board.get_node("%PromotionPicker")
	assert_true(picker.visible)
	var black := ["black_queen", "black_rook", "black_bishop", "black_knight"]
	for i in 4:
		assert_eq((picker.get_child(i) as Button).icon, load("res://assets/chess_pieces/%s.png" % black[i]))
	board.choose_promotion("q"); assert_eq(_moves(), ["a2a1q"])

func test_tapping_elsewhere_while_the_picker_is_open_cancels_it():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7"); board.tap_square("e8")
	board.tap_square("a1")
	assert_false(board.get_node("%PromotionPicker").visible); assert_signal_not_emitted(board, "move_chosen")
	assert_eq(board.selected_square(), "")
	board.choose_promotion("q"); assert_signal_not_emitted(board, "move_chosen")
	board.tap_square("e7"); board.tap_square("e8"); board.tap_square("")
	assert_false(board.get_node("%PromotionPicker").visible); assert_signal_not_emitted(board, "move_chosen")

func test_tapping_another_piece_while_the_picker_is_open_cancels_it_and_selects_that_piece():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7"); board.tap_square("e8")
	board.tap_square("e1")
	assert_false(board.get_node("%PromotionPicker").visible); assert_signal_not_emitted(board, "move_chosen")
	assert_eq(board.selected_square(), "e1")
	board.choose_promotion("q"); assert_signal_not_emitted(board, "move_chosen")

func test_choose_promotion_without_a_pending_promotion_does_nothing():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7")
	board.choose_promotion("q"); assert_signal_not_emitted(board, "move_chosen")
	board.tap_square("e8"); board.choose_promotion("k"); assert_signal_not_emitted(board, "move_chosen")
	assert_true(board.get_node("%PromotionPicker").visible, "a bad piece letter leaves the picker open")

func test_switching_the_board_off_closes_the_picker():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7"); board.tap_square("e8")
	board.set_interactive(false)
	assert_false(board.get_node("%PromotionPicker").visible); assert_eq(board.selected_square(), "")
	board.choose_promotion("q"); assert_signal_not_emitted(board, "move_chosen")

func test_input_handles_touch_and_left_click_but_not_emulated_mouse():
	board.show_position(UciEngine.START_FEN, true)
	var g1 := Vector2(6.5 * 80, 7.5 * 80); var f3 := Vector2(5.5 * 80, 5.5 * 80); var h3 := Vector2(7.5 * 80, 5.5 * 80)
	board._gui_input(_click(g1))
	assert_eq(board.selected_square(), "g1", "a real mouse press selects")
	var emulated := _click(f3); emulated.device = InputEvent.DEVICE_ID_EMULATION
	board._gui_input(emulated)
	assert_eq(board.selected_square(), "g1", "the mouse press Godot emulates from a touch is ignored")
	assert_signal_not_emitted(board, "move_chosen")
	board._gui_input(_touch(f3, false)); board._gui_input(_click(f3, false)); board._gui_input(_click(f3, true, MOUSE_BUTTON_RIGHT))
	assert_signal_not_emitted(board, "move_chosen")
	assert_eq(board.selected_square(), "g1", "releases and other buttons are not taps")
	board._gui_input(_touch(h3))
	assert_eq(_moves(), ["g1h3"], "a touch press taps")

func test_input_taps_the_square_under_the_finger():
	board.show_position("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", false)
	board._gui_input(_touch(Vector2(1.5 * 80, 7.5 * 80)))
	assert_eq(board.selected_square(), "g8", "with black at the bottom, g8 is in the second column of the bottom row")

func test_every_mark_and_the_picker_draw_together():
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true)
	board.mark_last_move("a5a4"); board.show_arrow("e1e7")
	board.tap_square("e7"); board.tap_square("e8")
	await wait_process_frames(2)
	assert_true(board.get_node("%PromotionPicker").visible)
