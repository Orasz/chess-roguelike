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

# Godot 4.7.2's headless editor crashes when it discovers a GDExtension that is
# not yet listed in .godot/extension_list.cfg in a project it has imported before.
# Listing ours up front makes Godot load it at startup instead.
native-android: net
	scons -C native platform=android arch=arm64 target=template_debug

apk: native-android import
	mkdir -p build
	$(GODOT) --headless --path game --export-debug "Android" ../build/spike.apk

install: apk
	$(ADB) install -r build/spike.apk

logcat:
	$(ADB) logcat -s godot

import:
	@mkdir -p game/.godot
	@grep -qx 'res://bin/stockfish_gd.gdextension' game/.godot/extension_list.cfg 2>/dev/null \
		|| echo 'res://bin/stockfish_gd.gdextension' >> game/.godot/extension_list.cfg
	$(GODOT) --headless --path game --import

test: native-macos import
	scripts/run_tests.sh "$(GODOT)"

.PHONY: net native-macos native-android apk install logcat import test
