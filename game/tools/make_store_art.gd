extends SceneTree
## Draws the Google Play feature graphic, 1024x500 px, from the game's own art (see CREDITS.md): a
## fragment of the Italian Game on a board, a strip of the overworld, a portrait of the gate's enemy,
## and the title. It shows no human character, so that nothing in it can read as aimed at children. It reads the CC0 chess pieces and the CC0 Ninja Adventure tiles and portraits, and
## writes a 24-bit PNG with no alpha channel, as Play requires:
##
##   godot --headless --path game -s res://tools/make_store_art.gd
##
## The output is deterministic: no randomness, and every pixel-art image is scaled by an integer
## factor with nearest-neighbour sampling, so the art stays crisp and shares one grid with the others.
## The title is drawn glyph by glyph from the text server, which works without a window: it is the
## game's default font (`ThemeDB.fallback_font`, since the project theme sets none). The file is
## committed; run the script again only to change the artwork. It never ships.

const _PIECES := "res://assets/chess_pieces/%s.png"
const _FLOOR := "res://assets/ninja_adventure/tilesets/floor.png"
const _NATURE := "res://assets/ninja_adventure/tilesets/nature.png"
const _ENEMY := "res://assets/ninja_adventure/bosses/demon_cyclop.png"
## The feature graphic sits outside the Godot project, in the repository's `store/` folder.
const _OUTPUT := "../store/graphics/feature_1024x500.png"

const _WIDTH := 1024
const _HEIGHT := 500
## The side of a tile or a piece in the source art, and the scale that makes it 64 px here.
const _TILE_PX := 16
const _SCALE := 4
const _CELL := _TILE_PX * _SCALE
## `TileLegend` names the same tiles: the grass with its two variants, the path, the pine's four quarters
## (top left, top right, bottom left, bottom right) and the two tall-grass clumps.
const _GRASS := Vector2i(0, 12)
const _GRASS_SPROUTS := Vector2i(3, 12)
const _GRASS_DASHES := Vector2i(4, 12)
const _PATH := Vector2i(6, 11)
const _PINE: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)]
const _TALL_GRASS: Array[Vector2i] = [Vector2i(4, 10), Vector2i(5, 10)]
## The cells of 64 px are counted from `_GRID_TOP`, a little below the canvas's top edge, so that the board
## and the path, which share the grid, clear the title's plate. The row of the map that the path runs along.
const _GRID_TOP := 20
const _PATH_ROW := 6

## The board's squares are those of `BoardView`.
const _LIGHT := Color("f0d9b5")
const _DARK := Color("b58863")
## The fragment of the board: files c to g (columns 2 to 6) and ranks 6 down to 3, after 1.e4 e5 2.Nf3 Nc6
## 3.Bc4 Bc5. Each piece is its file letter, its rank and its sprite name.
const _FILES_FROM := 2
const _FILES_COUNT := 5
const _RANKS_TOP := 6
const _RANKS_COUNT := 4
const _BOARD_ORIGIN := Vector2i(64, _GRID_TOP + 2 * _CELL)
const _POSITION: Array[Array] = [
	["c", 6, "black_knight"], ["c", 5, "black_bishop"], ["e", 5, "black_pawn"],
	["c", 4, "white_bishop"], ["e", 4, "white_pawn"], ["f", 3, "white_knight"],
]

## The plates are drawn as the game's theme draws its own.
const _PLATE := Color(0.11, 0.14, 0.2)
const _PLATE_BORDER := Color(0.88, 0.9, 0.94)
const _PLATE_BORDER_PX := 4
const _TITLE := "Chess Roguelike"
const _TITLE_SIZE := 68
const _TITLE_TOP := 12
const _NAME := "Gatekeeper Rook"
const _NAME_SIZE := 24
const _PORTRAIT_SCALE := 6
const _ENEMY_ORIGIN := Vector2i(740, _GRID_TOP + 2 * _CELL)

var _pieces := {}
var _floor: Image
var _nature: Image
## The outer rectangle of every plate drawn, so that the script can check that none touches another.
var _plates: Array[Rect2i] = []


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	var enemy := _load(_ENEMY)
	_floor = _load(_FLOOR)
	_nature = _load(_NATURE)
	for name in ["black_knight", "black_bishop", "black_pawn", "white_bishop", "white_pawn", "white_knight"]:
		_pieces[name] = _load(_PIECES % name)
	if enemy == null or _floor == null or _nature == null or _pieces.values().has(null):
		printerr("make_store_art: cannot read the game's art")
		quit(1)
		return
	var image := Image.create_empty(_WIDTH, _HEIGHT, false, Image.FORMAT_RGBA8)
	_paint_lawn(image)
	_paint_path(image)
	_paint_scenery(image)
	_paint_board(image)
	_paint_enemy(image, enemy)
	_paint_title(image)
	image.convert(Image.FORMAT_RGB8)
	quit(0 if _plates_are_apart() and _save(image, _OUTPUT) else 1)


