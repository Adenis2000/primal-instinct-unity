#!/bin/bash
# Screenshot tour of the real UI under a virtual display. Output: screenshots/*.png
export PATH=$HOME/bin:$PATH
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1
rm -f screenshots/*.png
timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy -- --tour --out="$PWD/screenshots" 2>&1 | grep -v -E "ALSA|^Godot Engine|audio driver|initialize \(" | tee /tmp/tour_out.txt
exit ${PIPESTATUS[0]}
