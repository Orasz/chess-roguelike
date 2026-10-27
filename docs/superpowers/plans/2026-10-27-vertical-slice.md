# Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one playable zone (spec §14, step 2). It has a map assembled from hand-made
chunks, Lichess one-move puzzles, one theory encounter for the Italian Game, one strong enemy
with HP as advantage, run HP, a potion, and save and resume that work even in the middle of a
battle. It runs on the author's Android phone.

**Architecture:**
- **Chess rules come from Stockfish itself.** The bridge exposes Stockfish's own move generator
  as a stateless call, `StockfishEngine.inspect_position`. Legal moves, check, repetition and the
  50-move counter therefore use the same code that guards against `std::exit`.
- **One engine per process.** `UciEngine` becomes the `ChessEngine` autoload and gains MultiPV.
- **Encounters are logic nodes and know nothing about the UI.** `PuzzleEncounter`,
  `TheoryEncounter` and `StrongEncounter` take moves and emit signals. They write a snapshot of
  themselves into `RunState` after every committed step.
- **Screens only render and forward input.** `BoardView`, `BattleScreen`, `Overworld` and the menu
  sit on top, and `Main` owns the run and switches screens.
- **Saving is atomic.** The whole run, including any battle in progress, is one versioned JSON
  file. It is rewritten through a temporary file and a rename after every change, and again
  whenever the app is paused.

**Tech Stack:**
- Godot 4.7.2, GDScript, GUT 9.7.1.
- The existing GDExtension: Stockfish `sf_19` and godot-cpp `10.0.0-stable`.
- Python 3 (standard library only) and `zstd`, for the offline puzzle script.
- Ninja Adventure (CC0) and SpicyGame Pixel Chess Pieces (CC0), as placeholder art.

**Spec:** `docs/superpowers/specs/2026-10-26-chess-roguelike-design.md`
- §5 Encounters, §6 HP as advantage, §7 Saving, §8 Items, §9 Overworld map, §10 Platform, §11
  Art, §14 step 2.
- Decision record: `docs/decisions/0001-engine-integration.md`, "Consequences".

## Global Constraints

- **Versions:** Godot **4.7.2-stable** (`$(HOME)/Applications/Godot.app/Contents/MacOS/Godot`),
  GUT **9.7.1** (vendored), Stockfish **`sf_19`**.
- **Stockfish stays unmodified, with its full net embedded** (`nn-1a298aa575a0.nnue`, about
  94 MiB). The author decided on 2026-10-27 to defer the net strategy to the open-beta plan, so no
  task here changes the net, adds an `EvalFile`, or applies a patch.
- **Every engine command goes through `UciEngine`.** Nothing calls `StockfishEngine.send` directly.
  Stockfish calls `std::exit` on invalid input, and `UciEngine.set_position` validates every
  position with Stockfish's own checks before it is sent.
- **One engine per process.** The engine is the `ChessEngine` autoload, and the game never starts
  a second one. Tests create their own `UciEngine`, or the `FakeEngine` test double, and **never
  start the autoload.**
