class_name MainMenu
extends Control
## The title screen. "Continue" resumes the saved run, and it is there only when a run is saved.
## Under "New run", one button per preset of `Tuning.RATING_PRESETS` starts a run at that rating.
## When a run is saved, the menu first asks the player to confirm that the saved run will be lost.
## "About" opens the About screen.
## The texts are those of the scene, which the controls translate.

## The player chose to resume the saved run.
signal continue_requested()
## The player chose a new run at `rating`.
signal new_run_requested(rating: int)
## The player chose "About".
signal about_requested()

## Whether there is a saved run to continue. Set it before the menu enters the tree.
var can_continue := false

## The rating of the preset chosen while a run is saved, until the player confirms or cancels.
var _pending_rating := 0

@onready var _continue_button: Button = %ContinueButton
## Each preset button, with the name of its preset in `Tuning.RATING_PRESETS`.
@onready var _presets := {%BeginnerButton: "Beginner", %ClubButton: "Club", %StrongButton: "Strong"}
## The question shown over the menu before a new run replaces the saved one.
@onready var _confirm_new_run: Control = %ConfirmNewRun


func _ready() -> void:
	_continue_button.visible = can_continue
	_continue_button.pressed.connect(continue_requested.emit)
	for button: Button in _presets:
		button.pressed.connect(_on_preset_pressed.bind(_presets[button]))
	(%AboutButton as Button).pressed.connect(about_requested.emit)
	(%StartNewRunButton as Button).pressed.connect(_on_start_new_run_pressed)
	(%CancelButton as Button).pressed.connect(_confirm_new_run.hide)


## The Back button of the phone: closes the new-run question when it is open and returns true, and
## returns false when there is nothing to close.
func handle_back() -> bool:
	if not _confirm_new_run.visible:
		return false
	_confirm_new_run.hide()
	return true


func _on_preset_pressed(preset: String) -> void:
	var rating: int = Tuning.RATING_PRESETS[preset]
	if not can_continue:
		new_run_requested.emit(rating)
		return
	_pending_rating = rating
	_confirm_new_run.show()


func _on_start_new_run_pressed() -> void:
	_confirm_new_run.hide()
	new_run_requested.emit(_pending_rating)
