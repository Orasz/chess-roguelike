class_name TheoryEncounter
extends Encounter
## An opening taught from its book. The enemy answers with book moves, chosen with the run's
## random numbers. A move that leaves the book is taken back, the book move is shown with an
## arrow and explained with the book's hand-written text, and it costs `Tuning.THEORY_DAMAGE` HP,
## once per position. Playing a line to its end wins.

## The pause before the enemy's reply, in seconds. Tests shorten it.
var opponent_delay_s := Tuning.OPPONENT_DELAY_S
## The moves played so far, all of them in the book.
var moves := PackedStringArray()

var _book: OpeningBook
## The plies (the number of moves played) at which the player already paid for leaving the book.
var _punished: Array = []


@warning_ignore("shadowed_variable")
func _init(book: OpeningBook, run: RunState) -> void:
	self.run = run
	_book = book
	_player_white = book.player_white


func begin() -> void:
	_show(_position(), "" if moves.is_empty() else moves[-1])
	if _is_finished():
		enemy_bar.emit(0.0 if outcome == RunState.Outcome.WON else 1.0)
		_repeat_message()
		await get_tree().process_frame
		finished.emit(outcome)
		return
	enemy_bar.emit(1.0)
	if moves.is_empty():
		_say(_book.plans())
	else:
		_repeat_message()
	_commit()
	if _book.enemy_replies(moves).is_empty():
		_set_input(true)
	else:
		await _reply()


func snapshot() -> Dictionary:
	var data := super()
	data["content"] = _book.id
	data["moves"] = Array(moves)
	data["punished"] = _punished.duplicate()
	return data


func restore(saved: Dictionary) -> void:
	super(saved)
	moves = PackedStringArray(saved.get("moves", []))
	_punished = []
	for ply: Variant in saved.get("punished", []):
		_punished.append(int(ply))


func _kind() -> String:
	return "theory"


func _on_player_move(uci: String) -> void:
	var options := _book.player_options(moves)
	for option: Dictionary in options:
		if option.move == uci:
			await _play_book_move(uci, option.why)
			return
	_leave_the_book(options[0])


## Plays `uci`, a move of the book, whose hand-written explanation is `why`. The player sees it
## before the enemy answers or the encounter is won, and reads why it is the book's move, or that
## the line is complete.
func _play_book_move(uci: String, why: Dictionary) -> void:
	moves.append(uci)
	if _book.is_complete(moves):
		outcome = RunState.Outcome.WON
		_say(tr("Line complete! You played the %s to the end.") % _book.name())
	else:
		_say(_book.text(why))
	_commit()
	_show(_position(), uci)
	if _is_finished():
		enemy_bar.emit(0.0)
		finished.emit(outcome)
	else:
		await _reply()


## The enemy answers with a random book move, after a pause, and the player may move again.
func _reply() -> void:
	await get_tree().create_timer(opponent_delay_s).timeout
	if not is_inside_tree():
		return
	var replies := _book.enemy_replies(moves)
	var reply := replies[run.rng.randi_range(0, replies.size() - 1)]
	moves.append(reply)
	_commit()
	_show(_position(), reply)
	_set_input(true)


## Takes the move back and shows `main`, the book's main move, with its explanation. The first
## time in a position it also costs HP.
func _leave_the_book(main: Dictionary) -> void:
	_show(_fen, "")
	arrow.emit(main.move)
	_say(tr("That leaves the book.") + " " + _book.text(main.why))
	var ply := moves.size()
	if not _punished.has(ply):
		_punished.append(ply)
		run.take_damage(Tuning.THEORY_DAMAGE)
	_commit()
	_set_input(true)


## The position after `moves`.
func _position() -> String:
	return ChessRules.fen_after(_book.start_fen, moves)
