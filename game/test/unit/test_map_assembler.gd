extends GutTest

const SCRATCH_DIR := "user://test_chunks"
const MIDDLES := ["bridge", "clearing", "grove"]
const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


func after_each():
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	for file_name in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(SCRATCH_DIR.path_join(file_name))
	DirAccess.remove_absolute(SCRATCH_DIR)


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## A copy of a shipped chunk with one of its rows replaced.
func _with_row(chunk_name: String, index: int, row: String) -> Dictionary:
	var chunk: Dictionary = MapAssembler.load_chunks()[chunk_name].duplicate(true)
	chunk["rows"][index] = row
	return chunk


## Every layout the slice can assemble: the start, two of the middles in either order, the gate.
func _all_layouts() -> Array[ZoneLayout]:
	var chunks := MapAssembler.load_chunks()
	var layouts: Array[ZoneLayout] = []
	for first in MIDDLES:
		for second in MIDDLES:
			if first != second:
				layouts.append(MapAssembler.rebuild(chunks, PackedStringArray(["start", first, second, "gate"])))
	return layouts


## The tiles of the spawns that pass `keep`, as a set.
func _spawn_tiles(layout: ZoneLayout, keep: Callable) -> Dictionary:
	var tiles := {}
	for spawn: Dictionary in layout.spawns.values():
		if keep.call(spawn):
			tiles[spawn.tile] = true
	return tiles


## The tiles the player can walk to from the start, never stepping on `blocked`.
func _reachable(layout: ZoneLayout, blocked: Dictionary) -> Dictionary:
	var seen := {layout.start_tile: true}
	var queue: Array[Vector2i] = [layout.start_tile]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_back()
		for step: Vector2i in STEPS:
			var next := tile + step
			if not seen.has(next) and layout.is_ground_walkable(next) and not blocked.has(next):
				seen[next] = true
				queue.append(next)
	return seen


## One map row as a string.
func _row(layout: ZoneLayout, y: int) -> String:
	var row := ""
	for x in layout.size.x:
		row += layout.cell(Vector2i(x, y))
	return row


func _write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	f.close()


func test_every_chunk_is_valid():
	var chunks := MapAssembler.load_chunks()
	assert_eq(chunks.size(), 5)
	for chunk_name in chunks:
		assert_eq(MapAssembler.validate(chunks[chunk_name]), PackedStringArray(), chunk_name)


func test_chunks_are_keyed_by_the_name_in_their_file():
	var chunks := MapAssembler.load_chunks()
	var names: Array = chunks.keys()
	names.sort()
	assert_eq(names, ["bridge", "clearing", "gate", "grove", "start"])
	for chunk_name in chunks:
		assert_eq(chunks[chunk_name].name, chunk_name)


func test_load_chunks_skips_what_it_cannot_use():
	assert_eq(MapAssembler.load_chunks("res://no_such_directory"), {})
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	_write(SCRATCH_DIR + "/ok.json", JSON.stringify({"name": "ok", "role": "start", "rows": []}))
	_write(SCRATCH_DIR + "/renamed.json", JSON.stringify({"name": "another", "role": "start", "rows": []}))
	_write(SCRATCH_DIR + "/broken.json", "{")
	_write(SCRATCH_DIR + "/notes.txt", "not a chunk")
	assert_eq(MapAssembler.load_chunks(SCRATCH_DIR).keys(), ["ok"])


func test_validate_catches_broken_chunks():
	var bad: Dictionary = MapAssembler.load_chunks()["clearing"].duplicate(true)
	bad.rows = bad.rows.map(func(r): return r.replace("p", "."))
	assert_false(MapAssembler.validate(bad).is_empty(), "no mandatory enemy left")
	assert_false(MapAssembler.validate({"name": "x", "role": "middle", "rows": ["#"]}).is_empty())
	assert_false(MapAssembler.validate({}).is_empty(), "nothing to read")
	var unknown_role: Dictionary = MapAssembler.load_chunks()["clearing"].duplicate(true)
	unknown_role.role = "boss"
	assert_false(MapAssembler.validate(unknown_role).is_empty())
	assert_false(MapAssembler.validate(_with_row("clearing", 3, "##..,o,_,,,..?#")).is_empty(), "unknown tile")


func test_validate_catches_a_mandatory_enemy_that_can_be_walked_around():
	var leaky := _with_row("clearing", 8, "###.###p#######")
	var problems := MapAssembler.validate(leaky)
	assert_eq(problems.size(), 1, str(problems))
	assert_string_contains(problems[0], "mandatory")


func test_validate_catches_a_tile_nobody_can_reach():
	var walled_in := _with_row("start", 17, ".####.....#####")
	var problems := MapAssembler.validate(walled_in)
	assert_eq(problems.size(), 1, str(problems))
	assert_string_contains(problems[0], "reach")


