#!/usr/bin/env bash
# Record Mixamo ship-scene combat demo (walk → aim → fire → holster).
# Needs a GPU window (NOT --headless). Writes:
#   screenshots/result/mixamo_combat_demo.mp4
#   screenshots/result/mixamo_combat_demo/*.png (scripted beat frames)
#
#   tools/record_mixamo_combat_demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer PATH / GODOT_BIN; fall back to macOS app bundle.
if [[ -z "${GODOT_BIN:-}" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
		GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
	else
		echo "ERROR: cannot find Godot. Set GODOT_BIN or add godot to PATH." >&2
		exit 2
	fi
fi

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

# Pick a rendering driver that exists on this host.
RENDER_DRIVER="${GODOT_RENDER_DRIVER:-}"
if [[ -z "$RENDER_DRIVER" ]]; then
	case "$(uname -s)" in
		Darwin) RENDER_DRIVER="metal" ;;
		*) RENDER_DRIVER="vulkan" ;;
	esac
fi

if [[ ! -f models/mixamo_openbot/YBot_rifle_combat.glb \
	&& ! -f models/mixamo_openbot/Swat_rifle_combat.glb \
	&& ! -f models/mixamo_openbot/Swat_rifle_idle.glb ]]; then
	echo "ERROR: Mixamo combat pack missing. Rebuild with:" >&2
	echo "  blender -b -P tools/blender_mixamo_rifle_combat.py -- --host ybot  # preferred" >&2
	echo "  blender -b -P tools/blender_mixamo_proxy_combat.py               # cloud fallback" >&2
	exit 1
fi

run_movie() {
	local driver="$1"
	echo "=== recording Mixamo combat demo (driver=$driver) ==="
	"$GODOT_BIN" --path . \
		--rendering-driver "$driver" \
		--fixed-fps 30 \
		--resolution 1280x720 \
		--write-movie "$RAW_AVI" \
		-s res://tests/shots/mixamo_combat_demo_movie.gd \
		2>&1 | tee screenshots/result/mixamo_combat_demo_record.log | tail -60
}

run_movie "$RENDER_DRIVER" || true
if [[ ! -f "$RAW_AVI" && "$RENDER_DRIVER" == "vulkan" ]]; then
	echo "WARN: vulkan Movie Maker produced no AVI — retrying with opengl3" >&2
	run_movie "opengl3" || true
fi

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
