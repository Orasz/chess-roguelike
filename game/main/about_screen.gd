class_name AboutScreen
extends Control
## The About screen: the version, the free-software notice, links to the source, the privacy policy
## and the feedback page, and the licences of everything the app ships. The licences are a long
## text, built the first time they are asked for. The texts are those of the scene, which the
## controls translate.

## The player pressed "Back".
signal closed()

const SOURCE_URL := "https://github.com/Orasz/chess-roguelike"
const PRIVACY_URL := "https://github.com/Orasz/chess-roguelike/blob/main/PRIVACY.md"
const FEEDBACK_URL := "https://github.com/Orasz/chess-roguelike/issues"
const _GPL_PATH := "res://legal/GPL-3.0.txt"
const _CREDITS_PATH := "res://legal/CREDITS.md"

## Opens a link. It is the system browser, which needs no permission; tests replace it.
var open_url: Callable = OS.shell_open

@onready var _licences: RichTextLabel = %Licences


func _ready() -> void:
	(%Version as Label).text = tr("Version %s") % ProjectSettings.get_setting("application/config/version")
	(%SourceButton as Button).pressed.connect(func() -> void: open_url.call(SOURCE_URL))
	(%PrivacyButton as Button).pressed.connect(func() -> void: open_url.call(PRIVACY_URL))
	(%FeedbackButton as Button).pressed.connect(func() -> void: open_url.call(FEEDBACK_URL))
	(%LicencesButton as Button).pressed.connect(_show_licences)
	(%BackButton as Button).pressed.connect(closed.emit)
	_licences.gui_input.connect(_on_licences_input)


## Shows the licences, building their text on the first call.
func _show_licences() -> void:
	if _licences.text.is_empty():
		_licences.text = _licences_text()
	_licences.get_v_scroll_bar().value = 0.0
	_licences.show()


## Everything the app ships, in order: the notice and the GPLv3, the credits, each component of the
## engine with its licence, and the texts of those licences.
func _licences_text() -> String:
	var parts: PackedStringArray = [
		(%Notice as Label).text,
		FileAccess.get_file_as_string(_GPL_PATH),
		FileAccess.get_file_as_string(_CREDITS_PATH),
		tr("Components of the Godot Engine"),
	]
	for component: Dictionary in Engine.get_copyright_info():
		var lines: PackedStringArray = [String(component["name"])]
		for part: Dictionary in component["parts"]:
			lines.append("  %s\n  %s, licence: %s" % [
				", ".join(PackedStringArray(part["files"])), ", ".join(PackedStringArray(part["copyright"])),
				part["license"]])
		parts.append("\n".join(lines))
	parts.append(tr("Licence texts"))
	var licences: Dictionary = Engine.get_license_info()
	for licence_name: String in licences:
		parts.append("%s\n\n%s" % [licence_name, String(licences[licence_name]).strip_edges()])
	return "\n\n".join(parts)


## A drag scrolls the licences: a RichTextLabel scrolls with its bar or a trackpad but not with a
## finger.
func _on_licences_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_licences.get_v_scroll_bar().value -= event.relative.y
