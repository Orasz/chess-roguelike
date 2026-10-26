# Engine Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that Stockfish can run inside a Godot 4 game on a real Android arm64 phone. The game
must be able to play a move at a chosen strength and read the evaluation, as required by spec §14,
step 1. The result is recorded as a decision.

**Architecture:**
- A C++ GDExtension (`native/`) compiles unmodified Stockfish `sf_19` into one shared library.
- Stockfish's UCI loop runs on a background thread. Its `std::cin` and `std::cout` are swapped for
  in-memory stream buffers, because Android 10 and later forbid launching a bundled executable.
- A thin GDScript layer (`game/engine/`) parses UCI and validates every command before it reaches
  Stockfish.
- A portrait test screen (`game/spike/`) exercises the engine on desktop and on the phone.

**Tech Stack:** Godot 4.7.2, GDScript, godot-cpp `10.0.0-stable`, SCons, Stockfish `sf_19`, GUT
9.7.1, Android NDK `28.1.13356709`, JDK 17.

**Spec:** `docs/superpowers/specs/2026-10-26-chess-roguelike-design.md`. Relevant sections: §10 "Biggest
technical risk" and §14 "Suggested order", step 1.

## Global Constraints

**Versions**
- Godot **4.7.2-stable**, installed with `brew install --cask godot`. The binary is
  `/Applications/Godot.app/Contents/MacOS/Godot`.
- godot-cpp tag **`10.0.0-stable`**, built with `api_version` **`4.7`**. In the `.gdextension` file:
  `compatibility_minimum = "4.7"` and `reloadable = false`.
- Stockfish tag **`sf_19`**, **unmodified**: this spike applies no patches.
  - The NNUE net is `nn-1a298aa575a0.nnue` (98,511,183 bytes), embedded with INCBIN.
  - Never compile `src/main.cpp` or `src/universal/*.cpp`.

**Build targets**
- macOS `arch=arm64` only, and Android `arm64` (`arm64-v8a`) only. No universal builds.

**Android toolchain**
- JDK 17 (`temurin@17`).
- The SDK lives at `~/Library/Android/sdk`. Do not use an SDK provided by Homebrew.
- Packages: `platform-tools`, `build-tools;36.1.0`, `platforms;android-36`, `cmdline-tools;latest`,
  `ndk;28.1.13356709`.

**Licence:** the whole repository is GPLv3 (spec §10, §12). `LICENSE` is a copy of Stockfish's
`Copying.txt`.

**How the engine is used**
- **One engine per process.** Stockfish's tables, the I/O lock and `std::cin`/`std::cout` are
  global. Only `UciEngine` talks to `StockfishEngine`.
- **Nothing malformed reaches Stockfish.** `sf_19` calls `std::exit(1)` on an invalid command, which
  kills the app. Because of that:
  - `UciEngine` checks FEN and move syntax, and never forwards raw strings.
  - Moves passed to `set_position` must come from the engine itself in this spike, and later from a
    legal-move generator.
- `UCI_Elo` accepts **1320–3190**. Stockfish silently ignores values outside that range, so the
  wrapper clamps them.
- Options sent at start: `Threads` **1**, `Hash` **16**.

**Project conventions**
- Tests use GUT 9.7.1, vendored in `game/addons/gut`. They live under `game/test/` and run headless
  with `make test`. Exit code 0 means everything passed.
- Code, comments, tests, docs and commit messages are in English. Commits carry no AI attribution
  lines.
- *Claude's call:* the window is portrait with a 720×1280 base size, the stretch mode is
  `canvas_items`, and the renderer is GL Compatibility, for the widest Android support.
- No proprietary SDKs (spec §10).

## Review Focus

1. **The engine is freed while a search is running**, for example on a scene change or when the
   app closes. The app must neither crash nor hang, and a new engine must start afterwards. This is
   tested in Task 3 by `test_free_during_search_then_restart`.
2. **An output line is split across several stream writes**, which happens with long `pv` lines
   and bursts of `info string`. Every line handed to GDScript must be a complete UCI line. This is
   tested in Task 2 by `test_every_polled_line_is_complete_uci`.
3. **A second engine instance is started.** Its `start()` must return `false`, and the first engine
   must keep answering. This is tested in Task 2 by `test_second_instance_cannot_start`.
4. **A caller passes a malformed FEN or move.** It must be rejected before reaching Stockfish, and the
   engine must stay alive. This is tested in Task 3 by
   `test_invalid_input_is_rejected_and_engine_stays_alive`.
5. **The UI is used before the engine is ready.** Cold start on a phone with a 94 MiB embedded net
   may be slow, so the buttons stay disabled until the engine is ready. This is tested in Task 4 by
   `test_buttons_disabled_until_ready`.

## File Structure

