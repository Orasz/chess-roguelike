class_name MainMenu
extends Control
## The title screen. "Continue" resumes the saved run, and it is there only when a run is saved.
## Under "New run", one button per preset of `Tuning.RATING_PRESETS` starts a run at that rating.
## The texts are those of the scene, which the controls translate.

## The player chose to resume the saved run.
signal continue_requested()
## The player chose a new run at `rating`.
signal new_run_requested(rating: int)

## Whether there is a saved run to continue. Set it before the menu enters the tree.
var can_continue := false

@onready var _continue_button: Button = %ContinueButton
## Each preset button, with the name of its preset in `Tuning.RATING_PRESETS`.
@onready var _presets := {%BeginnerButton: "Beginner", %ClubButton: "Club", %StrongButton: "Strong"}


func _ready() -> void:
	_continue_button.visible = can_continue
	_continue_button.pressed.connect(continue_requested.emit)
	for button: Button in _presets:
		button.pressed.connect(_on_preset_pressed.bind(_presets[button]))


func _on_preset_pressed(preset: String) -> void:
	new_run_requested.emit(Tuning.RATING_PRESETS[preset])