- **Engine options:** `Threads` **1** and `Hash` **16**. `UCI_Elo` accepts **1320–3190**, but
  battles do not use it (see the builder's calls).
- **Screen:** portrait, with a 720×1280 base, stretch mode `canvas_items`, stretch aspect
  **`expand`**, GL Compatibility, and nearest-neighbour texture filtering. Layouts must work from
  9:16 to 9:20.
- **Art and fonts** must be redistributable in a public GPLv3 repository:
  - allowed: CC0, CC BY 4.0, CC BY-SA 4.0, and OFL for fonts;
  - CC BY-SA 3.0 counts as incompatible, and NC or ND licences are out;
  - no Nintendo or fan-ripped Pokémon assets;
  - every asset is listed in `CREDITS.md`.
- **Puzzle data** comes from the Lichess puzzle database, which is CC0. The repository ships only
  the filtered subset, at most **200 KB**.
- **Player-facing text** goes through `tr()`, with English source strings. The slice ships no
  translation catalog, because localisation is spec §14 step 4. The opening content carries both
  `en` and `it` text, because spec §5 requires the theory text in both languages.
- **No proprietary SDKs** and no network access. Saves stay on the phone (spec §10).
- **Repository language:** code, comments, tests, docs and commit messages are in English. Commits
  carry no AI attribution lines, and the repo-local `user.email` (the GitHub noreply address)
  stays as it is.
- **Tests:** `make test` runs everything headless and exits with 0. Test files are named
  `test_*.gd`, and helpers live in `game/test/support/`.

## Builder's calls in this plan

These settle spec items that were "left to the builder". They are tuning starting points: every
number lives in `Tuning`.

| Topic | Call |
|---|---|
| Move generation | Stockfish's own movegen, through the bridge. There is no GDScript move generator. SAN and insufficient material are computed in GDScript |
| Opponent strength, at every Elo | One full-strength MultiPV search, with **5** lines in **700 ms**. `MovePicker` chooses among the lines with a softmax over centipawn loss, with a temperature that falls from 150 at Elo 400 to 1 at Elo 2400. The same search gives the evaluation that drives HP, so the bars always reflect real strength. This covers opponents below 1320. `UCI_Elo` stays in `UciEngine`, unused |
| Player damage in games | The loss of win chance caused by the player's own move. Win chance uses Lichess's published formula, `50 + 50·(2/(1+e^(−0.00368208·cp)) − 1)`. Losses under **3** points count as engine noise. Damage is **0.5 HP per point**, capped at **30** per move. A better position never heals |
| Enemy bar | It starts full at the battle's opening evaluation and empties linearly to the decisive threshold of **+800 cp**. Reaching +800 cp, or a forced mate, wins the battle |
| Strong enemy | It starts from a Lichess `advantage` puzzle of the opening, after the opponent's first move. The player gets **12** moves and there is no clock. When the moves run out, the enemy escapes: **15** HP and no drop. A draw gives nothing to either side. Being mated is a loss |
| Puzzles | A wrong answer costs **10** HP. Any checkmating move counts as correct. After a wrong answer the game shows the correct move with an arrow, the theme, and one sentence built from Stockfish's reply line |
| Theory encounter | The enemy answers with book moves. A move that leaves the book is taken back, costs **5** HP once per position, and is explained with the hand-written text. Finishing the line wins |
| The one item | The potion. It heals **30** HP, up to the maximum of **100**, and the player holds at most **3**. The run starts with **1**. It drops at 25% from puzzles and 100% from the theory and strong encounters. It cannot be used at full HP |
| Player rating | Chosen on the new-run screen: Beginner **600**, Club **1200** or Strong **1800**. The slice has no rating updates and no placement test (spec §14, step 4) |
| Map | Five chunk files, written as ASCII rows in JSON and 15×20 tiles each. A run stacks the start chunk, 2 of the 3 middle chunks in a seeded order, and the gate chunk. The camera zoom is 3, so 15 tiles fill 720 px |
| Lifecycle | The slice has no clock, so nothing pauses. An engine search keeps running in the background, and its result is applied when it arrives. The state before the search is already saved, so if the OS kills the app only the search is lost, and it reruns on resume |
| Spike screen | It stays in the repository as a developer scene, but it is no longer the main scene |

## Review Focus

1. **The app is killed between the player's move and the enemy's reply.** On resume, the game
   must show the same position, apply that move's damage exactly once, and let the enemy answer.
   This is tested in Task 11 by `test_restore_with_enemy_to_move_damages_once` and in Task 16 by
   `test_continue_restores_a_battle_in_progress`.
2. **A mate-in-one puzzle is solved with a different mate than the stored one.** It must count as
   correct, as it does on Lichess. This is tested in Task 9 by `test_any_checkmate_is_accepted`.
3. **A battle starts while the engine is busy or not ready.** This happens on a cold start (about
   2 s), or when a stale search is still running after the previous battle ended mid-search. The
   battle must wait without hanging, and it must ignore results it did not ask for. This is tested
   in Task 11 by `test_waits_for_a_busy_engine` and `test_ignores_a_search_it_did_not_start`, and
   in Task 9 by `test_explanation_falls_back_when_the_engine_never_answers`.
4. **The save file is corrupt, truncated or from another version.** The menu must offer only New
   run, and nothing may crash. This is tested in Task 8 by
   `test_corrupt_or_foreign_saves_load_as_none`.
5. **A special move is played on the board** (castling, en passant or promotion). `BoardView` must
   emit exactly the UCI string that Stockfish accepts. This is tested in Task 12 by
   `test_castling_en_passant_and_promotion_emit_stockfish_uci`.

## Before execution starts (the author)

The implementer cannot download these, because the packs are on itch.io behind a "name your own
price" page:
1. Download **Ninja Adventure**, unzip it, and give the implementer the path.
   https://pixel-boy.itch.io/ninja-adventure-asset-pack
2. Download **Pixel Chess Pieces** by SpicyGame, unzip it, and give the implementer the path.
   https://spicygame.itch.io/chess-pieces
3. Task 6 asks before it downloads the Lichess puzzle database. The request gives the size from
   `curl -sI`.

## File Structure

```
tools/puzzles/build_subset.py, test_build_subset.py   # offline Lichess filter (Task 6)
CREDITS.md                                            # every third-party asset and data source
native/bridge/sf_bridge.{h,cpp}                       # + inspect() (Task 1)
native/src/stockfish_engine.{h,cpp}                   # + inspect_position() (Task 1)
game/
├── project.godot                       # autoload ChessEngine, expand aspect, main scene
├── engine/uci_engine.gd                # + MultiPV, search_finished (Task 2)
├── chess/chess_rules.gd                # inspect, status, SAN, board helpers (Task 1)
├── chess/move_picker.gd                # Elo-based choice among MultiPV lines (Task 4)
├── chess/explanation_builder.gd        # theme names and mistake sentences (Task 5)
├── run/tuning.gd, run/hp_model.gd      # every number, and the HP maths (Task 3)
├── run/run_state.gd, run/save_store.gd # the run and its atomic save (Task 8)
├── run/run_setup.gd                    # builds a new run from layout and content (Task 16)
├── content/puzzle_bank.gd, content/opening_book.gd   # (Tasks 6, 7)
├── data/puzzles/italian_game.json, data/openings/italian_game.json
├── battle/encounter.gd, puzzle_encounter.gd, theory_encounter.gd, strong_encounter.gd
├── battle/encounter_factory.gd, enemy_roster.gd
├── battle/board_view.{gd,tscn}, battle_screen.{gd,tscn}
├── overworld/chunks/{start,clearing,bridge,grove,gate}.json
├── overworld/zone_layout.gd, map_assembler.gd, tile_legend.gd, overworld.{gd,tscn}
├── main/main.{gd,tscn}, main_menu.{gd,tscn}, run_end.{gd,tscn}
├── assets/ninja_adventure/…, assets/chess_pieces/…   # used subset only, plus its licence file
└── test/unit/…, test/integration/…, test/support/fake_engine.gd
```

---

## Phase A — Chess core

### Task 1: Position inspection from Stockfish, and `ChessRules`

**Files:**
- Modify: `native/bridge/sf_bridge.h`, `native/bridge/sf_bridge.cpp`,
  `native/src/stockfish_engine.h`, `native/src/stockfish_engine.cpp`
- Create: `game/chess/chess_rules.gd`
- Test: `game/test/integration/test_chess_rules.gd`

**Interfaces:**
- Produces, in the bridge (`namespace sfbridge`):
  - `struct PositionInfo { bool valid; std::string fen; std::vector<std::string> legal; bool in_check; int rule50; bool threefold; };`
  - `PositionInfo inspect(const std::string& fen, const std::vector<std::string>& moves);`
- Produces `static StockfishEngine.inspect_position(fen: String, moves: PackedStringArray) -> Dictionary`.
  It returns `{}` when the input is invalid, and otherwise `{fen, legal: PackedStringArray,
  in_check, rule50, threefold}`.
- Produces `class_name ChessRules extends RefCounted`, with only static functions:
  - `enum Status { ONGOING, CHECKMATE, STALEMATE, DRAW_FIFTY, DRAW_REPETITION, DRAW_MATERIAL }`
  - `inspect(fen: String, moves := PackedStringArray()) -> Dictionary` — the native call, made
    only after `UciParser.is_valid_fen` and `is_valid_uci_move` pass.
  - `fen_after(fen: String, moves: PackedStringArray) -> String` returns `""` when the input is
    invalid.
  - `status(fen: String, moves := PackedStringArray()) -> Status`
  - `san(fen: String, uci: String, suffix := true) -> String` returns `""` for an illegal move.
  - `piece_at(fen: String, square: String) -> String` returns the FEN letter, or `""`.
  - `side_to_move(fen: String) -> String` returns `"w"` or `"b"`.
  - `material(fen: String, color: String) -> int` counts P 100, N 300, B 300, R 500, Q 900, and
    no king.

- [ ] **Step 1: Write the failing tests** in `game/test/integration/test_chess_rules.gd`:

```gdscript
extends GutTest
const START := UciEngine.START_FEN
const ITALIAN := "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
const CHECKED := "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"  # side not to move is in check

func test_start_position():
	var info := ChessRules.inspect(START)
	assert_eq(info.legal.size(), 20); assert_false(info.in_check); assert_eq(info.fen, START)

func test_moves_are_replayed():
	assert_eq(ChessRules.fen_after(START, PackedStringArray(["e2e4", "e7e5"])),
		"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")

func test_invalid_input_returns_empty_and_never_exits():
	assert_true(ChessRules.inspect("not a fen").is_empty())
	assert_true(ChessRules.inspect(START, PackedStringArray(["e2e5"])).is_empty())
	assert_true(ChessRules.inspect(CHECKED).is_empty())
	assert_true(StockfishEngine.inspect_position(CHECKED, PackedStringArray()).is_empty())
	assert_eq(ChessRules.fen_after(START, PackedStringArray(["e2e4\n"])), "")

func test_status():
	var cases := [
		[ChessRules.Status.CHECKMATE, START, ["e2e4","e7e5","f1c4","b8c6","d1h5","g8f6","h5f7"]],
		[ChessRules.Status.STALEMATE, "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", []],
		[ChessRules.Status.DRAW_FIFTY, "4k3/8/8/8/8/8/8/R3K3 w - - 100 80", []],
		[ChessRules.Status.DRAW_REPETITION, START, ["g1f3","g8f6","f3g1","f6g8","g1f3","g8f6","f3g1","f6g8"]],
		[ChessRules.Status.DRAW_MATERIAL, "4k3/8/8/8/8/8/8/4K1N1 w - - 0 1", []],
		[ChessRules.Status.DRAW_MATERIAL, "4k3/8/8/8/8/8/8/4KB2 w - - 0 1", []],
		[ChessRules.Status.ONGOING, "4k3/8/8/8/8/8/8/R3K3 w - - 0 1", []]]
	for c in cases:
		assert_eq(ChessRules.status(c[1], PackedStringArray(c[2])), c[0], str(c))

func test_san():
	for c in [[START, "e2e4", "e4"], [START, "g1f3", "Nf3"], [ITALIAN, "e1g1", "O-O"],
			["rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "e4d5", "exd5"],
			["8/4P3/8/8/k7/8/8/4K3 w - - 0 1", "e7e8q", "e8=Q+"],
			["6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "a1a8", "Ra8#"],
			["4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1", "b1d2", "Nbd2"],
			["4k3/8/8/R7/8/8/8/R3K3 w - - 0 1", "a1a3", "R1a3"],
			["4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6", "exd6"]]:
		assert_eq(ChessRules.san(c[0], c[1]), c[2], c[1])
	assert_eq(ChessRules.san("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "a1a8", false), "Ra8")
	assert_eq(ChessRules.san(START, "e2e5"), "")

func test_board_helpers():
	assert_eq(ChessRules.piece_at(START, "e1"), "K"); assert_eq(ChessRules.piece_at(START, "e4"), "")
	assert_eq(ChessRules.side_to_move(ITALIAN), "w"); assert_eq(ChessRules.material(START, "b"), 3900)
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because `inspect_position` and `ChessRules`
  do not exist.
- [ ] **Step 3: Implement `sfbridge::inspect`.** Move the replay loop out of `validate_position`
  into a shared helper and make `validate_position` use it, so both calls run identical checks.
  - The legal moves are `MoveList<LEGAL>`, converted with `UCIEngine::move(m, false)`. This gives
    castling as `e1g1`.
  - `in_check` is `pos.checkers() != 0`, `rule50` is `pos.rule50_count()`, and `fen` is
    `pos.fen()`.
  - `threefold` is `st->repetition < 0` for the final state. Stockfish stores a negative distance
    there when the position has occurred for the third time.
  - Like `validate_position`, it is safe to call while the engine thread runs, because the tables
    are read-only after `init_tables()`.
- [ ] **Step 4: Bind it.** Add `StockfishEngine::inspect_position` and bind it with
  `ClassDB::bind_static_method`, next to `validate_position`.
- [ ] **Step 5: Implement `ChessRules`** in `game/chess/chess_rules.gd`.
  - `status` checks, in this order: checkmate or stalemate (no legal moves), `rule50 >= 100`,
    `threefold`, and then insufficient material. Insufficient material covers only K v K, K+N v K
    and K+B v K.
  - The SAN suffix is `#` when the position after the move has no legal moves and is in check, and
    `+` when it is only in check. Disambiguation comes from the other legal moves of the same piece
    type to the same square: use the file first, then the rank, then both.
- [ ] **Step 6: Run `make test`.** Expected: every test passes, including the 31 existing ones,
  and the exit code is 0.
- [ ] **Step 7: Commit.**

```bash
git add native/bridge native/src game/chess/chess_rules.gd game/test/integration/test_chess_rules.gd
git commit -m "feat(chess): expose Stockfish's move generator and add ChessRules"
```

---

### Task 2: MultiPV in `UciEngine`, the `ChessEngine` autoload, and `FakeEngine`

**Files:**
- Modify: `game/engine/uci_engine.gd`, `game/project.godot` (`[autoload]`)
- Create: `game/test/support/fake_engine.gd`
- Test: `game/test/integration/test_uci_engine.gd` (extend),
  `game/test/integration/test_chess_engine_autoload.gd`, `game/test/integration/test_fake_engine.gd`
  (integration, because its default reply calls the native `ChessRules`)

**Interfaces:**
- Consumes: `ChessRules.inspect` (Task 1).
- Produces, on `UciEngine`:
  - `const MULTIPV_MAX := 8`
  - `signal search_finished(move: String, lines: Array)`. The lines are `EngineEval`s: the latest
    line seen for each `multipv` index during this search, ordered by index. The signal is emitted
    right after `best_move`, once the engine is back to `READY`.
  - `set_multipv(n: int) -> int` clamps to 1–`MULTIPV_MAX` and returns the value applied, or -1
    when the engine is not ready.
- Produces the autoload `ChessEngine` (`*res://engine/uci_engine.gd`). Nothing starts it at boot;
  `Main` starts it (Task 16).
- Produces `game/test/support/fake_engine.gd`, with no `class_name`; tests `preload` it. It
  `extends UciEngine` and overrides `start`, `is_ready`, `new_game`, `set_full_strength`,
  `set_strength_elo`, `set_multipv`, `set_position`, `go_movetime` and `shutdown`. It sends nothing
  to Stockfish.
  - `var replies: Array` — each entry is an `Array` of `EngineEval`, popped by each
    `go_movetime`. When none is left, it answers with every legal move at 0 cp.
  - `var searches: Array` — one `{fen, moves, ms, multipv}` per search.
  - `var available := true` — when false, it never becomes ready. The name cannot be `ready`,
    because `Node` already has a `ready` signal.
  - `var busy_frames := 0` — `is_ready()` stays false for this many frames.
  - Results are emitted (`best_move`, then `search_finished`) one process frame after `go`.
    `go_movetime` numbers the delivered lines' `multipv` 1, 2, … in reply order.
  - `set_position` returns false when `ChessRules.inspect` rejects the input.
  - `static func line(move: String, value: int, mate := false, tail := PackedStringArray()) -> EngineEval`
    builds a line whose `pv` is `[move] + tail`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_uci_engine.gd (append)
func test_multipv_reports_every_line():
	watch_signals(engine)
	assert_eq(engine.set_multipv(3), 3)
	engine.set_position(UciEngine.START_FEN); engine.go_movetime(300)
	assert_true(await wait_for_signal(engine.search_finished, 10))
	var params := get_signal_parameters(engine, "search_finished")
	assert_eq(params[1].map(func(l): return l.multipv), [1, 2, 3])
	assert_has(params[1].map(func(l): return l.pv[0]), params[0])

func test_multipv_is_clamped_and_refused_while_searching():
	assert_eq(engine.set_multipv(0), 1); assert_eq(engine.set_multipv(99), UciEngine.MULTIPV_MAX)
	engine.set_position(UciEngine.START_FEN); engine.go_movetime(1000)
	assert_eq(engine.set_multipv(2), -1)

# test_chess_engine_autoload.gd
extends GutTest
func test_autoload_exists_and_tests_never_start_it():
	var node := get_tree().root.get_node_or_null("ChessEngine")
	assert_true(node is UciEngine); assert_false(node.is_ready())

# test_fake_engine.gd
extends GutTest
const FakeEngine := preload("res://test/support/fake_engine.gd")
func test_scripted_reply_arrives_next_frame():
	var fake := FakeEngine.new(); add_child_autofree(fake); watch_signals(fake)
	fake.replies = [[FakeEngine.line("e2e4", 30), FakeEngine.line("d2d4", 20)]]
	assert_true(fake.set_position(UciEngine.START_FEN)); assert_true(fake.go_movetime(700))
	assert_signal_not_emitted(fake, "search_finished")
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(fake, "best_move", ["e2e4"])
	assert_eq(fake.searches[0].ms, 700)
func test_default_reply_lists_legal_moves():
	var fake := FakeEngine.new(); add_child_autofree(fake); watch_signals(fake)
	fake.set_position(UciEngine.START_FEN); fake.go_movetime(1)
	await wait_for_signal(fake.search_finished, 1)
	assert_eq(get_signal_parameters(fake, "search_finished")[1].size(), 20)
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because `set_multipv`, `search_finished` and
  the autoload are missing.
- [ ] **Step 3: Implement it.**
  - `UciEngine` resets `_lines: Dictionary` on `go_movetime` and stores every parsed `info` line by
    `multipv`. It still emits `evaluation` only for `multipv` 1.
  - On `bestmove`, build the ordered lines array **before** emitting either signal. A `best_move`
    handler may start the next search, which resets `_lines`.
  - `set_multipv` sends `setoption name MultiPV value <n>` from a fixed template.
  - Register the autoload in `project.godot`. If GUT's command-line runner turns out not to load
    autoloads, stop and report it instead of working around it.
  - Write `FakeEngine` as specified.
- [ ] **Step 4: Run `make test`.** Expected: every test passes and the exit code is 0.
- [ ] **Step 5: Commit.**

```bash
git add game/engine/uci_engine.gd game/project.godot game/test
git commit -m "feat(engine): add MultiPV results and the ChessEngine autoload"
```

---

### Task 3: `Tuning` and `HpModel`

**Files:**
- Create: `game/run/tuning.gd`, `game/run/hp_model.gd`
- Test: `game/test/unit/test_hp_model.gd`

**Interfaces:**
- Produces `class_name Tuning extends RefCounted`, with constants only. This task fills the HP and
  engine values, and later tasks add theirs:
  - HP: `MAX_HP := 100`, `PUZZLE_DAMAGE := 10`, `THEORY_DAMAGE := 5`, `STRONG_FAIL_DAMAGE := 15`.
  - Damage curve: `DAMAGE_DEADZONE_WP := 3.0`, `DAMAGE_PER_WP := 0.5`, `MAX_MOVE_DAMAGE := 30`.
  - Thresholds: `DECISIVE_CP := 800`, `MIN_BAR_RANGE_CP := 200`, `MATE_CP := 10000`.
  - Strong enemy: `STRONG_MOVE_LIMIT := 12`, `STRONG_SEARCH_MS := 700`, `STRONG_CANDIDATES := 5`.
  - Engine: `EXPLAIN_SEARCH_MS := 300`, `ENGINE_WAIT_S := 20.0`.
- Produces `class_name HpModel extends RefCounted`, with static functions:
  - `win_chance(cp: int) -> float` returns 0–100, using the formula in the builder's calls.
  - `eval_to_cp(e: EngineEval) -> int`: a mate for the side to move gives `+MATE_CP`; a mate
    against it, or `mate 0`, gives `-MATE_CP`.
  - `player_damage(cp_before: int, cp_after: int) -> int`: both values are from the player's point
    of view.
  - `enemy_fraction(cp: int, cp_start: int) -> float` returns
    `clamp((DECISIVE − cp) / (DECISIVE − min(cp_start, DECISIVE − MIN_BAR_RANGE)), 0, 1)`.
  - `is_decisive(cp: int) -> bool` is true when `cp >= DECISIVE_CP`.

- [ ] **Step 1: Write the failing tests:**

```gdscript
extends GutTest
func _eval(mate: bool, value: int) -> EngineEval:
	var e := EngineEval.new(); e.is_mate = mate; e.value = value; return e

func test_win_chance():
	assert_almost_eq(HpModel.win_chance(0), 50.0, 0.001)
	assert_almost_eq(HpModel.win_chance(300), 75.11, 0.01)
	assert_almost_eq(HpModel.win_chance(-300) + HpModel.win_chance(300), 100.0, 0.001)

func test_eval_to_cp():
	assert_eq(HpModel.eval_to_cp(_eval(false, 42)), 42)
	assert_eq(HpModel.eval_to_cp(_eval(true, 3)), Tuning.MATE_CP)
	assert_eq(HpModel.eval_to_cp(_eval(true, -2)), -Tuning.MATE_CP)
	assert_eq(HpModel.eval_to_cp(_eval(true, 0)), -Tuning.MATE_CP)

func test_player_damage():
	assert_eq(HpModel.player_damage(0, -10), 0, "engine noise")
	assert_eq(HpModel.player_damage(0, -100), 5)
	assert_eq(HpModel.player_damage(300, -300), 25)
	assert_eq(HpModel.player_damage(300, 0), 13)
	assert_eq(HpModel.player_damage(-200, 300), 0, "a better position never heals or hurts")
	assert_eq(HpModel.player_damage(Tuning.MATE_CP, -Tuning.MATE_CP), Tuning.MAX_MOVE_DAMAGE)

func test_enemy_fraction():
	assert_eq(HpModel.enemy_fraction(300, 300), 1.0)
	assert_almost_eq(HpModel.enemy_fraction(550, 300), 0.5, 0.001)
	assert_eq(HpModel.enemy_fraction(800, 300), 0.0)
	assert_eq(HpModel.enemy_fraction(100, 300), 1.0, "losing ground refills, never above full")
	assert_almost_eq(HpModel.enemy_fraction(700, 750), 0.5, 0.001, "start capped below decisive")

func test_is_decisive():
	assert_true(HpModel.is_decisive(800)); assert_false(HpModel.is_decisive(799))
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because `HpModel` is not declared.
- [ ] **Step 3: Implement `Tuning` and `HpModel`.** `player_damage` takes
  `win_chance(before) − win_chance(after)`. It returns 0 when that loss is below
  `DAMAGE_DEADZONE_WP`; otherwise it returns `mini(roundi(loss × DAMAGE_PER_WP), MAX_MOVE_DAMAGE)`.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/run/tuning.gd game/run/hp_model.gd game/test/unit/test_hp_model.gd
git commit -m "feat(battle): add HP-as-advantage maths and tuning constants"
```

---

### Task 4: `MovePicker` — opponent strength at any Elo, below 1320 included

**Files:**
- Create: `game/chess/move_picker.gd`
- Modify: `game/run/tuning.gd` (add `PICKER_MIN_ELO := 400`, `PICKER_MAX_ELO := 2400`,
  `PICKER_TEMP_AT_MIN := 150.0`, `PICKER_TEMP_AT_MAX := 1.0`)
- Test: `game/test/unit/test_move_picker.gd`

**Interfaces:**
- Consumes: `HpModel.eval_to_cp` (Task 3), and `EngineEval`.
- Produces `class_name MovePicker extends RefCounted`:
  - `static func choose(lines: Array, elo: int, rng: RandomNumberGenerator) -> int` returns an index
    into `lines`, which must not be empty.
  - Each line's loss is the best `eval_to_cp` among the lines minus its own.
  - The weight of a line is `exp(−loss / T)`, where `T` is interpolated linearly between the
    temperatures at `PICKER_MIN_ELO` and `PICKER_MAX_ELO`, with the Elo clamped to that range.
  - At `elo >= PICKER_MAX_ELO` it always returns the best line and draws nothing from `rng`.

- [ ] **Step 1: Write the failing tests:**

```gdscript
extends GutTest
const LOSSES := [0, 40, 80, 150, 300]
func _lines() -> Array:
	var out := []
	for loss in LOSSES:
		var e := EngineEval.new(); e.value = 100 - loss; e.pv = PackedStringArray(["a2a3"]); out.append(e)
	return out
func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed; return r
func _mean_loss(elo: int) -> float:
	var rng := _rng(7); var total := 0.0
	for i in 2000: total += LOSSES[MovePicker.choose(_lines(), elo, rng)]
	return total / 2000.0

func test_strongest_level_always_plays_the_best_line():
	var rng := _rng(1)
	for i in 200: assert_eq(MovePicker.choose(_lines(), 2400, rng), 0)

func test_beginner_often_plays_inferior_lines():
	var rng := _rng(2); var inferior := 0
	for i in 1000:
		if MovePicker.choose(_lines(), 400, rng) != 0:
			inferior += 1
	assert_gt(inferior, 400)

func test_lower_elo_loses_more():
	assert_gt(_mean_loss(800), _mean_loss(1600)); assert_gt(_mean_loss(400), _mean_loss(800))

func test_one_line_and_determinism():
	assert_eq(MovePicker.choose(_lines().slice(0, 1), 400, _rng(3)), 0)
	assert_eq(MovePicker.choose(_lines(), 900, _rng(4)), MovePicker.choose(_lines(), 900, _rng(4)))
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because `MovePicker` is not declared.
- [ ] **Step 3: Implement `MovePicker.choose`.** Take a single `rng.randf()` against the cumulative
  weights.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/chess/move_picker.gd game/run/tuning.gd game/test/unit/test_move_picker.gd
git commit -m "feat(chess): weaken opponents by choosing among MultiPV lines by Elo"
```

---

### Task 5: `ExplanationBuilder` — theme names and the sentence after a mistake

**Files:**
- Create: `game/chess/explanation_builder.gd`
- Test: `game/test/integration/test_explanation_builder.gd` (it uses `ChessRules`, which is native)

**Interfaces:**
- Consumes: `ChessRules.san`, `fen_after` and `material` (Task 1), and `EngineEval`.
- Produces `class_name ExplanationBuilder extends RefCounted`, with static functions:
  - `theme_name(themes: PackedStringArray) -> String` returns the `tr()` name of the first theme
    found in this priority order:
    - `backRankMate` "Back-rank mate", `smotheredMate` "Smothered mate", `mateIn1` "Mate in one";
    - `fork` "Fork", `pin` "Pin", `skewer` "Skewer";
    - `discoveredAttack` "Discovered attack", `doubleCheck` "Double check";
    - `hangingPiece` "Hanging piece", `trappedPiece` "Trapped piece";
    - `attraction` "Attraction", `deflection` "Deflection", `capturingDefender` "Capturing the
      defender", `interference` "Interference", `clearance` "Clearance";
    - `exposedKing` "Exposed king", `promotion` "Promotion".

    It returns `""` when none is present.
  - `after_mistake(fen: String, wrong_uci: String, reply: EngineEval) -> String`. Here `reply` is
    the engine's best line in the position after the wrong move, from the opponent's point of view.
    The sentence uses SAN without suffixes, and comes from the first rule that matches:
    1. `reply.is_mate` and `value == 1`: `tr("After %s, %s is checkmate.")`.
    2. `reply.is_mate` and `value > 1`: `tr("After %s, the opponent has mate in %d.")`.
    3. The material balance for the mover, after the wrong move and up to 3 plies of `reply.pv`,
       fell by 100 or more: `tr("After %s, %s wins your %s.")`. The piece named is the
       highest-value type whose count went down, from `tr("pawn")`, `tr("knight")`,
       `tr("bishop")`, `tr("rook")` and `tr("queen")`.
    4. Otherwise: `tr("After %s, the best reply is %s.")`.

- [ ] **Step 1: Write the failing tests:**

```gdscript
extends GutTest
func _reply(mate: bool, value: int, pv: Array) -> EngineEval:
	var e := EngineEval.new(); e.is_mate = mate; e.value = value; e.pv = PackedStringArray(pv); return e

func test_theme_name_follows_priority_and_skips_generic_tags():
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["opening", "oneMove", "fork", "short"])), "Fork")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["mateIn1", "backRankMate"])), "Back-rank mate")
	assert_eq(ExplanationBuilder.theme_name(PackedStringArray(["oneMove"])), "")

func test_lost_piece_is_named():
	assert_eq(ExplanationBuilder.after_mistake("4k3/8/4p3/8/1N6/8/8/4K3 w - - 0 1", "b4d5",
		_reply(false, 300, ["e6d5"])), "After Nd5, exd5 wins your knight.")

func test_mate_in_one_and_longer_mates():
	var fen := "6k1/5ppp/8/8/8/8/r4PPP/R5K1 b - - 0 1"
	assert_eq(ExplanationBuilder.after_mistake(fen, "a2b2", _reply(true, 1, ["a1a8"])),
		"After Rb2, Ra8 is checkmate.")
	assert_eq(ExplanationBuilder.after_mistake(fen, "a2b2", _reply(true, 3, ["a1a8"])),
		"After Rb2, the opponent has mate in 3.")

func test_generic_sentence_without_material_change():
	assert_eq(ExplanationBuilder.after_mistake(UciEngine.START_FEN, "a2a3", _reply(false, 30, ["e7e5"])),
		"After a3, the best reply is e5.")
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because `ExplanationBuilder` is not declared.
- [ ] **Step 3: Implement `ExplanationBuilder`** as specified. Replay the plies with
  `ChessRules.fen_after`, and stop at the first PV move that is not legal.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/chess/explanation_builder.gd game/test/integration/test_explanation_builder.gd
git commit -m "feat(chess): explain mistakes from the engine line"
```

---

## Phase B — Content

### Task 6: Puzzle subset — offline script, data file and `PuzzleBank`

**Files:**
- Create: `tools/puzzles/build_subset.py`, `tools/puzzles/test_build_subset.py`,
  `game/data/puzzles/italian_game.json` (generated), `game/content/puzzle_bank.gd`, `CREDITS.md`
- Modify: `Makefile` (add `test-tools` and `puzzles`; `test` depends on `test-tools`),
  `game/run/tuning.gd` (add `PUZZLE_RATING_WINDOW := 150`). The dump goes in `build/`, which is
  already git-ignored.
- Test: `game/test/unit/test_puzzle_bank.gd`, `game/test/integration/test_puzzle_data.gd`

**Interfaces:**
- Produces the CLI
  `zstd -dc <dump> | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white > out.json`.
- Produces the function `build(lines, opening, side, per_band=30, strong_per_band=8,
  band_width=200, min_rating=400, max_rating=2600, max_rd=90, min_popularity=80, min_plays=300) -> dict`.
  It takes an iterable of CSV lines, header included. A missing column raises `ValueError`.
  - A row is kept when `OpeningTags` contains the `opening` token exactly, the solver is `side`,
    `RatingDeviation <= max_rd`, `Popularity >= min_popularity`, `NbPlays >= min_plays`, and the
    rating falls in [`min_rating`, `max_rating`).
  - The solver is the side to move **after** `Moves[0]`, so `side == "white"` means the FEN's
    side field is `b`.
  - The **puzzles** pool takes rows that have the `oneMove` theme and exactly 2 moves. The
    **strong** pool takes rows that have the `advantage` theme.
  - For each band of `band_width`, keep the top `per_band` (or `strong_per_band`), sorted by
    Popularity descending, then NbPlays descending, then PuzzleId ascending.
- Produces the output JSON, sorted by rating and then id, and written with
  `json.dumps(..., indent=1, sort_keys=True)`:
  `{"version": 1, "source": "Lichess puzzle database (CC0), https://database.lichess.org/", "opening": "Italian_Game", "side": "white", "puzzles": [{"id","fen","moves":[…],"rating","themes":[…]}], "strong": [same shape]}`
- Produces `class_name PuzzleBank extends RefCounted`:
  - `static func load_file(path: String) -> PuzzleBank` returns null on a missing file or bad
    JSON.
  - `static func from_dict(d: Dictionary) -> PuzzleBank`
  - Properties: `puzzles: Array` and `strong: Array`, holding the records as they are in the file.
  - `func pick(pool: String, rating: int, count: int, rng: RandomNumberGenerator, exclude := PackedStringArray()) -> Array`
    returns up to `count` distinct records. It draws from `rating ± PUZZLE_RATING_WINDOW`, and
    widens the window by the same step until it has enough or the pool runs out. `pool` is
    `"puzzles"` or `"strong"`.
  - `func by_id(id: String) -> Dictionary` returns `{}` when the id is unknown.

- [ ] **Step 1: Write the failing Python tests** in `tools/puzzles/test_build_subset.py`
  (`unittest`). Use a `row(**overrides)` helper that builds one CSV line with these defaults:
  `fen` side `b`, `moves "e7e5 g1f3"`, rating 1200, RD 75, popularity 90, plays 1000, themes
  `"oneMove short"`, tags `"Italian_Game Italian_Game_Classical_Variation"`.
  - `test_keeps_one_move_puzzles_for_the_opening_and_side`
  - `test_drops_other_openings_wrong_side_and_unreliable_rows`: tags `Sicilian_Defense`, side `w`,
    RD 120, popularity 50 and plays 100 are each dropped.
  - `test_advantage_rows_go_to_the_strong_pool`: themes `"advantage long"` and 4 moves.
  - `test_each_band_keeps_the_most_popular`: with `per_band=2` and popularities 95, 90 and 85, the
    ids of 95 and 90 are kept.
  - `test_output_is_sorted_and_deterministic`: two runs on shuffled input give equal JSON.
  - `test_missing_column_is_an_error`
- [ ] **Step 2: Add the Makefile targets and run `make test-tools`.** Expected: it fails, because
  the module is missing.

  Also change `test: native-macos import` to `test: test-tools native-macos import`, and add both
  new targets to `.PHONY`.

```make
PUZZLE_DB := build/lichess_db_puzzle.csv.zst
test-tools:
	python3 -m unittest discover -s tools -p 'test_*.py'
puzzles:
	zstd -dc $(PUZZLE_DB) | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white > game/data/puzzles/italian_game.json
```

- [ ] **Step 3: Implement `build_subset.py`.** Use the standard library only (`csv`, `json`,
  `argparse`, `sys`). `main(argv)` reads stdin and writes stdout.
- [ ] **Step 4: Run `make test-tools`.** Expected: OK.
- [ ] **Step 5: Download the dump, after asking.** Run
  `curl -sI https://database.lichess.org/lichess_db_puzzle.csv.zst`, then ask the author to
  approve the download, giving the `Content-Length`. Then run
  `curl -L -o build/lichess_db_puzzle.csv.zst https://database.lichess.org/lichess_db_puzzle.csv.zst`
  and `make puzzles`.
  - Expected: `game/data/puzzles/italian_game.json` exists and is under 200 KB
    (`stat -f %z`).
  - If it is too big, lower `--per-band` in the Makefile.
- [ ] **Step 6: Write the failing GDScript tests.**

```gdscript
# test_puzzle_bank.gd
extends GutTest
func _bank() -> PuzzleBank:
	var recs := []
	for r in [600, 650, 700, 1200, 1210, 1800]: recs.append({"id": "p%d" % r, "fen": "", "moves": [], "rating": r, "themes": []})
	return PuzzleBank.from_dict({"version": 1, "puzzles": recs, "strong": []})
func _rng(s) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r
func test_pick_stays_near_the_rating():
	for p in _bank().pick("puzzles", 650, 3, _rng(1)): assert_between(p.rating, 500, 800)
func test_pick_widens_when_the_window_is_thin():
	assert_eq(_bank().pick("puzzles", 1200, 4, _rng(1)).size(), 4)
func test_pick_is_distinct_deterministic_and_respects_exclude():
	var a := _bank().pick("puzzles", 650, 3, _rng(5)); var b := _bank().pick("puzzles", 650, 3, _rng(5))
	assert_eq_deep(a, b)
	var ids := {}
	for p in a: ids[p.id] = true
	assert_eq(ids.size(), 3)
	assert_false(_bank().pick("puzzles", 650, 2, _rng(5), PackedStringArray(["p650"])).any(func(p): return p.id == "p650"))
func test_by_id():
	assert_eq(_bank().by_id("p1800").rating, 1800); assert_true(_bank().by_id("nope").is_empty())

# test_puzzle_data.gd
extends GutTest
const PATH := "res://data/puzzles/italian_game.json"
func test_file_loads_within_budget():
	var bank := PuzzleBank.load_file(PATH)
	assert_not_null(bank); assert_gt(bank.puzzles.size(), 199); assert_gt(bank.strong.size(), 49)
	assert_lt(FileAccess.open(PATH, FileAccess.READ).get_length(), 200_000)
func test_every_record_is_legal_and_white_solves():
	var bank := PuzzleBank.load_file(PATH)
	for p in bank.puzzles + bank.strong:
		assert_false(ChessRules.inspect(p.fen, PackedStringArray(p.moves)).is_empty(), p.id)
		assert_eq(ChessRules.side_to_move(ChessRules.fen_after(p.fen, PackedStringArray([p.moves[0]]))), "w", p.id)
func test_every_rating_preset_is_served():
	var bank := PuzzleBank.load_file(PATH); var rng := RandomNumberGenerator.new()
	for rating in [600, 1200, 1800]:
		var picked := bank.pick("puzzles", rating, 8, rng)
		assert_eq(picked.size(), 8)
		for p in picked: assert_between(p.rating, rating - 300, rating + 300, p.id)
		var strong := bank.pick("strong", rating, 1, rng)
		assert_eq(strong.size(), 1); assert_between(strong[0].rating, rating - 500, rating + 500)
```

  - The rating presets come from the builder's calls; Task 16 adds them to `Tuning`.
  - If a floor fails on the real data (200 puzzles, 50 strong, the windows above), relax
    `--min-plays` first, then `--min-popularity`. Do not lower the floors.
- [ ] **Step 7: Run `make test`.** Expected: it fails, because `PuzzleBank` is not declared.
- [ ] **Step 8: Implement `PuzzleBank`** in `game/content/puzzle_bank.gd`.
- [ ] **Step 9: Run `make test`.** Expected: every test passes, the Python ones included.
- [ ] **Step 10: Create `CREDITS.md`.** Start it with two entries: Stockfish (GPLv3, linked to
  `LICENSE`) and the Lichess puzzle database (CC0, with the URL and the generation command). Add a
  "Development" line to the README for `make test-tools` and `make puzzles`. Then commit.

```bash
git add tools Makefile game/data/puzzles game/content/puzzle_bank.gd game/run/tuning.gd game/test CREDITS.md README.md
git commit -m "feat(content): ship a filtered Lichess puzzle subset for the Italian Game"
```

---

### Task 7: Opening book — Italian Game data and `OpeningBook`

**Files:**
- Create: `game/data/openings/italian_game.json`, `game/content/opening_book.gd`
- Test: `game/test/unit/test_opening_book.gd`, `game/test/integration/test_opening_data.gd`

**Interfaces:**
- The data file uses this schema:
  `{"version":1, "id":"italian_game", "side":"white", "name":{en,it}, "plans":{en,it}, "start_fen": START, "line":[player nodes]}`
  - A **player node** is `{"move", "why":{en,it}, "replies":[enemy nodes]}`.
  - An **enemy node** is `{"move", "next":[player nodes]}`.
  - The first player node in a list is the main move. A player node with `"replies": []` ends a
    line.
- The content has three lines. Every player node gets one or two sentences of `why`, in English
  and Italian, written by hand. `plans` is 3–4 sentences about the Italian Game's ideas.
  - **A:** `e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 c2c3 g8f6 d2d4 e5d4 c3d4 c5b4`, then `c1d2` (main) or
    `b1c3`. Both end the line.
  - **B:** `… f1c4 f8c5 d2d3 g8f6 c2c3 d7d6 e1g1`. At the fourth move, `d2d3` is the second player
    option after `c2c3`.
  - **C:** `… f1c4 g8f6 d2d3 f8c5 c2c3 d7d6 e1g1`.
- Produces `class_name OpeningBook extends RefCounted`:
  - `static func load_file(path: String) -> OpeningBook` returns null on failure.
  - `static func from_dict(d: Dictionary) -> OpeningBook`
  - Properties: `id: String`, `player_white: bool`, `start_fen: String`.
  - `player_options(moves: PackedStringArray) -> Array` returns the player-node Dictionaries
    available after `moves`. It returns `[]` when it is the enemy's turn, the moves are out of
    book, or the line is complete.
  - `enemy_replies(moves: PackedStringArray) -> PackedStringArray` returns `[]` otherwise.
  - `is_complete(moves: PackedStringArray) -> bool` is true when the last move was a player node
    with no replies.
  - `text(field: Dictionary) -> String` returns `field[locale]`, using the first two letters of
    `TranslationServer.get_locale()` and falling back to `en`.
  - `name() -> String` and `plans() -> String`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_opening_book.gd — a tiny inline book: 1.e4 (main) or 1.d4; after 1.e4 e5, 2.Nf3 ends the line
extends GutTest
func _book() -> OpeningBook:
	var why := {"en": "Because.", "it": "Perché."}
	return OpeningBook.from_dict({"version": 1, "id": "t", "side": "white", "name": why, "plans": why,
		"start_fen": UciEngine.START_FEN, "line": [
			{"move": "e2e4", "why": why, "replies": [{"move": "e7e5", "next": [{"move": "g1f3", "why": why, "replies": []}]}]},
			{"move": "d2d4", "why": why, "replies": []}]})
func test_navigation():
	var b := _book()
	assert_eq(b.player_options(PackedStringArray()).map(func(n): return n.move), ["e2e4", "d2d4"])
	assert_eq(b.enemy_replies(PackedStringArray(["e2e4"])), PackedStringArray(["e7e5"]))
	assert_true(b.player_options(PackedStringArray(["e2e4"])).is_empty(), "enemy's turn")
	assert_true(b.player_options(PackedStringArray(["a2a3"])).is_empty(), "out of book")
	assert_true(b.is_complete(PackedStringArray(["e2e4", "e7e5", "g1f3"])))
	assert_false(b.is_complete(PackedStringArray(["e2e4"])))
func test_text_falls_back_to_english():
	TranslationServer.set_locale("fr"); assert_eq(_book().text({"en": "Hi", "it": "Ciao"}), "Hi")
	TranslationServer.set_locale("it"); assert_eq(_book().text({"en": "Hi", "it": "Ciao"}), "Ciao")
	TranslationServer.set_locale("en")

# test_opening_data.gd
extends GutTest
func test_italian_book_is_legal_complete_and_bilingual():
	var book := OpeningBook.load_file("res://data/openings/italian_game.json")
	assert_not_null(book); assert_true(book.player_white)
	var leaves := _walk(book, PackedStringArray())
	assert_gt(leaves, 2, "at least the three lines")
func _walk(book: OpeningBook, moves: PackedStringArray) -> int:
	assert_false(ChessRules.inspect(book.start_fen, moves).is_empty(), " ".join(moves))
	if book.is_complete(moves): return 1
	var count := 0
	for node in book.player_options(moves):
		assert_ne(node.why.get("en", ""), ""); assert_ne(node.why.get("it", ""), "")
		count += _walk(book, moves + PackedStringArray([node.move]))
	for reply in book.enemy_replies(moves):
		count += _walk(book, moves + PackedStringArray([reply]))
	return count
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because `OpeningBook` is not declared.
- [ ] **Step 3: Implement `OpeningBook`, and write `italian_game.json`** with the three lines.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/data/openings game/content/opening_book.gd game/test
git commit -m "feat(content): add the Italian Game book with English and Italian notes"
```

---

## Phase C — The run

### Task 8: `RunState` and `SaveStore`

**Files:**
- Create: `game/run/run_state.gd`, `game/run/save_store.gd`
- Modify: `game/run/tuning.gd` (add `POTION_HEAL := 30`, `POTION_MAX := 3`, `START_POTIONS := 1`,
  and `DROP_CHANCE := {"puzzle": 0.25, "theory": 1.0, "strong": 1.0}`)
- Test: `game/test/unit/test_run_state.gd`, `game/test/unit/test_save_store.gd`

**Interfaces:**
- Produces `class_name RunState extends RefCounted`:
  - `enum Outcome { WON, LOST, DRAWN }`, `const VERSION := 1`
  - `signal changed()` fires after every mutation. `signal died()` fires once, when HP reaches 0.
  - Fields:
    - `seed: int`, `rng: RandomNumberGenerator` (its `state` is saved), `rating: int`,
      `opening_id: String`, `hp: int`, `potions: int`;
    - `chunk_order: PackedStringArray`, `player_tile: Vector2i`;
    - `encounters: Dictionary`, mapping each id to `{kind, content, mandatory, resolved}`;
    - `battle: Dictionary`, which is `{}` outside a battle and otherwise the encounter snapshot,
      including `"id"`.
  - `static func create(seed: int, rating: int, opening_id: String) -> RunState` gives full HP and
    `START_POTIONS`, and seeds `rng` with `seed`.
  - Methods:
    - `take_damage(n: int) -> void`
    - `use_potion() -> bool` is false with no potion or at full HP.
    - `add_potion() -> bool` is false at the cap.
    - `set_player_tile(t: Vector2i) -> void` and `set_battle(snapshot: Dictionary) -> void`
    - `resolve_encounter(id: String, outcome: int) -> int` marks the encounter resolved, clears
      `battle`, rolls the drop with `DROP_CHANCE[kind]` only on `WON`, and returns the number of
      potions gained (0 or 1). It emits `changed` once.
    - `to_dict() -> Dictionary`. JSON-safe: a `Vector2i` is stored as `[x, y]`. `seed` and
      `rng.state` are stored as **decimal strings**: they are 64-bit, and JSON numbers are doubles,
      which would corrupt them.
    - `static func from_dict(d: Dictionary) -> RunState` returns null when the version or any
      field is missing or of the wrong type. `JSON.parse_string` returns every number as a float,
      so the integer fields are converted with `int()`.
- Produces `class_name SaveStore extends RefCounted`:
  - `func _init(path := "user://run.json")`
  - `save(run: RunState) -> bool` writes `path + ".tmp"`, then renames it over `path`.
  - `load_run() -> RunState` returns null when the file is missing, corrupt or of another
    version. A corrupt file is renamed to `path + ".corrupt"`.
  - `has_save() -> bool` and `clear() -> void`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_run_state.gd
extends GutTest
func _run() -> RunState: return RunState.create(42, 1200, "italian_game")
func test_new_run():
	var r := _run(); assert_eq([r.hp, r.potions], [Tuning.MAX_HP, Tuning.START_POTIONS])
func test_damage_floors_at_zero_and_dies_once():
	var r := _run(); watch_signals(r)
	r.take_damage(70); r.take_damage(70); r.take_damage(5)
	assert_eq(r.hp, 0); assert_signal_emit_count(r, "died", 1)
func test_potion_rules():
	var r := _run()
	assert_false(r.use_potion(), "refused at full HP"); r.take_damage(10)
	assert_true(r.use_potion()); assert_eq([r.hp, r.potions], [Tuning.MAX_HP, 0])
	assert_false(r.use_potion(), "none left")
	for i in Tuning.POTION_MAX: r.add_potion()
	assert_false(r.add_potion()); assert_eq(r.potions, Tuning.POTION_MAX)
func test_resolve_encounter():
	var r := _run(); r.encounters = {"a": {"kind": "strong", "content": "x", "mandatory": true, "resolved": false},
		"b": {"kind": "puzzle", "content": "y", "mandatory": false, "resolved": false}}
	r.set_battle({"id": "a"})
	assert_eq(r.resolve_encounter("a", RunState.Outcome.WON), 1)
	assert_true(r.encounters.a.resolved); assert_true(r.battle.is_empty())
	assert_eq(r.resolve_encounter("b", RunState.Outcome.LOST), 0)
func test_round_trip_keeps_everything():
	var r := _run(); r.take_damage(30); r.chunk_order = PackedStringArray(["start", "bridge"])
	r.set_player_tile(Vector2i(7, 70)); r.set_battle({"id": "a", "moves": ["e2e4"]}); r.rng.randi()
	var copy := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq_deep(copy.to_dict(), r.to_dict()); assert_eq(copy.rng.randi(), r.rng.randi())
func test_large_rng_state_survives_json():
	var r := RunState.create(9_000_000_000_000_000_001, 1200, "italian_game")
	var copy := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(copy.seed, r.seed); assert_eq(copy.rng.state, r.rng.state)
func test_from_dict_rejects_bad_input():
	assert_null(RunState.from_dict({})); assert_null(RunState.from_dict({"version": 99}))

# test_save_store.gd
extends GutTest
const PATH := "user://test_run.json"
func after_each():
	for p in [PATH, PATH + ".tmp", PATH + ".corrupt"]: DirAccess.remove_absolute(p)
func test_save_then_load():
	var store := SaveStore.new(PATH); var r := RunState.create(1, 600, "italian_game"); r.take_damage(12)
	assert_true(store.save(r)); assert_true(store.has_save()); assert_eq(store.load_run().hp, 88)
	assert_false(FileAccess.file_exists(PATH + ".tmp"))
func test_corrupt_or_foreign_saves_load_as_none():
	var store := SaveStore.new(PATH)
	for content in ["{\"version\": 1, \"hp\": ", "garbage", JSON.stringify({"version": 999})]:
		var f := FileAccess.open(PATH, FileAccess.WRITE); f.store_string(content); f.close()
		assert_null(store.load_run(), content)
	assert_true(FileAccess.file_exists(PATH + ".corrupt"))
func test_stale_temp_file_is_ignored():
	var store := SaveStore.new(PATH); store.save(RunState.create(1, 600, "italian_game"))
	var f := FileAccess.open(PATH + ".tmp", FileAccess.WRITE); f.store_string("half"); f.close()
	assert_not_null(store.load_run())
func test_clear():
	var store := SaveStore.new(PATH); store.save(RunState.create(1, 600, "italian_game")); store.clear()
	assert_false(store.has_save()); assert_null(store.load_run())
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because the classes are not declared.
- [ ] **Step 3: Implement `RunState` and `SaveStore`.** Use `DirAccess.rename_absolute` for the
  rename. It replaces the target atomically on Android and macOS.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/run game/test/unit/test_run_state.gd game/test/unit/test_save_store.gd
git commit -m "feat(run): add run state with atomic, versioned saves"
```

---

## Phase D — Encounters (logic only, no UI)

All three encounters share this base, which is created in Task 9:

```gdscript
class_name Encounter extends Node
signal board_changed(fen: String, last_move: String)
signal message(text: String)
signal arrow(uci: String)            # "" clears it
signal enemy_bar(fraction: float)    # 1.0 = full
signal input_enabled(on: bool)
signal finished(outcome: int)        # RunState.Outcome; also re-emitted by a restored finished encounter
var encounter_id: String
var enemy_name: String
var run: RunState
var outcome := -1
var engine_wait_s := Tuning.ENGINE_WAIT_S   # tests shorten it
func begin() -> void                 # abstract
func submit_move(uci: String) -> void
func player_white() -> bool
func current_fen() -> String         # the position on the board now
func snapshot() -> Dictionary        # always contains "id", "kind", "outcome"
func restore(snapshot: Dictionary) -> void   # called before begin()
func _commit() -> void               # run.set_battle(snapshot())
```

- **Commit before anything asynchronous.** Every encounter calls `_commit()` after each committed
  step, before it starts a search or a timer. That ordering is what makes resuming after a kill
  exact.
- **Waiting for the engine.** An encounter polls `engine.is_ready()` once per frame, for at most
  `engine_wait_s`. It acts on `search_finished` only while its own `_awaiting_search` flag is set,
  and it disconnects from the engine in `_exit_tree`.
- **Restoring.** `restore()` converts numbers with `int()`, because a snapshot that went through
  JSON holds floats. An encounter restored with an outcome emits `finished` one frame after
  `begin()`, so callers can connect first.

### Task 9: `Encounter` base and `PuzzleEncounter`

**Files:**
- Create: `game/battle/encounter.gd`, `game/battle/puzzle_encounter.gd`
- Modify: `game/run/tuning.gd` (add `OPPONENT_DELAY_S := 0.6`, `EXPLAIN_TIMEOUT_S := 5.0`)
- Test: `game/test/integration/test_puzzle_encounter.gd`

**Interfaces:**
- Consumes: `RunState` (Task 8), `ChessRules` (Task 1), `ExplanationBuilder` (Task 5), the
  `UciEngine` API and `FakeEngine` (Task 2), and `Tuning`.
- Produces `class_name PuzzleEncounter extends Encounter`:
  - `func _init(puzzle: Dictionary, run: RunState, engine: UciEngine)`
  - `var opponent_delay_s := Tuning.OPPONENT_DELAY_S` and
    `var explain_timeout_s := Tuning.EXPLAIN_TIMEOUT_S`, which tests can override.
  - The snapshot is `{id, kind: "puzzle", content: puzzle.id, outcome}`.
- **Flow:**
  1. `begin()` emits `board_changed(fen, "")` and `enemy_bar(1.0)`. After the delay it emits
     `board_changed(after_first, moves[0])`, then the intro message
     `tr("%s attacks! Find the best move.") % enemy_name`, then `input_enabled(true)`.
  2. A **correct move** is `moves[1]`, or any move that gives `CHECKMATE`. It wins: the encounter
     sets `outcome`, calls `_commit()`, and emits `board_changed`, `enemy_bar(0.0)`,
     `message(tr("Correct!"))` and `finished(WON)`.
  3. A **wrong move** costs HP: `run.take_damage(PUZZLE_DAMAGE)`. The encounter sets `outcome =
     LOST`, calls `_commit()`, emits `board_changed(after_first, "")` (taking the move back) and
     `arrow(moves[1])`, then runs one search: MultiPV 1, `EXPLAIN_SEARCH_MS`, on the position after
     the wrong move.
     - The message is `"<Theme>. <sentence> " + tr("The best move was %s.")`. An empty theme or
       sentence is left out.
     - If the engine is not ready within `explain_timeout_s`, the message has no sentence.
     - `finished(LOST)` follows the message.
  4. A **restored snapshot with an outcome** shows the solved position (after `moves[1]`) without
     any damage, then emits `finished(outcome)` on the next frame.

- [ ] **Step 1: Write the failing tests:**

```gdscript
extends GutTest
const FakeEngine := preload("res://test/support/fake_engine.gd")
const PUZZLE := {"id": "p1", "fen": "5k2/5ppp/8/8/8/8/8/RR4K1 b - - 0 1", "moves": ["f8g8", "a1a8"],
	"rating": 1000, "themes": ["mateIn1", "oneMove", "backRankMate"]}
var fake
var run: RunState
var enc: PuzzleEncounter

func before_each():
	fake = FakeEngine.new(); add_child_autofree(fake)
	run = RunState.create(1, 1200, "italian_game")
	enc = PuzzleEncounter.new(PUZZLE, run, fake); enc.encounter_id = "e1"; enc.enemy_name = "Greedy Pawn"
	enc.opponent_delay_s = 0.0; enc.explain_timeout_s = 0.2
	watch_signals(enc); add_child_autofree(enc)

func _start():
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)

func test_opponent_move_is_played_first():
	await _start()
	assert_eq(get_signal_parameters(enc, "board_changed", 1)[1], "f8g8")

func test_correct_move_wins_without_damage():
	await _start(); enc.submit_move("a1a8")
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	assert_eq(run.hp, 100); assert_eq(run.battle.outcome, RunState.Outcome.WON)

func test_any_checkmate_is_accepted():
	await _start(); enc.submit_move("b1b8")
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])

func test_wrong_move_costs_hp_and_shows_the_solution():
	fake.replies = [[FakeEngine.line("g8f8", 0)]]
	await _start(); enc.submit_move("a1a7")
	assert_eq(run.hp, 90); assert_signal_emitted_with_parameters(enc, "arrow", ["a1a8"])
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0],
		"Back-rank mate. After Ra7, the best reply is Kf8. The best move was Ra8#.")

func test_explanation_falls_back_when_the_engine_never_answers():
	fake.available = false
	await _start(); enc.submit_move("a1a7")
	await wait_for_signal(enc.finished, 2)
	assert_eq(get_signal_parameters(enc, "message")[0], "Back-rank mate. The best move was Ra8#.")

func test_restored_finished_puzzle_does_not_damage_again():
	enc.restore({"id": "e1", "kind": "puzzle", "content": "p1", "outcome": RunState.Outcome.LOST})
	enc.begin(); await wait_for_signal(enc.finished, 2)
	assert_eq(run.hp, 100); assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])
```

- [ ] **Step 2: Run `make test`.** Expected: it fails, because the classes are not declared.
- [ ] **Step 3: Implement `Encounter` and `PuzzleEncounter`** as specified.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/battle/encounter.gd game/battle/puzzle_encounter.gd game/run/tuning.gd game/test/integration/test_puzzle_encounter.gd
git commit -m "feat(battle): add puzzle encounters with generated explanations"
```

---

### Task 10: `TheoryEncounter`

**Files:**
- Create: `game/battle/theory_encounter.gd`
- Test: `game/test/integration/test_theory_encounter.gd`

**Interfaces:**
- Consumes: `Encounter` (Task 9), `OpeningBook` (Task 7), `ChessRules`, `RunState` and `Tuning`.
- Produces `class_name TheoryEncounter extends Encounter`:
  - `func _init(book: OpeningBook, run: RunState)`, which uses `run.rng` for the enemy's book
    replies.
  - `var opponent_delay_s := Tuning.OPPONENT_DELAY_S`
  - `var moves: PackedStringArray` is public, for the factory and the tests.
  - The snapshot is `{id, kind: "theory", content: book.id, moves, punished: [plies], outcome}`.
- **Flow:**
  1. `begin()` shows the position after `moves`, emits `message(book.plans())` when `moves` is
     empty, and then plays the enemy reply if it is the enemy's turn. Otherwise it enables input.
  2. **A book move** is appended and committed. If the line is complete, the encounter wins.
     Otherwise the enemy plays a random book reply after the delay, which is appended and
     committed, and input is enabled.
  3. **An off-book move:**
     - The encounter emits `board_changed(current, "")`, which takes the move back, and
       `arrow(main.move)`.
     - It emits
       `message(tr("That leaves the book.") + " " + book.text(main.why))`.
     - If the current ply is not yet in `punished`, it adds the ply, calls
       `run.take_damage(THEORY_DAMAGE)` and commits.
     - It re-enables input.

- [ ] **Step 1: Write the failing tests.** They use the real `italian_game.json`.
  - `test_book_moves_complete_the_line_and_win`: loop `submit_move(book.player_options(enc.moves)[0].move)`,
    awaiting `input_enabled` between moves, until `finished`. Then assert `WON` and `run.hp == 100`.
  - `test_enemy_replies_only_with_book_moves`: after `e2e4`, `moves[1]` is in
    `book.enemy_replies(["e2e4"])`.
  - `test_leaving_the_book_costs_hp_once_and_shows_the_book_move`:
    - `submit_move("d2d4")` at move 1 gives `hp == 95`, `arrow("e2e4")`, and a message that
      contains `book.text(...why)`.
    - `submit_move("a2a3")` keeps `hp == 95`.
    - Then `submit_move("e2e4")` makes `moves.size()` 2 after the reply.
  - `test_restore_continues_mid_line`: restore
    `{id, kind: "theory", content: "italian_game", moves: ["e2e4","e7e5"], punished: [], outcome: -1}`.
    Then `begin()` emits a `board_changed` whose FEN equals
    `ChessRules.fen_after(START, ["e2e4","e7e5"])`, and enables input.
- [ ] **Step 2: Run `make test`.** Expected: it fails, because `TheoryEncounter` is not declared.
- [ ] **Step 3: Implement `TheoryEncounter`.**
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/battle/theory_encounter.gd game/test/integration/test_theory_encounter.gd
git commit -m "feat(battle): add the opening theory encounter"
```

---

### Task 11: `StrongEncounter` — HP as advantage

**Files:**
- Create: `game/battle/strong_encounter.gd`
- Modify: `game/run/tuning.gd` (add `EXPLAIN_MIN_DAMAGE := 5`)
- Test: `game/test/integration/test_strong_encounter.gd`

**Interfaces:**
- Consumes: `Encounter`, `UciEngine` (`new_game`, `set_full_strength`, `set_multipv`,
  `set_position`, `go_movetime`, `search_finished`), `HpModel`, `MovePicker`,
  `ExplanationBuilder`, `ChessRules`, `RunState` and `Tuning`.
- Produces `class_name StrongEncounter extends Encounter`:
  - `func _init(position: Dictionary, run: RunState, engine: UciEngine, enemy_elo: int)`. Here
    `position` is a puzzle record; the battle starts after `position.moves[0]`.
  - `var move_limit := Tuning.STRONG_MOVE_LIMIT`
  - `var moves: PackedStringArray` is the line from `position.fen`, starting with `moves[0]`.
  - The snapshot is
    `{id, kind: "strong", content: position.id, moves, cp_start, cp_now, player_moves, hint, outcome}`.
    `cp_start` and `cp_now` are from the player's point of view, and `cp_start` is `null` until
    the opening evaluation exists.
- **Flow.** Every search is preceded by `set_full_strength()`, `set_multipv(STRONG_CANDIDATES)` and
  `set_position(position.fen, moves)`, and runs `go_movetime(STRONG_SEARCH_MS)`. It always follows
  a wait for `is_ready()`.
  1. `begin()` calls `new_game()` and waits for the engine. On a fresh battle it first emits
     `message(tr("%s blocks the way! Convert your advantage within %d moves.") % [enemy_name, move_limit])`.
     - If `cp_start` is null, it searches the player-to-move position and sets
       `cp_start = cp_now = eval_to_cp(best line)` and `hint = best.pv[0]`. Then it commits and
       emits `enemy_bar(1.0)`.
     - If the snapshot has the enemy to move, it goes straight to step 3.
  2. **Player move:**
     - It appends the move, increments `player_moves` and commits.
     - On `CHECKMATE` it wins. On any draw status it ends `DRAWN`. Otherwise it searches.
  3. **The search result** (the enemy is to move):
     - `cp_after = −max(eval_to_cp(line))`.
     - The player takes `player_damage(cp_now, cp_after)`. If the damage is at least
       `Tuning.EXPLAIN_MIN_DAMAGE := 5` (added by this task), the encounter emits `arrow(hint)` and
       `message(ExplanationBuilder.after_mistake(fen_before, player_move, best))`.
     - It emits `enemy_bar(enemy_fraction(cp_after, cp_start))`.
     - Then the first matching case applies:
       - `is_decisive(cp_after)`: the encounter wins.
       - `player_moves >= move_limit`: the player takes `STRONG_FAIL_DAMAGE`, the message is
         `tr("%s escapes!")`, and the encounter is `LOST`.
       - Otherwise the enemy plays `lines[MovePicker.choose(lines, enemy_elo, run.rng)]`. Then
         `cp_now = −eval_to_cp(chosen)` and `hint = chosen.pv[1]` (if any). The encounter commits
         and emits `board_changed`. If the player is now checkmated, it is `LOST`; on a draw it is
         `DRAWN`; otherwise input is enabled.
  4. **If the engine never becomes ready, or `set_position` is refused:** the encounter emits
     `message(tr("The opponent hesitates and withdraws."))` and ends `DRAWN`, with no damage.

- [ ] **Step 1: Write the failing tests.**

```gdscript
extends GutTest
const FakeEngine := preload("res://test/support/fake_engine.gd")
const OPENING := {"id": "s1", "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "moves": ["e7e5", "g1f3"]}
const ENDGAME := {"id": "s2", "fen": "6k1/4Q3/6K1/8/8/8/8/8 b - - 0 1", "moves": ["g8h8"]}
var fake
var run: RunState
var enc: StrongEncounter

func _make(position: Dictionary, first_reply: Array) -> void:
	fake = FakeEngine.new(); add_child_autofree(fake); fake.replies = [first_reply]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(position, run, fake, 2400); enc.encounter_id = "g"; enc.enemy_name = "Gatekeeper"
	watch_signals(enc); add_child_autofree(enc)
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)

func test_opening_eval_fills_the_enemy_bar():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	assert_signal_emitted_with_parameters(enc, "enemy_bar", [1.0]); assert_eq(enc.snapshot().cp_start, 300)

func test_mistake_costs_hp_from_lost_win_chance():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", 300), FakeEngine.line("g8f6", 250)])
	enc.submit_move("b1c3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75); assert_eq(enc.moves[-1], "b8c6")
	assert_signal_emitted_with_parameters(enc, "arrow", ["g1f3"])

func test_good_move_lowers_the_enemy_bar_without_damage():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", -550)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 100); assert_almost_eq(get_signal_parameters(enc, "enemy_bar")[0], 0.5, 0.001)

func test_decisive_advantage_wins_before_the_enemy_moves():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.replies.append([FakeEngine.line("b8c6", -900)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON]); assert_eq(enc.moves.size(), 2)

func test_checkmate_wins_and_stalemate_draws_without_searching():
	await _make(ENDGAME, [FakeEngine.line("e7e8", 500)])
	enc.submit_move("e7e8"); assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.WON])
	await _make(ENDGAME, [FakeEngine.line("e7e8", 500)])
	enc.submit_move("e7f7"); assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN])
	assert_eq(fake.searches.size(), 1, "only the opening eval")

func test_move_limit_lets_the_enemy_escape():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)]); enc.move_limit = 1
	fake.replies.append([FakeEngine.line("b8c6", 0)])
	enc.submit_move("g1f3"); await wait_for_signal(enc.finished, 2)
	assert_eq(run.hp, 100 - 13 - Tuning.STRONG_FAIL_DAMAGE)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.LOST])

func test_restore_with_enemy_to_move_damages_once():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.replies = [[FakeEngine.line("b8c6", 300)]]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); add_child_autofree(enc)
	enc.restore({"id": "g", "kind": "strong", "content": "s1", "moves": ["e7e5", "b1c3"], "cp_start": 300,
		"cp_now": 300, "player_moves": 1, "hint": "g1f3", "outcome": -1})
	enc.begin(); await wait_for_signal(enc.input_enabled, 2)
	assert_eq(run.hp, 75); assert_eq(fake.searches.size(), 1); assert_eq(enc.moves[-1], "b8c6")

func test_waits_for_a_busy_engine():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.busy_frames = 5
	fake.replies = [[FakeEngine.line("g1f3", 300)]]
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); add_child_autofree(enc); enc.begin()
	await wait_process_frames(2); assert_eq(fake.searches.size(), 0)
	await wait_for_signal(enc.input_enabled, 2); assert_eq(fake.searches.size(), 1)

func test_ignores_a_search_it_did_not_start():
	await _make(OPENING, [FakeEngine.line("g1f3", 300)])
	fake.search_finished.emit("b8c6", [FakeEngine.line("b8c6", 900)])
	assert_eq(run.hp, 100); assert_eq(enc.moves.size(), 1)

func test_engine_that_never_answers_ends_in_a_draw():
	fake = FakeEngine.new(); add_child_autofree(fake); fake.available = false
	run = RunState.create(1, 1200, "italian_game")
	enc = StrongEncounter.new(OPENING, run, fake, 2400); enc.engine_wait_s = 0.2
	watch_signals(enc); add_child_autofree(enc); enc.begin()
	await wait_for_signal(enc.finished, 2)
	assert_signal_emitted_with_parameters(enc, "finished", [RunState.Outcome.DRAWN]); assert_eq(run.hp, 100)
```

  Also add `test_real_engine_plays_a_reply`. It uses a real `UciEngine` that the test starts and
    shuts down. Play `g1f3` from `OPENING`, wait up to 15 s for a second `board_changed`, and
    assert that its last move is in `ChessRules.inspect(OPENING.fen, ["e7e5","g1f3"]).legal` and
    that `run.hp <= 100`.
- [ ] **Step 2: Run `make test`.** Expected: it fails, because `StrongEncounter` is not declared.
- [ ] **Step 3: Implement `StrongEncounter`** as specified.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/battle game/run/tuning.gd game/test/integration/test_strong_encounter.gd
git commit -m "feat(battle): add strong enemies with HP as advantage"
```

---

## Phase E — Screens

### Task 12: Piece art and `BoardView`

**Files:**
- Create: `game/assets/chess_pieces/…`, which holds only the 12 piece images used and the pack's
  licence or readme. Also `game/battle/board_view.gd` and `game/battle/board_view.tscn`.
- Modify: `game/project.godot` (`rendering/textures/canvas_textures/default_texture_filter=0`),
  `CREDITS.md`
- Test: `game/test/integration/test_board_view.gd`

**Interfaces:**
- Consumes: `ChessRules` (Task 1).
- Produces `class_name BoardView extends Control`:
  - `signal move_chosen(uci: String)`
  - `show_position(fen: String, white_at_bottom: bool) -> void` also clears the selection, the
    marks and the promotion picker.
  - `fen() -> String` returns the position shown.
  - `set_interactive(on: bool) -> void`
  - `mark_last_move(uci: String) -> void` and `show_arrow(uci: String) -> void` (`""` clears).
  - `tap_square(square: String) -> void` is what touch input calls.
  - `choose_promotion(piece: String) -> void` is what the `%PromotionPicker` buttons call.
  - `square_at(local: Vector2) -> String` returns `""` outside the board.
  - `selected_square() -> String` and `target_squares() -> PackedStringArray` (sorted).
- **Rules:**
  - Only the pieces of the side to move are selectable, and only while the board is interactive.
  - Tapping another selectable piece reselects. Tapping anything else deselects.
  - A target with several promotion moves shows `%PromotionPicker` (q, r, b, n). The move is
    emitted only after a choice.
  - `_gui_input` maps `InputEventScreenTouch` and the left mouse button to `tap_square`.
  - Rendering: the squares are drawn in `_draw`, and the pieces are textures with nearest
    filtering. Highlight the last move, show dots on the targets, and draw the arrow as a line with
    a head.

- [ ] **Step 1: Import the art.** From the author's Pixel Chess Pieces folder, copy the 12 piece
  images, or one sheet with its regions, plus the licence file, into `game/assets/chess_pieces/`.
  Look at the images before choosing.
  - Add a `CREDITS.md` row: the asset, the author (SpicyGame), CC0, the URL, and the files used.
- [ ] **Step 2: Write the failing tests:**

```gdscript
extends GutTest
var board: BoardView
func before_each():
	board = load("res://battle/board_view.tscn").instantiate(); add_child_autofree(board)
	board.size = Vector2(640, 640); board.set_interactive(true); watch_signals(board)

func test_tap_own_piece_shows_its_targets_then_moves():
	board.show_position(UciEngine.START_FEN, true); board.tap_square("g1")
	assert_eq(board.target_squares(), PackedStringArray(["f3", "h3"]))
	board.tap_square("f3"); assert_signal_emitted_with_parameters(board, "move_chosen", ["g1f3"])

func test_opponent_pieces_and_inactive_board_ignore_taps():
	board.show_position(UciEngine.START_FEN, true); board.tap_square("g8"); assert_eq(board.selected_square(), "")
	board.set_interactive(false); board.tap_square("g1"); assert_eq(board.selected_square(), "")

func test_castling_en_passant_and_promotion_emit_stockfish_uci():
	board.show_position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", true); board.tap_square("e1"); board.tap_square("g1")
	board.show_position("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", true); board.tap_square("e5"); board.tap_square("d6")
	board.show_position("8/4P3/8/8/k7/8/8/4K3 w - - 0 1", true); board.tap_square("e7"); board.tap_square("e8")
	assert_true(board.get_node("%PromotionPicker").visible); assert_signal_emit_count(board, "move_chosen", 2)
	board.choose_promotion("n")
	assert_eq([get_signal_parameters(board, "move_chosen", 0)[0], get_signal_parameters(board, "move_chosen", 1)[0],
		get_signal_parameters(board, "move_chosen", 2)[0]], ["e1g1", "e5d6", "e7e8n"])

func test_square_at_respects_orientation():
	board.show_position(UciEngine.START_FEN, true); assert_eq(board.square_at(Vector2(1, 1)), "a8")
	board.show_position(UciEngine.START_FEN, false); assert_eq(board.square_at(Vector2(1, 1)), "h1")
	assert_eq(board.square_at(Vector2(700, 1)), "")
```

- [ ] **Step 3: Run `make test`.** Expected: it fails, because the scene is missing.
- [ ] **Step 4: Build `board_view.tscn` and `board_view.gd`.**
- [ ] **Step 5: Run `make test`.** Expected: every test passes.
- [ ] **Step 6: Commit.**

```bash
git add game/assets/chess_pieces game/battle/board_view.* game/project.godot CREDITS.md game/test/integration/test_board_view.gd
git commit -m "feat(battle): add a tap-to-move board view with promotion"
```

---

### Task 13: `BattleScreen` and the enemy roster

**Files:**
- Create: `game/battle/battle_screen.gd`, `game/battle/battle_screen.tscn`,
  `game/battle/enemy_roster.gd`, and `game/assets/ninja_adventure/…`. The pack folder holds only
  the battle sprites used (3 monsters, 1 elder NPC, 1 boss-like enemy, and the hero's face or
  idle frame) plus the pack's licence file.
- Modify: `game/project.godot` (`display/window/stretch/aspect="expand"`), `CREDITS.md`,
  `game/run/tuning.gd` (add `BAR_TWEEN_S := 0.4`)
- Test: `game/test/integration/test_battle_screen.gd`, `game/test/unit/test_project_settings.gd`

**Interfaces:**
- Consumes: `Encounter` and its signals (Task 9), `BoardView` (Task 12), `RunState` (Task 8), and
  `Tuning`.
- Produces `class_name EnemyRoster extends RefCounted`:
  - `static func for_encounter(kind: String, id: String) -> Dictionary`, which returns
    `{name: String, sprite: String}`. The choice is deterministic from `id.hash()`.
  - Puzzle names are `tr("Greedy Pawn")`, `tr("Sneaky Bishop")` and `tr("Knight of the Centre")`.
    The theory name is `tr("Opening Scholar")`, and the strong name is `tr("Gatekeeper Rook")`.
- Produces `class_name BattleScreen extends Control`:
  - `signal closed(outcome: int)`
  - `open(encounter: Encounter, run: RunState) -> void` adds the encounter as a child, wires its
    signals, and calls `begin()`.
  - `var encounter: Encounter`
  - Unique nodes: `%EnemyName`, `%EnemySprite`, `%EnemyHp` (0–100), `%Board`, `%PlayerHp`
    (0–`MAX_HP`), `%PlayerHpLabel` (`"HP 72/100"`), `%PotionButton` (`"Potion ×N"`), `%Dialogue`
    and `%ContinueButton`.
  - Layout, top to bottom: the enemy plate, the board (square, as wide as the screen minus 16 px
    gutters), the player plate, the item bar, and the dialogue box. The dialogue box takes all the
    extra height.
  - The bars tween over `Tuning.BAR_TWEEN_S`.
  - `%PotionButton` is disabled at 0 potions or at full HP, and calls `run.use_potion()`. The HP
    bar, the label and the button refresh on `run.changed`.
  - On `finished`, the board is disabled and `%ContinueButton` is shown. Pressing it emits
    `closed(outcome)`.

- [ ] **Step 1: Import the battle sprites.** Look at the Ninja Adventure folders and pick the
  sprites listed above. Copy only those, plus the licence file, into `game/assets/ninja_adventure/`.
  Add a `CREDITS.md` row (pixel-boy, CC0, the URL and the files used).
- [ ] **Step 2: Write the failing tests.** The tests use a stub `Encounter` subclass, declared as an
  inner class of the test, that emits on command.
  - `test_project_settings.gd`:
    - `ProjectSettings.get_setting("display/window/stretch/aspect") == "expand"`
    - `.../stretch/mode == "canvas_items"`
    - `rendering/textures/canvas_textures/default_texture_filter == 0`
    - `autoload/ChessEngine` is set.
  - `test_board_is_square_and_fits_from_9_16_to_9_20`: for each of `Vector2(720, 1280)` and
    `Vector2(720, 1600)`, set `screen.size`, wait two frames, then assert:
    - `%Board.size.x == %Board.size.y`;
    - `%Board.size.x <= 720 - 32`;
    - the bottom of `%Board`'s rect is at or above the top of `%Dialogue`'s rect;
    - the bottom of `%Dialogue`'s rect is at or within `screen.size.y`.
  - `test_encounter_signals_drive_the_ui`:
    - The stub emits `enemy_bar(0.5)`; after the tween (`await wait_seconds(0.5)`),
      `%EnemyHp.value` is 50.
    - It emits `message("Hi")`, and `%Dialogue.text` is `"Hi"`.
    - It emits `board_changed(START, "")`, and `%Board.fen()` is `START`.
    - `%Board.move_chosen` reaches `stub.submit_move`.
  - `test_finish_shows_continue_and_close_reports_the_outcome`: `finished(WON)` makes
    `%ContinueButton.visible` true and the board non-interactive. Pressing the button emits
    `closed(WON)`.
  - `test_potion_button_follows_the_rules`:
    - At full HP it is disabled.
    - After `run.take_damage(50)` it is enabled. Pressing it makes `run.hp` 80 and `run.potions` 0.
    - Then it is disabled.
  - `test_roster_is_deterministic`: `for_encounter("puzzle", "3_41")` gives the same result twice,
    and its sprite path exists.
- [ ] **Step 3: Run `make test`.** Expected: it fails, because the scene is missing.
- [ ] **Step 4: Build the scene, `battle_screen.gd` and `EnemyRoster`.** Set the stretch aspect.
  Use one `Theme` resource with `default_font_size = 28` (Godot's default font, which keeps the
  Italian accents for later).
- [ ] **Step 5: Run `make test`.** Expected: every test passes.
- [ ] **Step 6: Commit.**

```bash
git add game/assets/ninja_adventure game/battle game/project.godot game/run/tuning.gd CREDITS.md game/test
git commit -m "feat(battle): add the battle screen with HP bars, potion and dialogue"
```

---

### Task 14: Map chunks, `ZoneLayout` and `MapAssembler`

**Files:**
- Create: `game/overworld/chunks/start.json`, `clearing.json`, `bridge.json`, `grove.json` and
  `gate.json`, plus `game/overworld/zone_layout.gd` and `game/overworld/map_assembler.gd`
- Test: `game/test/unit/test_map_assembler.gd`

**Interfaces:**
- **Chunk file:** `{"name": "...", "role": "start"|"middle"|"exit", "rows": [20 strings of 15 chars]}`.
  - Legend:
    - solid: `#` tree, `~` water;
    - walkable: `.` grass, `,` tall grass, `_` path, `=` bridge;
    - markers: `@` start, `X` exit;
    - spawns: `p` mandatory puzzle, `o` optional puzzle, `t` theory slot, `s` strong enemy.

    Spawn tiles count as walkable once the encounter is resolved.
  - Doors are columns 6–8. The top row of a start or middle chunk is walkable exactly there, and
    so is the bottom row of a middle or exit chunk. The start chunk's bottom row is all solid. The
    exit chunk has its `X` tiles inside, behind its `s`.
  - Content by role:
    - **start** has exactly one `@` and no spawns;
    - **middle** has at least one `p`, at least one `o` (put them in tall grass or on side paths),
      and exactly one `t`;
    - **exit** has exactly one `s`, at least one `X`, and no `t`.
- Produces `class_name ZoneLayout extends RefCounted`:
  - `size: Vector2i`, `chunk_order: PackedStringArray` (listed bottom to top, so `start` comes
    first), `start_tile: Vector2i` and `exit_tiles: Array[Vector2i]`.
  - `spawns: Dictionary` maps each id (`"<x>_<y>"`, in zone coordinates) to
    `{kind: "puzzle"|"theory"|"strong", tile: Vector2i, mandatory: bool}`.
  - `cell(tile: Vector2i) -> String` returns `"#"` outside the map.
  - `is_ground_walkable(tile: Vector2i) -> bool` ignores whether a spawn is resolved.
- Produces `class_name MapAssembler extends RefCounted`, with static functions:
  - `load_chunks(dir := "res://overworld/chunks") -> Dictionary` maps each name to the parsed
    chunk.
  - `validate(chunk: Dictionary) -> PackedStringArray` lists the problems; empty means valid.
  - `assemble(chunks: Dictionary, rng: RandomNumberGenerator) -> ZoneLayout` stacks the chunks with
    the start at the bottom, as rows 60–79, and y growing downward. The order is start, then 2 of
    the 3 middles shuffled with `rng`, then exit.
  - `rebuild(chunks: Dictionary, order: PackedStringArray) -> ZoneLayout` is used on resume.
  - The `t` with the largest y becomes `theory`, and every other `t` becomes an optional puzzle.

- [ ] **Step 1: Write the failing tests:**

```gdscript
extends GutTest
func _rng(s) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r

func test_every_chunk_is_valid():
	var chunks := MapAssembler.load_chunks(); assert_eq(chunks.size(), 5)
	for name in chunks: assert_eq(MapAssembler.validate(chunks[name]), PackedStringArray(), name)

func test_validate_catches_broken_chunks():
	var bad := MapAssembler.load_chunks()["clearing"].duplicate(true)
	bad.rows = bad.rows.map(func(r): return r.replace("p", "."))
	assert_false(MapAssembler.validate(bad).is_empty(), "no mandatory enemy left")
	assert_false(MapAssembler.validate({"name": "x", "role": "middle", "rows": ["#"]}).is_empty())

func test_assembly_is_seeded_and_complete():
	var chunks := MapAssembler.load_chunks()
	var a := MapAssembler.assemble(chunks, _rng(9)); var b := MapAssembler.assemble(chunks, _rng(9))
	assert_eq(a.chunk_order, b.chunk_order); assert_eq(a.size, Vector2i(15, 80))
	assert_eq([a.chunk_order[0], a.chunk_order[3]], ["start", "gate"])
	var kinds := a.spawns.values().map(func(s): return s.kind)
	assert_eq(kinds.count("theory"), 1); assert_eq(kinds.count("strong"), 1); assert_gt(kinds.count("puzzle"), 3)
	assert_eq(MapAssembler.rebuild(chunks, a.chunk_order).spawns.keys(), a.spawns.keys())

func test_different_seeds_reach_different_orders():
	var chunks := MapAssembler.load_chunks(); var orders := {}
	for s in 20: orders[str(MapAssembler.assemble(chunks, _rng(s)).chunk_order)] = true
	assert_gt(orders.size(), 1)
```

  `validate` must also check that every walkable tile and spawn is reachable from the entry (the
  bottom door, or `@`). It must check that the exit side (the top door, or an `X`) cannot be
  reached when `p` and `s` count as solid. That second check is what makes "mandatory" true.
- [ ] **Step 2: Run `make test`.** Expected: it fails, because the classes and files are missing.
- [ ] **Step 3: Write the five chunk files** by hand: a start clearing, a clearing, a river with a
  bridge, a grove, and the castle gate. Then implement `ZoneLayout` and `MapAssembler`.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Commit.**

```bash
git add game/overworld game/test/unit/test_map_assembler.gd
git commit -m "feat(overworld): assemble the zone from hand-made chunks"
```

---

### Task 15: `Overworld` scene — tap to move, enemies and HUD

**Files:**
- Create: `game/overworld/overworld.gd`, `game/overworld/overworld.tscn`,
  `game/overworld/tile_legend.gd`, plus the tileset and walking sprites in
  `game/assets/ninja_adventure/`
- Modify: `CREDITS.md` (the files used)
- Test: `game/test/integration/test_overworld.gd`

**Interfaces:**
- Consumes: `ZoneLayout` (Task 14), `RunState` (Task 8), `EnemyRoster` (Task 13), and
  `AStarGrid2D` (Godot).
- Produces `class_name TileLegend extends RefCounted`:
  - `static func paint(layer: TileMapLayer, layout: ZoneLayout) -> void` builds the `TileSet` in
    code from one atlas texture, with 16 px tiles, and maps each legend character to atlas
    coordinates. Tall grass and path use their own tiles.
- Produces `class_name Overworld extends Node2D`:
  - `signal encounter_requested(id: String)` and `signal zone_cleared()`
  - `var step_seconds := 0.15`, which tests set to 0.01.
  - `setup(run: RunState, layout: ZoneLayout) -> void` spawns only the unresolved encounters and
    places the player at `run.player_tile`.
  - `tap_tile(tile: Vector2i) -> void`:
    - Tapping a walkable tile walks there along an `AStarGrid2D` path with no diagonals, where the
      unresolved spawns are solid.
    - Tapping an unresolved spawn walks to its nearest reachable neighbour, then emits
      `encounter_requested(id)`.
    - Stepping onto an `X` emits `zone_cleared`.
    - A new tap during a walk replaces the path.
  - `player_tile() -> Vector2i`
  - Every completed step calls `run.set_player_tile`.
  - `_unhandled_input` maps a touch or click to a world tile and calls `tap_tile`.
  - `Camera2D` has zoom `Vector2(3, 3)`, follows the player, and is limited to the map rectangle.
  - HUD (`CanvasLayer`): `%HpLabel` and `%PotionButton`, with the same rules as in Task 13.

- [ ] **Step 1: Import the overworld art.** Pick one Ninja Adventure tileset atlas, covering grass,
  tall grass, path, trees, water, a bridge, and a castle gate or door. Pick one hero walking sheet.
  Copy them, and record the atlas coordinates in `TileLegend`. Enemies on the map reuse their
  `EnemyRoster` sprite.
- [ ] **Step 2: Write the failing tests.** Build a layout with `MapAssembler.assemble(chunks, rng)`
  and a run from `RunState.create`, and set `run.encounters` from `layout.spawns`, all unresolved.
  - `test_player_starts_at_the_saved_tile`
  - `test_tap_on_an_enemy_walks_next_to_it_and_requests_the_encounter`: tap the first mandatory
    puzzle spawn, await `encounter_requested` (up to 5 s), and check the id. The player's distance
    to the spawn tile is 1.
  - `test_mandatory_enemy_blocks_the_way_north`: tapping a tile beyond the first middle chunk's
    `p` does not get the player past that `p`'s row.
  - `test_resolved_encounters_are_gone_and_walkable`: after marking every spawn resolved and
    calling `setup` again, no enemy sprite remains, and tapping the strong spawn's tile walks onto
    it.
  - `test_reaching_the_exit_clears_the_zone`: with every spawn resolved, tap an `X` and await
    `zone_cleared`.
  - `test_steps_are_written_to_the_run`: watch `run.changed`; after a walk, `run.player_tile`
    equals `player_tile()`.
- [ ] **Step 3: Run `make test`.** Expected: it fails, because the scene is missing.
- [ ] **Step 4: Build `overworld.tscn`, `overworld.gd` and `TileLegend`.**
- [ ] **Step 5: Run `make test`.** Expected: every test passes.
- [ ] **Step 6: Check by eye.** Run `$(GODOT) --path game res://overworld/overworld.tscn`, or a
  temporary harness scene, and take a screenshot. The tiles must line up, and the player must walk
  where you tap.
- [ ] **Step 7: Commit.**

```bash
git add game/overworld game/assets/ninja_adventure CREDITS.md game/test/integration/test_overworld.gd
git commit -m "feat(overworld): add the tap-to-move zone with enemies and HUD"
```

---

### Task 16: `Main` — menu, run lifecycle, autosave and resume

**Files:**
- Create: `game/main/main.gd`, `game/main/main.tscn`, `game/main/main_menu.gd`,
  `game/main/main_menu.tscn`, `game/main/run_end.gd`, `game/main/run_end.tscn`,
  `game/battle/encounter_factory.gd`, `game/run/run_setup.gd`
- Modify: `game/project.godot` (`run/main_scene="res://main/main.tscn"`), `game/run/tuning.gd`
  (add `RATING_PRESETS := {"Beginner": 600, "Club": 1200, "Strong": 1800}`), `README.md`
  (current milestone)
- Test: `game/test/integration/test_run_setup.gd`, `game/test/integration/test_main.gd`

**Interfaces:**
- Consumes: everything above.
- Produces `class_name RunSetup extends RefCounted`:
  - `static func create(seed: int, rating: int, layout: ZoneLayout, bank: PuzzleBank) -> RunState`
    fills `chunk_order`, `player_tile` and `encounters` for every spawn:
    - puzzle spawns get distinct puzzles from `bank.pick("puzzles", …)`;
    - the strong spawn gets one record from `bank.pick("strong", …)`;
    - the theory spawn's content is `"italian_game"`.
  - It picks with the run's own `rng`, which `RunState.create` seeds with `seed`. `Main` assembles
    the layout beforehand with a separate generator seeded the same way.
- Produces `class_name EncounterFactory extends RefCounted`:
  - `static func create(id: String, run: RunState, engine: UciEngine, bank: PuzzleBank, book: OpeningBook) -> Encounter`
  - It sets `encounter_id` and `enemy_name` (from `EnemyRoster`), and calls `restore(run.battle)`
    when `run.battle.id == id`.
  - The strong enemy's Elo is `clampi(run.rating, 400, 2400)`.
- Produces `main.gd` (the root of `main.tscn`):
  - `var engine: UciEngine` and `var save_path := "user://run.json"`, which can be injected before
    `add_child`. A null engine becomes the `ChessEngine` autoload. `_ready` calls
    `engine.start()` either way; it returns false when the engine already runs, which is fine.
  - `var run: RunState`
  - `show_menu()`, `start_run(rating: int, seed: int)`, `continue_run() -> bool`,
    `open_encounter(id: String)` and `current_screen() -> Node`.
- **Behaviour:**
  - `_ready` loads `PuzzleBank`, `OpeningBook` and the chunks. If any of them fails, it shows a
    plain error label instead of the menu.
  - **Saving.** `run.changed` triggers one deferred `SaveStore.save` per frame.
    `NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_WM_CLOSE_REQUEST` and
    `NOTIFICATION_WM_GO_BACK_REQUEST` save immediately.
  - **Menu:** "Continue" appears only with a save, and "New run" offers the three rating presets.
  - **Encounters:** `encounter_requested` leads to `open_encounter`, with the overworld hidden but
    kept. `BattleScreen.closed(outcome)` calls `run.resolve_encounter`, then the overworld calls
    `setup` again.
  - **Run end:** `run.died` shows a defeat screen, and `zone_cleared` shows a victory screen. Both
    call `SaveStore.clear()`, and "Back to menu" returns to the menu.
  - **Resume:** `continue_run` rebuilds the layout from `run.chunk_order`. If `run.battle` is not
    empty, it reopens that battle directly.

- [ ] **Step 1: Write the failing tests.** Use `FakeEngine` and the save path
  `user://test_main_run.json`, which is deleted in `after_each`. The helper `_main()` instantiates
  `main.tscn`, injects both, and adds it with `add_child_autofree`.
  - `test_run_setup.gd`:
    - `test_every_spawn_gets_content`: no `content` is empty, and the puzzle ids are distinct.
    - `test_same_seed_same_run`: the `to_dict()` of both runs is equal.
  - `test_main.gd`:
    - `test_menu_offers_continue_only_with_a_save`
    - `test_new_run_opens_the_overworld_and_saves`: `current_screen() is Overworld`, and the store
      has a save after one frame.
    - `test_continue_restores_a_battle_in_progress`:
      1. Run `start_run(1200, 42)`, then `open_encounter(<the strong id>)`.
      2. Wait for `input_enabled`, then submit
         `ChessRules.inspect(enc.current_fen()).legal[0]`.
      3. Wait for the next `input_enabled`.
      4. Note `run.hp` and the encounter's `moves`, then free `main`.
      5. Create a new `_main()` on the same path and call `continue_run()`.
      6. Expected: `current_screen() is BattleScreen`, its encounter's `moves` and `run.hp` equal
         the noted values, and `fake.searches` of the new fake is empty, because no damage is
         recomputed while the player is to move.
    - `test_finishing_a_battle_returns_to_the_overworld_with_the_enemy_gone`: open a puzzle, submit
      its solution, and press `%ContinueButton`. The overworld is current, the encounter is
      resolved, and `run.battle` is empty.
    - `test_hp_zero_ends_the_run_and_deletes_the_save`
    - `test_pause_saves_immediately`: `run.take_damage(50)`, then
      `main._notification(NOTIFICATION_APPLICATION_PAUSED)`, without waiting a frame. Then
      `SaveStore.new(path).load_run().hp == 50`.
- [ ] **Step 2: Run `make test`.** Expected: it fails, because the scenes and classes are missing.
- [ ] **Step 3: Implement `RunSetup`, `EncounterFactory`, the three scenes and `main.gd`.** Set the
  main scene. Leave `game/spike/` as it is: it remains runnable with
  `$(GODOT) --path game res://spike/engine_spike.tscn`.
- [ ] **Step 4: Run `make test`.** Expected: every test passes.
- [ ] **Step 5: Play it on the desktop.** Run `$(GODOT) --path game`. Play a new Club run to the
  gate. Quit in the middle of the strong battle, relaunch, and continue.
- [ ] **Step 6: Update `README.md`.** Change the current milestone to the vertical slice and link
  this plan. Then commit.

```bash
git add game/main game/battle/encounter_factory.gd game/run game/project.godot README.md game/test
git commit -m "feat(main): wire the run lifecycle with autosave and resume"
```

---

## Phase F — On the phone

### Task 17: Slice APK, device check and decision record

**Files:**
- Modify: `game/export_presets.cfg`, `Makefile` (`apk` writes `build/slice.apk`; `install` uses
  it), `README.md` (the `make` table)
- Create: `docs/decisions/0002-vertical-slice.md`

**Interfaces:**
- Consumes: everything above.
- Produces `build/slice.apk` (package `io.github.chessroguelike.slice`, name
  `Chess Roguelike Slice`). The final application id is a beta decision.

- [ ] **Step 1: Update the export preset.** Set the package, name and path above, and set
  `include_filter="*.json"` so that the data and chunk files are exported. Run `make apk`.
  Expected: the APK exists, and the export log names the JSON files.
- [ ] **Step 2: Install it and run the checklist.** Run `make install`, and launch the app with
  `adb shell monkey -p io.github.chessroguelike.slice -c android.intent.category.LAUNCHER 1`. Drive
  the phone with `adb` as in decision 0001 (`input tap`, `screencap`), and keep `make logcat`
  running.

  | # | Check | Pass if |
  |---|---|---|
  | 1 | Cold start | The menu shows. Record the time until the first battle's engine is ready |
  | 2 | Screen shape | The screenshot shows no black bars on the 9:20 screen, in the overworld and in battle |
  | 3 | New Club run, tap to move | The player walks where you tap, and the camera follows |
  | 4 | Puzzle, right and wrong | A right answer wins. A wrong one costs 10 HP and shows the arrow, the theme and the sentence |
  | 5 | Theory encounter | Leaving the book is explained once, and finishing the line wins |
  | 6 | Strong enemy | The bars move, a bad move costs HP, and the battle resolves |
  | 7 | Potion | It works from the HUD and in battle |
  | 8 | Swipe the app away from Recents mid-battle, then relaunch | Continue gives the same position and HP |
  | 9 | Home during the enemy's search, wait 10 s, return | The enemy's move is applied |
  | 10 | logcat and `dumpsys meminfo` | No `FATAL` and no signal. Record TOTAL PSS for the deferred net decision |

- [ ] **Step 3: Write `docs/decisions/0002-vertical-slice.md`.** Follow the format of 0001:
  Context, What was built, Measurements, Decision, and Consequences. The Consequences are the
  inputs to the open-beta plan:
  - the net strategy spike comes first;
  - the tuning observations from playing;
  - the final application id;
  - anything from the checklist that failed.
- [ ] **Step 4: Commit.**

```bash
git add game/export_presets.cfg Makefile README.md docs/decisions/0002-vertical-slice.md
git commit -m "docs: record the vertical slice device check"
```
