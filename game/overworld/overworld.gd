class_name Overworld
extends Node2D
## The top-down map of the zone. It paints the `ZoneLayout`, stands the unresolved encounters on it
## as sprites, and walks the player to the tile that is tapped, one tile at a time without
## diagonals, around the trees, the water and every enemy. A tap on an enemy walks to the tile
## beside it and asks for the encounter. The HUD, in its own canvas layer, shows the HP and the
## potion button.
##
## A screen that shows this scene calls `setup` before the first frame and again after every
## encounter, and hides the scene while another one is on top: a hidden overworld takes no taps,
## and gives the camera and the HUD back.

## The player stands next to the enemy of encounter `id`, which he tapped.
signal encounter_requested(id: String)
## The player stepped onto an exit tile.
signal zone_cleared()

## The enemies are portraits of 38 px. At half size they stand on a tile and a little over it.
const _ENEMY_SCALE := 0.5
## How long each frame of the walking sheet stays, in seconds.
const _WALK_FRAME_S := 0.1
const _WALK_FRAMES := 4
## The column of the walking sheet that faces each way: down, up, left, right.
const _FACING_COLUMN := {Vector2i.DOWN: 0, Vector2i.UP: 1, Vector2i.LEFT: 2, Vector2i.RIGHT: 3}
const _NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## How long the player takes to cross one tile, in seconds. Tests make it shorter.
var step_seconds := 0.15

var _run: RunState
var _layout: ZoneLayout
## The map as a grid: a tile is solid when it is not ground, or when an unresolved enemy stands on it.
var _grid: AStarGrid2D
## Maps the tile of each unresolved enemy to its encounter id.
var _enemy_tiles := {}
## The last tile the player stepped onto.
var _tile := Vector2i.ZERO
## The tiles still to walk, the next one first.
var _path: Array[Vector2i] = []
## The encounter to request when the walk ends, or "".
var _pending_encounter := ""
var _stepping := false
## The tile the current step ends on.
var _step_target := Vector2i.ZERO
var _step_tween: Tween
var _facing := 0
var _walk_time := 0.0
var _zone_cleared_sent := false

@onready var _ground: TileMapLayer = $Ground
@onready var _enemies: Node2D = $Enemies
@onready var _player: Node2D = $Player
@onready var _hero: Sprite2D = $Player/Hero
@onready var _camera: Camera2D = $Player/Camera2D
@onready var _hud: CanvasLayer = $Hud
@onready var _hp_label: Label = %HpLabel
@onready var _potion_button: Button = %PotionButton


