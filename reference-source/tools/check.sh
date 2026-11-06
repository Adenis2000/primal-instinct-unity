#!/bin/bash
# Compile-check every GDScript file. Usage: tools/check.sh
export PATH=$HOME/bin:$PATH
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1
godot --headless --script res://tests/compile_all.gd 2>&1 | grep -v ALSA | grep -vE "^Godot Engine|audio|^\s+at: initialize"
