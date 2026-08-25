#!/usr/bin/env bash
# Thin CLI wrapper over the headless save inspector + editor. Operates on the
# LIVE player saves root (user://saves/) by default — set SGU_SAVE_ROOT to
# target a sandbox. Workflow: stage a slot, launch the game, hit Continue, and
# land in that exact scene/room/quest step.
#
# Usage:
#   tests/tools/save.sh list
#   tests/tools/save.sh profiles                   (profile + checkpoint model)
#   tests/tools/save.sh dump <slot>
#   tests/tools/save.sh validate [slot|all]        (default: all)
#   tests/tools/save.sh set <slot> <dot.path>=<value>
#   tests/tools/save.sh clone <from-slot> <to-slot>
#   tests/tools/save.sh scenario <slot> <name>

set -u
cd "$(dirname "$0")/../.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	command -v godot >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)" || { echo "ERROR: no Godot binary (set GODOT_BIN)"; exit 2; }
fi

INSPECT="res://tests/tools/save_inspect.gd"
EDIT="res://tests/tools/save_edit.gd"

run_godot() {
	local script="$1"; shift
	if [[ -n "${SGU_SAVE_ROOT:-}" ]]; then
		"$GODOT_BIN" --headless --quit-after 600 -s "$script" ++ "$@" "--save-root=${SGU_SAVE_ROOT}"
	else
		"$GODOT_BIN" --headless --quit-after 600 -s "$script" ++ "$@"
	fi
}

CMD="${1:-}"
shift || true

case "$CMD" in
	list)     run_godot "$INSPECT" --list ;;
	profiles) run_godot "$INSPECT" --profiles ;;
	dump)     run_godot "$INSPECT" --dump "${1:?need a slot id}" ;;
	validate) run_godot "$INSPECT" --validate "${1:-all}" ;;
	set)      run_godot "$EDIT" --slot "${1:?need a slot id}" --set "${2:?need <path>=<value>}" ;;
	clone)    run_godot "$EDIT" --from "${1:?need a from slot}" --to "${2:?need a to slot}" ;;
	scenario) run_godot "$EDIT" --slot "${1:?need a slot id}" --scenario "${2:?need a scenario name}" ;;
	*)
		echo "usage: save.sh list | profiles | dump <slot> | validate [slot|all] | set <slot> <path>=<val> | clone <from> <to> | scenario <slot> <name>"
		exit 2 ;;
esac