```
chess-roguelike/
├── .gitignore, .gitmodules, LICENSE, README.md, Makefile
├── docs/decisions/0001-engine-integration.md      # spike outcome (Task 6)
├── native/                                         # GDExtension source
│   ├── SConstruct
│   ├── godot-cpp/                                  # submodule @ 10.0.0-stable
│   ├── thirdparty/Stockfish/                       # submodule @ sf_19
│   ├── bridge/sf_bridge.{h,cpp}                    # Stockfish side: std-only API, no Godot headers
│   └── src/register_types.{h,cpp}, stockfish_engine.{h,cpp}   # Godot side: no Stockfish headers
└── game/                                           # Godot project root
    ├── project.godot, export_presets.cfg
    ├── addons/gut/                                 # vendored GUT 9.7.1
    ├── bin/stockfish_gd.gdextension                # bin/macos, bin/android = build output (ignored)
    ├── engine/engine_eval.gd, uci_parser.gd, uci_engine.gd
    ├── spike/engine_spike.{tscn,gd}
    └── test/unit/…, test/integration/…
```

The bridge is the only file that includes Stockfish headers. It is compiled with exactly
Stockfish's defines, to respect the one-definition rule. The Godot class talks to the bridge only
through `sf_bridge.h`.

---

### Task 1: Repository, Godot project, test runner and UCI parser

**Files:**
- Create: `.gitignore`, `README.md`, `Makefile`, `game/project.godot`, `game/addons/gut/**`
  (vendored), `game/engine/engine_eval.gd`, `game/engine/uci_parser.gd`
- Test: `game/test/unit/test_uci_parser.gd`

**Interfaces:**
- Produces:
  - `class_name EngineEval extends RefCounted` with the fields `depth: int`, `multipv: int` (default
    1), `is_mate: bool`, `value: int` (centipawns, or moves to mate, from the side to move's point
    of view), `nodes: int`, `nps: int`, `time_ms: int`, `pv: PackedStringArray`.
  - `class_name UciParser extends RefCounted`, with only static functions:
    - `parse_info(line: String) -> EngineEval` returns `null` unless the line is `info …` and
      contains `score`.
    - `parse_bestmove(line: String) -> String` returns the move, `"(none)"`, or `""` when the line
      is not a `bestmove` line.
    - `is_valid_fen(fen: String) -> bool` is a syntax check only.
    - `is_valid_uci_move(move: String) -> bool` is a syntax check: `^[a-h][1-8][a-h][1-8][qrbn]?$`.

- [ ] **Step 1: Install Godot.** Run `brew install --cask godot`, then
  `/Applications/Godot.app/Contents/MacOS/Godot --version`. Expected output: it starts with
  `4.7.2.stable`.
- [ ] **Step 2: Initialise the repository.** Run `git init` in the repository root, then create
  `.gitignore`:

```
.superpowers/
.godot/
/build/
game/bin/macos/
game/bin/android/
native/*.nnue
*.os
*.o
.sconsign.dblite
```

- [ ] **Step 3: Create `game/project.godot`.** Set `config_version=5`,
  `config/name="Chess Roguelike"`, `display/window/size/viewport_width=720`,
  `viewport_height=1280`, `display/window/handheld/orientation=1` (portrait),
  `display/window/stretch/mode="canvas_items"`, and
  `rendering/renderer/rendering_method="gl_compatibility"`, also for `.mobile`.
- [ ] **Step 4: Vendor GUT 9.7.1.** Download
  `https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip`, copy its `addons/gut` into
  `game/addons/gut`, and check that `game/addons/gut/gut_cmdln.gd` exists. Ask before downloading.
- [ ] **Step 5: Create the `Makefile`.**

```make
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot

import:
	$(GODOT) --headless --path game --import

test: import
	$(GODOT) --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

- [ ] **Step 6: Write the failing tests** in `game/test/unit/test_uci_parser.gd`
  (`extends GutTest`):

```gdscript
const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const QGA_FEN := "rnbqkbnr/p3pppp/8/1p6/2pP4/4P3/1P3PPP/RNBQKBNR w KQkq - 0 6"

func test_parse_info_cp():
	var e := UciParser.parse_info("info depth 12 seldepth 18 multipv 1 score cp 34 nodes 1000 nps 100000 hashfull 1 tbhits 0 time 10 pv e2e4 e7e5")
	assert_eq([e.depth, e.multipv, e.is_mate, e.value, e.nodes, e.nps, e.time_ms], [12, 1, false, 34, 1000, 100000, 10])
	assert_eq(e.pv, PackedStringArray(["e2e4", "e7e5"]))

func test_parse_info_negative_mate():
	var e := UciParser.parse_info("info depth 5 seldepth 5 multipv 1 score mate -2 nodes 50 nps 5000 time 1 pv g8h8 a1a8")
	assert_true(e.is_mate); assert_eq(e.value, -2)

func test_parse_info_skips_bound_and_wdl():
	var e := UciParser.parse_info("info depth 10 multipv 2 score cp -15 upperbound wdl 100 800 100 nodes 9 nps 9 time 1 pv d2d4")
	assert_eq([e.multipv, e.value], [2, -15]); assert_eq(e.pv, PackedStringArray(["d2d4"]))

func test_parse_info_mate_zero_without_pv():
	var e := UciParser.parse_info("info depth 0 score mate 0")
	assert_true(e.is_mate); assert_eq(e.value, 0); assert_eq(e.pv.size(), 0); assert_eq(e.multipv, 1)

func test_parse_info_ignores_lines_without_score():
	assert_null(UciParser.parse_info("info depth 10 currmove e2e4 currmovenumber 1"))
	assert_null(UciParser.parse_info("info string NNUE evaluation using nn-1a298aa575a0.nnue"))
	assert_null(UciParser.parse_info("readyok"))

