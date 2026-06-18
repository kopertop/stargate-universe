#!/usr/bin/env bash
# Offline IndexTTS-2 voice-line bake. Renders a job's lines to WAVs under the repo, then
# runs `godot --headless --import` so each WAV gets its .import sidecar (without which
# AudioStream load() returns null in-game — same trap as PNGs/OGGs).
#
#   ./run.sh                # bake jobs/cold_open.json
#   ./run.sh cold_open      # explicit job name
#   SKIP_IMPORT=1 ./run.sh  # skip the godot import pass
#
# First run pulls the IndexTTS-2 checkpoints (several GB). Set INDEXTTS2_DIR to a
# pre-downloaded checkpoint dir to skip the HF fetch. Slow: ~30-130s per line.
set -uo pipefail
cd "$(dirname "$0")"

JOB="${1:-cold_open}"
REPO="$(cd ../.. && pwd)"

# indextts pins numba 0.58.1 / llvmlite 0.41.1 (no py3.12 wheel) -> use 3.11.
uv run --python-preference only-managed --python 3.11 \
	--with "git+https://github.com/index-tts/index-tts" \
	--with huggingface_hub --with soundfile \
	python bake.py "$JOB"
rc=$?
[ $rc -ne 0 ] && echo "[run] bake exited $rc" >&2

if [ "${SKIP_IMPORT:-0}" != "1" ]; then
	GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
	[ -x "$GODOT_BIN" ] || GODOT_BIN="$(command -v godot 2>/dev/null || true)"
	if [ -x "$GODOT_BIN" ]; then
		echo "[run] generating .import sidecars via godot --headless --import"
		( cd "$REPO" && "$GODOT_BIN" --headless --import 2>&1 | tail -3 )
	else
		echo "[run] WARNING: Godot not found — run 'godot --headless --import' yourself so the WAVs load." >&2
	fi
fi
echo "[run] done."
