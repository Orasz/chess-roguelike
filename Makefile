GODOT ?= $(HOME)/Applications/Godot.app/Contents/MacOS/Godot
NET := nn-1a298aa575a0.nnue

net: native/$(NET)
native/$(NET):
	$(MAKE) -C native/thirdparty/Stockfish/src net
	cp native/thirdparty/Stockfish/src/$(NET) native/$(NET)

native-macos: net
	scons -C native platform=macos arch=arm64 target=template_debug

# Godot 4.7.2's headless editor crashes when it discovers a GDExtension that is
# not yet listed in .godot/extension_list.cfg in a project it has imported before.
# Listing ours up front makes Godot load it at startup instead.
import:
	@mkdir -p game/.godot
	@grep -qx 'res://bin/stockfish_gd.gdextension' game/.godot/extension_list.cfg 2>/dev/null \
		|| echo 'res://bin/stockfish_gd.gdextension' >> game/.godot/extension_list.cfg
	$(GODOT) --headless --path game --import

test: native-macos import
	scripts/run_tests.sh "$(GODOT)"

.PHONY: net native-macos import test
