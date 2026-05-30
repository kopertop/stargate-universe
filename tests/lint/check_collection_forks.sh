#!/usr/bin/env bash
# Collection-fork lint for Stargate Universe.
#
# Policy: a SET of like things (inventory items, discovered rooms, unlocked
# abilities, earned achievements) must live in ONE collection behind ONE
# add/remove/enumerate API — never as scattered per-instance boolean fields.
#
# This lint catches the "scattered collection" anti-pattern at its cheapest
# interception point: the moment someone declares a top-level bool field whose
# name uses ACQUISITION vocabulary — `*_found`, `*_acquired`, `*_collected`,
# `*_unlocked`, `*_owned`, `*_looted`, `*_obtained`, or `has_*` / `got_*`.
# Those verbs mean "the player now possesses a discrete thing", which is
# collection membership — it belongs in a registry (e.g. data/items.json +
# Inventory, or data/ship_layout.json room state), not a one-off bool.
#
# Why this matters: when items fork into ad-hoc bools, every consumer
# (renderer, serializer, save/load) must special-case each one, so a newly
# added member silently fails to appear / save / display. This is exactly how
# the looted fuses never showed up in the Kino Remote inventory (issue #41),
# and how quest progress fragmented before #36.
#
# Scope: top-level `var` fields in scripts/*.gd only (indented locals like a
# throwaway `var found := false` inside a loop are NOT fields and are ignored).
# State flags that use NON-acquisition verbs (met_*, *_examined, *_diagnosed,
# *_visited, *_triggered, *_started, *_done) are world-state, not collection
# membership, and are intentionally NOT flagged.
#
# Escape hatch (for genuinely-distinct state that merely looks like the
# pattern): add a marker on the same line as the field, or on the line
# directly above it:
#       var legacy_thing_found: bool = false  # @collection-ok: <reason>
#
# Usage:
#   tests/lint/check_collection_forks.sh           # check working tree
#   tests/lint/check_collection_forks.sh --staged  # check git index (pre-commit)

set -u

cd "$(dirname "$0")/../.."

mode="working"
if [[ "${1:-}" == "--staged" ]]; then
	mode="staged"
fi

read_file() {
	local path="$1"
	if [[ "$mode" == "staged" ]]; then
		git show ":$path" 2>/dev/null
	else
		cat "$path" 2>/dev/null
	fi
}

# The set of .gd files to scan. In --staged mode, restrict to files that are
# actually staged so the pre-commit hook only judges what would land; in
# working mode, scan the whole scripts/ tree.
target_files() {
	if [[ "$mode" == "staged" ]]; then
		git diff --cached --name-only --diff-filter=ACM -- 'scripts/*.gd' 2>/dev/null
	else
		# Tracked AND untracked-not-ignored, so a brand-new (not-yet-added)
		# script is scanned — that's the most common moment a fork appears.
		git ls-files --cached --others --exclude-standard -- 'scripts/*.gd' 2>/dev/null
	fi
}

# Per-file scan. awk emits one "line<TAB>name" record per offending field.
#
# A field offends when ALL of:
#   - it is a TOP-LEVEL declaration (`var ` at column 0, no leading whitespace)
#   - it is boolean (`: bool`, or default literal `true`/`false`)
#   - its name matches acquisition vocabulary (suffix verb or has_/got_ prefix,
#     minus a stoplist of world-state verbs that follow has_/got_)
#   - neither the line itself nor the line directly above carries
#     `@collection-ok`
scan_file() {
	read_file "$1" | awk '
		# Remember the previous line so an above-the-field marker counts.
		{ prevline = curline; curline = $0 }

		/^var [a-zA-Z_]/ {
			line = $0

			# boolean? typed bool, or default literal true/false.
			isbool = (line ~ /:[ \t]*bool([ \t]|=|$)/) \
			      || (line ~ /=[ \t]*(true|false)([^a-zA-Z0-9_]|$)/)
			if (!isbool) next

			# field name = token after `var`, stripped of type/default.
			name = $2
			sub(/[:=].*$/, "", name)

			# escape hatch: same line OR line directly above.
			if (line ~ /@collection-ok/ || prevline ~ /@collection-ok/) next

			# acquisition SUFFIX verbs (high precision). These denote the
			# player GAINING POSSESSION of a discrete thing. Deliberately
			# excludes object-state participles (looted/opened/used/
			# destroyed) which describe a single object, not membership.
			acq = (name ~ /_(found|acquired|collected|obtained|unlocked|owned)$/)

			# acquisition PREFIX (has_/got_/owns_) EXCEPT world-state verbs.
			if (!acq && name ~ /^(has|got|owns)_/) {
				rest = name
				sub(/^(has|got|owns)_/, "", rest)
				if (rest !~ /^(seen|met|visited|used|read|done|finished|started|completed|triggered|played|begun|entered|left|reached|heard|spoken|talked|opened|closed|fired|warned|booted|loaded|run|been|gone)([_]|$)/)
					acq = 1
			}

			if (acq) printf "%d\t%s\n", NR, name
		}
	'
}

