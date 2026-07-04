#!/usr/bin/env bash
# hud_loop.sh — capture the live HUD over a gameplay scene and score it against
# the WoW concept image. The driver for the Karpathy commit-if-closer loop on
# the HUD redesign (see docs/hud-redesign/HANDOFF.md).
#
# It does NOT decide commit/rollback for you — it prints a deterministic SCORE
# (and the delta vs the recorded baseline) so YOU (or a wrapper) can decide.
#
# Usage:
#   tools/hud_loop.sh <label> [room_id] [scene]
#     label    output name, e.g. "baseline" or "phase1"
#     room_id  room to spawn (default: control_interface_room)
#     scene    scene to launch (default: res://scenes/room.tscn)
#
# Env:
#   GODOT_BIN       path to Godot (default: /Applications/Godot.app/...)
#   RENDER_DRIVER   e.g. "opengl3" to force GLES (default: project Forward+)
#   REF             reference image (default: docs/hud-redesign/wow-hud-reference.png)
#
# Outputs (under docs/hud-redesign/captures/):
#   <label>.png         the raw HUD capture
#   <label>.json        per-region score breakdown
#   <label>.composite.png  side-by-side concept|candidate w/ region boxes
#   _scores.log         append-only history of label<TAB>score
#
# NOTE: must run HEADED — `--headless` disables rendering and saves a blank PNG
# (memory godot-png/headless capture). A window flashes briefly then quits.

set -u
cd "$(dirname "$0")/.."

LABEL="${1:?usage: hud_loop.sh <label> [room_id] [scene]}"
ROOM_ID="${2:-control_interface_room}"
SCENE="${3:-res://scenes/room.tscn}"
REF="${REF:-docs/hud-redesign/wow-hud-reference.png}"

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	command -v godot >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)" || {
		echo "ERROR: cannot find Godot. Set GODOT_BIN." >&2; exit 2; }
fi

OUT_DIR="docs/hud-redesign/captures"
mkdir -p "$OUT_DIR"

# user:// resolves to the macOS app_userdata dir; capture.png is written there
# by scripts/test_capture.gd (the TestCapture autoload, armed by the "capture" arg).
USER_CAPTURE="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe/capture.png"
rm -f "$USER_CAPTURE"

DRIVER_ARGS=()
[[ -n "${RENDER_DRIVER:-}" ]] && DRIVER_ARGS=(--rendering-driver "$RENDER_DRIVER")

echo "[hud_loop] capturing '$LABEL' — scene=$SCENE room_id=$ROOM_ID"
"$GODOT_BIN" ${DRIVER_ARGS[@]+"${DRIVER_ARGS[@]}"} --quit-after 200 "$SCENE" ++ capture "room_id=${ROOM_ID}" \
	2>&1 | grep -E "(\[test_capture\]|ERROR|SCRIPT ERROR)" || true

if [[ ! -f "$USER_CAPTURE" ]]; then
	echo "[hud_loop] ✗ capture missing at: $USER_CAPTURE" >&2
	exit 1
fi
cp "$USER_CAPTURE" "$OUT_DIR/${LABEL}.png"
echo "[hud_loop] ✓ $OUT_DIR/${LABEL}.png"

SCORE_OUT=$(python3 tools/hud_compare.py \
	--reference "$REF" \
	--candidate "$OUT_DIR/${LABEL}.png" \
	--json "$OUT_DIR/${LABEL}.json" \
	--composite "$OUT_DIR/${LABEL}.composite.png")
echo "$SCORE_OUT"

SCORE=$(echo "$SCORE_OUT" | grep -oE 'SCORE=[0-9.]+' | cut -d= -f2)
printf '%s\t%s\n' "$LABEL" "$SCORE" >> "$OUT_DIR/_scores.log"

# Delta vs the recorded baseline, if present.
BASE=$(grep -E '^baseline\b' "$OUT_DIR/_scores.log" 2>/dev/null | tail -1 | cut -f2)
if [[ -n "${BASE:-}" && "$LABEL" != "baseline" ]]; then
	DELTA=$(python3 -c "print(f'{${SCORE} - ${BASE}:+.4f}')")
	VERDICT=$(python3 -c "print('CLOSER ✓ (commit)' if ${SCORE} > ${BASE} else 'NOT closer ✗ (rollback)')")
	echo "[hud_loop] $LABEL=$SCORE  baseline=$BASE  delta=$DELTA  -> $VERDICT"
fi
