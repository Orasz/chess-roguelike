#!/usr/bin/env bash
# Run the GUT suite headless and fail on what GUT itself lets through:
# test scripts skipped because of parse errors, and runs where nothing ran.
set -uo pipefail

godot=$1
log=$(mktemp)
trap 'rm -f "$log"' EXIT

"$godot" --headless --path game -s addons/gut/gut_cmdln.gd \
  -gdir=res://test -ginclude_subdirs -gexit 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if grep -qE "SCRIPT ERROR|Ignoring script|Nothing was run" "$log"; then
  echo "run_tests: a test script failed to load or nothing ran" >&2
  exit 1
fi
exit "$status"
