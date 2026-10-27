class_name RunEnd
extends Control
## The end of a run: a victory when the player cleared the zone, and a defeat when the HP ran out.
## The run's save is gone by then. "Back to menu" leaves.

## The player pressed "Back to menu".
signal back_requested()

## Whether the player cleared the zone. Set it before the screen enters the tree.
var won := false

@onready var _title: Label = %Title
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_title.text = tr("Victory!") if won else tr("Defeat")
	_back_button.pressed.connect(back_requested.emit)
