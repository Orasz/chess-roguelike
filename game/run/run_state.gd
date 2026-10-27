class_name RunState
extends RefCounted
## The whole run as data: the player's HP and potions, the seed that shaped the map, the
## encounters on it, and the battle in progress. It is the one thing a save file stores, so
## the app resumes exactly where it was. Every mutation emits `changed`, and the owner saves.

enum Outcome { WON, LOST, DRAWN }

const VERSION := 1
## The kinds of encounter the game builds.
const _ENCOUNTER_KINDS: Array[String] = ["puzzle", "theory", "strong"]

## Emitted after every mutation of the run.
signal changed()
## Emitted once per run, on the damage that takes HP to 0.
signal died()

## The run's seed. The name shadows the global `seed()`, but it is the field the saves and the
## callers know.
@warning_ignore("shadowed_global_identifier")
var seed := 0
## The run's random numbers: the map, the picks and the drops. Its `state` is saved.
var rng := RandomNumberGenerator.new()
var rating := 0
var opening_id := ""
var hp := Tuning.MAX_HP
var potions := Tuning.START_POTIONS
## The ids of the middle chunks, in the order the run stacks them.
var chunk_order := PackedStringArray()
var player_tile := Vector2i.ZERO
## Maps each encounter id to `{kind, content, mandatory, resolved}`.
var encounters := {}
## `{}` outside a battle, and otherwise the snapshot of the encounter in progress, with its `"id"`.
var battle := {}


## Starts a run at full HP with `Tuning.START_POTIONS` potions. `rng` is seeded with `seed`.
@warning_ignore("shadowed_global_identifier")
static func create(seed: int, rating: int, opening_id: String) -> RunState:
	var run := RunState.new()
	run.seed = seed
	run.rng.seed = seed
	run.rating = rating
	run.opening_id = opening_id
	return run


## Takes `n` HP off, down to 0. `died` fires on the damage that reaches 0, and never again.
func take_damage(n: int) -> void:
	var before := hp
	hp = maxi(hp - maxi(n, 0), 0)
	if hp == before:
		return
	changed.emit()
	if hp == 0:
		died.emit()


## Whether a potion can be drunk now: not with no potion, not at full HP, and not once the run
## is dead (at 0 HP).
func can_use_potion() -> bool:
	return potions > 0 and hp > 0 and hp < Tuning.MAX_HP


## Drinks a potion for `Tuning.POTION_HEAL` HP, up to the maximum. Returns false, and changes
## nothing, when `can_use_potion()` is false.
func use_potion() -> bool:
	if not can_use_potion():
		return false
	potions -= 1
	hp = mini(hp + Tuning.POTION_HEAL, Tuning.MAX_HP)
	changed.emit()
	return true


## Adds a potion. Returns false, and changes nothing, at `Tuning.POTION_MAX`.
func add_potion() -> bool:
	if not _gain_potion():
		return false
	changed.emit()
	return true


func set_player_tile(t: Vector2i) -> void:
	if t == player_tile:
		return
	player_tile = t
	changed.emit()


## Stores the snapshot of the battle in progress. It must carry the encounter's `"id"`.
func set_battle(snapshot: Dictionary) -> void:
	battle = snapshot
	changed.emit()


## Marks encounter `id` resolved and ends the battle in progress. A `WON` encounter rolls its
## drop with `Tuning.DROP_CHANCE` for its kind. Returns the potions gained, 0 or 1. Emits
## `changed` once.
func resolve_encounter(id: String, outcome: int) -> int:
	if not encounters.has(id):
		push_error("RunState: no encounter '%s' to resolve" % id)
		return 0
	encounters[id]["resolved"] = true
	battle = {}
	var gained := 0
	if outcome == Outcome.WON:
		var kind: String = encounters[id]["kind"]
		if _rolls_drop(kind) and _gain_potion():
			gained = 1
	changed.emit()
	return gained


## The run as JSON-safe data. `seed` and `rng.state` are 64-bit, and a JSON number is a double,
## which would corrupt them, so they are stored as decimal strings.
func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"seed": str(seed),
		"rng_state": str(rng.state),
		"rating": rating,
		"opening_id": opening_id,
		"hp": hp,
		"potions": potions,
		"chunk_order": Array(chunk_order),
		"player_tile": [player_tile.x, player_tile.y],
		"encounters": encounters.duplicate(true),
		"battle": battle.duplicate(true),
	}


## Rebuilds a run from `to_dict()` output, or from the same after a trip through JSON. Returns
## null when the version differs, when a field is missing or of the wrong type, or when an
## encounter is not `{kind, content, mandatory, resolved}` with a kind of `_ENCOUNTER_KINDS`.
## `encounters` and `battle` are kept as given: the encounters restore their own numbers.
static func from_dict(d: Dictionary) -> RunState:
	if not _is_valid(d):
		return null
	var run := RunState.new()
	run.seed = String(d["seed"]).to_int()
	run.rng.seed = run.seed
	run.rng.state = String(d["rng_state"]).to_int()
	run.rating = int(d["rating"])
	run.opening_id = d["opening_id"]
	run.hp = int(d["hp"])
	run.potions = int(d["potions"])
	run.chunk_order = PackedStringArray(d["chunk_order"])
	run.player_tile = Vector2i(int(d["player_tile"][0]), int(d["player_tile"][1]))
	run.encounters = d["encounters"]
	run.battle = d["battle"]
	return run


## Adds a potion without emitting. False at `Tuning.POTION_MAX`.
func _gain_potion() -> bool:
	if potions >= Tuning.POTION_MAX:
		return false
	potions += 1
	return true


## Rolls the drop of an encounter of `kind`.
func _rolls_drop(kind: String) -> bool:
	var chance: float = Tuning.DROP_CHANCE.get(kind, 0.0)
	# `randf()` includes 1.0, so `<=` keeps a 100% chance certain.
	return chance > 0.0 and rng.randf() <= chance


static func _is_valid(d: Dictionary) -> bool:
	if not _is_number(d.get("version")) or int(d["version"]) != VERSION:
		return false
	for field in ["seed", "rng_state"]:
		if not _is_decimal_string(d.get(field)):
			return false
	for field in ["rating", "hp", "potions"]:
		if not _is_number(d.get(field)):
			return false
	return (
		typeof(d.get("opening_id")) == TYPE_STRING
		and _is_string_array(d.get("chunk_order"))
		and _is_tile(d.get("player_tile"))
		and _are_encounters(d.get("encounters"))
		and typeof(d.get("battle")) == TYPE_DICTIONARY
	)


## A Dictionary whose every value is an encounter: `{kind, content, mandatory, resolved}`, a
## String of `_ENCOUNTER_KINDS`, a String and two booleans.
static func _are_encounters(v: Variant) -> bool:
	if typeof(v) != TYPE_DICTIONARY:
		return false
	for entry: Variant in (v as Dictionary).values():
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var e: Dictionary = entry
		if not (
			typeof(e.get("kind")) == TYPE_STRING and _ENCOUNTER_KINDS.has(e["kind"])
			and typeof(e.get("content")) == TYPE_STRING
			and typeof(e.get("mandatory")) == TYPE_BOOL
			and typeof(e.get("resolved")) == TYPE_BOOL
		):
			return false
	return true


## JSON parses every number as a float, and `to_dict()` itself holds ints.
static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _is_decimal_string(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and String(v).is_valid_int()


static func _is_string_array(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	for item: Variant in v:
		if typeof(item) != TYPE_STRING:
			return false
	return true


static func _is_tile(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY and (v as Array).size() == 2 and _is_number(v[0]) and _is_number(v[1])
