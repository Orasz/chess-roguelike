class_name PuzzleEncounter
extends Encounter
## One Lichess puzzle. The opponent plays `moves[0]`, then the player must find `moves[1]`, or any
## move that mates. A wrong answer costs `Tuning.PUZZLE_DAMAGE` HP, takes the move back, shows the
## right one with an arrow, and explains the mistake: the puzzle's theme, one sentence built from the
## engine's best reply, and the best move.

## The pause before the opponent's first move, in seconds. Tests shorten it.
var opponent_delay_s := Tuning.OPPONENT_DELAY_S
## How long the explanation waits for the engine, in seconds. Tests shorten it.
var explain_timeout_s := Tuning.EXPLAIN_TIMEOUT_S

var _puzzle: Dictionary
var _moves := PackedStringArray()
## The position the player faces: the puzzle's FEN after the opponent's first move.
var _start_fen := ""


## `puzzle` is a record of the puzzle bank. `engine` explains the mistakes.
@warning_ignore("shadowed_variable")
func _init(puzzle: Dictionary, run: RunState, engine: UciEngine) -> void:
	self.run = run
	self.engine = engine
	_puzzle = puzzle
	_moves = PackedStringArray(puzzle["moves"])
	_start_fen = ChessRules.fen_after(puzzle["fen"], _moves.slice(0, 1))
	_player_white = ChessRules.side_to_move(_start_fen) == "w"


func begin() -> void:
	if _is_finished():
		_show(_fen_after_player(_moves[1]), _moves[1])
		enemy_bar.emit(0.0 if outcome == RunState.Outcome.WON else 1.0)
		_repeat_message()
		await get_tree().process_frame
		finished.emit(outcome)
		return
	_show(_puzzle["fen"], "")
	enemy_bar.emit(1.0)
	_repeat_message()
	_commit()
	await get_tree().create_timer(opponent_delay_s).timeout
	_show(_start_fen, _moves[0])
	_say(tr("%s attacks! Find the best move.") % enemy_name)
	_set_input(true)


func snapshot() -> Dictionary:
	var data := super()
	data["content"] = String(_puzzle["id"])
	return data


func _kind() -> String:
	return "puzzle"


func _on_player_move(uci: String) -> void:
	if uci == _moves[1] or ChessRules.status(_start_fen, PackedStringArray([uci])) == ChessRules.Status.CHECKMATE:
		_win(uci)
	else:
		await _lose(uci)


func _win(uci: String) -> void:
	outcome = RunState.Outcome.WON
	_say(tr("Correct!"))
	_commit()
	_show(_fen_after_player(uci), uci)
	enemy_bar.emit(0.0)
	finished.emit(outcome)


## Charges the mistake, takes the move back and shows the answer, all before the engine is asked
## anything, so that a kill during the search loses only the explanation.
func _lose(wrong_uci: String) -> void:
	run.take_damage(Tuning.PUZZLE_DAMAGE)
	outcome = RunState.Outcome.LOST
	# A kill during the explanation must not resume with the opening line, which is no verdict.
	_message = ""
	_commit()
	_show(_start_fen, "")
	arrow.emit(_moves[1])
	var parts: Array[String] = []
	var theme := ExplanationBuilder.theme_name(PackedStringArray(_puzzle["themes"]))
	if not theme.is_empty():
		parts.append(theme + ".")
	var sentence := await _explain(wrong_uci)
	if not sentence.is_empty():
		parts.append(sentence)
	parts.append(tr("The best move was %s.") % Notation.display(ChessRules.san(_start_fen, _moves[1])))
	_say(" ".join(parts))
	_commit()
	finished.emit(outcome)


## One sentence on why `wrong_uci` was a mistake, from the engine's best reply to it, or "" when
## the engine is not ready in time, refuses the position or the search, or gives no usable line.
func _explain(wrong_uci: String) -> String:
	if not await _wait_for_engine(explain_timeout_s):
		return ""
	if engine.set_multipv(1) < 0 or not engine.set_position(_start_fen, PackedStringArray([wrong_uci])):
		return ""
	var lines := await _run_search(Tuning.EXPLAIN_SEARCH_MS, explain_timeout_s)
	if lines.is_empty():
		return ""
	return ExplanationBuilder.after_mistake(_start_fen, wrong_uci, lines[0])


func _fen_after_player(uci: String) -> String:
	return ChessRules.fen_after(_start_fen, PackedStringArray([uci]))
