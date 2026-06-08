#!/usr/bin/env bash
# Render the hero gate-room beauty shot to a known path for the self-improvement
# loop. Outputs to screenshots/loop/<name>.png (default: candidate).
#
#   tools/gate_hero_render.sh            # → screenshots/loop/candidate.png
#   tools/gate_hero_render.sh best       # → screenshots/loop/best.png
#
# Forward+ (project default); NOT --headless (that yields a blank frame).

set -u
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	command -v godot >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)" || { echo "ERROR: no Godot binary (set GODOT_BIN)"; exit 2; }
fi

NAME="${1:-candidate}"
WAIT="${2:-150}"
mkdir -p screenshots/loop

# Import first so any new shader/.tscn has sidecars (silent-fail trap otherwise).
"$GODOT_BIN" --headless --import >/dev/null 2>&1 || true

"$GODOT_BIN" --quit-after 700 -s res://tests/shots/hero_shot.gd ++ out=user://hero.png wait="$WAIT" 2>&1 \
	| grep -E "CAM |SHOT |SHOT_ERROR|SHOT_WARN" || true

ABS="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe/hero.png"
if [[ -f "$ABS" ]]; then
	cp "$ABS" "screenshots/loop/${NAME}.png"
	echo "  -> screenshots/loop/${NAME}.png"
else
	echo "  ✗ no image produced at $ABS"
	exit 3
fi
