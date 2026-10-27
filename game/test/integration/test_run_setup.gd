extends GutTest
## A new run gets its content from the shipped puzzle bank: a distinct puzzle for every puzzle
## spawn, an advantage position for the strong enemy and the Italian Game for the theory slot.

const PUZZLES_PATH := "res://data/puzzles/italian_game.json"

var bank: PuzzleBank


func before_each():
	bank = PuzzleBank.load_file(PUZZLES_PATH)


## The zone of `seed`, assembled the way Main does: with a generator of its own.
@warning_ignore("shadowed_global_identifier")
func _layout(seed: int) -> ZoneLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return MapAssembler.assemble(MapAssembler.load_chunks(), rng)


func test_every_spawn_gets_content():
	var layout := _layout(42)
	var run := RunSetup.create(42, 1200, layout, bank)
	assert_eq(run.encounters.size(), layout.spawns.size(), "one encounter per spawn")
	var puzzle_ids := {}
	var puzzle_spawns := 0
	for id: String in layout.spawns:
		var spawn: Dictionary = layout.spawns[id]
		var encounter: Dictionary = run.encounters[id]
		assert_eq(encounter["kind"], spawn["kind"], id)
		assert_eq(encounter["mandatory"], spawn["mandatory"], id)
		assert_false(encounter["resolved"], id)
		assert_ne(encounter["content"], "", id)
		match spawn["kind"]:
			"puzzle":
				puzzle_spawns += 1
				puzzle_ids[encounter["content"]] = true
				assert_true(bank.puzzles.has(bank.by_id(encounter["content"])), "%s holds a puzzle" % id)
			"strong":
				assert_true(bank.strong.has(bank.by_id(encounter["content"])), "%s holds a strong position" % id)
			"theory":
				assert_eq(encounter["content"], "italian_game", id)
	assert_gt(puzzle_spawns, 1, "the zone has several puzzles")
	assert_eq(puzzle_ids.size(), puzzle_spawns, "the puzzle ids are distinct")


func test_the_run_starts_on_the_layout():
	var layout := _layout(42)
	var run := RunSetup.create(42, 1200, layout, bank)
	assert_eq(run.seed, 42)
	assert_eq(run.rating, 1200)
	assert_eq(run.opening_id, "italian_game")
	assert_eq(run.chunk_order, layout.chunk_order)
	assert_eq(run.player_tile, layout.start_tile)
	assert_eq(run.hp, Tuning.MAX_HP)
	assert_eq(run.battle, {})


func test_same_seed_same_run():
	var first := RunSetup.create(42, 1200, _layout(42), bank)
	var second := RunSetup.create(42, 1200, _layout(42), bank)
	assert_eq(first.to_dict(), second.to_dict())
	var other := RunSetup.create(7, 1200, _layout(7), bank)
	assert_ne(other.encounters, first.encounters, "another seed picks other content")
