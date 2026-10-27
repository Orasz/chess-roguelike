extends GutTest
## The overworld scene: it paints the zone, stands the unresolved encounters on it, and walks the
## player to the tile that was tapped, along a path that never crosses an encounter.

const MIDDLE_ROWS := Vector2i(40, 59)
## How long a walk may take before a test gives up. The steps last 0.01 s each in these tests.
const WALK_TIMEOUT_S := 10.0

var layout: ZoneLayout
var run: RunState
var world: Overworld


func before_each():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	layout = MapAssembler.assemble(MapAssembler.load_chunks(), rng)
	run = RunState.create(7, 1200, "italian_game")
	run.player_tile = layout.start_tile
	for id: String in layout.spawns:
		var spawn: Dictionary = layout.spawns[id]
		run.encounters[id] = {"kind": spawn["kind"], "content": id, "mandatory": spawn["mandatory"], "resolved": false}
	world = (load("res://overworld/overworld.tscn") as PackedScene).instantiate()
	world.step_seconds = 0.01
	add_child_autofree(world)
	world.setup(run, layout)
	watch_signals(world)


## The id of the spawn nearest to the start (the largest y) among those that are mandatory puzzles,
## and the leftmost on its row.
func _first_mandatory_puzzle() -> String:
	var best := ""
	for id: String in layout.spawns:
		var spawn: Dictionary = layout.spawns[id]
		if spawn["kind"] != "puzzle" or not spawn["mandatory"]:
			continue
		if best.is_empty():
			best = id
			continue
		var tile: Vector2i = spawn["tile"]
		var best_tile: Vector2i = layout.spawns[best]["tile"]
		if tile.y > best_tile.y or (tile.y == best_tile.y and tile.x < best_tile.x):
			best = id
	return best


func _strong_tile() -> Vector2i:
	for id: String in layout.spawns:
		if layout.spawns[id]["kind"] == "strong":
			return layout.spawns[id]["tile"]
	return Vector2i(-1, -1)


func _resolve_everything() -> void:
	for id: String in run.encounters:
		run.encounters[id]["resolved"] = true
	world.setup(run, layout)


## Waits until the player stands on `tile`, and returns whether it got there in time.
func _walk_to(tile: Vector2i) -> bool:
	world.tap_tile(tile)
	return await wait_until(func(): return world.player_tile() == tile, WALK_TIMEOUT_S)


## The screen position of the centre of `tile`, through the camera.
func _screen_position_of(tile: Vector2i) -> Vector2:
	var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * TileLegend.TILE_PX
	return world.get_global_transform_with_canvas() * centre


func _touch_at(screen_position: Vector2) -> InputEventScreenTouch:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = screen_position
	return touch


func _click_at(screen_position: Vector2, device := 0) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_position
	click.device = device
	return click


func test_player_starts_at_the_saved_tile():
	var saved := layout.start_tile + Vector2i(0, -3)
	run.player_tile = saved
	world.setup(run, layout)
	assert_eq(world.player_tile(), saved)
	assert_eq((world.get_node("Player") as Node2D).position, (Vector2(saved) + Vector2(0.5, 0.5)) * TileLegend.TILE_PX)


func test_a_new_run_starts_at_the_start_tile():
	run.player_tile = Vector2i.ZERO
	world.setup(run, layout)
	assert_eq(world.player_tile(), layout.start_tile)
	assert_eq(run.player_tile, layout.start_tile, "the run is told, so the save agrees with the screen")


func test_tap_on_an_enemy_walks_next_to_it_and_requests_the_encounter():
	var id := _first_mandatory_puzzle()
	var tile: Vector2i = layout.spawns[id]["tile"]
	world.tap_tile(tile)
	var requested: bool = await wait_for_signal(world.encounter_requested, 5.0)
	assert_true(requested, "the encounter is requested once the player arrives")
	assert_signal_emitted_with_parameters(world, "encounter_requested", [id])
	var gap := (world.player_tile() - tile).abs()
	assert_eq(gap.x + gap.y, 1, "the player stands next to the enemy")


func test_tap_on_an_adjacent_enemy_requests_the_encounter_at_once():
	var id := _first_mandatory_puzzle()
	var tile: Vector2i = layout.spawns[id]["tile"]
	var beside := tile + Vector2i(0, 1)
	assert_true(await _walk_to(beside), "walk to the tile below the enemy")
	assert_signal_emit_count(world, "encounter_requested", 0)
	world.tap_tile(tile)
	assert_signal_emitted_with_parameters(world, "encounter_requested", [id])
	assert_eq(world.player_tile(), beside, "the player did not move")


