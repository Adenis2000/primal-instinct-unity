#!/bin/bash
# Runs the headless suite; fails on test failures OR any engine script error in the output.
export PATH=$HOME/bin:$PATH
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1
godot --headless --script res://tests/run_tests.gd 2>&1 | grep -v -E "ALSA|^Godot Engine|audio driver|initialize \(" | tee /tmp/test_out.txt
code=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|^ERROR:" /tmp/test_out.txt; then echo "ENGINE ERRORS DETECTED"; code=1; fi
exit $code
