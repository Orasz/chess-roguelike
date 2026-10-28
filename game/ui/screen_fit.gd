class_name ScreenFit
extends RefCounted
## How the 720-wide portrait layout fits the phone it runs on. A tall window expands the layout
## downwards; a wide one (a foldable, a tablet) is pillarboxed, because Android 16 draws edge to
## edge and ignores the portrait lock on screens of 600 dp or more. The display's safe area (camera
## hole, gesture bar) becomes margins in viewport units, so nothing tappable sits under them.


## `CONTENT_SCALE_ASPECT_EXPAND` for a window whose width/height ratio is at most
## `Tuning.MAX_EXPAND_ASPECT`, and `CONTENT_SCALE_ASPECT_KEEP` (pillarbox) for a wider one.
static func aspect_for(window: Vector2i) -> Window.ContentScaleAspect:
	if window.y > 0 and float(window.x) / float(window.y) <= Tuning.MAX_EXPAND_ASPECT:
		return Window.CONTENT_SCALE_ASPECT_EXPAND
	return Window.CONTENT_SCALE_ASPECT_KEEP


## The inset of the safe area `safe` (in physical pixels) from each edge of the content, in
## viewport units: `{left, top, right, bottom}`. The content is `viewport` scaled by the smaller
## ratio of `window` to `viewport` and centred in `window`; what lies outside it (the bars of a
## pillarbox) is not content, and where the safe area reaches the content's edge the margin is 0.
static func safe_margins(safe: Rect2i, window: Vector2i, viewport: Vector2) -> Dictionary:
	var scale := minf(window.x / viewport.x, window.y / viewport.y)
	var content := viewport * scale
	var offset := (Vector2(window) - content) / 2.0
	var from := (Vector2(safe.position) - offset) / scale
	var to := (offset + content - Vector2(safe.end)) / scale
	return {
		"left": maxf(from.x, 0.0),
		"top": maxf(from.y, 0.0),
		"right": maxf(to.x, 0.0),
		"bottom": maxf(to.y, 0.0),
	}


## The margins of the display's safe area for `viewport`, on `platform` (an `OS.get_name()`
## value). Zeros when the display reports no safe area, or one that does not lie inside the window:
## a desktop or a headless run, where it is the whole screen. On Android the bottom is then raised
## to `Tuning.ANDROID_MIN_BOTTOM_MARGIN`, see `with_platform_minimum`.
static func current_margins(viewport: Viewport, platform: String = OS.get_name()) -> Dictionary:
	var margins := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var safe := DisplayServer.get_display_safe_area()
	var window := DisplayServer.window_get_size()
	var size := viewport.get_visible_rect().size
	if safe.size != Vector2i.ZERO and Rect2i(Vector2i.ZERO, window).encloses(safe) and size.x > 0.0 and size.y > 0.0:
		margins = safe_margins(safe, window, size)
	return with_platform_minimum(margins, platform)


## `margins` with the bottom raised to `Tuning.ANDROID_MIN_BOTTOM_MARGIN` on Android, and returned
## unchanged elsewhere. Godot reports the safe area of an immersive Android game from the display
## cutout alone, so the hidden navigation bar and the system's gesture zone at the bottom of the
## screen are not part of it, and content there would be swallowed by the swipe-up gesture.
static func with_platform_minimum(margins: Dictionary, platform: String) -> Dictionary:
	if platform != "Android":
		return margins
	var raised := margins.duplicate()
	raised["bottom"] = maxf(margins["bottom"], float(Tuning.ANDROID_MIN_BOTTOM_MARGIN))
	return raised
