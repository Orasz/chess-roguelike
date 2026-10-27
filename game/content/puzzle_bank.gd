class_name PuzzleBank
extends RefCounted
## The puzzle subset that ships with the game, built offline from the Lichess puzzle database
## by tools/puzzles/build_subset.py. Each record is a Dictionary with `id`, `fen`, `moves`
## (UCI strings), `rating` and `themes`, exactly as in the file. `puzzles` holds one-move
## puzzles for basic enemies; `strong` holds `advantage` positions for the strong enemy.
## Godot's JSON parser reads every number as a float, so records from `load_file` carry a
## float `rating`.

var puzzles: Array = []
var strong: Array = []


## Loads the bank at `path`. Returns null when the file is missing or is not a JSON object.
static func load_file(path: String) -> PuzzleBank:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data)


## Builds a bank from the parsed file.
static func from_dict(d: Dictionary) -> PuzzleBank:
	var bank := PuzzleBank.new()
	bank.puzzles = d.get("puzzles", [])
	bank.strong = d.get("strong", [])
	return bank


## Returns up to `count` distinct records of `pool` ("puzzles" or "strong") with an id that is
## not in `exclude`. They are drawn from ratings within `Tuning.PUZZLE_RATING_WINDOW` of `rating`.
## When that holds too few records, the window grows by the same step until it does, or until
## the pool has nothing left to add. The draw depends only on `rng` and on the order of the file.
func pick(pool: String, rating: int, count: int, rng: RandomNumberGenerator, exclude := PackedStringArray()) -> Array:
	var eligible: Array = []
	for record: Dictionary in _pool(pool):
		if not exclude.has(record.id):
			eligible.append(record)
	var farthest := 0
	for record: Dictionary in eligible:
		farthest = maxi(farthest, absi(int(record.rating) - rating))
	var window := Tuning.PUZZLE_RATING_WINDOW
	var candidates := _within(eligible, rating, window)
	while candidates.size() < count and window < farthest:
		window += Tuning.PUZZLE_RATING_WINDOW
		candidates = _within(eligible, rating, window)
	var picked: Array = []
	for i in mini(count, candidates.size()):
		# A partial Fisher-Yates shuffle: slot `i` takes a random one of the records left.
		var j := rng.randi_range(i, candidates.size() - 1)
		var chosen: Dictionary = candidates[j]
		candidates[j] = candidates[i]
		candidates[i] = chosen
		picked.append(chosen)
	return picked


## Returns the record with `id`, looking in `puzzles` first and then in `strong`, or an empty
## Dictionary when the id is unknown.
func by_id(id: String) -> Dictionary:
	for record: Dictionary in puzzles:
		if record.id == id:
			return record
	for record: Dictionary in strong:
		if record.id == id:
			return record
	return {}


func _pool(pool: String) -> Array:
	match pool:
		"puzzles":
			return puzzles
		"strong":
			return strong
	push_error("PuzzleBank: unknown pool '%s'" % pool)
	return []


## The records of `records` whose rating is at most `window` away from `rating`, in file order.
func _within(records: Array, rating: int, window: int) -> Array:
	var near: Array = []
	for record: Dictionary in records:
		if absi(int(record.rating) - rating) <= window:
			near.append(record)
	return near
