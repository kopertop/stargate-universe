#!/usr/bin/env bash
# Build a self-contained HTML5 package for itch.io: dist/ + dist/sgu-destiny-html5.zip
#   - vendors Three.js 0.180 (module + the addons we import, with their relative deps) from jsdelivr
#   - copies the repo assets the game loads (Quaternius rig/clips, gate sounds, items.json) under dist/assets/
#   - rewrites the import map to ./vendor/ and sets window.__ASSET_ROOT = './assets/'
# Usage: web/gate-room/build.sh   (needs curl, python3, zip)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"; DIST="$HERE/dist"
THREE_VER="0.180.0"; CDN="https://cdn.jsdelivr.net/npm/three@${THREE_VER}"
rm -rf "$DIST"; mkdir -p "$DIST/vendor/three/build" "$DIST/vendor/three/examples/jsm" "$DIST/assets"

echo "→ sources"; cp -R "$HERE/src" "$HERE/data" "$DIST/"
echo "→ assets"
mkdir -p "$DIST/assets/models/quaternius/anim_lib" "$DIST/assets/sounds" "$DIST/assets/data"
cp "$REPO"/models/quaternius/anim_lib/UAL1_Standard.glb "$REPO"/models/quaternius/anim_lib/UAL2_Standard.glb "$DIST/assets/models/quaternius/anim_lib/"
cp "$REPO"/sounds/stargate_chevron_incom.mp3 "$REPO"/sounds/gate_kawoosh.wav "$REPO"/sounds/gate_active_hum.wav "$DIST/assets/sounds/"
cp "$REPO"/data/items.json "$REPO"/data/ship_layout.json "$REPO"/data/room_connections.json "$DIST/assets/data/"

echo "→ vendor three ${THREE_VER}"
curl -fsSL "$CDN/build/three.module.js" -o "$DIST/vendor/three/build/three.module.js"
# r16x+ splits the module build: three.module.js re-exports ./three.core.js
curl -fsSL "$CDN/build/three.core.js" -o "$DIST/vendor/three/build/three.core.js"
# resolve the addon import graph (relative imports inside examples/jsm) starting from what src/ imports
python3 - "$HERE/src" "$DIST/vendor/three/examples/jsm" "$CDN/examples/jsm" <<'PY'
import re, sys, os, subprocess, pathlib
src, out, cdn = sys.argv[1], sys.argv[2], sys.argv[3]
seeds = set()
for f in pathlib.Path(src).glob('*.js'):
    for m in re.finditer(r"""['"]three/addons/([^'"]+)['"]""", f.read_text()): seeds.add(m.group(1))
todo, done = list(seeds), set()
while todo:
    rel = todo.pop()
    if rel in done: continue
    done.add(rel)
    dst = pathlib.Path(out, rel); dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['curl', '-fsSL', f'{cdn}/{rel}', '-o', str(dst)], check=True)
    for m in re.finditer(r"""from\s+['"](\.{1,2}/[^'"]+)['"]""", dst.read_text()):
        todo.append(os.path.normpath(os.path.join(os.path.dirname(rel), m.group(1))))
print(f'   vendored {len(done)} addon files: {sorted(done)}')
PY

echo "→ index.html"
python3 - "$HERE/index.html" "$DIST/index.html" <<'PY'
import sys
h = open(sys.argv[1]).read()
h = h.replace('"three": "https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js"', '"three": "./vendor/three/build/three.module.js"')
h = h.replace('"three/addons/": "https://cdn.jsdelivr.net/npm/three@0.180.0/examples/jsm/"', '"three/addons/": "./vendor/three/examples/jsm/"')
h = h.replace('<script type="module" src="./src/main.js"></script>', '<script>window.__ASSET_ROOT = "./assets/";</script>\n<script type="module" src="./src/main.js"></script>')
assert 'cdn.jsdelivr' not in h, 'CDN reference left in index.html'
open(sys.argv[2], 'w').write(h)
PY
rm -f "$DIST/src/recorder.js"   # dev-only (needs the local save server)

echo "→ zip"
( cd "$DIST" && rm -f sgu-destiny-html5.zip && zip -qr sgu-destiny-html5.zip index.html src data vendor assets )
du -sh "$DIST/sgu-destiny-html5.zip" | awk '{print "   " $1 "  " $2}'
echo "done → upload dist/sgu-destiny-html5.zip to itch.io as an HTML project (index.html at zip root)."
