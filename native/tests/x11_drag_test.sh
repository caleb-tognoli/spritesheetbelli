#!/bin/bash
# Drags a file from a GTK window into Godot's, out, back in, and drops it, on a virtual X
# display, and checks the monitor saw it (see drag_probe.gd). Needs Xvfb, xdotool,
# python3-gi with GTK 3 (for the system Python, or $PYTHON), a built library (python
# native/build.py) and Godot:
#   GODOT=path/to/godot native/tests/x11_drag_test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
project=$(cd "$here/../.." && pwd)
godot=${GODOT:-godot}
export DISPLAY=:99

Xvfb "$DISPLAY" -screen 0 1280x800x24 >/dev/null 2>&1 &
xvfb=$!
trap 'kill $xvfb $source 2>/dev/null' EXIT
sleep 1
"$godot" --headless --path "$project" --import >/dev/null 2>&1
"$godot" --path "$project" --display-driver x11 --rendering-driver opengl3 \
	-s "$here/drag_probe.gd" &
probe=$!
"${PYTHON:-/usr/bin/python3}" "$here/drag_source_gtk.py" "$project/icon.svg" &
source=$!
sleep 5

glide() {
	for i in $(seq 1 20); do
		xdotool mousemove $(($1 + ($3 - $1) * i / 20)) $(($2 + ($4 - $2) * i / 20))
		sleep 0.02
	done
}
xdotool mousemove 900 200
sleep 0.3
xdotool mousedown 1
glide 900 200 400 300
sleep 1
glide 400 300 20 20
sleep 1
glide 20 20 400 300
sleep 1
xdotool mouseup 1

wait $probe
