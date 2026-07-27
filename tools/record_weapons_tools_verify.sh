#!/usr/bin/env bash
# Record weapons-tools playtest verify: tablet-only, hotwire UI, loading overlay.
#
# Writes:
#   screenshots/result/weapons_tools_verify.mp4
#   screenshots/result/weapons_tools_verify/*.png
#
#   tools/record_weapons_tools_verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
RAW_AVI="screenshots/result/weapons_tools_verify_raw.avi"
OUT_MP4="screenshots/result/weapons_tools_verify.mp4"
OVERRIDE_CFG="override.cfg"
OUT_DIR="screenshots/result/weapons_tools_verify"

mkdir -p "$OUT_DIR" out/raw

cleanup() {
	rm -f "$OVERRIDE_CFG"
}
trap cleanup EXIT

cat > "$OVERRIDE_CFG" <<'EOF'
[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/size/mode=0
EOF

rm -f "$RAW_AVI" "$OUT_MP4"

echo "=== recording weapons_tools_verify ==="
set +e
"$GODOT_BIN" --path . \
	--rendering-driver metal \
	--fixed-fps 30 \
	--resolution 1280x720 \
	--write-movie "$RAW_AVI" \
	-s res://tests/shots/weapons_tools_verify_movie.gd \
	2>&1 | tee screenshots/result/weapons_tools_verify_record.log
GODOT_EC=${PIPESTATUS[0]}
set -e
echo "[record] Godot exit=$GODOT_EC"

if [[ ! -f "$RAW_AVI" ]]; then
	echo "ERROR: Movie Maker did not write $RAW_AVI" >&2
	exit 1
fi

IDLE_PNG="$OUT_DIR/01_tablet_only_idle.png"
if [[ ! -f "$IDLE_PNG" ]]; then
	echo "ERROR: missing $IDLE_PNG — recording aborted early" >&2
	exit 1
fi

echo "=== transcoding → $OUT_MP4 ==="
ffmpeg -y -loglevel error -i "$RAW_AVI" \
	-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
	-c:a aac -b:a 192k \
	-movflags +faststart \
	"$OUT_MP4"
echo "saved $OUT_MP4"
ls -la "$OUT_DIR"/*.png "$OUT_MP4" 2>/dev/null || true
exit "$GODOT_EC"