func test_mandatory_enemy_blocks_the_way_north():
	var wall_y := -1
	for id: String in layout.spawns:
		var tile: Vector2i = layout.spawns[id]["tile"]
		if layout.spawns[id]["mandatory"] and tile.y >= MIDDLE_ROWS.x and tile.y <= MIDDLE_ROWS.y:
			wall_y = tile.y
	assert_gt(wall_y, -1, "the first middle chunk has a mandatory enemy")
	var beyond := Vector2i(layout.start_tile.x, wall_y - 3)
	assert_true(layout.is_ground_walkable(beyond), "the target is a walkable tile north of the wall")
	world.tap_tile(beyond)
	await wait_seconds(1.0)
	assert_gt(world.player_tile().y, wall_y, "the player did not get past the enemy's row")


func test_resolved_encounters_are_gone_and_walkable():
	_resolve_everything()
	assert_eq(world.get_node("Enemies").get_child_count(), 0, "no enemy sprite remains")
	var strong := _strong_tile()
	assert_true(await _walk_to(strong), "the player walks onto the tile the strong enemy stood on")


func test_only_unresolved_encounters_have_a_sprite():
	var id := _first_mandatory_puzzle()
	assert_eq(world.get_node("Enemies").get_child_count(), layout.spawns.size())
	run.encounters[id]["resolved"] = true
	world.setup(run, layout)
	assert_eq(world.get_node("Enemies").get_child_count(), layout.spawns.size() - 1)
	assert_false(world.get_node("Enemies").has_node(id))


func test_reaching_the_exit_clears_the_zone():
	_resolve_everything()
	world.tap_tile(layout.exit_tiles[0])
	var cleared: bool = await wait_for_signal(world.zone_cleared, WALK_TIMEOUT_S)
	assert_true(cleared)
	await wait_process_frames(5)
	assert_signal_emit_count(world, "zone_cleared", 1)
	assert_eq(layout.cell(world.player_tile()), "X")


func test_steps_are_written_to_the_run():
	watch_signals(run)
	var target := layout.start_tile + Vector2i(0, -5)
	assert_true(await _walk_to(target))
	assert_eq(run.player_tile, world.player_tile())
	assert_signal_emit_count(run, "changed", 5, "one change per step")


func test_a_new_tap_replaces_the_walk():
	var far := layout.start_tile + Vector2i(0, -8)
	var near := layout.start_tile + Vector2i(0, -2)
	world.tap_tile(far)
	world.tap_tile(near)
	assert_true(await wait_until(func(): return world.player_tile() == near, 5.0))
	await wait_seconds(0.3)
	assert_eq(world.player_tile(), near, "the first walk is gone")
	assert_eq(run.player_tile, near)


func test_a_tap_on_a_tree_or_off_the_map_does_nothing():
	world.tap_tile(Vector2i(0, 0))
	world.tap_tile(Vector2i(-5, 3))
	world.tap_tile(layout.size)
	await wait_seconds(0.2)
	assert_eq(world.player_tile(), layout.start_tile)


func test_a_touch_walks_to_the_tile_under_the_finger():
	var target := layout.start_tile + Vector2i(0, -3)
	world._unhandled_input(_touch_at(_screen_position_of(target)))
	assert_true(await wait_until(func(): return world.player_tile() == target, 5.0))


func test_a_click_walks_unless_a_touch_emulated_it():
	var target := layout.start_tile + Vector2i(0, -3)
	world._unhandled_input(_click_at(_screen_position_of(target), InputEvent.DEVICE_ID_EMULATION))
	await wait_seconds(0.2)
	assert_eq(world.player_tile(), layout.start_tile, "an emulated click is the touch's echo")
	world._unhandled_input(_click_at(_screen_position_of(target)))
	assert_true(await wait_until(func(): return world.player_tile() == target, 5.0))


func test_only_the_left_button_walks():
	var click := _click_at(_screen_position_of(layout.start_tile + Vector2i(0, -3)))
	click.button_index = MOUSE_BUTTON_RIGHT
	world._unhandled_input(click)
	await wait_seconds(0.2)
	assert_eq(world.player_tile(), layout.start_tile)


