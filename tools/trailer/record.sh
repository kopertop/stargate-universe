#!/usr/bin/env bash
# Capture a REAL human playthrough for the trailer generator.
#
# Launches the game normally (windowed, Forward+) with the trailer-capture flag
# set, so this ONE run records the live camera + character path + animation +
# scene changes every frame. Play the stretch you want in the trailer, then quit
# (Esc → menu, or close the window) — the capture JSON is written on exit.
#
# Normal play (without this launcher) records nothing.
#
#   tools/trailer/record.sh [out.json]
#
# Then render the trailer from the capture with:
#   tools/make_trailer.sh           (replay mode auto-detects the capture)

set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "ERROR: cannot find Godot. Set GODOT_BIN or add 'godot' to PATH." >&2
		exit 2
	fi
fi

OUT="${1:-$ROOT/out/capture/playthrough.json}"
mkdir -p "$(dirname "$OUT")"

echo "=== trailer capture ==="
echo "  Recording this run → $OUT"
echo "  Play the part you want in the trailer, then QUIT the game to save."
echo "  (Tip: keep it tight — walk the route, talk to NPCs, use the Kino, step"
echo "   through the gate, mine, return. Whatever you do is what gets filmed.)"
echo

SGU_TRAILER_RECORD="$OUT" "$GODOT_BIN" --rendering-driver metal

if [[ -f "$OUT" ]]; then
	echo
	echo "=== capture saved: $OUT ==="
	echo "  Now render the trailer:  tools/make_trailer.sh"
else
	echo "WARN: no capture written. Did gameplay start (a 3D camera must be active)?" >&2
fi
