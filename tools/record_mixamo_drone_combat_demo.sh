#!/usr/bin/env bash
# Record Mixamo gate_room combat demo: Target Lock + destroy hostile drone.
# Uses lit Destiny gate room + Eli host. Does not steal OS mouse.
#
# Writes:
#   screenshots/result/mixamo_drone_combat_demo.mp4
#   screenshots/result/mixamo_drone_combat_demo/*.png
# Also copies into ~/Desktop/SGU Demos/
#
#   tools/record_mixamo_drone_combat_demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
RAW_AVI="screenshots/result/mixamo_drone_combat_demo_raw.avi"
OUT_MP4="screenshots/result/mixamo_drone_combat_demo.mp4"
OVERRIDE_CFG="override.cfg"
DESKTOP_DIR="${HOME}/Desktop/SGU Demos"

mkdir -p screenshots/result/mixamo_drone_combat_demo out/raw "$DESKTOP_DIR"

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

echo "=== recording Mixamo drone combat demo (gate_room + Eli) ==="
set +e
"$GODOT_BIN" --path . \
	--rendering-driver metal \
	--fixed-fps 30 \
	--resolution 1280x720 \
	--write-movie "$RAW_AVI" \
	-s res://tests/shots/mixamo_drone_combat_demo_movie.gd \
	2>&1 | tee screenshots/result/mixamo_drone_combat_demo_record.log
GODOT_EC=${PIPESTATUS[0]}
set -e
echo "[record] Godot exit=$GODOT_EC"

if [[ ! -f "$RAW_AVI" ]]; then
	echo "ERROR: Movie Maker did not write $RAW_AVI" >&2
	exit 1
fi

# Fail if the idle beat is near-black (previous void-arena failure mode).
IDLE_PNG="screenshots/result/mixamo_drone_combat_demo/01_idle.png"
if [[ ! -f "$IDLE_PNG" ]]; then
	echo "ERROR: missing $IDLE_PNG — recording aborted early" >&2
	exit 1
fi
python3 - <<'PY'
from pathlib import Path
p = Path("screenshots/result/mixamo_drone_combat_demo/01_idle.png")
# Minimal PNG reader via Godot already validated bright_ratio; here check file size.
if p.stat().st_size < 80_000:
    raise SystemExit(f"ERROR: idle beat too small ({p.stat().st_size} bytes) — likely blank")
print(f"idle beat ok: {p.stat().st_size} bytes")
PY

echo "=== transcoding → $OUT_MP4 (video + audio) ==="
# Movie Maker AVI carries pcm_s16le — keep it (earlier remux dropped audio).
ffmpeg -y -loglevel error -i "$RAW_AVI" \
	-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
	-c:a aac -b:a 192k \
	-movflags +faststart \
	"$OUT_MP4"
echo "saved $OUT_MP4"
ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 "$OUT_MP4"
ffprobe -v error -show_entries format=duration,size -of default=nw=1:nk=1 "$OUT_MP4" \
	| paste - - | awk '{printf "duration: %.1fs  size: %.1fMB\n", $1, $2/1024/1024}'

STAMP="$(date +%Y%m%d_%H%M%S)"
DEST_MP4="${DESKTOP_DIR}/SGU_Drone_Combat_Demo_${STAMP}.mp4"
DEST_DIR="${DESKTOP_DIR}/SGU_Drone_Combat_Demo_${STAMP}_frames"
cp -f "$OUT_MP4" "$DEST_MP4"
mkdir -p "$DEST_DIR"
cp -f screenshots/result/mixamo_drone_combat_demo/*.png "$DEST_DIR/" 2>/dev/null || true
# Also keep a stable latest name for quick open.
cp -f "$OUT_MP4" "${DESKTOP_DIR}/SGU_Drone_Combat_Demo_LATEST.mp4"
echo "copied → $DEST_MP4"
echo "frames → $DEST_DIR"
echo "latest → ${DESKTOP_DIR}/SGU_Drone_Combat_Demo_LATEST.mp4"
echo "done."