func test_a_hidden_overworld_ignores_taps_and_gives_the_screen_back():
	world.hide()
	assert_false((world.get_node("Hud") as CanvasLayer).visible, "the HUD is its own canvas, so it is hidden too")
	assert_false((world.get_node("Player/Camera2D") as Camera2D).enabled, "the camera no longer moves the other screens")
	world._unhandled_input(_touch_at(_screen_position_of(layout.start_tile + Vector2i(0, -3))))
	await wait_seconds(0.2)
	assert_eq(world.player_tile(), layout.start_tile)
	world.show()
	assert_true((world.get_node("Hud") as CanvasLayer).visible)
	assert_true((world.get_node("Player/Camera2D") as Camera2D).is_current())


func test_an_overworld_that_starts_hidden_has_no_hud_and_no_camera():
	var hidden: Overworld = (load("res://overworld/overworld.tscn") as PackedScene).instantiate()
	hidden.visible = false
	add_child_autofree(hidden)
	assert_false((hidden.get_node("Hud") as CanvasLayer).visible)
	assert_false((hidden.get_node("Player/Camera2D") as Camera2D).enabled)


func test_the_camera_follows_the_player_inside_the_map():
	var camera: Camera2D = world.get_node("Player/Camera2D")
	assert_eq(camera.zoom, Vector2(3, 3))
	assert_eq(camera.limit_left, 0)
	assert_eq(camera.limit_top, 0)
	assert_eq(camera.limit_right, layout.size.x * TileLegend.TILE_PX)
	assert_eq(camera.limit_bottom, layout.size.y * TileLegend.TILE_PX)
	assert_eq(camera.get_parent(), world.get_node("Player"))


func test_the_hud_shows_the_hp_and_the_potions():
	var label: Label = world.get_node("%HpLabel")
	var button: Button = world.get_node("%PotionButton")
	assert_eq(label.text, "HP 100/100")
	assert_eq(button.text, "Potion ×1")
	assert_true(button.disabled, "no potion at full HP")
	run.take_damage(40)
	assert_eq(label.text, "HP 60/100")
	assert_false(button.disabled)
	button.pressed.emit()
	assert_eq(run.hp, 90)
	assert_eq(label.text, "HP 90/100")
	assert_eq(button.text, "Potion ×0")
	assert_true(button.disabled, "no potion left")


func test_the_potion_button_is_off_when_dead():
	run.potions = 2
	run.take_damage(Tuning.MAX_HP)
	assert_true((world.get_node("%PotionButton") as Button).disabled)


func test_every_tile_of_the_zone_is_painted():
	var ground: TileMapLayer = world.get_node("Ground")
	for y in layout.size.y:
		for x in layout.size.x:
			assert_ne(ground.get_cell_source_id(Vector2i(x, y)), -1, "ground at (%d, %d)" % [x, y])


func test_tall_grass_trees_and_doors_stand_on_the_ground():
	var ground: TileMapLayer = world.get_node("Ground")
	var overlay: TileMapLayer = ground.get_node("Overlay")
	var seen := {}
	for y in layout.size.y:
		for x in layout.size.x:
			var tile := Vector2i(x, y)
			var ch := layout.cell(tile)
			seen[ch] = true
			if "#~.,_=X".contains(ch):
				var stands_on_ground := overlay.get_cell_source_id(tile) != -1
				assert_eq(stands_on_ground, ",#X".contains(ch), "overlay of '%s' at %s" % [ch, tile])
	assert_eq(seen.size(), MapAssembler.KNOWN_CELLS.length(), "the test saw every legend character")


func test_tall_grass_and_path_have_their_own_tiles():
	var ground: TileMapLayer = world.get_node("Ground")
	var overlay: TileMapLayer = ground.get_node("Overlay")
	var tall: Vector2i
	var path: Vector2i
	var grass: Vector2i
	for y in layout.size.y:
		for x in layout.size.x:
			var tile := Vector2i(x, y)
			match layout.cell(tile):
				",": tall = tile
				"_": path = tile
				".": grass = tile
	assert_ne(ground.get_cell_atlas_coords(path), ground.get_cell_atlas_coords(grass), "path is not grass")
	assert_ne(overlay.get_cell_atlas_coords(tall), Vector2i(-1, -1), "tall grass has a tile of its own")
	assert_eq(overlay.get_cell_source_id(grass), -1, "plain grass has nothing on top")
	assert_eq(overlay.get_cell_source_id(path), -1, "the path has nothing on top")
