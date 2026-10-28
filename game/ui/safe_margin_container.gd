class_name SafeMarginContainer
extends MarginContainer
## A margin container that keeps its content inside the display's safe area. Its own theme margins
## are the base; the inset of the safe area (see `ScreenFit`) is added to them on `_ready` and every
## time the viewport changes size.

## The margins changed: a layout that depends on them has to be redone.
signal margins_changed()

const _SIDES := ["left", "top", "right", "bottom"]

## The margins this container has without the safe area.
var _base := {}


func _ready() -> void:
	for side: String in _SIDES:
		_base[side] = get_theme_constant("margin_" + side)
	get_viewport().size_changed.connect(_refresh)
	_refresh()


## Sets each margin to its base plus `margins` (`{left, top, right, bottom}` in viewport units),
## rounded up to a whole pixel.
func apply_margins(margins: Dictionary) -> void:
	if _base.is_empty():
		for side: String in _SIDES:
			_base[side] = get_theme_constant("margin_" + side)
	for side: String in _SIDES:
		add_theme_constant_override("margin_" + side, _base[side] + ceili(margins[side]))
	margins_changed.emit()


func _refresh() -> void:
	apply_margins(ScreenFit.current_margins(get_viewport()))