## Grass over the whole canvas, on the same 64 px grid as the rest, with the blades on a fixed pattern.
func _paint_lawn(image: Image) -> void:
	var tiles: Array[Vector2i] = [_GRASS, _GRASS_SPROUTS, _GRASS, _GRASS_DASHES]
	for row in range(-1, ceili(float(_HEIGHT - _GRID_TOP) / _CELL)):
		for column in range(_WIDTH / _CELL):
			_stamp(image, _floor, tiles[posmod(column + 2 * row, tiles.size())], _cell(column, row))


## The path that runs along the foot of the board and the portrait, edge to edge.
func _paint_path(image: Image) -> void:
	for column in range(_WIDTH / _CELL):
		_stamp(image, _floor, _PATH, _cell(column, _PATH_ROW))


## Two pines and some tall grass between the board and the portrait, on the grass above the path.
func _paint_scenery(image: Image) -> void:
	for origin in [Vector2i(7, 3), Vector2i(9, 3)]:
		for quarter in 4:
			var offset := Vector2i(quarter % 2, quarter / 2)
			_stamp(image, _nature, _PINE[quarter], _cell(origin.x + offset.x, origin.y + offset.y))
	for column in [6, 8, 10]:
		_stamp(image, _nature, _TALL_GRASS[column % 2], _cell(column, 5))


## The top left corner, in pixels, of the cell at `column` and `row` of the map's grid.
func _cell(column: int, row: int) -> Vector2i:
	return Vector2i(column * _CELL, _GRID_TOP + row * _CELL)


func _paint_board(image: Image) -> void:
	var size := Vector2i(_FILES_COUNT, _RANKS_COUNT) * _CELL
	_paint_plate(image, Rect2i(_BOARD_ORIGIN, size), _PLATE_BORDER_PX * 2)
	for row in _RANKS_COUNT:
		for column in _FILES_COUNT:
			var rank_index := _RANKS_TOP - 1 - row
			var dark := (_FILES_FROM + column + rank_index) % 2 == 0
			var square := Rect2i(_BOARD_ORIGIN + Vector2i(column, row) * _CELL, Vector2i(_CELL, _CELL))
			image.fill_rect(square, _DARK if dark else _LIGHT)
	for piece: Array in _POSITION:
		var column: int = (piece[0] as String).unicode_at(0) - "a".unicode_at(0) - _FILES_FROM
		var row: int = _RANKS_TOP - (piece[1] as int)
		_stamp_whole(image, _pieces[piece[2]], _BOARD_ORIGIN + Vector2i(column, row) * _CELL, _SCALE)


func _paint_enemy(image: Image, enemy: Image) -> void:
	var portrait := enemy.get_size() * _PORTRAIT_SCALE
	var border := _PLATE_BORDER_PX * 2
	var name_height := _NAME_SIZE + 24
	var plate := Rect2i(_ENEMY_ORIGIN, Vector2i(portrait.x, portrait.y + name_height))
	_paint_plate(image, plate, border)
	_stamp_whole(image, enemy, _ENEMY_ORIGIN, _PORTRAIT_SCALE)
	var width := _text_width(_NAME, _NAME_SIZE)
	var left := _ENEMY_ORIGIN.x + (portrait.x - width) / 2
	_draw_text(image, _NAME, _NAME_SIZE, Vector2i(left, _ENEMY_ORIGIN.y + portrait.y + 8 + _NAME_SIZE), _PLATE_BORDER)


## The title, centred on a plate at the top, in the game's default font.
func _paint_title(image: Image) -> void:
	var width := _text_width(_TITLE, _TITLE_SIZE)
	var plate := Rect2i((_WIDTH - width) / 2 - 28, _TITLE_TOP, width + 56, _TITLE_SIZE + 36)
	_paint_plate(image, plate, _PLATE_BORDER_PX * 2)
	_draw_text(image, _TITLE, _TITLE_SIZE, Vector2i((_WIDTH - width) / 2, _TITLE_TOP + 14 + _TITLE_SIZE * 3 / 4), _PLATE_BORDER)


