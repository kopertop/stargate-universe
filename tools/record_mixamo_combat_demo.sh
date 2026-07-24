#!/usr/bin/env bash
# Record Mixamo ship-scene combat demo (walk → aim → fire → holster).
# Needs a GPU window (NOT --headless). Writes:
#   screenshots/result/mixamo_combat_demo.mp4
#   screenshots/result/mixamo_combat_demo/*.png (scripted beat frames)
#
#   tools/record_mixamo_combat_demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
RAW_AVI="screenshots/result/mixamo_combat_demo_raw.avi"
OUT_MP4="screenshots/result/mixamo_combat_demo.mp4"
OVERRIDE_CFG="override.cfg"

mkdir -p screenshots/result/mixamo_combat_demo out/raw

cleanup() {
	rm -f "$OVERRIDE_CFG"
}
trap cleanup EXIT

# Movie Maker records at project viewport size; pin 1280x720 for the demo.
cat > "$OVERRIDE_CFG" <<'EOF'
[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/size/mode=0
EOF

echo "=== recording Mixamo combat demo ==="
"$GODOT_BIN" --path . \
	--rendering-driver metal \
	--fixed-fps 30 \
	--resolution 1280x720 \
	--write-movie "$RAW_AVI" \
	-s res://tests/shots/mixamo_combat_demo_movie.gd \
	2>&1 | tee screenshots/result/mixamo_combat_demo_record.log | tail -40

if [[ ! -f "$RAW_AVI" ]]; then
	echo "ERROR: Movie Maker did not write $RAW_AVI" >&2
	echo "Beat PNGs (if any) are under screenshots/result/mixamo_combat_demo/" >&2
	exit 1
fi

echo "=== transcoding → $OUT_MP4 ==="
ffmpeg -y -loglevel error -i "$RAW_AVI" \
	-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
	-movflags +faststart \
	"$OUT_MP4"
echo "saved $OUT_MP4"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT_MP4" \
	| awk '{printf "duration: %.1fs\n", $1}'
echo "beat frames: screenshots/result/mixamo_combat_demo/"
echo "done."
