#!/usr/bin/env bash
# Rebuild every Mixamo combat host pack that has an incoming FBX.
# Local/ToS only — outputs under models/mixamo_openbot/ are gitignored.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SCRIPT="$ROOT/tools/blender_mixamo_rifle_combat.py"
HOSTS=(swat ybot xbot eli greer)

if [[ ! -x "$BLENDER" ]]; then
	echo "ERROR: Blender not found at $BLENDER (set BLENDER=...)" >&2
	exit 1
fi

for host in "${HOSTS[@]}"; do
	echo "======== BUILD $host ========"
	"$BLENDER" -b -P "$SCRIPT" -- --host "$host"
done

echo "All host packs rebuilt."
