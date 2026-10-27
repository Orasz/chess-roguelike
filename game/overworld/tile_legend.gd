class_name TileLegend
extends RefCounted
## Draws a `ZoneLayout` with the Ninja Adventure tiles (see CREDITS.md): it builds the `TileSet` in
## code and maps each legend character of `ZoneLayout` to a tile.
##
## No single atlas of the pack holds grass, a path, trees, water, a bridge and a door, so the
## `TileSet` has one atlas source per image: the floor, the nature, the water and the house
## tilesets. A tile is named by a `Vector3i(source, column, row)`, with the source ids below.
##
## Trees, tall grass and doors have see-through corners, so they are drawn on a second layer, an
## `Overlay` child of the painted layer, over the grass or path they stand on.

## The side of a tile, in pixels. Every atlas is a grid of tiles this size.
const TILE_PX := 16

const SOURCE_FLOOR := 0
const SOURCE_NATURE := 1
const SOURCE_WATER := 2
const SOURCE_HOUSE := 3

const _ATLASES := {
	SOURCE_FLOOR: "res://assets/ninja_adventure/tilesets/floor.png",
	SOURCE_NATURE: "res://assets/ninja_adventure/tilesets/nature.png",
	SOURCE_WATER: "res://assets/ninja_adventure/tilesets/water.png",
	SOURCE_HOUSE: "res://assets/ninja_adventure/tilesets/house.png",
}

const GRASS := Vector3i(SOURCE_FLOOR, 0, 12)
## Two grass tiles with a few blades drawn on them, mixed in so that the lawns are not flat.
const GRASS_SPROUTS := Vector3i(SOURCE_FLOOR, 3, 12)
const GRASS_DASHES := Vector3i(SOURCE_FLOOR, 4, 12)
const PATH := Vector3i(SOURCE_FLOOR, 6, 11)
const WATER := Vector3i(SOURCE_WATER, 11, 1)
const BRIDGE := Vector3i(SOURCE_WATER, 1, 13)
const DOOR := Vector3i(SOURCE_HOUSE, 9, 3)
## Two clumps of tall grass, which alternate in a checkerboard.
const TALL_GRASS: Array[Vector3i] = [Vector3i(SOURCE_NATURE, 4, 10), Vector3i(SOURCE_NATURE, 5, 10)]
## The four quarters of one pine: top left, top right, bottom left, bottom right.
const PINE: Array[Vector3i] = [
	Vector3i(SOURCE_NATURE, 2, 0), Vector3i(SOURCE_NATURE, 3, 0),
	Vector3i(SOURCE_NATURE, 2, 1), Vector3i(SOURCE_NATURE, 3, 1),
]

const _OVERLAY_NAME := "Overlay"
const _NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Paints every tile of `layout` on `layer`, replacing what it held: the ground on `layer` itself,
## and the trees, the tall grass and the doors on its `Overlay` child, which is created on the
## first call. Both layers get the same freshly built `TileSet`.
##
## A spawn letter is painted as the ground the encounter stands on: tall grass when most of the
## tiles around it are tall grass, the path when it touches one, and grass otherwise. `@` is the
## path, and `X` a door on the path.
static func paint(layer: TileMapLayer, layout: ZoneLayout) -> void:
	var overlay := layer.get_node_or_null(_OVERLAY_NAME) as TileMapLayer
	if overlay == null:
		overlay = TileMapLayer.new()
		overlay.name = _OVERLAY_NAME
		layer.add_child(overlay)
	var tile_set := _build_tile_set()
	layer.tile_set = tile_set
	overlay.tile_set = tile_set
	layer.clear()
	overlay.clear()
	for y in layout.size.y:
		for x in layout.size.x:
			var tile := Vector2i(x, y)
			var ground := _ground_of(layout, tile)
			_put(layer, tile, _ground_tile(ground, tile))
			if layout.cell(tile) == "X":
				_put(overlay, tile, DOOR)
			elif ground == "#":
				_put(overlay, tile, _tree_tile(layout, tile))
			elif ground == ",":
				_put(overlay, tile, TALL_GRASS[(tile.x + tile.y) % 2])


## The `TileSet`: 16 px tiles, with one atlas source per image holding just the tiles the legend uses.
static func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_PX, TILE_PX)
	var sources := {}
	for source_id: int in _ATLASES:
		var source := TileSetAtlasSource.new()
		source.texture = load(_ATLASES[source_id])
		source.texture_region_size = Vector2i(TILE_PX, TILE_PX)
		sources[source_id] = source
		tile_set.add_source(source, source_id)
	for tile in _all_tiles():
		var source: TileSetAtlasSource = sources[tile.x]
		var coords := Vector2i(tile.y, tile.z)
		if source.get_tile_at_coords(coords) == Vector2i(-1, -1):
			source.create_tile(coords)
	return tile_set


static func _all_tiles() -> Array[Vector3i]:
	var tiles: Array[Vector3i] = [GRASS, GRASS_SPROUTS, GRASS_DASHES, PATH, WATER, BRIDGE, DOOR]
	tiles.append_array(TALL_GRASS)
	tiles.append_array(PINE)
	return tiles


static func _put(layer: TileMapLayer, tile: Vector2i, atlas_tile: Vector3i) -> void:
	layer.set_cell(tile, atlas_tile.x, Vector2i(atlas_tile.y, atlas_tile.z))


## What the ground of `tile` is, as a character: `.`, `,`, `_`, `~`, `=`, or `#` for a tree (which
## stands on grass: the ground tile of `#` is grass).
static func _ground_of(layout: ZoneLayout, tile: Vector2i) -> String:
	var ch := layout.cell(tile)
	if ch == "@" or ch == "X":
		return "_"
	if not MapAssembler.SPAWN_KINDS.has(ch):
		return ch
	var tall := 0
	var path := 0
	for step: Vector2i in _NEIGHBOURS:
		var next := layout.cell(tile + step)
		if next == ",":
			tall += 1
		elif next == "_":
			path += 1
	if tall >= 2:
		return ","
	return "_" if path >= 1 else "."


static func _ground_tile(ground: String, tile: Vector2i) -> Vector3i:
	match ground:
		"_": return PATH
		"~": return WATER
		"=": return BRIDGE
	# Tall grass and trees stand on grass. A fixed mix of the lawn tiles, so that the same zone
	# always looks the same.
	match (tile.x * 7 + tile.y * 13) % 11:
		0, 5: return GRASS_DASHES
		3: return GRASS_SPROUTS
	return GRASS


## The quarter of a pine for the tree at `tile`: the column alternates along the row, and the row
## of the pine alternates down a column of trees, starting with the top at the first tree.
static func _tree_tile(layout: ZoneLayout, tile: Vector2i) -> Vector3i:
	var above := 0
	while above < tile.y and layout.cell(tile + Vector2i(0, -above - 1)) == "#":
		above += 1
	return PINE[(above % 2) * 2 + tile.x % 2]
