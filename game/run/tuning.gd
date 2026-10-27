class_name Tuning
extends RefCounted
## Every tuning number of the vertical slice, as constants. Later tasks append
## their own groups below the ones here.

## HP: the player's pool, and the flat damage of puzzles, theory and strong encounters.
const MAX_HP := 100
const PUZZLE_DAMAGE := 10
const THEORY_DAMAGE := 5
const STRONG_FAIL_DAMAGE := 15

## Damage curve: how a move's loss of win chance, in points, becomes HP lost.
const DAMAGE_DEADZONE_WP := 3.0
const DAMAGE_PER_WP := 0.5
const MAX_MOVE_DAMAGE := 30

## Thresholds in centipawns, for the enemy bar and for mate.
const DECISIVE_CP := 800
const MIN_BAR_RANGE_CP := 200
const MATE_CP := 10000

## Strong enemy: the move limit, the search time, and the lines it chooses among.
const STRONG_MOVE_LIMIT := 12
const STRONG_SEARCH_MS := 700
const STRONG_CANDIDATES := 5

## Engine: the search time for explanations, and how long a caller waits for the engine.
const EXPLAIN_SEARCH_MS := 300
const ENGINE_WAIT_S := 20.0

## Move picker: the Elo range it covers, and its softmax temperature, in centipawns, at each end.
const PICKER_MIN_ELO := 400
const PICKER_MAX_ELO := 2400
const PICKER_TEMP_AT_MIN := 150.0
const PICKER_TEMP_AT_MAX := 1.0

## Puzzle bank: how far a puzzle's rating may be from the player's, in rating points. The window
## widens by this same step when too few puzzles fall inside it.
const PUZZLE_RATING_WINDOW := 150

## Items: the potion's heal, how many the player holds at most and at the start, and its drop chance.
const POTION_HEAL := 30
const POTION_MAX := 3
const START_POTIONS := 1
const DROP_CHANCE := {"puzzle": 0.25, "theory": 1.0, "strong": 1.0}

## Battle timing: the pause before an opponent's move, and how long an encounter waits for the
## engine to explain a mistake.
const OPPONENT_DELAY_S := 0.6
const EXPLAIN_TIMEOUT_S := 5.0
