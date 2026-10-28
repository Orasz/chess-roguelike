GODOT ?= $(HOME)/Applications/Godot.app/Contents/MacOS/Godot
ANDROID_HOME ?= $(HOME)/Library/Android/sdk
JAVA_HOME ?= /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
KEYSTORE := $(HOME)/Library/Application Support/Godot/keystores/debug.keystore
ADB := $(ANDROID_HOME)/platform-tools/adb
export ANDROID_HOME JAVA_HOME
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH := $(KEYSTORE)
export GODOT_ANDROID_KEYSTORE_DEBUG_USER := androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD := android
NET := nn-1a298aa575a0.nnue

net: native/$(NET)
native/$(NET):
	$(MAKE) -C native/thirdparty/Stockfish/src net
	cp native/thirdparty/Stockfish/src/$(NET) native/$(NET)

native-macos: net
	scons -C native platform=macos arch=arm64 target=template_debug

native-android: net
	scons -C native platform=android arch=arm64 target=template_debug

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
# stays untouched. SF_TREE is a Stockfish checkout (the submodule, or a patched copy of it): the
# net its evaluate.h names is taken from native/ and embedded. SF_OUT receives the binary.
SF_TREE ?= native/thirdparty/Stockfish
SF_OUT ?= build/stockfish

stockfish-cli: net
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

# Offline tools: unit tests for the Python scripts, and the puzzle subset builder.
# `puzzles` needs the Lichess dump in build/, which is not downloaded automatically: see CREDITS.md.
PUZZLE_DB := build/lichess_db_puzzle.csv.zst

test-tools:
	python3 -m unittest discover -s tools -p 'test_*.py'

puzzles: $(PUZZLE_DB)
	zstd -dc $(PUZZLE_DB) | python3 tools/puzzles/build_subset.py --opening Italian_Game --side white > game/data/puzzles/italian_game.json

.PHONY: net stockfish-cli native-macos native-android apk install logcat import test test-tools puzzles