func _ready() -> void:
	_potion_button.pressed.connect(_on_potion_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


## Shows `new_layout` and the encounters of `new_run` that are not resolved yet, and puts the player
## on `new_run.player_tile`. A tile that is not ground, such as the (0, 0) of a run that has not
## moved yet, becomes the layout's start tile, and the run is told. The scene must be in the tree
## already. It can be called again, for the same run or another: whatever it showed is replaced.
func setup(new_run: RunState, new_layout: ZoneLayout) -> void:
	if _run != null and _run.changed.is_connected(_refresh_hud):
		_run.changed.disconnect(_refresh_hud)
	_run = new_run
	_layout = new_layout
	_run.changed.connect(_refresh_hud)
	_stop_walking()
	_zone_cleared_sent = false
	TileLegend.paint(_ground, _layout)
	_spawn_enemies()
	_build_grid()
	_tile = _run.player_tile
	if not _layout.is_ground_walkable(_tile):
		_tile = _layout.start_tile
		_run.set_player_tile(_tile)
	_player.position = _centre_of(_tile)
	_face(Vector2i.UP)
	_limit_camera()
	_refresh_hud()


## Walks the player to `tile` along the shortest path that avoids what is solid. A tap on an
## unresolved enemy walks to the nearest tile beside it that the player can reach, and then emits
## `encounter_requested`. A tap on a tile that is not walkable, or that no path reaches, does
## nothing. During a walk the new path starts where the step under way ends, and replaces what
## was left of the old one.
func tap_tile(tile: Vector2i) -> void:
	if _layout == null or not Rect2i(Vector2i.ZERO, _layout.size).has_point(tile):
		return
	var from := _step_target if _stepping else _tile
	var path: Array[Vector2i] = []
	var encounter_id := ""
	if _enemy_tiles.has(tile):
		path = _path_beside(from, tile)
		encounter_id = _enemy_tiles[tile]
	elif not _grid.is_point_solid(tile):
		path = _grid.get_id_path(from, tile)
	if path.is_empty():
		return
	_path = path.slice(1)
	_pending_encounter = encounter_id
	if not _stepping:
		_begin_next_step()


## The last tile the player stepped onto. During a step, it is still the tile he is leaving.
func player_tile() -> Vector2i:
	return _tile


func _process(delta: float) -> void:
	if _stepping:
		_walk_time += delta
	else:
		_walk_time = 0.0
	_hero.frame_coords = Vector2i(_facing, int(_walk_time / _WALK_FRAME_S) % _WALK_FRAMES)


## A touch, or a click of the left button, is a tap on the tile under it. A mouse event that a touch
## made (the engine emulates one for every touch) is skipped, because the touch itself arrives too.
func _unhandled_input(event: InputEvent) -> void:
	if _layout == null or not is_visible_in_tree():
		return
	var touch := event as InputEventScreenTouch
	var click := event as InputEventMouseButton
	var screen_position: Vector2
	if touch != null and touch.pressed:
		screen_position = touch.position
	elif click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		screen_position = click.position
	else:
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	tap_tile(_tile_at(screen_position))


## The tile under a position of the screen, through the camera.
func _tile_at(screen_position: Vector2) -> Vector2i:
	var world_position := get_global_transform_with_canvas().affine_inverse() * screen_position
	return Vector2i((world_position / TileLegend.TILE_PX).floor())


func _centre_of(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TileLegend.TILE_PX


## The path from `from` to the nearest reachable walkable tile beside `spawn_tile`, or empty when
## none can be reached.
func _path_beside(from: Vector2i, spawn_tile: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for step: Vector2i in _NEIGHBOURS:
		var beside := spawn_tile + step
		if not _grid.region.has_point(beside) or _grid.is_point_solid(beside):
			continue
		var path := _grid.get_id_path(from, beside)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
			best = path
	return best


func _spawn_enemies() -> void:
	# Freed at once, not queued: the sprites are plain nodes, and the old ones must be gone when
	# `setup` returns.
	for child in _enemies.get_children():
		child.free()
	_enemy_tiles.clear()
	for id: String in _run.encounters:
		var encounter: Dictionary = _run.encounters[id]
		if encounter["resolved"] or not _layout.spawns.has(id):
			continue
		var tile: Vector2i = _layout.spawns[id]["tile"]
		_enemy_tiles[tile] = id
		var sprite := Sprite2D.new()
		sprite.name = id
		sprite.texture = load(EnemyRoster.for_encounter(encounter["kind"], id)["sprite"])
		sprite.scale = Vector2.ONE * _ENEMY_SCALE
		sprite.position = _centre_of(tile)
		_enemies.add_child(sprite)


func _build_grid() -> void:
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, _layout.size)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.update()
	for y in _layout.size.y:
		for x in _layout.size.x:
			var tile := Vector2i(x, y)
			_grid.set_point_solid(tile, not _layout.is_ground_walkable(tile))
	for tile: Vector2i in _enemy_tiles:
		_grid.set_point_solid(tile, true)


## The camera stays inside the map, so that no screen shows what is beyond its edge.
func _limit_camera() -> void:
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = _layout.size.x * TileLegend.TILE_PX
	_camera.limit_bottom = _layout.size.y * TileLegend.TILE_PX
	_camera.reset_smoothing()
	_camera.force_update_scroll()


func _stop_walking() -> void:
	if _step_tween != null:
		_step_tween.kill()
	_stepping = false
	_path.clear()
	_pending_encounter = ""


## Starts the next step of the path, or ends the walk: then a pending encounter is requested.
func _begin_next_step() -> void:
	if _path.is_empty():
		var encounter_id := _pending_encounter
		_pending_encounter = ""
		if not encounter_id.is_empty():
			encounter_requested.emit(encounter_id)
		return
	_step_target = _path.pop_front()
	_stepping = true
	_face(_step_target - _tile)
	_step_tween = create_tween()
	_step_tween.tween_property(_player, "position", _centre_of(_step_target), step_seconds)
	_step_tween.finished.connect(_on_step_finished)


## The step is done: the run learns the new tile. Stepping onto an exit ends the walk and the zone.
func _on_step_finished() -> void:
	_stepping = false
	_tile = _step_target
	_run.set_player_tile(_tile)
	if _layout.cell(_tile) == "X":
		_path.clear()
		_pending_encounter = ""
		if not _zone_cleared_sent:
			_zone_cleared_sent = true
			zone_cleared.emit()
		return
	_begin_next_step()


func _face(step: Vector2i) -> void:
	_facing = _FACING_COLUMN.get(step, _facing)


## The HUD is a canvas layer of its own, which a hidden parent does not hide, and the camera would
## go on moving the screens that are shown instead of this one.
func _on_visibility_changed() -> void:
	if not is_inside_tree():
		return
	var shown := is_visible_in_tree()
	_hud.visible = shown
	_camera.enabled = shown
	if shown:
		_camera.make_current()


func _on_potion_pressed() -> void:
	_run.use_potion()


## Brings the HP label and the potion button up to date with the run, by the rules of the battle screen.
func _refresh_hud() -> void:
	_hp_label.text = tr("HP %d/%d") % [_run.hp, Tuning.MAX_HP]
	_potion_button.text = tr("Potion ×%d") % _run.potions
	_potion_button.disabled = _run.potions <= 0 or _run.hp <= 0 or _run.hp >= Tuning.MAX_HP
