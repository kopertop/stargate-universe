#!/usr/bin/env bash
# Record the crew showcase + standoff cutscene via Godot Movie Maker and
# transcode to MP4. Needs a GPU context (NOT --headless) — local only.
#   tools/record_showcase.sh [showcase|standoff|all]
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
WHAT="${1:-all}"
mkdir -p out/raw

record() {
	local name="$1" scene="$2"
	echo "=== recording $name ==="
	"$GODOT_BIN" --path . \
		--write-movie "out/raw/${name}.avi" \
		--fixed-fps 30 \
		--resolution 1280x720 \
		"$scene" 2>&1 | tail -2 || true
	echo "=== transcoding $name ==="
	ffmpeg -y -loglevel error -i "out/raw/${name}.avi" \
		-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
		-movflags +faststart \
		"out/${name}.mp4"
	echo "saved out/${name}.mp4"
}

if [[ "$WHAT" == "showcase" || "$WHAT" == "all" ]]; then
	record "crew_showcase" "tools/showcase/showcase.tscn"
fi
if [[ "$WHAT" == "standoff" || "$WHAT" == "all" ]]; then
	record "cutscene_standoff" "tools/showcase/cutscene_standoff.tscn"
fi
echo "done."
