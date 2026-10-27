class_name RunSetup
extends RefCounted
## Deals a new run: it stands the run at the start of an assembled zone and gives every spawn its
## content. A puzzle spawn gets a puzzle of the bank, distinct from the others, the strong enemy an
## advantage position, and the theory slot the run's opening.

## The opening the slice teaches, and the content of its theory encounter.
const OPENING_ID := "italian_game"


## A new run of `seed` at `rating` on `layout`, which the caller assembled with a generator of its
## own seeded with `seed`. The content is drawn with the run's `rng`, in the sorted order of the
## spawn ids, so the same seed and layout give the same run. `bank` must hold a puzzle for every
## puzzle spawn and a strong position, as the shipped bank does at every rating preset.
@warning_ignore("shadowed_global_identifier")
static func create(seed: int, rating: int, layout: ZoneLayout, bank: PuzzleBank) -> RunState:
	var run := RunState.create(seed, rating, OPENING_ID)
	run.chunk_order = layout.chunk_order
	run.player_tile = layout.start_tile
	var ids: Array = layout.spawns.keys()
	ids.sort()
	var puzzle_count := 0
	for id: String in ids:
		if layout.spawns[id]["kind"] == "puzzle":
			puzzle_count += 1
	var puzzles := bank.pick("puzzles", rating, puzzle_count, run.rng)
	var strong: Dictionary = bank.pick("strong", rating, 1, run.rng)[0]
	var next_puzzle := 0
	for id: String in ids:
		var spawn: Dictionary = layout.spawns[id]
		var content := ""
		match spawn["kind"]:
			"puzzle":
				content = String(puzzles[next_puzzle]["id"])
				next_puzzle += 1
			"strong":
				content = String(strong["id"])
			"theory":
				content = OPENING_ID
		run.encounters[id] = {
			"kind": spawn["kind"],
			"content": content,
			"mandatory": spawn["mandatory"],
			"resolved": false,
		}
	return run
