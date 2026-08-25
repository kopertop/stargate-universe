#!/usr/bin/env bash
# Save-registration lint for Stargate Universe.
#
# Policy: every Godot autoload listed in project.godot must EITHER
#   (a) call SaveManager.register_system("<id>", self) somewhere in its
#       script (typically in _ready, optionally via the autoload-tolerant
#       get_node_or_null("/root/SaveManager") pattern), OR
#   (b) declare itself stateless with a single-line marker comment:
#         # @no-save: <reason>
#       somewhere in the file (top of file is conventional).
#
# Without this guard, a new autoload that holds gameplay state can ship
# without being persisted — the auto-save / resume pipeline would
# silently drop its state across save and load.
#
# Usage:
#   tests/lint/check_save_registration.sh           # check working tree
#   tests/lint/check_save_registration.sh --staged  # check git index
#                                                    (used by pre-commit)

set -u

cd "$(dirname "$0")/../.."

mode="working"
if [[ "${1:-}" == "--staged" ]]; then
	mode="staged"
fi

# Resolve a file's contents from whichever source the mode picks. This
# lets the same logic check either the working tree (developer iterating
# locally) or the git index (pre-commit hook checking what would land).
read_file() {
	local path="$1"
	if [[ "$mode" == "staged" ]]; then
		git show ":$path" 2>/dev/null
	else
		cat "$path" 2>/dev/null
	fi
}

# Extract autoload script paths from the [autoload] section. We use awk
# instead of Godot itself so the lint is fast and runs without an editor.
autoload_paths() {
	read_file "project.godot" | awk '
		/^\[autoload\]/ { flag = 1; next }
		/^\[/           { flag = 0 }
		flag && /=/ {
			# Lines look like:  Name="*res://path/to/script.gd"
			sub(/^[^=]+="\*?res:\/\//, "")
			sub(/"$/, "")
			if (length($0)) print $0
		}
	'
}

violations=()

while IFS= read -r path; do
	[[ -z "$path" ]] && continue
	contents="$(read_file "$path")"
	if [[ -z "$contents" ]]; then
		# Autoload references a missing file — separate concern; let
		# Godot's own parse-error catch it rather than blocking commits.
		continue
	fi
	# (b) Stateless opt-out marker. Single substring search keeps the
	# rule cheap and easy to grep for in code reviews.
	if grep -q "@no-save" <<<"$contents"; then
		continue
	fi
	# (a) Direct or duck-typed registration call.
	if grep -q "register_system" <<<"$contents"; then
		continue
	fi
	violations+=("$path")
done < <(autoload_paths)

if (( ${#violations[@]} > 0 )); then
	echo "save-registration check FAILED" >&2
	echo "" >&2
	for v in "${violations[@]}"; do
		echo "  ✗ $v" >&2
	done
	echo "" >&2
	echo "Each autoload listed above is in project.godot but does not call" >&2
	echo "SaveManager.register_system(...) and is not marked stateless." >&2
	echo "" >&2
	echo "Fix one of two ways:" >&2
	echo "" >&2
	echo "  (a) If the autoload holds gameplay state, implement the" >&2
	echo "      ISaveableSystem contract — serialize()/deserialize(data," >&2
	echo "      version) — and register from _ready():" >&2
	echo "" >&2
	echo "        func _ready() -> void:" >&2
	echo "            SaveManager.register_system(\"<id>\", self)" >&2
	echo "" >&2
	echo "      (Or use get_node_or_null(\"/root/SaveManager\") for" >&2
	echo "      autoload-tolerant scripts that also run in -s mode.)" >&2
	echo "" >&2
	echo "  (b) If the autoload deliberately holds no gameplay state," >&2
	echo "      add a marker comment anywhere in the file:" >&2
	echo "" >&2
	echo "        # @no-save: <one-line reason>" >&2
	echo "" >&2
	echo "See design/gdd/save-load-interface.md for the contract." >&2
	exit 1
fi

echo "save-registration check: ${mode} tree clean ✓"
exit 0
