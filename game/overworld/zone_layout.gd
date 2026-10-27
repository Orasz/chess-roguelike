class_name ZoneLayout
extends RefCounted
## The zone map, assembled from chunks by `MapAssembler`: one grid of tile characters, where the
## player starts, where the zone ends, and the encounters standing on it. It is data only.
##
## The characters are the chunk legend. Solid: `#` tree, `~` water. Walkable: `.` grass, `,` tall
## grass, `_` path, `=` bridge, `@` start, `X` exit. A spawn letter (`p`, `o`, `t`, `s`) marks the
## tile of an encounter. The ground under it is walkable, but a screen treats the tile as solid
## until the encounter is resolved.

## The characters that nothing can walk through.
const SOLID_CELLS := "#~"

## The map's size in tiles.
var size := Vector2i.ZERO
## The chunks by name, from the bottom of the map to the top, so `start` comes first.
var chunk_order := PackedStringArray()
var start_tile := Vector2i.ZERO
## The `X` tiles, which end the zone.
var exit_tiles: Array[Vector2i] = []
## Maps each encounter id (`"<x>_<y>"`, in zone coordinates) to `{kind, tile, mandatory}`, where
## `kind` is "puzzle", "theory" or "strong". Mandatory encounters stand where the player has to
## beat them to go on.
var spawns := {}
## The tile characters of the whole map, top row first. Read them through `cell`.
var rows := PackedStringArray()


## The character at `tile`, and `"#"` outside the map.
func cell(tile: Vector2i) -> String:
	if tile.x < 0 or tile.y < 0 or tile.x >= size.x or tile.y >= size.y:
		return "#"
	return rows[tile.y][tile.x]


## Whether the ground at `tile` can be walked on, whether or not an encounter stands there.
func is_ground_walkable(tile: Vector2i) -> bool:
	return not SOLID_CELLS.contains(cell(tile))
