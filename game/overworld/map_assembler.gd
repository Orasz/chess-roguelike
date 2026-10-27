class_name MapAssembler
extends RefCounted
## Builds the zone from hand-made chunk files: it loads and checks the chunks, and stacks the
## start chunk, two of the middle chunks in a seeded order, and the exit chunk into a
## `ZoneLayout`.
##
## A chunk file is `{"name", "role": "start"|"middle"|"exit", "rows": [20 strings of 15
## characters]}`, written in the legend of `ZoneLayout`, plus the spawns: `p` a mandatory puzzle,
## `o` an optional puzzle, `t` a theory slot, `s` the strong enemy. Chunks meet at doors, in
## columns 6 to 8 of the top and bottom rows. The start chunk has no door south and the exit
## chunk none north.

const CHUNK_SIZE := Vector2i(15, 20)
const DOOR_FIRST := 6
const DOOR_LAST := 8
## How many of the middle chunks a zone holds.
const MIDDLES_PER_ZONE := 2

const ROLE_START := "start"
const ROLE_MIDDLE := "middle"
const ROLE_EXIT := "exit"
const ROLES := [ROLE_START, ROLE_MIDDLE, ROLE_EXIT]

## Every character a chunk may hold.
const KNOWN_CELLS := "#~.,_=@Xpots"
## The kind of each spawn letter. A `t` is a puzzle until `_index_markers` promotes the lowest.
const SPAWN_KINDS := {"p": "puzzle", "o": "puzzle", "t": "puzzle", "s": "strong"}
## The spawns the player has to beat to go on. Every other spawn is optional.
const MANDATORY_CELLS := "ps"
const NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Loads every `*.json` chunk in `dir`, keyed by the chunk's `"name"`. The name must equal the
## file's name without the extension. Files that cannot be read, are not a JSON object or break
## that rule are skipped, so callers check that the chunks they need are present.
static func load_chunks(dir := "res://overworld/chunks") -> Dictionary:
	var chunks := {}
	var access := DirAccess.open(dir)
	if access == null:
		return chunks
	for file_name in access.get_files():
		if file_name.get_extension() != "json":
			continue
		var chunk := _read_chunk(dir.path_join(file_name))
		if chunk.get("name") == file_name.get_basename():
			chunks[chunk["name"]] = chunk
	return chunks


