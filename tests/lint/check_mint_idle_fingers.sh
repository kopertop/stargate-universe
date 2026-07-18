#!/usr/bin/env bash
# Mint Idle finger-bind policy.
#
# Meshy animation hosts are 24-bone (no fingers). A bad post-process that
# inserts finger bones + over-weights skin turns aim grips into spaghetti
# mesh (studio incident 2026-07-17).
#
# Policy driven by data/mint/characters.json `finger_rig`:
#   - hand_bias* / *pending* / unset → Idle.glb must have 0 finger joints
#     and exactly 24 skin joints (clean Meshy host).
#   - postprocess_humanoid            → Idle.glb must include finger joints
#     (>= 20 finger-like names). Deep rest/skin audit is in
#     tests/smoke/mint_finger_bind.gd.
#
# Usage:
#   tests/lint/check_mint_idle_fingers.sh           # working tree
#   tests/lint/check_mint_idle_fingers.sh --staged  # git index (pre-commit)

set -u

cd "$(dirname "$0")/../.."

mode="working"
if [[ "${1:-}" == "--staged" ]]; then
	mode="staged"
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "ERROR: python3 required for mint Idle finger lint" >&2
	exit 2
fi

# In --staged mode, only run when Idle hosts or the registry are part of the
# commit — otherwise skip cleanly so unrelated commits stay fast.
if [[ "$mode" == "staged" ]]; then
	staged="$(git diff --cached --name-only --diff-filter=ACM -- \
		'data/mint/characters.json' \
		'models/mint/*/clips/Idle.glb' \
		2>/dev/null || true)"
	if [[ -z "$staged" ]]; then
		echo "mint Idle finger lint: no staged Idle/registry changes (skip)"
		exit 0
	fi
fi

export MINT_LINT_MODE="$mode"
python3 <<'PY'
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(".").resolve()
mode = os.environ.get("MINT_LINT_MODE", "working")

FINGER_HINTS = ("Thumb", "Index", "Middle", "Ring", "Little", "Pinky", "Finger")


def read_text(path: Path) -> str:
	rel = path.relative_to(ROOT).as_posix()
	if mode == "staged":
		try:
			return subprocess.check_output(["git", "show", f":{rel}"], text=True)
		except subprocess.CalledProcessError:
			return path.read_text(encoding="utf-8")
	return path.read_text(encoding="utf-8")


def read_bytes(path: Path) -> bytes:
	rel = path.relative_to(ROOT).as_posix()
	if mode == "staged":
		try:
			return subprocess.check_output(["git", "show", f":{rel}"])
		except subprocess.CalledProcessError:
			return path.read_bytes()
	return path.read_bytes()


def glb_skin_joint_names(data: bytes) -> list[str]:
	if data[:4] != b"glTF":
		raise ValueError("not a GLB")
	length = struct.unpack_from("<I", data, 8)[0]
	off = 12
	while off + 8 <= length:
		clen, ctype = struct.unpack_from("<I4s", data, off)
		chunk = data[off + 8 : off + 8 + clen]
		off += 8 + clen
		if ctype != b"JSON":
			continue
		doc = json.loads(chunk)
		nodes = doc.get("nodes", [])
		names: list[str] = []
		for skin in doc.get("skins", []):
			for ji in skin.get("joints", []):
				names.append(str(nodes[ji].get("name", "")))
		return names
	raise ValueError("no JSON chunk")


def is_finger(name: str) -> bool:
	return any(h in name for h in FINGER_HINTS)


def expects_clean_host(finger_rig: str) -> bool:
	fr = (finger_rig or "").strip().lower()
	if not fr:
		return True
	if "pending" in fr or fr.startswith("hand_bias"):
		return True
	if fr == "postprocess_humanoid":
		return False
	# Unknown modes default to clean-host (safer).
	return True


reg_path = ROOT / "data/mint/characters.json"
if not reg_path.is_file():
	print("ERROR: missing data/mint/characters.json", file=sys.stderr)
	sys.exit(2)

registry = json.loads(read_text(reg_path))
chars = registry.get("characters") or {}
errors: list[str] = []
checked = 0

for slug, entry in sorted(chars.items()):
	if not isinstance(entry, dict):
		continue
	clips_dir = entry.get("clips_dir") or f"res://models/mint/{slug}/clips"
	if not isinstance(clips_dir, str) or not clips_dir.startswith("res://"):
		continue
	rel = clips_dir[len("res://") :]
	idle = ROOT / rel / "Idle.glb"
	if not idle.is_file() and mode != "staged":
		continue
	# Staged-only characters with no Idle yet: skip.
	try:
		data = read_bytes(idle)
	except Exception:
		continue
	try:
		joints = glb_skin_joint_names(data)
	except Exception as exc:
		errors.append(f"{slug}: cannot parse {idle.relative_to(ROOT)}: {exc}")
		continue
	fingers = [n for n in joints if is_finger(n)]
	finger_rig = str(entry.get("finger_rig", ""))
	checked += 1
	if expects_clean_host(finger_rig):
		if len(joints) != 24:
			errors.append(
				f"{slug}: finger_rig={finger_rig!r} requires 24-bone Idle host, got {len(joints)} joints"
			)
		if fingers:
			errors.append(
				f"{slug}: finger_rig={finger_rig!r} forbids finger joints on Idle, found {len(fingers)} "
				f"({', '.join(fingers[:6])}{'…' if len(fingers) > 6 else ''}). "
				"Restore clean Meshy Idle or set finger_rig=postprocess_humanoid after a verified bind."
			)
	else:
		if len(fingers) < 20:
			errors.append(
				f"{slug}: finger_rig=postprocess_humanoid expects >=20 finger joints on Idle, got {len(fingers)}"
			)

if checked == 0:
	print("mint Idle finger lint: no Idle hosts found (skip)")
	sys.exit(0)

if errors:
	print("mint Idle finger lint: FAIL")
	for e in errors:
		print(f"  - {e}")
	sys.exit(1)

print(f"mint Idle finger lint: PASS ({checked} character Idle host(s))")
sys.exit(0)
PY
