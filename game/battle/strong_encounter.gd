class_name StrongEncounter
extends Encounter
## A game already under way, which the player must convert within `move_limit` moves. It starts
## from a puzzle record, after the enemy's first move. The enemy's bar is the player's advantage:
## it starts full at the opening evaluation and empties as the advantage grows, and a decisive
## advantage (a fixed gain over the start, see `HpModel.decisive_cp()`) or a mate wins. Each of
## the player's moves costs the win chance it throws away, as HP, and a costly one is explained.
## When the moves run out, the enemy escapes.
##
## One search per enemy turn both charges the player's last move and gives the enemy's answer. Its
## result is applied without a pause, up to the commit, so no save holds the damage without the
## enemy's move: a kill during the search reruns it on resume, and the move is charged once.
##
## After an explained mistake the enemy's reply is saved at once but shown only after
## `mistake_pause_s`, so the arrow and the sentence are read on the position they refer to. A kill
## during that pause resumes on the position after the reply, with nothing left to search.

## How many moves the player has left before the enemy escapes: `move_limit` less the moves made.
## Emitted once `begin()` has shown the position, fresh or restored, and after each accepted move.
signal moves_left(count: int)

## How many moves the player has to win.
var move_limit := Tuning.STRONG_MOVE_LIMIT
## How long the enemy's reply waits after an explained mistake, in seconds. Tests and offline
## tools set it to 0.
var mistake_pause_s := Tuning.MISTAKE_PAUSE_S
## The line played from the record's FEN, starting with the enemy's first move.
var moves := PackedStringArray()

var _content_id := ""
## The FEN that `moves` are played from.
var _root_fen := ""
var _enemy_elo := 0
## The opening evaluation, in centipawns from the player's point of view, or null before it exists.
var _cp_start: Variant = null
## The latest evaluation of the game, in centipawns from the player's point of view. The player's
## next move is charged against it.
var _cp_now := 0
var _player_moves := 0
## The player's best move in the position on the board, from the latest search, or "".
var _hint := ""


## `position` is a puzzle record; the battle starts after its first move. `enemy_elo` sets how
## well the enemy chooses among the engine's lines.
@warning_ignore("shadowed_variable")
func _init(position: Dictionary, run: RunState, engine: UciEngine, enemy_elo: int) -> void:
	self.run = run
	self.engine = engine
	_content_id = String(position["id"])
	_root_fen = String(position["fen"])
	_enemy_elo = enemy_elo
	moves = PackedStringArray(position["moves"]).slice(0, 1)
	_player_white = ChessRules.side_to_move(_position()) == "w"


func begin() -> void:
	_show(_position(), moves[-1])
	moves_left.emit(move_limit - _player_moves)
	if _is_finished():
		enemy_bar.emit(_bar_fraction())
		_repeat_message()
		await get_tree().process_frame
		finished.emit(outcome)
		return
	if _cp_start == null:
		_say(tr("%s blocks the way! Convert your advantage within %d moves.") % [enemy_name, move_limit])
	else:
		enemy_bar.emit(_bar_fraction())
		_repeat_message()
	_commit()
	if not await _prepare_engine():
		if is_inside_tree():
			_withdraw()
		return
	if _cp_start == null:
		if not await _evaluate_opening():
			return
	if _enemy_to_move():
		await _after_player_move()
	else:
		_set_input(true)


func snapshot() -> Dictionary:
	var data := super()
	data["content"] = _content_id
	data["moves"] = Array(moves)
	data["cp_start"] = _cp_start
	data["cp_now"] = _cp_now
	data["player_moves"] = _player_moves
	data["hint"] = _hint
	return data


func restore(saved: Dictionary) -> void:
	super(saved)
	moves = PackedStringArray(saved.get("moves", Array(moves)))
	var cp_start: Variant = saved.get("cp_start")
	if cp_start == null:
		_cp_start = null
	else:
		_cp_start = int(cp_start)
	_cp_now = int(saved.get("cp_now", 0))
	_player_moves = int(saved.get("player_moves", 0))
	_hint = String(saved.get("hint", ""))


func _kind() -> String:
	return "strong"


func _on_player_move(uci: String) -> void:
	moves.append(uci)
	_player_moves += 1
	_commit()
	_show(_position(), uci)
	moves_left.emit(move_limit - _player_moves)
	await _after_player_move()


## The game after the player's move: a mate wins, a draw ends it, and otherwise the enemy answers.
func _after_player_move() -> void:
	match ChessRules.status(_root_fen, moves):
		ChessRules.Status.CHECKMATE:
			enemy_bar.emit(0.0)
			_say(tr("Checkmate! %s is beaten.") % enemy_name)
			_finish(RunState.Outcome.WON)
		ChessRules.Status.ONGOING:
			await _enemy_turn()
		_:
			_finish(RunState.Outcome.DRAWN)


## The enemy's turn: one search of the position after the player's move. The opponent withdraws
## when the search fails.
func _enemy_turn() -> void:
	var lines := await _search()
	if not is_inside_tree():
		return
	if lines.is_empty():
		_withdraw()
	else:
		await _apply_search(lines)


