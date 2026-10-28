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
const DAMAGE_DEADZONE_WP := 5.0
const DAMAGE_PER_WP := 0.5
const MAX_MOVE_DAMAGE := 30

## Thresholds in centipawns, for the enemy bar and for mate. A strong enemy is beaten at its
## battle's opening evaluation plus `DECISIVE_GAIN_CP`, and never below `DECISIVE_MIN_CP`. The gain
## is tuned with the game's own engine by `make strong-sim` (docs/research/2026-10-28-strong-tuning.md).
const DECISIVE_GAIN_CP := 150
const DECISIVE_MIN_CP := 500
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

## Battle: the pause before an opponent's move, how long an encounter waits for the engine to
## explain a mistake, the least damage, in HP, that a strong enemy's battle explains, and how long
## its reply then waits so the explanation is read on the position it refers to.
const OPPONENT_DELAY_S := 0.6
const EXPLAIN_TIMEOUT_S := 5.0
const EXPLAIN_MIN_DAMAGE := 5
const MISTAKE_PAUSE_S := 1.5
## The most one frame adds to an engine wait, in seconds, so time in the background is one step.
const MAX_WAIT_STEP_S := 0.25

## UI: how long an HP bar takes to move to its new value, in seconds.
const BAR_TWEEN_S := 0.4

## Screen: the widest window, as width/height, that expands the layout downwards (a wider one is
## pillarboxed); the least height of the dialogue box, and the smallest side of the board, in
## viewport pixels.
const MAX_EXPAND_ASPECT := 0.75
const DIALOGUE_MIN_HEIGHT := 160
const BOARD_MIN_SIDE := 384
## UI: the least bottom margin on Android, in viewport units. The hidden navigation bar and the
## system's gesture zone (96 px at the 1.75 scale of a 1260x2800 phone) are not part of the display
## safe area while the game is immersive, so content stays this far from the bottom edge regardless.
const ANDROID_MIN_BOTTOM_MARGIN := 56

## Player rating: the presets of the new-run menu, by name. The slice has no rating updates.
const RATING_PRESETS := {"Beginner": 600, "Club": 1200, "Strong": 1800}
