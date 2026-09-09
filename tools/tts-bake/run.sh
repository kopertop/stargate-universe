#!/usr/bin/env bash
# Offline IndexTTS-2 voice-line bake. Renders a job's lines to WAVs under sounds/dialog/ for the web game.
#
#   ./run.sh                # bake jobs/cold_open.json
#   ./run.sh cold_open      # explicit job name
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

# (the Godot .import sidecar pass was removed with the Godot build on 2026-09-08; the web game plays WAV/MP3 directly)

echo "[run] done."