## The problems of `chunk`, one sentence each. Empty means the chunk is valid:
## - the name, the role and the 20 rows of 15 known characters are there;
## - the doors are where the role says, and the rest of the top and bottom rows is solid;
## - the role holds what it must: a start has one `@` and no spawns, a middle has `p`, `o` and
##   exactly one `t`, an exit has exactly one `s`, an `X` and no `t`;
## - from the entry (`@` in a start, the bottom door elsewhere) every walkable tile and spawn
##   can be reached;
## - in a middle or an exit chunk the exit side (the top door, or an `X`) cannot be reached
##   while `p` and `s` count as solid. That is what makes them mandatory.
static func validate(chunk: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var chunk_name: Variant = chunk.get("name")
	if not chunk_name is String or chunk_name.is_empty():
		problems.append("the chunk has no name")
	var role: Variant = chunk.get("role")
	var role_known := ROLES.has(role)
	if not role_known:
		problems.append("the role must be start, middle or exit")
	var rows := _rows_of(chunk.get("rows"), problems)
	if rows.is_empty() or not role_known:
		return problems
	problems.append_array(_door_problems(rows, role))
	problems.append_array(_content_problems(rows, role))
	problems.append_array(_reachability_problems(rows, role))
	return problems


## Stacks the start chunk at the bottom, then `MIDDLES_PER_ZONE` of the middle chunks in an order
## shuffled with `rng`, then the exit chunk on top. The same seed gives the same zone, because
## the middle names are sorted first. Returns null when `chunks` lacks a start, an exit or
## enough middles.
static func assemble(chunks: Dictionary, rng: RandomNumberGenerator) -> ZoneLayout:
	var starts := _names_with_role(chunks, ROLE_START)
	var middles := _names_with_role(chunks, ROLE_MIDDLE)
	var exits := _names_with_role(chunks, ROLE_EXIT)
	if starts.is_empty() or exits.is_empty() or middles.size() < MIDDLES_PER_ZONE:
		return null
	# Fisher-Yates with the run's generator, never the global one.
	for i in range(middles.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := middles[i]
		middles[i] = middles[j]
		middles[j] = swap
	var order := PackedStringArray([starts[0]])
	order.append_array(middles.slice(0, MIDDLES_PER_ZONE))
	order.append(exits[0])
	return rebuild(chunks, order)


## The zone of a saved `order` (`ZoneLayout.chunk_order`, bottom to top), used on resume. Returns
## null when `order` is empty or names a chunk that `chunks` does not have.
static func rebuild(chunks: Dictionary, order: PackedStringArray) -> ZoneLayout:
	if order.is_empty():
		return null
	for chunk_name in order:
		if not chunks.has(chunk_name):
			return null
	var layout := ZoneLayout.new()
	layout.chunk_order = order
	layout.size = Vector2i(CHUNK_SIZE.x, CHUNK_SIZE.y * order.size())
	for i in range(order.size() - 1, -1, -1):
		for row: String in chunks[order[i]]["rows"]:
			layout.rows.append(row)
	_index_markers(layout)
	return layout


static func _read_chunk(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func _names_with_role(chunks: Dictionary, role: String) -> PackedStringArray:
	var names := PackedStringArray()
	for chunk_name: String in chunks:
		if chunks[chunk_name].get("role") == role:
			names.append(chunk_name)
	names.sort()
	return names


## Reads the start, the exits and the spawns off the stacked rows. Of the `t` slots, the one
## with the largest y, the nearest to the start, becomes the theory encounter.
static func _index_markers(layout: ZoneLayout) -> void:
	var theory_id := ""
	for y in layout.size.y:
		for x in layout.size.x:
			var tile := Vector2i(x, y)
			var ch: String = layout.rows[y][x]
			if ch == "@":
				layout.start_tile = tile
			elif ch == "X":
				layout.exit_tiles.append(tile)
			elif SPAWN_KINDS.has(ch):
				var id := "%d_%d" % [x, y]
				layout.spawns[id] = {
					"kind": SPAWN_KINDS[ch],
					"tile": tile,
					"mandatory": MANDATORY_CELLS.contains(ch),
				}
				if ch == "t":
					theory_id = id
	if not theory_id.is_empty():
		layout.spawns[theory_id]["kind"] = "theory"


# --- validation ---------------------------------------------------------------------------------


## The 20 rows of `value` as strings, or an empty array after adding to `problems` what is wrong.
static func _rows_of(value: Variant, problems: PackedStringArray) -> PackedStringArray:
	var rows := PackedStringArray()
	var before := problems.size()
	if not (value is Array or value is PackedStringArray) or value.size() != CHUNK_SIZE.y:
		problems.append("the chunk needs %d rows" % CHUNK_SIZE.y)
		return rows
	for i in value.size():
		var line: Variant = value[i]
		if not line is String or line.length() != CHUNK_SIZE.x:
			problems.append("row %d must be a string of %d characters" % [i, CHUNK_SIZE.x])
			continue
		for x in line.length():
			if not KNOWN_CELLS.contains(line[x]):
				problems.append("row %d has the unknown character '%s'" % [i, line[x]])
				break
		rows.append(line)
	if problems.size() > before:
		return PackedStringArray()
	return rows


static func _door_problems(rows: PackedStringArray, role: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var top := _door_problem("top", rows[0], role != ROLE_EXIT)
	if not top.is_empty():
		problems.append(top)
	var bottom := _door_problem("bottom", rows[rows.size() - 1], role != ROLE_START)
	if not bottom.is_empty():
		problems.append(bottom)
	return problems


## What is wrong with the door of `row`, or "" when it is right: with a door, the row is walkable
## exactly in the door columns, and without one it is solid.
static func _door_problem(side: String, row: String, has_door: bool) -> String:
	for x in row.length():
		var in_door := x >= DOOR_FIRST and x <= DOOR_LAST
		if _is_walkable(row[x]) != (has_door and in_door):
			if has_door:
				return "the %s row must be walkable exactly in columns %d to %d, the door" % [side, DOOR_FIRST, DOOR_LAST]
			return "the %s row must be solid, because there is no door" % side
	return ""


static func _content_problems(rows: PackedStringArray, role: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var starts := _count(rows, "@")
	var exits := _count(rows, "X")
	var mandatory_puzzles := _count(rows, "p")
	var optional_puzzles := _count(rows, "o")
	var theory_slots := _count(rows, "t")
	var strong := _count(rows, "s")
	match role:
		ROLE_START:
			if starts != 1:
				problems.append("a start chunk needs exactly one '@'")
			if mandatory_puzzles + optional_puzzles + theory_slots + strong > 0:
				problems.append("a start chunk has no spawns")
		ROLE_MIDDLE:
			if mandatory_puzzles < 1:
				problems.append("a middle chunk needs a mandatory puzzle, 'p'")
			if optional_puzzles < 1:
				problems.append("a middle chunk needs an optional puzzle, 'o'")
			if theory_slots != 1:
				problems.append("a middle chunk needs exactly one theory slot, 't'")
		ROLE_EXIT:
			if strong != 1:
				problems.append("an exit chunk needs exactly one strong enemy, 's'")
			if exits < 1:
				problems.append("an exit chunk needs at least one 'X'")
			if theory_slots > 0:
				problems.append("an exit chunk has no theory slot")
	if role != ROLE_START and starts > 0:
		problems.append("only a start chunk has '@'")
	if role != ROLE_EXIT and exits > 0:
		problems.append("only an exit chunk has 'X'")
	if role != ROLE_EXIT and strong > 0:
		problems.append("only an exit chunk has a strong enemy, 's'")
	return problems


static func _reachability_problems(rows: PackedStringArray, role: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var entry: Array[Vector2i] = _find(rows, "@") if role == ROLE_START else _door_tiles(CHUNK_SIZE.y - 1)
	var reached := _flood(rows, entry, "")
	var cut_off := 0
	var first_cut_off := Vector2i.ZERO
	for y in rows.size():
		for x in rows[y].length():
			var tile := Vector2i(x, y)
			if _is_walkable(rows[y][x]) and not reached.has(tile):
				if cut_off == 0:
					first_cut_off = tile
				cut_off += 1
	if cut_off > 0:
		problems.append("%d walkable tiles cannot be reached from the entry, the first at (%d, %d)" % [cut_off, first_cut_off.x, first_cut_off.y])
	if role == ROLE_START:
		return problems
	var exit_side: Array[Vector2i] = _door_tiles(0) if role == ROLE_MIDDLE else _find(rows, "X")
	var past_enemies := _flood(rows, entry, MANDATORY_CELLS)
	for tile in exit_side:
		if past_enemies.has(tile):
			problems.append("the exit side can be reached without beating a mandatory enemy: 'p' and 's' must block the way")
			break
	return problems


## The tiles reachable from `from` in steps without diagonals, never entering a character in
## `blocked`, as a set. Spawns are walkable unless they are in `blocked`.
static func _flood(rows: PackedStringArray, from: Array[Vector2i], blocked: String) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = []
	for tile in from:
		if _is_open(rows, tile, blocked) and not seen.has(tile):
			seen[tile] = true
			queue.append(tile)
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for step: Vector2i in NEIGHBOURS:
			var next := tile + step
			if not seen.has(next) and _is_open(rows, next, blocked):
				seen[next] = true
				queue.append(next)
	return seen


static func _is_open(rows: PackedStringArray, tile: Vector2i, blocked: String) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= CHUNK_SIZE.x or tile.y >= CHUNK_SIZE.y:
		return false
	var ch: String = rows[tile.y][tile.x]
	return _is_walkable(ch) and not blocked.contains(ch)


static func _is_walkable(ch: String) -> bool:
	return not ZoneLayout.SOLID_CELLS.contains(ch)


static func _count(rows: PackedStringArray, ch: String) -> int:
	var n := 0
	for row in rows:
		n += row.count(ch)
	return n


static func _find(rows: PackedStringArray, ch: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == ch:
				tiles.append(Vector2i(x, y))
	return tiles


static func _door_tiles(y: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(DOOR_FIRST, DOOR_LAST + 1):
		tiles.append(Vector2i(x, y))
	return tiles
