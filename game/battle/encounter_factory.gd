class_name EncounterFactory
extends RefCounted
## Builds the encounter that a spawn of the run stands for, from its kind and its content, and
## picks up the battle in progress when the run's snapshot is of that encounter.


## The encounter `id` of `run`, named after its enemy in `EnemyRoster`. A puzzle and the strong
## enemy read their record from `bank`, and the theory encounter plays `book`. When `run.battle` is
## the snapshot of `id`, the encounter is restored from it, so `begin()` resumes. Returns null when
## the run has no encounter `id`, or when its content is not in `bank` or is not `book`.
static func create(id: String, run: RunState, engine: UciEngine, bank: PuzzleBank, book: OpeningBook) -> Encounter:
	var entry: Dictionary = run.encounters.get(id, {})
	var kind: String = entry.get("kind", "")
	var content: String = entry.get("content", "")
	var encounter: Encounter = null
	match kind:
		"puzzle":
			var puzzle := bank.by_id(content)
			if not puzzle.is_empty():
				encounter = PuzzleEncounter.new(puzzle, run, engine)
		"theory":
			if content == book.id:
				encounter = TheoryEncounter.new(book, run)
		"strong":
			var position := bank.by_id(content)
			if not position.is_empty():
				var elo := clampi(run.rating, Tuning.PICKER_MIN_ELO, Tuning.PICKER_MAX_ELO)
				encounter = StrongEncounter.new(position, run, engine, elo)
	if encounter == null:
		return null
	encounter.encounter_id = id
	encounter.enemy_name = EnemyRoster.for_encounter(kind, id)["name"]
	if run.battle.get("id") == id:
		encounter.restore(run.battle)
	return encounter
