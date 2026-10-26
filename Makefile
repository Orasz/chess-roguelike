GODOT ?= $(HOME)/Applications/Godot.app/Contents/MacOS/Godot

import:
	$(GODOT) --headless --path game --import

test: import
	scripts/run_tests.sh "$(GODOT)"