func test_validate_catches_doors_in_the_wrong_place():
	assert_false(MapAssembler.validate(_with_row("clearing", 0, "###############")).is_empty(), "middle: no door north")
	assert_false(MapAssembler.validate(_with_row("clearing", 19, "###############")).is_empty(), "middle: no door south")
	assert_false(MapAssembler.validate(_with_row("gate", 0, "######___######")).is_empty(), "exit: door north")
	assert_false(MapAssembler.validate(_with_row("start", 19, "######___######")).is_empty(), "start: door south")
	assert_false(MapAssembler.validate(_with_row("clearing", 19, "#####.___.#####")).is_empty(), "door too wide")


func test_validate_checks_what_each_role_must_hold():
	assert_false(MapAssembler.validate(_with_row("start", 6, "#.....o_......#")).is_empty(), "start with a spawn")
	assert_false(MapAssembler.validate(_with_row("bridge", 5, "##..,.._..t..##")).is_empty(), "two theory slots")
	assert_false(MapAssembler.validate(_with_row("gate", 12, "#..,,,._.t,,..#")).is_empty(), "exit with a theory slot")
	assert_false(MapAssembler.validate(_with_row("gate", 14, "#..,,.._.,s...#")).is_empty(), "exit with two strong enemies")
	assert_false(MapAssembler.validate(_with_row("clearing", 6, "#......X......#")).is_empty(), "exit marker in a middle")
	assert_false(MapAssembler.validate(_with_row("clearing", 6, "#......@......#")).is_empty(), "start marker in a middle")


func test_assembly_is_seeded_and_complete():
	var chunks := MapAssembler.load_chunks()
	var a := MapAssembler.assemble(chunks, _rng(9))
	var b := MapAssembler.assemble(chunks, _rng(9))
	assert_eq(a.chunk_order, b.chunk_order)
	assert_eq(a.size, Vector2i(15, 80))
	assert_eq([a.chunk_order[0], a.chunk_order[3]], ["start", "gate"])
	var kinds := a.spawns.values().map(func(s): return s.kind)
	assert_eq(kinds.count("theory"), 1)
	assert_eq(kinds.count("strong"), 1)
	assert_gt(kinds.count("puzzle"), 3)
	assert_eq(MapAssembler.rebuild(chunks, a.chunk_order).spawns.keys(), a.spawns.keys())


func test_different_seeds_reach_different_orders():
	var chunks := MapAssembler.load_chunks()
	var orders := {}
	for s in 20:
		orders[str(MapAssembler.assemble(chunks, _rng(s)).chunk_order)] = true
	assert_gt(orders.size(), 1)


func test_assembly_leaves_the_global_random_numbers_alone():
	var chunks := MapAssembler.load_chunks()
	seed(77)
	var expected := randi()
	seed(77)
	MapAssembler.assemble(chunks, _rng(3))
	assert_eq(randi(), expected)


func test_the_two_middles_are_distinct_and_rebuild_keeps_the_order():
	var chunks := MapAssembler.load_chunks()
	for s in 10:
		var layout := MapAssembler.assemble(chunks, _rng(s))
		assert_ne(layout.chunk_order[1], layout.chunk_order[2])
		assert_true(MIDDLES.has(layout.chunk_order[1]) and MIDDLES.has(layout.chunk_order[2]))
		assert_eq(MapAssembler.rebuild(chunks, layout.chunk_order).chunk_order, layout.chunk_order)


func test_a_chunk_set_that_cannot_make_a_zone_gives_no_layout():
	var chunks := MapAssembler.load_chunks()
	assert_null(MapAssembler.rebuild(chunks, PackedStringArray(["start", "nowhere", "gate"])))
	var no_gate := chunks.duplicate()
	no_gate.erase("gate")
	assert_null(MapAssembler.assemble(no_gate, _rng(1)))
	var one_middle := chunks.duplicate()
	one_middle.erase("grove")
	one_middle.erase("bridge")
	assert_null(MapAssembler.assemble(one_middle, _rng(1)))


func test_chunks_stack_with_the_start_at_the_bottom():
	var chunks := MapAssembler.load_chunks()
	var layout := MapAssembler.rebuild(chunks, PackedStringArray(["start", "bridge", "grove", "gate"]))
	assert_eq(layout.start_tile, Vector2i(7, 76))
	assert_eq(layout.cell(layout.start_tile), "@")
	assert_false(layout.exit_tiles.is_empty())
	for tile in layout.exit_tiles:
		assert_eq(layout.cell(tile), "X")
		assert_lt(tile.y, 20, "the gate is the top chunk")
	for y in 20:
		assert_eq(_row(layout, 60 + y), chunks["start"].rows[y], "start row %d" % y)
		assert_eq(_row(layout, 40 + y), chunks["bridge"].rows[y], "first middle row %d" % y)
		assert_eq(_row(layout, 20 + y), chunks["grove"].rows[y], "second middle row %d" % y)
		assert_eq(_row(layout, y), chunks["gate"].rows[y], "gate row %d" % y)