func test_parse_bestmove():
	assert_eq(UciParser.parse_bestmove("bestmove e7e8q ponder d1d8"), "e7e8q")
	assert_eq(UciParser.parse_bestmove("bestmove (none)"), "(none)")
	assert_eq(UciParser.parse_bestmove("readyok"), "")

func test_valid_fens():
	assert_true(UciParser.is_valid_fen(START_FEN))
	assert_true(UciParser.is_valid_fen(QGA_FEN))
	assert_true(UciParser.is_valid_fen("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"))

func test_invalid_fens():
	for fen in ["", "not a fen",
			"8/8/8/8/8/8/8/8 w - - 0 1",                                  # no kings
			"rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",  # 9 files
			"rnbqkbnr/pppppppp/8/8/8/8/RNBQKBNR w KQkq - 0 1",            # 7 ranks
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",   # side
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KX - 0 1",     # castling
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e5 0 1",  # en passant rank
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 -1"]: # move number
		assert_false(UciParser.is_valid_fen(fen), fen)

func test_uci_move_syntax():
	for m in ["e2e4", "e7e8q", "a7a8n"]: assert_true(UciParser.is_valid_uci_move(m), m)
	for m in ["", "e7e8k", "e9e4", "e2-e4", "e2e4 ", "E2E4"]: assert_false(UciParser.is_valid_uci_move(m), m)
```

- [ ] **Step 7: Run `make test`.** Expected: it fails, because the parse errors show that
  `UciParser` is not defined.
- [ ] **Step 8: Implement `EngineEval` and `UciParser`.** Write them in `game/engine/engine_eval.gd`
  and `game/engine/uci_parser.gd`.
  - `parse_info` splits on spaces and reads these keys: `depth`, `seldepth`, `multipv`,
    `score cp|mate N`, `nodes`, `nps`, `time`, and `pv` (everything after it).
  - It skips `lowerbound`, `upperbound`, `wdl a b c`, `hashfull` and `tbhits`.
  - `is_valid_fen` checks these fields:
    - **Board:** 8 ranks of 8 squares each, built only from `prnbqkPRNBQK1-8`, with exactly one `K`
      and one `k`.
    - **Side to move:** `w|b`.
    - **Castling:** `-` or a non-empty subset of `KQkq`, in that order.
    - **En passant:** `-|[a-h][36]`.
    - **Halfmove clock:** an integer ≥ 0.
    - **Fullmove number:** an integer ≥ 1.
- [ ] **Step 9: Run `make test`.** Expected: all tests in `test_uci_parser.gd` pass and the exit
  code is 0.
- [ ] **Step 10: Write `README.md`.** Cover three things: what the project is (link the spec), that
  the licence is GPLv3, and `make test`.
- [ ] **Step 11: Commit.**

```bash
git add .gitignore README.md Makefile game docs
git commit -m "chore: bootstrap Godot project with GUT and a UCI parser"
```

---

### Task 2: GDExtension that runs Stockfish in-process (macOS)

**Files:**
- Create: `.gitmodules` and the submodules `native/godot-cpp` and `native/thirdparty/Stockfish`
- Create: `LICENSE`, `native/SConstruct`, `native/bridge/sf_bridge.h`, `native/bridge/sf_bridge.cpp`,
  `native/src/register_types.h`, `native/src/register_types.cpp`,
  `native/src/stockfish_engine.h`, `native/src/stockfish_engine.cpp`,
  `game/bin/stockfish_gd.gdextension`
- Modify: `Makefile` (add `net`, `native-macos`; `test` depends on `native-macos`)
- Test: `game/test/integration/test_stockfish_engine.gd`

**Interfaces:**
- Consumes: `UciParser.parse_info` (Task 1).
- Produces:
  - Bridge (`sf_bridge.h`, standard library only), `namespace sfbridge`:
    - `bool start();`
    - `void send_line(const std::string& line);`
    - `std::vector<std::string> drain_lines();`
    - `void stop();`
    - `bool running();`
  - Godot class `StockfishEngine extends RefCounted`:
    - `start() -> bool` returns false if any instance already runs.
    - `send(command: String) -> void`
    - `poll_lines() -> PackedStringArray` returns the complete lines produced since the last call.
    - `stop() -> void`, which is also called from the destructor. It does nothing unless this
      instance owns the engine.
    - `is_running() -> bool`
  - Extension entry symbol: `stockfish_gd_library_init`.

- [ ] **Step 1: Install SCons.** Run `brew install scons` and check that `scons --version` reports
  4.x.
- [ ] **Step 2: Add the submodules and the licence.**

```bash
git submodule add https://github.com/godotengine/godot-cpp native/godot-cpp
git -C native/godot-cpp checkout 10.0.0-stable
git submodule add https://github.com/official-stockfish/Stockfish native/thirdparty/Stockfish
git -C native/thirdparty/Stockfish checkout sf_19
cp native/thirdparty/Stockfish/Copying.txt LICENSE
```

  Expected: `git -C native/thirdparty/Stockfish describe --tags` prints `sf_19`.
- [ ] **Step 3: Add the Makefile targets and fetch the net.**

```make
NET := nn-1a298aa575a0.nnue

net: native/$(NET)
native/$(NET):
	$(MAKE) -C native/thirdparty/Stockfish/src net
	cp native/thirdparty/Stockfish/src/$(NET) native/$(NET)

native-macos: net
	scons -C native platform=macos arch=arm64 target=template_debug
```

  Change the prerequisites of `test` to `native-macos import` and leave its recipe as it is.
  Then run `make net`. Expected: `stat -f %z native/nn-1a298aa575a0.nnue` prints `98511183`.
- [ ] **Step 4: Write the failing tests** in `game/test/integration/test_stockfish_engine.gd`:

```gdscript
extends GutTest
var engines: Array = []

func _new_engine() -> StockfishEngine:
	var e := StockfishEngine.new(); engines.append(e); return e

func after_each():
	for e in engines: e.stop()
	engines.clear()

func _collect_until(e: StockfishEngine, prefix: String, timeout_s := 10.0) -> PackedStringArray:
	var out := PackedStringArray()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		for line in e.poll_lines():
			out.append(line)
			if line.begins_with(prefix): return out
		await get_tree().process_frame
	return out

func test_uci_handshake():
	var e := _new_engine()
	assert_true(e.start())
	e.send("uci")
	var lines := await _collect_until(e, "uciok")
	assert_eq(lines[-1], "uciok")
	assert_true(Array(lines).any(func(l): return l.begins_with("id name Stockfish 19")))

func test_readyok_after_isready():
	var e := _new_engine(); e.start(); e.send("isready")
	assert_eq((await _collect_until(e, "readyok"))[-1], "readyok")

func test_every_polled_line_is_complete_uci():
	var e := _new_engine(); e.start()
	for c in ["uci", "isready", "position startpos", "go depth 12"]: e.send(c)
	var lines := await _collect_until(e, "bestmove", 30.0)
	assert_true(lines[-1].begins_with("bestmove "))
	for l in lines:
		assert_has(["id", "option", "uciok", "readyok", "info", "bestmove"], l.get_slice(" ", 0), l)
		if l.begins_with("info depth") and l.contains(" score "):
			assert_not_null(UciParser.parse_info(l), l)

func test_second_instance_cannot_start():
	var a := _new_engine(); var b := _new_engine()
	assert_true(a.start()); assert_false(b.start())
	a.send("isready")
	assert_eq((await _collect_until(a, "readyok"))[-1], "readyok")

func test_restart_after_stop():
	var e := _new_engine(); e.start(); e.stop()
	assert_false(e.is_running())
	assert_true(e.start()); e.send("isready")
	assert_eq((await _collect_until(e, "readyok"))[-1], "readyok")
```

- [ ] **Step 5: Run `make test`.** Expected: it fails. If the SConstruct is missing the build fails;
  otherwise the error is `StockfishEngine` not declared.
- [ ] **Step 6: Write `native/SConstruct`.** The values are pinned by the research: the defines match
  Stockfish's own `ARCH=armv8` and `apple-silicon` targets.

```python
#!/usr/bin/env python
import os

LIB = "stockfish_gd"
SF = "thirdparty/Stockfish/src"   # submodule at sf_19; NOT added to CPPPATH (its memory.h would shadow <memory.h>)
NET = "nn-1a298aa575a0.nnue"      # INCBIN resolves it from the compiler's cwd = this directory

env = SConscript("godot-cpp/SConstruct", {"api_version": "4.7"})
if env["platform"] == "macos" and env["arch"] != "arm64":
    print("Build macOS with arch=arm64"); Exit(1)

gd = env.Clone()                  # Godot-side code; never append to env itself (it leaks into godot-cpp)
gd.Append(CPPPATH=["src/"])

sf = env.Clone()                  # Stockfish + bridge share exactly these defines
sf.Append(CPPDEFINES=["IS_64BIT", "USE_POPCNT", ("USE_NEON", 8)])
sf.Append(CXXFLAGS=["-fconstexpr-steps=500000000"])
sf.Append(CCFLAGS=["-O3", "-funroll-loops"])
if env["platform"] == "macos":
    sf.Append(CPPDEFINES=["USE_NEON_DOTPROD"], CCFLAGS=["-march=armv8.2-a+dotprod"])

def cpp(pattern, exclude=()):
    return [f for f in Glob(pattern) if os.path.basename(str(f)) not in exclude]

sf_src = (cpp(SF + "/*.cpp", exclude=("main.cpp",))
          + cpp(SF + "/nnue/*.cpp", exclude=("network.cpp",))
          + cpp(SF + "/nnue/features/*.cpp")
          + cpp(SF + "/syzygy/*.cpp")
          + cpp("bridge/*.cpp"))
sf_objs = [sf.SharedObject(s) for s in sf_src]
net_obj = sf.SharedObject(SF + "/nnue/network.cpp")
sf.Depends(net_obj, NET)          # SCons does not scan .incbin

gd_objs = [gd.SharedObject(s) for s in Glob("src/*.cpp")]

suffix = env["suffix"].replace(".dev", "").replace(".universal", "")
lib = gd.SharedLibrary(
    "../game/bin/{}/{}{}{}{}".format(env["platform"], env.subst("$SHLIBPREFIX"), LIB, suffix,
                                     env.subst("$SHLIBSUFFIX")),
    source=gd_objs + sf_objs + [net_obj])
Default(lib)
```

- [ ] **Step 7: Implement the bridge** in `native/bridge/sf_bridge.cpp`, keeping the API from
  `sf_bridge.h`.
  - **Mirror `sf_19` `src/main.cpp`.** Use its includes and its init sequence: `Attacks::init();
    Position::init();`. Run that init once, under `std::call_once`.
  - **Input buffer.** `InputBuf : std::streambuf` holds a queue of characters behind a mutex and a
    condition variable. `underflow()` blocks until data arrives or the buffer is closed; after
    `close()` it returns EOF. `reopen()` resets it.
  - **Output buffer.** `LineBuf : std::streambuf`. `overflow()` and `xsputn()` append to the current
    line. On `'\n'`, the finished line (without the newline) moves to a completed-lines deque under a
    mutex. Partial lines are never exposed.
  - **`start()`:**
    - It returns false if the engine is already running.
    - It saves the original buffers and swaps them with `std::cin.rdbuf(&in)` and
      `std::cout.rdbuf(&out)`.
    - It starts a `pthread` with an **8 MB stack**, the same as Stockfish's search threads in
      `thread_native.h`. The thread builds `CommandLine` with **argc = 1** (`{"stockfish",
      nullptr}`), creates `std::make_unique<UCIEngine>(…)`, calls `Tune::init(uci->engine_options())`
      and runs `uci->loop()`.
  - **`stop()`** sends `quit`, closes the input, joins the thread and restores the original buffers.
  - **Leave out:** `exit` handling, `engine_info()` printing and any Godot includes.
- [ ] **Step 8: Implement the Godot class.**
  - **`stockfish_engine.{h,cpp}`:** `StockfishEngine` wraps the bridge. A
    `static std::atomic<StockfishEngine*>` records the owning instance: `start()` fails while
    another instance owns the engine, and `stop()` releases it. Methods are bound with
    `ClassDB::bind_method`. The destructor calls `stop()` when this instance is the owner.
  - **`register_types.{h,cpp}`:** follow `godot-cpp-template`. Use
    `GDREGISTER_CLASS(StockfishEngine)` at `MODULE_INITIALIZATION_LEVEL_SCENE`, with the entry symbol
    `stockfish_gd_library_init`.
- [ ] **Step 9: Write `game/bin/stockfish_gd.gdextension`.**

```ini
[configuration]
entry_symbol = "stockfish_gd_library_init"
compatibility_minimum = "4.7"
reloadable = false

[libraries]
macos.debug.arm64     = "res://bin/macos/libstockfish_gd.macos.template_debug.arm64.dylib"
macos.release.arm64   = "res://bin/macos/libstockfish_gd.macos.template_release.arm64.dylib"
android.debug.arm64   = "res://bin/android/libstockfish_gd.android.template_debug.arm64.so"
android.release.arm64 = "res://bin/android/libstockfish_gd.android.template_release.arm64.so"
```

- [ ] **Step 10: Build.** Run `make native-macos`. Expected:
  `game/bin/macos/libstockfish_gd.macos.template_debug.arm64.dylib` exists. The first build also
  compiles godot-cpp and takes several minutes.
- [ ] **Step 11: Run `make test`.** Expected: all tests pass, including Task 1's, and the exit code
  is 0.
- [ ] **Step 12: Commit.**

```bash
git add .gitmodules LICENSE Makefile native game/bin/stockfish_gd.gdextension game/test/integration
git commit -m "feat(native): run Stockfish sf_19 in-process through a GDExtension"
```

---

### Task 3: `UciEngine` — the only GDScript entry point to the engine

**Files:**
- Create: `game/engine/uci_engine.gd`
- Test: `game/test/integration/test_uci_engine.gd`

**Interfaces:**
- Consumes: `StockfishEngine` (Task 2), and `UciParser` and `EngineEval` (Task 1).
- Produces `class_name UciEngine extends Node`:
  - Signals: `ready_ok()`, `evaluation(eval: EngineEval)`, `best_move(move: String)`.
  - Constants: `START_FEN` (the standard start position), `ELO_MIN := 1320`, `ELO_MAX := 3190`.
  - Properties: `engine_name: String`, taken from `id name`, and `last_eval: EngineEval`.
  - Methods:
    - `start() -> bool` sends `uci`, then after `uciok` sends `setoption name Threads value 1`,
      `setoption name Hash value 16` and `isready`. After `readyok` it emits `ready_ok`.
    - `is_ready() -> bool` is true when the engine is ready and not searching.
    - `new_game() -> void` sends `ucinewgame` and `isready`.
    - `set_strength_elo(elo: int) -> int` clamps the value, sends `UCI_LimitStrength true` and
      `UCI_Elo`, and returns the value applied.
    - `set_full_strength() -> void` sends `UCI_LimitStrength false`.
    - `set_position(fen: String, moves := PackedStringArray()) -> bool` returns false and sends
      nothing if the FEN or any move fails validation.
    - `go_movetime(ms: int) -> bool` returns false if the engine is not ready.
    - `shutdown() -> void`, which is also called on `NOTIFICATION_PREDELETE`. It is idempotent.
  - `_process` drains `poll_lines()` and dispatches each line. `bestmove` returns the engine to the
    ready state and then emits `best_move`.

- [ ] **Step 1: Write the failing tests** in `game/test/integration/test_uci_engine.gd`:

```gdscript
extends GutTest
const MATE_FEN := "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
const FIRST_MOVES := ["a2a3","a2a4","b2b3","b2b4","c2c3","c2c4","d2d3","d2d4","e2e3","e2e4",
	"f2f3","f2f4","g2g3","g2g4","h2h3","h2h4","b1a3","b1c3","g1f3","g1h3"]
var engine: UciEngine

func before_each():
	engine = UciEngine.new(); add_child_autofree(engine)
	assert_true(engine.start())
	assert_true(await wait_for_signal(engine.ready_ok, 15), "ready_ok")

func after_each():
	if is_instance_valid(engine): engine.shutdown()

func test_engine_name_is_stockfish_19():
	assert_true(engine.engine_name.begins_with("Stockfish 19"), engine.engine_name)

func test_bestmove_from_start_is_a_legal_first_move():
	watch_signals(engine)
	assert_true(engine.set_position(UciEngine.START_FEN)); assert_true(engine.go_movetime(200))
	assert_true(await wait_for_signal(engine.best_move, 10))
	assert_has(FIRST_MOVES, get_signal_parameters(engine, "best_move")[0])
	assert_signal_emitted(engine, "evaluation")

func test_finds_mate_in_one():
	watch_signals(engine)
	engine.set_position(MATE_FEN); engine.go_movetime(500)
	await wait_for_signal(engine.best_move, 10)
	assert_eq(get_signal_parameters(engine, "best_move")[0], "a1a8")
	assert_true(engine.last_eval.is_mate); assert_eq(engine.last_eval.value, 1)

func test_strength_elo_is_clamped():
	assert_eq(engine.set_strength_elo(800), 1320)
	assert_eq(engine.set_strength_elo(5000), 3190)
	assert_eq(engine.set_strength_elo(1500), 1500)

func test_go_is_refused_while_searching():
	engine.set_position(UciEngine.START_FEN); assert_true(engine.go_movetime(2000))
	assert_false(engine.go_movetime(100), "second go while searching")

func test_invalid_input_is_rejected_and_engine_stays_alive():
	watch_signals(engine)
	assert_false(engine.set_position("not a fen"))
	assert_false(engine.set_position(UciEngine.START_FEN, PackedStringArray(["e2-e4"])))
	assert_true(engine.set_position(UciEngine.START_FEN, PackedStringArray(["e2e4"])))
	engine.go_movetime(100)
	assert_true(await wait_for_signal(engine.best_move, 10), "engine still alive")

func test_free_during_search_then_restart():
	engine.set_position(UciEngine.START_FEN); engine.go_movetime(5000)
	engine.queue_free(); await get_tree().process_frame; await get_tree().process_frame
	engine = UciEngine.new(); add_child_autofree(engine)
	assert_true(engine.start())
	assert_true(await wait_for_signal(engine.ready_ok, 15), "restarted")
```

- [ ] **Step 2: Run `make test`.** Expected: it fails because `UciEngine` is not declared.
- [ ] **Step 3: Implement `UciEngine`** in `game/engine/uci_engine.gd`, following the Interfaces
  block.
  - It tracks its state with `enum State { STOPPED, STARTING, READY, SEARCHING }`.
  - It builds commands with fixed templates only: `position fen <fen> moves <m…>` and
    `go movetime <ms>`.
- [ ] **Step 4: Run `make test`.** Expected: every test passes and the exit code is 0.
- [ ] **Step 5: Commit.**

```bash
git add game/engine/uci_engine.gd game/test/integration/test_uci_engine.gd
git commit -m "feat(engine): add UciEngine wrapper with input validation and Elo clamping"
```

---

### Task 4: Portrait spike screen

**Files:**
- Create: `game/spike/engine_spike.tscn`, `game/spike/engine_spike.gd`
- Modify: `game/project.godot` (set `run/main_scene="res://spike/engine_spike.tscn"`)
- Test: `game/test/integration/test_engine_spike.gd`

**Interfaces:**
- Consumes: `UciEngine` (Task 3).
- Produces the scene root script with `var engine: UciEngine`, created and started in `_ready`, and
  these unique-named nodes:
  - `%Status`, `%EloSpin` (a SpinBox from 1320 to 3190, step 10, default 1500), `%FullStrength` (a
    CheckBox);
  - the buttons `%PlayButton`, `%MateCheckButton`, `%QgaCheckButton`, `%NewGameButton`;
  - the labels `%MovesLabel`, `%BestMoveLabel`, `%EvalLabel`, `%SpeedLabel`, `%CheckLabel`.

Behaviour:
- **Status and buttons.** The status reads `Starting…`, `Ready` or `Searching…`. All buttons are
  disabled unless `engine.is_ready()`.
- **Play.** It applies the strength: `set_full_strength()` if the checkbox is ticked, otherwise
  `set_strength_elo(%EloSpin.value)`. Then it calls `set_position(START_FEN, moves)` and
  `go_movetime(1000)`.
  - When the move arrives, the screen appends it to `moves` and sets three labels:
    - `%EvalLabel` reads `Eval: +0.34 (depth 12, side to move)` or `Eval: mate 1`.
    - `%SpeedLabel` reads `Speed: <nps/1000> knps, <time_ms> ms`.
    - `(none)` shows `Game over`.
- **Mate check.** It uses `MATE_FEN` with `go_movetime(500)`. `%CheckLabel` reads
  `Mate-in-1: ✓ a1a8` or `Mate-in-1: ✗ got <move>`.
- **QGA check.** It uses `QGA_FEN` with `go_movetime(1000)`. `%CheckLabel` reads
  `QGA trap: ✓ d1f3` or `QGA trap: – got <move> (theory says d1f3)`. This one is informational
  only.
- The script defines its own constants, with the same values as the tests:
  - `MATE_FEN := "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"`
  - `QGA_FEN := "rnbqkbnr/p3pppp/8/1p6/2pP4/4P3/1P3PPP/RNBQKBNR w KQkq - 0 6"`
- **New game.** It calls `new_game()` and clears `moves`.

- [ ] **Step 1: Write the failing tests** in `game/test/integration/test_engine_spike.gd`:

```gdscript
extends GutTest
var scene

func before_each():
	scene = load("res://spike/engine_spike.tscn").instantiate(); add_child_autofree(scene)

func after_each():
	if is_instance_valid(scene): scene.engine.shutdown()

func test_buttons_disabled_until_ready():
	for b in ["%PlayButton", "%MateCheckButton", "%QgaCheckButton", "%NewGameButton"]:
		assert_true(scene.get_node(b).disabled, b)
	await wait_for_signal(scene.engine.ready_ok, 15)
	await get_tree().process_frame
	assert_false(scene.get_node("%PlayButton").disabled)

func test_play_button_appends_engine_move():
	await wait_for_signal(scene.engine.ready_ok, 15)
	scene.get_node("%PlayButton").pressed.emit()
	await wait_for_signal(scene.engine.best_move, 10)
	await get_tree().process_frame
	assert_ne(scene.get_node("%MovesLabel").text.strip_edges(), "")

func test_mate_check_reports_success():
	await wait_for_signal(scene.engine.ready_ok, 15)
	scene.get_node("%MateCheckButton").pressed.emit()
	await wait_for_signal(scene.engine.best_move, 10)
	await get_tree().process_frame
	assert_string_contains(scene.get_node("%CheckLabel").text, "✓ a1a8")
```

- [ ] **Step 2: Run `make test`.** Expected: it fails because the scene is missing.
- [ ] **Step 3: Build the scene and its script** as described above. Use a `VBoxContainer` that fills
  the 720×1280 viewport, and a font size of at least 28 px so the screen is readable on a phone.
- [ ] **Step 4: Run `make test`.** Expected: every test passes and the exit code is 0.
- [ ] **Step 5: Check manually.** Run
  `/Applications/Godot.app/Contents/MacOS/Godot --path game`. Expected:
  - the status reaches `Ready`;
  - Play produces moves;
  - the mate check shows `✓ a1a8`.
- [ ] **Step 6: Commit.**

```bash
git add game/spike game/project.godot game/test/integration/test_engine_spike.gd
git commit -m "feat(spike): add portrait engine spike screen"
```

---

### Task 5: Android build and debug APK

**Files:**
- Create: `game/export_presets.cfg`
- Modify: `Makefile` (add `native-android`, `apk`, `install`, `logcat`), `README.md` (an "Android
  setup" section)

**Interfaces:**
- Consumes: everything above.
- Produces `build/spike.apk`, with the package `io.github.chessroguelike.spike`.

- [ ] **Step 1: Install the JDK and the Android command-line tools.** Run
  `brew install --cask temurin@17 android-commandlinetools`. Then check that
  `/usr/libexec/java_home -v 17` prints a path.
- [ ] **Step 2: Install the SDK packages** into the single SDK location.

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" "cmdline-tools;latest" "platform-tools" "build-tools;36.1.0" "platforms;android-36" "ndk;28.1.13356709"
```

  Expected: `ls "$ANDROID_HOME/ndk"` lists `28.1.13356709`.
- [ ] **Step 3: Create the debug keystore if it is missing.** Use the same arguments as Godot's
  editor:

```bash
mkdir -p "$HOME/Library/Application Support/Godot/keystores"
keytool -genkey -keystore "$HOME/Library/Application Support/Godot/keystores/debug.keystore" \
  -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
  -validity 10000 -dname "cn=Godot, ou=Godot Engine, o=Stichting Godot, c=NL"
```

- [ ] **Step 4: Install the Android export templates.** This is a manual step in the editor: open
  Editor › Manage Export Templates, select Android, and choose Install Selected Templates.
  Expected: `"$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/android_debug.apk"`
  exists.
- [ ] **Step 5: Extend the `Makefile`.**

```make
ANDROID_HOME ?= $(HOME)/Library/Android/sdk
JAVA_HOME ?= $(shell /usr/libexec/java_home -v 17 2>/dev/null)
KEYSTORE := $(HOME)/Library/Application Support/Godot/keystores/debug.keystore
ADB := $(ANDROID_HOME)/platform-tools/adb
export ANDROID_HOME JAVA_HOME
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH := $(KEYSTORE)
export GODOT_ANDROID_KEYSTORE_DEBUG_USER := androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD := android

native-android: net
	scons -C native platform=android arch=arm64 target=template_debug

apk: native-android import
	mkdir -p build
	$(GODOT) --headless --path game --export-debug "Android" ../build/spike.apk

install: apk
	$(ADB) install -r build/spike.apk

logcat:
	$(ADB) logcat -s godot
```

- [ ] **Step 6: Build the Android library.** Run `make native-android`. Expected:
  `file game/bin/android/libstockfish_gd.android.template_debug.arm64.so` reports `ELF 64-bit LSB
  shared object, ARM aarch64`.
- [ ] **Step 7: Write `game/export_presets.cfg`.**
  - `[preset.0]`: `name="Android"`, `platform="Android"`, `runnable=true`,
    `export_filter="all_resources"`, `exclude_filter="test/*, addons/gut/*"`,
    `export_path="../build/spike.apk"`.
  - `[preset.0.options]`:
    - `gradle_build/use_gradle_build=false`
    - `architectures/arm64-v8a=true`, with `armeabi-v7a`, `x86` and `x86_64` set to `false`
    - `package/unique_name="io.github.chessroguelike.spike"`
    - `package/name="Chess Roguelike Spike"`
  - If the headless export complains about missing keys, open the project in the editor once, go to
    Project › Export, select the preset and close the dialog. Godot fills in its defaults. Then
    commit the resulting file.
- [ ] **Step 8: Build the APK.** Run `make apk`. Expected:
  - `unzip -l build/spike.apk | grep lib/arm64-v8a/libstockfish_gd` lists the library.
  - Record the size of `ls -l build/spike.apk`. Over 100 MB is expected, because of the embedded
    net.
- [ ] **Step 9: Write the README "Android setup" section** covering Steps 1–4 and the `make` targets.
  Then commit.

```bash
git add game/export_presets.cfg Makefile README.md
git commit -m "build(android): export a debug APK with the Stockfish GDExtension"
```

---

### Task 6: On-device verification and decision record

**Files:**
- Create: `docs/decisions/0001-engine-integration.md`
- Modify: `docs/superpowers/specs/2026-10-26-chess-roguelike-design.md` (§10, the findings)

**Interfaces:**
- Consumes: `build/spike.apk` (Task 5).
- Produces the verdict that gates the vertical slice (spec §14, step 2).

- [ ] **Step 1: Connect the phone.** Enable Developer options and USB debugging, plug the phone in
  and accept the prompt. Expected: `$ANDROID_HOME/platform-tools/adb devices` lists the device.
- [ ] **Step 2: Record the device.** Run these three commands:
  - `adb shell getprop ro.product.model`
  - `adb shell getprop ro.build.version.release`
  - `adb shell grep -m1 -o asimddp /proc/cpuinfo`, which shows whether the phone supports dotprod.
- [ ] **Step 3: Install and launch the APK.**
  - Run `make install`.
  - Run `adb shell monkey -p io.github.chessroguelike.spike -c android.intent.category.LAUNCHER 1`.
  - Keep `make logcat` running in a second terminal.
- [ ] **Step 4: Run the device checklist** and write down each result.

  | # | Check | Pass if |
  |---|---|---|
  | 1 | Cold start until the status reads `Ready` | It reaches `Ready`. Record the seconds |
  | 2 | Ten Play presses at Elo 1320 | Every press gives a move, and the eval updates |
  | 3 | Tick Full strength, then press Play | It gives a move |
  | 4 | Mate check | It shows `✓ a1a8` |
  | 5 | QGA check | Record the move it shows |
  | 6 | Speed label after Play | Record knps at 1000 ms |
  | 7 | Press Home during a search, wait 10 s, return | The app is alive and the next Play works |
  | 8 | Swipe the app away from Recents and relaunch | It reaches `Ready` again |
  | 9 | logcat for the whole session | No `FATAL`, no `signal 11`, no unexpected process exit |

- [ ] **Step 5: Write `docs/decisions/0001-engine-integration.md`.** It has five sections:
  - **Context:** spec §10.
  - **What was built:** Tasks 2–5.
  - **Measurements:** the device, the APK size and the checklist results.
  - **Decision:**
    - If every check passes, the GDExtension route is **confirmed**.
    - Otherwise, pick a fallback from spec §10: a Godot Android plugin that calls Stockfish through
      JNI, or an engine of our own. Explain why.
  - **Consequences:** these become inputs to the vertical-slice plan.
    - **Net strategy before the beta.** The full embedded net makes the APK larger than 100 MB.
      The alternatives are the 1.1 MB light net (the patch Lichess uses) or `EvalFile` loaded from
      `user://`.
    - **Opponents below Elo 1320** need a weakening approach of their own.
    - **The `std::exit` risk** means every move must be checked for legality before it is sent.
- [ ] **Step 6: Update spec §10.** Replace the "Not verified" `UCI_Elo` warning with the verified
  facts: the range is 1320–3190, and values outside it are silently ignored. Add the APK size
  finding with a link to the decision record.
- [ ] **Step 7: Commit.**

```bash
git add docs/decisions/0001-engine-integration.md docs/superpowers/specs/2026-10-26-chess-roguelike-design.md
git commit -m "docs: record engine integration spike outcome"
```