## Charges the player's last move with the search's best line, then the enemy is beaten, escapes,
## or answers with the line `MovePicker` chooses. Nothing waits between the damage and the commit
## that ends each branch, so that commit saves the damage together with what follows it. Only
## after it may the reply wait out the mistake pause.
func _apply_search(lines: Array) -> void:
	var best := _best_line(lines)
	var cp_after := -HpModel.eval_to_cp(best)
	var damage := HpModel.player_damage(_cp_now, cp_after)
	_cp_now = cp_after
	run.take_damage(damage)
	var explained := damage >= Tuning.EXPLAIN_MIN_DAMAGE
	if explained:
		_explain(best)
	enemy_bar.emit(HpModel.enemy_fraction(cp_after, _cp_start))
	if HpModel.is_decisive(cp_after, _cp_start):
		_say(tr("Decisive advantage! %s is beaten.") % enemy_name)
		_finish(RunState.Outcome.WON)
	elif _player_moves >= move_limit:
		run.take_damage(Tuning.STRONG_FAIL_DAMAGE)
		_say(tr("%s escapes!") % enemy_name)
		_finish(RunState.Outcome.LOST)
	else:
		# A run that died with this mistake has no reply to wait for: the run ends over it.
		var pause_s := mistake_pause_s if explained and run.hp > 0 else 0.0
		await _play_enemy_move(lines[MovePicker.choose(lines, _enemy_elo, run.rng)], pause_s)


## Shows the move the player should have played, and why the move played was a mistake. `best` is
## the enemy's best line after it.
func _explain(best: EngineEval) -> void:
	if not _hint.is_empty():
		arrow.emit(_hint)
	var before := ChessRules.fen_after(_root_fen, moves.slice(0, -1))
	var text := ExplanationBuilder.after_mistake(before, moves[-1], best)
	if not text.is_empty():
		_say(text)


## Plays the first move of `chosen`, one of the enemy's lines, and takes the line's evaluation and
## its next move as the new evaluation and hint. A mate ends the game lost and a draw drawn;
## otherwise the player moves. The move is saved first, and then it waits `pause_s` seconds before
## it is shown, unless it ends the game: the arrow and the explanation stay on the player's move
## until then, and the arrow is cleared when the reply appears.
func _play_enemy_move(chosen: EngineEval, pause_s := 0.0) -> void:
	moves.append(chosen.pv[0])
	_cp_now = -HpModel.eval_to_cp(chosen)
	_hint = chosen.pv[1] if chosen.pv.size() > 1 else ""
	_commit()
	var status := ChessRules.status(_root_fen, moves)
	if pause_s > 0.0 and status == ChessRules.Status.ONGOING:
		await get_tree().create_timer(pause_s).timeout
		if not is_inside_tree():
			return
		arrow.emit("")
	_show(_position(), chosen.pv[0])
	match status:
		ChessRules.Status.CHECKMATE:
			_finish(RunState.Outcome.LOST)
		ChessRules.Status.ONGOING:
			_set_input(true)
		_:
			_finish(RunState.Outcome.DRAWN)


## Waits for the engine and starts a new game on it. The real engine is busy again until it
## confirms the new game, so this waits once more. Returns false when the engine is not ready in
## time.
func _prepare_engine() -> bool:
	if not await _wait_for_engine(engine_wait_s):
		return false
	if not engine.new_game():
		return false
	return await _wait_for_engine(engine_wait_s)


## Evaluates the position the player starts from, with the player to move: it sets the opening
## evaluation, fills the enemy's bar and gives the first hint. Returns false when the opponent
## withdrew instead, or the encounter left the tree.
func _evaluate_opening() -> bool:
	var lines := await _search()
	if not is_inside_tree():
		return false
	if lines.is_empty():
		_withdraw()
		return false
	var best := _best_line(lines)
	var cp := HpModel.eval_to_cp(best)
	_cp_start = cp
	_cp_now = cp
	_hint = best.pv[0]
	_commit()
	enemy_bar.emit(_bar_fraction())
	return true


## Searches the position on the board at full strength, for `Tuning.STRONG_CANDIDATES` lines, and
## returns the ones that have a move: every line kept may be played or read for its first move.
## Returns [] when the engine is not ready in time, refuses the configuration or the position,
## never answers, or answers with no line that has a move.
func _search() -> Array:
	if not await _wait_for_engine(engine_wait_s):
		return []
	if not engine.set_full_strength() or engine.set_multipv(Tuning.STRONG_CANDIDATES) < 0:
		return []
	if not engine.set_position(_root_fen, moves):
		return []
	var lines := await _run_search(Tuning.STRONG_SEARCH_MS, engine_wait_s)
	return lines.filter(func(line: EngineEval) -> bool: return not line.pv.is_empty())


## The opponent leaves when the engine fails it: a draw, with no damage.
func _withdraw() -> void:
	_say(tr("The opponent hesitates and withdraws."))
	_finish(RunState.Outcome.DRAWN)


func _finish(result: int) -> void:
	outcome = result
	_commit()
	finished.emit(outcome)


## How full the enemy's bar is for the state as saved: empty once won, full before the opening
## evaluation, and otherwise where the latest evaluation puts it.
func _bar_fraction() -> float:
	if outcome == RunState.Outcome.WON:
		return 0.0
	if _cp_start == null:
		return 1.0
	return HpModel.enemy_fraction(_cp_now, _cp_start)


func _enemy_to_move() -> bool:
	return (ChessRules.side_to_move(_fen) == "w") != _player_white


## The position after `moves`.
func _position() -> String:
	return ChessRules.fen_after(_root_fen, moves)


## The line with the highest evaluation for the side to move; the first one on ties.
static func _best_line(lines: Array) -> EngineEval:
	var best: EngineEval = lines[0]
	for line: EngineEval in lines:
		if HpModel.eval_to_cp(line) > HpModel.eval_to_cp(best):
			best = line
	return best