func test_spawns_are_named_by_zone_tile_and_flagged_mandatory_by_kind():
	var layout := MapAssembler.assemble(MapAssembler.load_chunks(), _rng(4))
	for id: String in layout.spawns:
		var spawn: Dictionary = layout.spawns[id]
		var tile: Vector2i = spawn.tile
		assert_eq(id, "%d_%d" % [tile.x, tile.y])
		match layout.cell(tile):
			"p":
				assert_eq([spawn.kind, spawn.mandatory], ["puzzle", true], id)
			"o":
				assert_eq([spawn.kind, spawn.mandatory], ["puzzle", false], id)
			"s":
				assert_eq([spawn.kind, spawn.mandatory], ["strong", true], id)
			"t":
				assert_false(spawn.mandatory, id)
			_:
				fail_test("%s stands on %s, which is not a spawn" % [id, layout.cell(tile)])
	var strong: Array = layout.spawns.values().filter(func(s): return s.kind == "strong")
	assert_lt(strong[0].tile.y, 20, "the guardian is in the gate")


func test_the_lowest_theory_slot_becomes_the_theory_and_the_other_a_puzzle():
	var layout := MapAssembler.rebuild(MapAssembler.load_chunks(), PackedStringArray(["start", "clearing", "bridge", "gate"]))
	var slots: Array[Vector2i] = []
	for spawn: Dictionary in layout.spawns.values():
		if layout.cell(spawn.tile) == "t":
			slots.append(spawn.tile)
	assert_eq(slots.size(), 2)
	slots.sort_custom(func(a: Vector2i, b: Vector2i): return a.y > b.y)
	var lowest: Dictionary = layout.spawns["%d_%d" % [slots[0].x, slots[0].y]]
	var other: Dictionary = layout.spawns["%d_%d" % [slots[1].x, slots[1].y]]
	assert_eq([lowest.kind, lowest.mandatory], ["theory", false])
	assert_eq([other.kind, other.mandatory], ["puzzle", false])
	assert_between(slots[0].y, 40, 59, "the theory is in the first middle chunk")


func test_cell_is_solid_outside_the_map_and_ground_ignores_spawns():
	var layout := MapAssembler.assemble(MapAssembler.load_chunks(), _rng(2))
	for outside in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(15, 0), Vector2i(0, 80)]:
		assert_eq(layout.cell(outside), "#", str(outside))
		assert_false(layout.is_ground_walkable(outside), str(outside))
	assert_true(layout.is_ground_walkable(layout.start_tile))
	for spawn: Dictionary in layout.spawns.values():
		assert_true(layout.is_ground_walkable(spawn.tile), "a spawn is ground")
	assert_false(layout.is_ground_walkable(Vector2i(0, 79)), "a tree")
	assert_eq(layout.cell(Vector2i(0, 79)), "#")


func test_the_stacked_zone_is_one_walkable_region():
	for layout in _all_layouts():
		var reachable := _reachable(layout, {})
		var cut_off: Array[Vector2i] = []
		for y in layout.size.y:
			for x in layout.size.x:
				var tile := Vector2i(x, y)
				if layout.is_ground_walkable(tile) and not reachable.has(tile):
					cut_off.append(tile)
		assert_eq(cut_off.size(), 0, "%s cut off: %s" % [layout.chunk_order, cut_off])
		assert_true(reachable.has(layout.exit_tiles[0]), "the gate leads to X")


func test_unresolved_mandatory_enemies_wall_off_everything_beyond():
	for layout in _all_layouts():
		var reachable := _reachable(layout, _spawn_tiles(layout, func(_s): return true))
		var first_walls: Array[int] = []
		for spawn: Dictionary in layout.spawns.values():
			if spawn.mandatory and spawn.tile.y >= 40 and spawn.tile.y < 60:
				first_walls.append(spawn.tile.y)
		assert_false(first_walls.is_empty(), "the first middle has a mandatory enemy")
		assert_eq(first_walls.min(), first_walls.max(), "its enemies share one wall row")
		var beyond: Array = reachable.keys().filter(func(t: Vector2i): return t.y <= first_walls[0])
		assert_eq(beyond.size(), 0, "%s reaches past the wall: %s" % [layout.chunk_order, beyond])
		for exit in layout.exit_tiles:
			assert_false(reachable.has(exit))


func test_optional_enemies_block_nothing():
	for layout in _all_layouts():
		var optional := _spawn_tiles(layout, func(s): return not s.mandatory)
		var free := _reachable(layout, {})
		var with_optional_in_the_way := _reachable(layout, optional)
		var cut_off: Array[Vector2i] = []
		for tile: Vector2i in free:
			if not optional.has(tile) and not with_optional_in_the_way.has(tile):
				cut_off.append(tile)
		assert_eq(cut_off.size(), 0, "%s cut off by optional enemies: %s" % [layout.chunk_order, cut_off])
