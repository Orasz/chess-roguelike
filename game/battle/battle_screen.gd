class_name BattleScreen
extends Control
## The battle screen, laid out like a monster-battle game: the enemy's plate (name, HP bar and
## portrait), the chessboard, the player's plate, the item bar and the dialogue box, which takes
## the height that is left. It renders an `Encounter`'s signals and forwards the player's moves
## to it; the encounter decides everything else. When the encounter finishes, the board stops
## and the Continue button appears, and pressing it emits `closed`.

## The player pressed Continue after the encounter finished with `outcome` (a `RunState.Outcome`).
signal closed(outcome: int)

## The side of the board is a whole number of these, so that every 16 px piece is drawn at a whole
## number of screen pixels: 8 squares of 16 px art.
const _BOARD_STEP := 128.0

## The encounter on screen: set by `open()`, and a child of this screen from then on.
var encounter: Encounter

var _run: RunState
## The outcome the encounter finished with, or -1 while it has not.
var _outcome := -1
var _enemy_tween: Tween
var _player_tween: Tween

@onready var _margin: MarginContainer = $Margin
@onready var _enemy_name: Label = %EnemyName
@onready var _enemy_sprite: TextureRect = %EnemySprite
@onready var _enemy_hp: ProgressBar = %EnemyHp
@onready var _board: BoardView = %Board
@onready var _player_hp: ProgressBar = %PlayerHp
@onready var _player_hp_label: Label = %PlayerHpLabel
@onready var _potion_button: Button = %PotionButton
@onready var _dialogue: RichTextLabel = %Dialogue
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	_player_hp.max_value = Tuning.MAX_HP
	_board.move_chosen.connect(_on_move_chosen)
	_potion_button.pressed.connect(_on_potion_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_dialogue.gui_input.connect(_on_dialogue_input)
	resized.connect(_fit_board)
	_fit_board()


## Shows `new_encounter` and starts it: the enemy's name and portrait, the player's HP and
## potions from `new_run`, then the encounter's signals wired to the board, the bars and the
## dialogue, and finally `begin()`. The screen must be in the tree already, since the board needs
## to be ready for the first position. The encounter becomes a child of the screen, so it goes
## when the screen does.
func open(new_encounter: Encounter, new_run: RunState) -> void:
	encounter = new_encounter
	_run = new_run
	_enemy_name.text = encounter.enemy_name
	var kind: String = encounter.snapshot()["kind"]
	_enemy_sprite.texture = load(EnemyRoster.for_encounter(kind, encounter.encounter_id)["sprite"])
	_player_hp.value = _run.hp
	_refresh_player()
	_run.changed.connect(_refresh_player)
	add_child(encounter)
	encounter.board_changed.connect(_on_board_changed)
	encounter.message.connect(_on_message)
	encounter.arrow.connect(_board.show_arrow)
	encounter.enemy_bar.connect(_on_enemy_bar)
	encounter.input_enabled.connect(_on_input_enabled)
	encounter.finished.connect(_on_finished)
	encounter.begin()


## Sizes the board to the largest multiple of `_BOARD_STEP` that fits between the gutters (the
## side margins of `Margin`). The column that holds every row is as wide as the board, so the
## plates and the dialogue line up with its edges, and it is centred.
func _fit_board() -> void:
	var gutters := _margin.get_theme_constant("margin_left") + _margin.get_theme_constant("margin_right")
	var side := maxf(floorf((size.x - gutters) / _BOARD_STEP), 1.0) * _BOARD_STEP
	_board.custom_minimum_size = Vector2.ONE * side


func _on_board_changed(fen: String, last_move: String) -> void:
	_board.show_position(fen, encounter.player_white())
	_board.mark_last_move(last_move)


func _on_message(text: String) -> void:
	_dialogue.text = text
	_dialogue.scroll_to_line(0)


## A drag scrolls the dialogue. A long text, such as an opening's plans, does not fit the box, and
## a RichTextLabel scrolls with its bar or a trackpad but not with a finger.
func _on_dialogue_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_dialogue.get_v_scroll_bar().value -= event.relative.y


func _on_enemy_bar(fraction: float) -> void:
	_enemy_tween = _tween_bar(_enemy_hp, fraction * 100.0, _enemy_tween)


## The player's moves are only taken while the encounter has not finished: a finished encounter
## never gets the board back.
func _on_input_enabled(on: bool) -> void:
	_board.set_interactive(on and _outcome == -1)


func _on_finished(outcome: int) -> void:
	_outcome = outcome
	_board.set_interactive(false)
	_continue_button.show()


## The arrow of the last answer goes when the player moves again.
func _on_move_chosen(uci: String) -> void:
	_board.show_arrow("")
	encounter.submit_move(uci)


func _on_potion_pressed() -> void:
	_run.use_potion()


## Pressing it twice must not close the battle twice.
func _on_continue_pressed() -> void:
	_continue_button.disabled = true
	closed.emit(_outcome)


## Brings the HP label, the HP bar and the potion button up to date with the run.
func _refresh_player() -> void:
	_player_hp_label.text = tr("HP %d/%d") % [_run.hp, Tuning.MAX_HP]
	_potion_button.text = tr("Potion ×%d") % _run.potions
	_potion_button.disabled = not _run.can_use_potion()
	_player_tween = _tween_bar(_player_hp, _run.hp, _player_tween)


## Moves `bar` to `target` over `Tuning.BAR_TWEEN_S`, in place of the move `previous` was still
## making, and returns the new tween.
func _tween_bar(bar: ProgressBar, target: float, previous: Tween) -> Tween:
	if previous != null:
		previous.kill()
	var tween := create_tween()
	tween.tween_property(bar, "value", target, Tuning.BAR_TWEEN_S)
	return tween
