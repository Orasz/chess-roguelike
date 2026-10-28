extends SceneTree
## Draws the game's icons from two CC0 sources (see CREDITS.md): the white knight of the pixel chess
## pieces, over a lawn of the Ninja Adventure grass tiles. It writes the project icon, the launcher
## icons the export presets point at (the adaptive foreground, background and monochrome layers), and the
## 512 px Play listing icon:
##
##   godot --headless --path game -s res://tools/make_icons.gd
##
## The output is deterministic: no randomness, and every scale is an integer with nearest-neighbour
## sampling, so the knight's and the lawn's pixels stay square and share one grid. The files are
## committed; run the script again only to change the artwork. It never ships.

const _KNIGHT := "res://assets/chess_pieces/white_knight.png"
const _FLOOR := "res://assets/ninja_adventure/tilesets/floor.png"
## The side of a tile of the floor atlas, and the lawn's tiles in it as (column, row): the plain
## grass, and two with a few blades. `TileLegend` names the same tiles.
const _TILE_PX := 16
const _GRASS := Vector2i(0, 12)
const _GRASS_SPROUTS := Vector2i(3, 12)
const _GRASS_DASHES := Vector2i(4, 12)
## Android's adaptive icons are drawn on 432 px (108 dp at xxxhdpi), and only the centred circle of
## 264 px (66 dp) is safe from every launcher's mask.
const _ADAPTIVE_PX := 432
const _SAFE_CIRCLE_PX := 264
## The files: `res://` path, side in pixels, and what it holds.
const _ICON := "res://assets/icon/icon.png"
const _LAUNCHER := "res://assets/icon/launcher_192.png"
const _ADAPTIVE_FOREGROUND := "res://assets/icon/adaptive_fg_432.png"
const _ADAPTIVE_BACKGROUND := "res://assets/icon/adaptive_bg_432.png"
const _ADAPTIVE_MONOCHROME := "res://assets/icon/adaptive_mono_432.png"
## The Play listing icon sits outside the Godot project, in the repository's `store/` folder.
const _STORE_ICON := "../store/graphics/icon_512.png"

var _knight: Image
var _floor: Image


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	_knight = _load(_KNIGHT)
	_floor = _load(_FLOOR)
	if _knight == null or _floor == null:
		printerr("make_icons: cannot read the knight or the floor tileset")
		quit(1)
		return
	_knight.convert(Image.FORMAT_RGBA8)
	_floor.convert(Image.FORMAT_RGBA8)
	var ok := true
	ok = _save(_composed(256), _ICON) and ok
	ok = _save(_composed(192), _LAUNCHER) and ok
	ok = _save(_composed(512), _STORE_ICON) and ok
	ok = _save(_foreground(_ADAPTIVE_PX), _ADAPTIVE_FOREGROUND) and ok
	ok = _save(_lawn(_ADAPTIVE_PX, _scale_for(_ADAPTIVE_PX)), _ADAPTIVE_BACKGROUND) and ok
	ok = _save(_monochrome(_ADAPTIVE_PX), _ADAPTIVE_MONOCHROME) and ok
	quit(0 if ok else 1)


## The full icon of `side` px: the lawn, with the knight on it.
func _composed(side: int) -> Image:
	var scale := _scale_for(side)
	var image := _lawn(side, scale)
	_stamp_knight(image, scale)
	return image


## The adaptive icon's foreground: the knight alone, with a see-through background.
func _foreground(side: int) -> Image:
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	_stamp_knight(image, _scale_for(side))
	return image


## The adaptive icon's monochrome layer, which Android 13+ tints for themed icons: the foreground's knight, at
## the same scale and place, with every opaque pixel turned opaque white. The launcher reads only its alpha.
func _monochrome(side: int) -> Image:
	var image := _foreground(side)
	for y in side:
		for x in side:
			if image.get_pixel(x, y).a > 0.0:
				image.set_pixel(x, y, Color.WHITE)
	return image


## The largest integer scale at which every opaque pixel of the knight lies inside the safe circle of
## an icon of `side` px (the circle is `_SAFE_CIRCLE_PX / _ADAPTIVE_PX` of the side).
func _scale_for(side: int) -> int:
	var radius := side * float(_SAFE_CIRCLE_PX) / _ADAPTIVE_PX / 2.0
	var bounds := _opaque_bounds(_knight)
	var centre := Vector2(bounds.position) + Vector2(bounds.size) / 2.0
	var scale := 1
	while _farthest_corner(bounds, centre) * (scale + 1) <= radius:
		scale += 1
	return scale


## The farthest distance, in knight pixels, from `centre` to a corner of an opaque pixel.
func _farthest_corner(bounds: Rect2i, centre: Vector2) -> float:
	var farthest := 0.0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if _knight.get_pixel(x, y).a == 0.0:
				continue
			for corner in [Vector2(x, y), Vector2(x + 1, y), Vector2(x, y + 1), Vector2(x + 1, y + 1)]:
				farthest = maxf(farthest, centre.distance_to(corner))
	return farthest


func _opaque_bounds(image: Image) -> Rect2i:
	var used := image.get_used_rect()
	return used if used.has_area() else Rect2i(Vector2i.ZERO, image.get_size())


## Paints the knight, scaled by `scale`, so that the middle of its opaque pixels is the middle of `image`.
## Pixels are placed on the lawn's grid: a multiple of `scale` from the image's top left corner.
func _stamp_knight(image: Image, scale: int) -> void:
	var bounds := _opaque_bounds(_knight)
	var size := bounds.size * scale
	var origin := (image.get_size() - size) / 2 - bounds.position * scale
	var scaled := _knight.duplicate() as Image
	scaled.resize(_knight.get_width() * scale, _knight.get_height() * scale, Image.INTERPOLATE_NEAREST)
	image.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), origin)


## A `side` px lawn: the grass tiles repeated, each source pixel `scale` px wide, so it shares the
## knight's pixel grid. The blades go on a fixed pattern of tiles.
func _lawn(side: int, scale: int) -> Image:
	var tiles: Array[Image] = [_tile(_GRASS), _tile(_GRASS_SPROUTS), _tile(_GRASS), _tile(_GRASS_DASHES)]
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var tile_side := _TILE_PX * scale
	for y in side:
		for x in side:
			var tile := tiles[((x / tile_side) + 2 * (y / tile_side)) % tiles.size()]
			image.set_pixel(x, y, tile.get_pixel((x / scale) % _TILE_PX, (y / scale) % _TILE_PX))
	return image


func _tile(cell: Vector2i) -> Image:
	return _floor.get_region(Rect2i(cell * _TILE_PX, Vector2i(_TILE_PX, _TILE_PX)))


## Reads a source PNG as it is on disk. The script runs from the project folder, so the source is not
## imported, and `Image.load_from_file` warns when it is given a `res://` path.
func _load(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


## Writes `image` to `path`, a `res://` path or a path relative to the project folder.
func _save(image: Image, path: String) -> bool:
	var file := path
	if not path.begins_with("res://"):
		file = ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var error := image.save_png(file)
	if error != OK:
		printerr("make_icons: cannot write %s (error %d)" % [file, error])
		return false
	print("make_icons: wrote %s (%dx%d)" % [file, image.get_width(), image.get_height()])
	return true
