GODOT ?= $(HOME)/Applications/Godot.app/Contents/MacOS/Godot
ANDROID_HOME ?= $(HOME)/Library/Android/sdk
JAVA_HOME ?= /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
KEYSTORE := $(HOME)/Library/Application Support/Godot/keystores/debug.keystore
ADB := $(ANDROID_HOME)/platform-tools/adb
export ANDROID_HOME JAVA_HOME
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH := $(KEYSTORE)
export GODOT_ANDROID_KEYSTORE_DEBUG_USER := androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD := android
# The engine the game builds. Decision docs/decisions/0003-engine-net.md adopts the light net: Stockfish
# sf_19 plus native/patches/sf19-light-net.patch, in a patched copy of the submodule, and the 1.1 MB net
# that goes with it. SF_TREE is the Stockfish checkout to build and NET the net its evaluate.h embeds.
# To build the full net instead (a 94 MB net, from the pristine submodule), override both:
#   make SF_TREE=native/thirdparty/Stockfish NET=nn-1a298aa575a0.nnue BENCH_NODES=2497913 test
SF_TREE ?= build/stockfish-light
NET ?= nn-61e7af4bb97d.nnue
LIGHT_TREE := build/stockfish-light
LIGHT_PATCH := native/patches/sf19-light-net.patch
SUBMODULE := native/thirdparty/Stockfish
# sf_dir is relative to native/, where scons runs.
SCONS_ENGINE := sf_dir=../$(SF_TREE)/src net=$(NET)

# The light net is committed. The full net is downloaded by Stockfish's own makefile.
net: native/$(NET)
native/$(NET):
	@if [ "$(SF_TREE)" = "$(SUBMODULE)" ]; then \
		$(MAKE) -C $(SUBMODULE)/src net && cp $(SUBMODULE)/src/$(NET) native/$(NET); \
	else \
		echo "native/$(NET) is missing"; exit 1; \
	fi

# The patched Stockfish tree: a copy of the pristine submodule with the light-net patch applied. The
# submodule itself stays untouched. `git apply` run inside a subdirectory of another repository
# silently ignores the paths, and `patch -p1` does not follow the renames, so the copy gets a throwaway
# git repository of its own for the apply. The stamp holds the submodule revision and the patch's
# hash: the tree is rebuilt only when one of them changes. Nothing happens for another SF_TREE.
stockfish-tree:
	@set -e; \
	if [ "$(SF_TREE)" != "$(LIGHT_TREE)" ]; then exit 0; fi; \
	key="$$(git -C $(SUBMODULE) rev-parse HEAD) $$(shasum -a 256 < $(LIGHT_PATCH))"; \
	if [ -f $(LIGHT_TREE)/.patched ] && [ "$$(cat $(LIGHT_TREE)/.patched)" = "$$key" ]; then exit 0; fi; \
	echo "Patching a copy of Stockfish into $(LIGHT_TREE)"; \
	rm -rf $(LIGHT_TREE); \
	mkdir -p $(LIGHT_TREE); \
	rsync -a --exclude='.git' --exclude='*.o' --exclude='*.os' --exclude='*.nnue' $(SUBMODULE)/ $(LIGHT_TREE)/; \
	git -C $(LIGHT_TREE) init -q; \
	git -C $(LIGHT_TREE) apply "$(CURDIR)/$(LIGHT_PATCH)"; \
	rm -rf $(LIGHT_TREE)/.git; \
	echo "$$key" > $(LIGHT_TREE)/.patched

native-macos: net stockfish-tree
	scons -C native platform=macos arch=arm64 target=template_debug $(SCONS_ENGINE)

native-android: net stockfish-tree
	scons -C native platform=android arch=arm64 target=template_debug $(SCONS_ENGINE)

apk: native-android import
	mkdir -p build
	$(GODOT) --headless --path game --export-debug "Android" ../build/slice.apk

install: apk
	$(ADB) install -r build/slice.apk

logcat:
	$(ADB) logcat -s godot

# Godot 4.7.2's headless editor crashes when it discovers a GDExtension that is
# not yet listed in .godot/extension_list.cfg in a project it has imported before.
# Listing ours up front makes Godot load it at startup instead.
import:
	@mkdir -p game/.godot
	@grep -qx 'res://bin/stockfish_gd.gdextension' game/.godot/extension_list.cfg 2>/dev/null \
		|| echo 'res://bin/stockfish_gd.gdextension' >> game/.godot/extension_list.cfg
	$(GODOT) --headless --path game --import