# Item ids from the data catalog (if it exists). A bool field whose name
# CONTAINS one of these ids is a registry fork even if its verb is unusual
# (e.g. `small_fuse_slotted`). Dormant until data/items.json lands (#41),
# then activates automatically.
catalog_ids() {
	read_file "data/items.json" 2>/dev/null \
		| grep -oE '"id"[ \t]*:[ \t]*"[a-z0-9_]+"' \
		| grep -oE '"[a-z0-9_]+"$' \
		| tr -d '"'
}

# Portable array build (macOS ships bash 3.2 — no mapfile/readarray).
IDS=()
while IFS= read -r _id; do
	[[ -z "$_id" ]] && continue
	IDS+=("$_id")
done < <(catalog_ids)

violations=()

while IFS= read -r path; do
	[[ -z "$path" ]] && continue
	contents="$(read_file "$path")"
	[[ -z "$contents" ]] && continue

	# Rule 1 — acquisition vocabulary.
	while IFS=$'\t' read -r lineno name; do
		[[ -z "$name" ]] && continue
		violations+=("$path:$lineno  $name  (acquisition-flag — route through a collection API)")
	done < <(scan_file "$path")

	# Rule 2 — references a catalog-managed item id (registry-aware).
	if (( ${#IDS[@]} > 0 )); then
		while IFS= read -r ln; do
			lineno="${ln%%:*}"
			text="${ln#*:}"
			# skip lines already opted out
			[[ "$text" == *"@collection-ok"* ]] && continue
			name="$(awk '{print $2}' <<<"$text")"
			name="${name%%[:=]*}"
			for id in "${IDS[@]}"; do
				if [[ "$name" == *"$id"* && "$name" != "$id" ]]; then
					violations+=("$path:$lineno  $name  (references catalog item '$id' — use the Inventory registry)")
					break
				fi
			done
		done < <(grep -nE '^var [a-zA-Z_].*(:[ ]*bool|=[ ]*(true|false))' <<<"$contents")
	fi
done < <(target_files)

# De-duplicate (rule 1 + rule 2 can both flag the same field).
if (( ${#violations[@]} > 0 )); then
	deduped=()
	while IFS= read -r _v; do
		[[ -z "$_v" ]] && continue
		deduped+=("$_v")
	done < <(printf '%s\n' "${violations[@]}" | sort -u)
	violations=("${deduped[@]}")
fi

if (( ${#violations[@]} > 0 )); then
	echo "collection-fork check FAILED" >&2
	echo "" >&2
	for v in "${violations[@]}"; do
		echo "  ✗ $v" >&2
	done
	echo "" >&2
	echo "Each field above names a discrete thing the player POSSESSES — that is" >&2
	echo "collection membership, not world-state. A set of like things must live" >&2
	echo "in ONE registry behind ONE add/remove/enumerate API, so every consumer" >&2
	echo "(UI, save/load) iterates it generically and new members can't silently" >&2
	echo "go missing (the looted-fuse bug, #41; quest fork, #36)." >&2
	echo "" >&2
	echo "Fix one of two ways:" >&2
	echo "" >&2
	echo "  (a) Route it through the owning collection's API instead of a field:" >&2
	echo "        Inventory.add_item(\"small_fuse\")   # not  var small_fuse_found" >&2
	echo "        ShipLayout room state               # not  var quarters_found" >&2
	echo "      Consumers read Inventory.entries() / the registry, never the field." >&2
	echo "" >&2
	echo "  (b) If this is genuinely-distinct state that only LOOKS like the" >&2
	echo "      pattern, acknowledge it with a marker on the field (or line above):" >&2
	echo "" >&2
	echo "        var foo_found: bool = false  # @collection-ok: <one-line reason>" >&2
	echo "" >&2
	echo "See the 'homogeneous-collection-single-model' skill and" >&2
	echo "design/gdd/resource-inventory.md." >&2
	exit 1
fi

echo "collection-fork check: ${mode} tree clean ✓"
exit 0
