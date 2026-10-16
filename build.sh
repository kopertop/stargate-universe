#!/usr/bin/env bash
# Build a self-contained HTML5 package for itch.io: dist/ + dist/sgu-destiny-html5.zip
#   - vendors Three.js 0.180 (module + addons) from jsdelivr via tools/vendor.py
#   - copies the repo assets the game loads under dist/assets/
#   - rewrites the import map to ./vendor/ and sets window.__ASSET_ROOT = './assets/'
# Usage: ./build.sh   (needs curl, python3, and either zip or python3 stdlib for zipfile fallback)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE"; DIST="$HERE/dist"
THREE_VER="0.180.0"
rm -rf "$DIST"; mkdir -p "$DIST/assets"

echo "→ sources"; cp -R "$HERE/src" "$HERE/data" "$DIST/"
echo "→ assets"
mkdir -p "$DIST/assets/models/quaternius/anim_lib" "$DIST/assets/sounds" "$DIST/assets/data"
cp "$REPO"/models/quaternius/anim_lib/UAL1_Standard.glb "$REPO"/models/quaternius/anim_lib/UAL2_Standard.glb "$DIST/assets/models/quaternius/anim_lib/"
mkdir -p "$DIST/assets/sounds/music/loops" "$DIST/assets/items"
cp "$HERE"/assets/items/*.png "$DIST/assets/items/"
for f in stargate_chevron_incom.mp3 gate_kawoosh.wav gate_active_hum.wav impact_metal_heavy_000.ogg impact_metal_000.ogg terminal_boot.ogg menu_open.ogg menu_close.ogg radio_click.ogg ftl-dropout.ogg discovery_stinger.ogg discovery_stinger_key.ogg footstep_01.ogg footstep_02.ogg footstep_03.ogg footstep_04.ogg footstep_desert_00.ogg footstep_desert_01.ogg footstep_desert_02.ogg footstep_desert_03.ogg; do cp "$REPO/sounds/$f" "$DIST/assets/sounds/"; done
cp "$REPO"/sounds/music/sgu_main_theme.mp3 "$DIST/assets/sounds/music/"
for f in bed_derelict_cold bed_ship_warm bed_space_vast bed_planet_open pad_shimmer pad_strings_tense pulse_slow pulse_drive mel_cello_lonely; do cp "$REPO/sounds/music/loops/$f.ogg" "$DIST/assets/sounds/music/loops/"; done
cp "$REPO"/data/items.json "$REPO"/data/ship_layout.json "$REPO"/data/room_connections.json "$REPO"/data/knockout_lines.json "$DIST/assets/data/"

echo "→ vendor three ${THREE_VER}"
python3 "$HERE/tools/vendor.py" "$HERE/src" "$DIST" "$THREE_VER"
rm -f "$DIST/src/recorder.js"   # dev-only (needs the local save server)

echo "→ zip"
rm -f "$DIST/sgu-destiny-html5.zip"
if command -v zip >/dev/null 2>&1; then
	( cd "$DIST" && zip -qr sgu-destiny-html5.zip index.html src data vendor assets )
else
	python3 "$HERE/tools/zip.py" "$DIST" sgu-destiny-html5.zip index.html src data vendor assets
fi
du -sh "$DIST/sgu-destiny-html5.zip" | awk '{print "   " $1 "  " $2}'
echo "done → upload dist/sgu-destiny-html5.zip to itch.io as an HTML project (index.html at zip root)."