# A desktop Stockfish for the offline tools, built out of tree so that the Stockfish checkout
# stays untouched. SF_TREE is built (see above): the net its evaluate.h names is taken from native/
# and embedded. SF_OUT receives the binary.
SF_OUT ?= build/stockfish

stockfish-cli: net stockfish-tree
	@set -e; \
	name=$$(grep -oE 'nn-[0-9a-f]{12}\.nnue' $(SF_TREE)/src/evaluate.h | head -1); \
	test -f native/$$name || { echo "native/$$name is missing: copy the net that $(SF_TREE) embeds there"; exit 1; }; \
	mkdir -p $(SF_OUT)/tree; \
	rsync -a --delete --exclude='.git' --exclude='*.o' --exclude='*.os' --exclude='*.nnue' $(SF_TREE)/ $(SF_OUT)/tree/; \
	cp native/$$name $(SF_OUT)/tree/src/$$name; \
	$(MAKE) -C $(SF_OUT)/tree/src -j $$(sysctl -n hw.ncpu) build ARCH=apple-silicon; \
	cp $(SF_OUT)/tree/src/stockfish $(SF_OUT)/stockfish

test: test-tools native-macos import
	scripts/run_tests.sh "$(GODOT)"

# The licence and the credits that the About screen shows ship in game/legal/ as copies of the files at
# the root. tools/legal/test_legal_copies.py fails when a copy is stale; this refreshes them.
legal:
	cp LICENSE game/legal/GPL-3.0.txt
	cp CREDITS.md game/legal/CREDITS.md

# Offline tools: unit tests for the Python scripts, and the puzzle subset builder.
# `puzzles` needs the Lichess dump in build/, which is not downloaded automatically: see CREDITS.md.
PUZZLE_DB := build/lichess_db_puzzle.csv.zst

test-tools:
	python3 -m unittest discover -s tools -p 'test_*.py'
	python3 tools/l10n/extract_strings.py game --check game/locale/messages.pot

# The translation template: every string the game shows. Italian is game/locale/it.po, written by hand.
pot:
	python3 tools/l10n/extract_strings.py game > game/locale/messages.pot.tmp \
	&& mv game/locale/messages.pot.tmp game/locale/messages.pot; \
	status=$$?; rm -f game/locale/messages.pot.tmp; exit $$status

# The strong positions' evaluations come from the game's own engine (the light-net build), at a fixed depth
# on one thread, so the output is reproducible. The file is written aside and moved only on success.
PUZZLES_FILE := game/data/puzzles/italian_game.json

puzzles: $(PUZZLE_DB) $(SF_OUT)/stockfish
	set -o pipefail; \
	zstd -dc $(PUZZLE_DB) | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white \
		--engine $(SF_OUT)/stockfish --strong-depth 14 > $(PUZZLES_FILE).tmp \
	&& mv $(PUZZLES_FILE).tmp $(PUZZLES_FILE); \
	status=$$?; rm -f $(PUZZLES_FILE).tmp; exit $$status

# Plays every strong position against the game's own engine, with a player who follows the hint, and
# prints how many it wins and how fast: the measure that tunes the strong enemy's win condition (see
# docs/research/2026-10-28-strong-tuning.md). It takes about 20 minutes. RATING sets the enemy's Elo.
RATING ?= 1200

strong-sim: native-macos import
	mkdir -p build
	$(GODOT) --headless --path game -s res://tools/strong_sim.gd -- --rating $(RATING) --out ../build/strong-sim-$(RATING).json

# The patched tree must reproduce the node count of the patch's own commit (2793281 for sf_19 plus the
# light-net patch), so a rebase onto a new Stockfish release is caught here. Stockfish prints the
# `bench` summary on stderr.
BENCH_NODES ?= 2793281

check-engine: stockfish-cli
	@nodes=$$($(SF_OUT)/stockfish bench 2>&1 | sed -n 's/^Nodes searched *: *//p'); \
	if [ "$$nodes" = "$(BENCH_NODES)" ]; then echo "bench: $$nodes nodes, as expected"; \
	else echo "bench: $${nodes:-no node count} nodes, expected $(BENCH_NODES)"; exit 1; fi

.PHONY: pot net stockfish-tree stockfish-cli check-engine native-macos native-android apk install logcat import test test-tools legal puzzles strong-sim
