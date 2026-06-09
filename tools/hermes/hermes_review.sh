#!/usr/bin/env bash
# Independent reviewer PANEL for the gate-room hero loop — three HERMES AGENTS
# running under distinct profiles (gd-qa-1/2/3), each on a DIFFERENT model, each
# given a different review lens. This is the judge separation that keeps the loop
# honest: the developer agent never grades its own homework, and three different
# models must agree before a change is accepted.
#
#   tools/hermes/hermes_review.sh <target.png> <best.png> <candidate.png>
#
# Each reviewer returns one line of strict JSON {closer, candidate_score,
# best_score, gap}. Majority "closer" AND avg candidate_score > avg best_score ⇒
# ACCEPT. Emits a machine-readable verdict; exit 0 = ACCEPT, 10 = REJECT, 2 = error.
#
# Env: REVIEW_PROFILES (default "gd-qa-1 gd-qa-2 gd-qa-3"); set up via
# tools/hermes/setup_reviewer_profiles.sh. Run from the repo root (image paths
# are passed through to the agents relative to cwd).

set -u
TARGET="${1:?usage: hermes_review.sh target best candidate}"
BEST="${2:?need best.png}"
CAND="${3:?need candidate.png}"
for f in "$TARGET" "$BEST" "$CAND"; do [[ -f "$f" ]] || { echo "ERROR: missing image $f"; exit 2; }; done
command -v hermes >/dev/null 2>&1 || { echo "ERROR: hermes not found"; exit 2; }
command -v jq     >/dev/null 2>&1 || { echo "ERROR: jq not found"; exit 2; }

read -r -a PROFILES <<< "${REVIEW_PROFILES:-gd-qa-1 gd-qa-2 gd-qa-3}"

RUBRIC='You are a STRICT, HONEST Godot art-QA reviewer comparing a render to a concept image. Score similarity-to-TARGET on: dark high-contrast tonality (NOT a black void, NOT a flat wash); cool steel+black palette with selective blue only in portal+screens; dim-but-readable ribbed architecture + tiered ceiling dome; a thick segmented dark gate ring with glowing triangular chevrons; a near-circular churning blue plasma vortex with a SMALL dark eye; foreground console banks both sides; subtle wet floor reflections; symmetric one-point composition.'

lens_for() { case "$1" in
	0) echo 'Weight tonality, palette and overall gestalt resemblance most.' ;;
	1) echo 'Weight the gate ring + vortex most (segmented dark ring, triangular chevrons, churning plasma with a small dark eye).' ;;
	*) echo 'Weight architecture depth, console banks, floor reflections and composition most.' ;;
esac; }

closer_votes=0; valid=0; sum_c=0; sum_b=0; gaps=""
i=0
for p in "${PROFILES[@]}"; do
	lens="$(lens_for $(( i % 3 )))"
	prompt="$RUBRIC $lens You are shown THREE local images (paths relative to the current directory): TARGET (the goal) = $TARGET ; BEST (previous render) = $BEST ; CANDIDATE (new render) = $CAND . View all three. Decide whether CANDIDATE is GENUINELY closer to TARGET than BEST is — a real, visible improvement with no clear regression; a lateral move or merely-different means closer=false; when unsure, false. Reply with ONLY one line of strict JSON, no prose, no markdown: {\"closer\": <true|false>, \"candidate_score\": <0-100>, \"best_score\": <0-100>, \"gap\": \"<biggest remaining gap vs target, <=12 words>\"}"
	raw="$(timeout 200 hermes --profile "$p" --yolo --accept-hooks -z "$prompt" 2>/dev/null)"
	# Extract the last {...} object containing "closer" from whatever the agent printed.
	json="$(printf '%s' "$raw" | grep -oE '\{[^{}]*"closer"[^{}]*\}' | tail -1)"
	v="$(printf '%s' "$json" | jq -rc '{closer:(.closer==true), cs:(.candidate_score//0|floor), bs:(.best_score//0|floor), gap:(.gap//"")}' 2>/dev/null)"
	if [[ -z "$v" ]]; then echo "review $p: NO/!JSON"; i=$((i+1)); continue; fi
	valid=$((valid+1))
	c="$(jq -r .closer <<<"$v")"; cs="$(jq -r .cs <<<"$v")"; bs="$(jq -r .bs <<<"$v")"; gap="$(jq -r .gap <<<"$v")"
	[[ "$c" == "true" ]] && closer_votes=$((closer_votes+1))
	sum_c=$((sum_c+cs)); sum_b=$((sum_b+bs)); gaps="$gaps; $gap"
	echo "review $p: closer=$c cand=$cs best=$bs gap=$gap"
	i=$((i+1))
done

if (( valid < 2 )); then echo "VERDICT=REJECT (panel too thin: $valid valid)"; exit 10; fi
avg_c=$(( sum_c / valid )); avg_b=$(( sum_b / valid ))
echo "PANEL: closer=$closer_votes/$valid avg_cand=$avg_c avg_best=$avg_b"
echo "GAPS:$gaps"
if (( closer_votes * 2 > valid )) && (( avg_c > avg_b )); then
	echo "VERDICT=ACCEPT score=$avg_c"; exit 0
else
	echo "VERDICT=REJECT score=$avg_c"; exit 10
fi
