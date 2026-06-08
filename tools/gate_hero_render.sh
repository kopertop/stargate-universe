#!/usr/bin/env bash
# Render the hero gate-room beauty shot to a known path for the self-improvement
# loop. Outputs to screenshots/loop/<name>.png (default: candidate).
#
#   tools/gate_hero_render.sh            # → screenshots/loop/candidate.png
#   tools/gate_hero_render.sh best       # → screenshots/loop/best.png
#
# Forward+ (project default); NOT --headless (that yields a blank frame).
#
# CROSS-PLATFORM (macOS dev + sparky/Linux loop host):
#   • GODOT_BIN: env override → macOS Godot.app → `godot` / `godot4` on PATH.
#   • Linux headless: the render needs an X display for Godot's window even when a
#     Vulkan GPU does the rasterising, so if there's no $DISPLAY we wrap the run in
#     `xvfb-run` (a virtual framebuffer). Install with: sudo apt-get install -y xvfb.
#   • Output userdata dir differs per-OS; we locate it from `uname`.

set -u
cd "$(dirname "$0")/.."

# --- resolve Godot binary -------------------------------------------------
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
	if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
		GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
	elif command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	elif command -v godot4 >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot4)"
	else
		echo "ERROR: no Godot binary (set GODOT_BIN=/path/to/godot)"; exit 2
	fi
fi

NAME="${1:-candidate}"
WAIT="${2:-150}"
mkdir -p screenshots/loop

# --- display wrapper: Xvfb on headless Linux ------------------------------
# On macOS (and any host with a real $DISPLAY) RUN runs Godot directly. On Linux
# with no display, prefix with xvfb-run so Godot can open its (offscreen) window.
RUN=( )
if [[ "$(uname -s)" == "Linux" && -z "${DISPLAY:-}" ]]; then
	if command -v xvfb-run >/dev/null 2>&1; then
		RUN=( xvfb-run -a -s "-screen 0 1280x720x24" )
	else
		echo "WARN: Linux headless but xvfb-run not found — render may produce a blank frame."
		echo "      install with: sudo apt-get install -y xvfb"
	fi
fi

# Import first so any new shader/.tscn has sidecars (silent-fail trap otherwise).
# ${RUN[@]+...} expands safely even when RUN is empty under `set -u` (bash 3.2).
"${RUN[@]+"${RUN[@]}"}" "$GODOT_BIN" --headless --import >/dev/null 2>&1 || true

"${RUN[@]+"${RUN[@]}"}" "$GODOT_BIN" --quit-after 700 -s res://tests/shots/hero_shot.gd ++ out=user://hero.png wait="$WAIT" 2>&1 \
	| grep -E "CAM |SHOT |SHOT_ERROR|SHOT_WARN" || true

# --- locate the rendered PNG in the per-OS userdata dir -------------------
case "$(uname -s)" in
	Darwin) USERDATA="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe" ;;
	*)      USERDATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Stargate Universe" ;;
esac
ABS="$USERDATA/hero.png"
if [[ -f "$ABS" ]]; then
	cp "$ABS" "screenshots/loop/${NAME}.png"
	echo "  -> screenshots/loop/${NAME}.png"
else
	echo "  ✗ no image produced at $ABS"
	exit 3
fi