## A plate of the theme's colours around `inner`: `margin` px of dark fill with a light border on the
## outside of it. The margin is drawn outside `inner`, which the caller fills.
func _paint_plate(image: Image, inner: Rect2i, margin: int) -> void:
	var outer := inner.grow(margin)
	_plates.append(outer)
	image.fill_rect(outer, _PLATE_BORDER)
	image.fill_rect(outer.grow(-_PLATE_BORDER_PX), _PLATE)
	image.fill_rect(inner, _PLATE)


## Whether every plate lies inside the canvas and clear of the others, with the rectangles printed.
func _plates_are_apart() -> bool:
	var canvas := Rect2i(0, 0, _WIDTH, _HEIGHT)
	var ok := true
	for i in _plates.size():
		print("make_store_art: plate %d is %s" % [i, _plates[i]])
		ok = canvas.encloses(_plates[i]) and ok
		for j in range(i + 1, _plates.size()):
			if _plates[i].intersects(_plates[j]):
				ok = false
	if not ok:
		printerr("make_store_art: a plate leaves the canvas or touches another")
	return ok


## Paints tile `cell` (column, row) of the atlas `source` at `position`, scaled to a 64 px cell.
func _stamp(image: Image, source: Image, cell: Vector2i, position: Vector2i) -> void:
	var tile := source.get_region(Rect2i(cell * _TILE_PX, Vector2i(_TILE_PX, _TILE_PX)))
	_stamp_whole(image, tile, position, _SCALE)


## Paints the whole of `source`, scaled by an integer `scale` with nearest-neighbour sampling.
func _stamp_whole(image: Image, source: Image, position: Vector2i, scale: int) -> void:
	var scaled := source.duplicate() as Image
	scaled.resize(source.get_width() * scale, source.get_height() * scale, Image.INTERPOLATE_NEAREST)
	image.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), position)


## The width in pixels of `text` at `size`.
func _text_width(text: String, size: int) -> int:
	var server := TextServerManager.get_primary_interface()
	var shaped := _shape(server, text, size)
	var width := int(ceil(server.shaped_text_get_size(shaped).x))
	server.free_rid(shaped)
	return width


## Draws `text` in `colour`, with its baseline at `baseline`'s y and its left edge at its x. Each glyph
## is rendered by the text server into its font's texture, an `LA8` image of coverage, and blended.
func _draw_text(image: Image, text: String, size: int, baseline: Vector2i, colour: Color) -> void:
	var server := TextServerManager.get_primary_interface()
	var shaped := _shape(server, text, size)
	var pen := float(baseline.x)
	for glyph: Dictionary in server.shaped_text_get_glyphs(shaped):
		var font: RID = glyph["font_rid"]
		var glyph_size := Vector2i(glyph["font_size"], 0)
		var index: int = glyph["index"]
		server.font_render_glyph(font, glyph_size, index)
		var rect := server.font_get_glyph_uv_rect(font, glyph_size, index)
		if rect.has_area():
			var atlas := server.font_get_texture_image(font, glyph_size, server.font_get_glyph_texture_idx(font, glyph_size, index))
			var offset := server.font_get_glyph_offset(font, glyph_size, index)
			_blend_coverage(image, atlas, Rect2i(rect), Vector2i(roundi(pen + offset.x), baseline.y + roundi(offset.y)), colour)
		pen += glyph["advance"] * glyph["repeat"]
	server.free_rid(shaped)


func _shape(server: TextServer, text: String, size: int) -> RID:
	var shaped := server.create_shaped_text()
	server.shaped_text_add_string(shaped, text, ThemeDB.fallback_font.get_rids(), size)
	server.shaped_text_shape(shaped)
	return shaped


## Blends `colour`, scaled by the coverage of `region` of `atlas`, onto `image` at `position`.
func _blend_coverage(image: Image, atlas: Image, region: Rect2i, position: Vector2i, colour: Color) -> void:
	for y in region.size.y:
		for x in region.size.x:
			var coverage := atlas.get_pixel(region.position.x + x, region.position.y + y).a
			var at := position + Vector2i(x, y)
			if coverage <= 0.0 or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(at):
				continue
			image.set_pixelv(at, image.get_pixelv(at).lerp(colour, coverage))


## Reads a source PNG as it is on disk, as RGBA. The script runs from the project folder, so the source
## is not imported, and `Image.load_from_file` warns when it is given a `res://` path.
func _load(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
	return image


## Writes `image` to `path`, relative to the project folder.
func _save(image: Image, path: String) -> bool:
	var file := ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var error := image.save_png(file)
	if error != OK:
		printerr("make_store_art: cannot write %s (error %d)" % [file, error])
		return false
	print("make_store_art: wrote %s (%dx%d)" % [file, image.get_width(), image.get_height()])
	return true
