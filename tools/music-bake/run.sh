#!/usr/bin/env bash
# Bake a job's SGU music stems via ElevenLabs, transcode to .ogg, generate Godot .import
# sidecars, and build the audition page.
#
#   ./run.sh                 # bake jobs/sgu_sample.json (the audition batch)
#   ./run.sh sgu_full        # bake the full library
#   SKIP_IMPORT=1 ./run.sh   # skip the godot import pass
#   SKIP_INDEX=1 ./run.sh    # skip rebuilding out/index.html
#
# Requires ELEVENLABS_API_KEY in the environment and ffmpeg on PATH. Stem prompts live in
# palette.py; jobs/*.json select which to bake.
set -uo pipefail
cd "$(dirname "$0")"

JOB="${1:-sgu_sample}"
REPO="$(cd ../.. && pwd)"

if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
	echo "[run] ERROR: ELEVENLABS_API_KEY not set. export it (or pass inline) before baking." >&2
	exit 1
fi
command -v ffmpeg >/dev/null 2>&1 || { echo "[run] ERROR: ffmpeg not found on PATH." >&2; exit 1; }

# --python-preference only-managed so an active conda base can't shadow uv's env
# (see feedback_uv_run_anaconda_sitepackages_leak).
uv run --python-preference only-managed --with elevenlabs python bake.py "$JOB"
rc=$?
[ $rc -ne 0 ] && echo "[run] bake exited $rc" >&2

if [ "${SKIP_IMPORT:-0}" != "1" ]; then
	GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
	[ -x "$GODOT_BIN" ] || GODOT_BIN="$(command -v godot 2>/dev/null || true)"
	if [ -x "$GODOT_BIN" ]; then
		echo "[run] generating .import sidecars via godot --headless --import"
		( cd "$REPO" && "$GODOT_BIN" --headless --import 2>&1 | tail -3 )
	else
		echo "[run] WARNING: Godot not found — run 'godot --headless --import' yourself so the OGGs load." >&2
	fi
fi

if [ "${SKIP_INDEX:-0}" != "1" ]; then
	uv run --python-preference only-managed python build_index.py
	echo "[run] audition: open tools/music-bake/out/index.html"
fi
echo "[run] done."
