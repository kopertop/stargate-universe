#!/usr/bin/env bash
# Independent reviewer PANEL for the gate-room hero loop, using an Ollama Cloud
# VISION model (qwen3-vl) — NOT the hermes agent that made the change. This is the
# judge separation that makes the Karpathy loop trustworthy: the developer (hermes)
# does not get to grade its own homework.
#
#   tools/hermes/ollama_review.sh <target.png> <best.png> <candidate.png>
#
# Runs N independent judges (default 3, different lenses) through the Ollama chat
# API with all three images, each returning strict JSON {closer, candidate_score,
# best_score, gap}. Majority "closer" AND avg candidate_score > avg best_score ⇒
# ACCEPT. Emits a machine-readable verdict block on stdout; exit 0 = ACCEPT,
# 10 = REJECT, 2 = error (treat as REJECT).
#
# Env:
#   OLLAMA_HOST     default https://ollama.com   (cloud). Local: http://127.0.0.1:11434
#   OLLAMA_API_KEY  bearer token for the cloud host (required for ollama.com)
#   OLLAMA_VL_MODEL default qwen3-vl:235b-instruct
#   JUDGES          default 3

set -u
# The hermes terminal tool runs with env_passthrough=[], so a cron-dispatched PM
# agent's shell-outs may not inherit the Ollama creds. Self-source a known env file
# (written chmod-600 by install_on_sparky.sh) when they're not already present.
if [[ -z "${OLLAMA_API_KEY:-}" && -f "$HOME/.config/gate-hero-loop.env" ]]; then
	# shellcheck disable=SC1091
	. "$HOME/.config/gate-hero-loop.env"
fi

TARGET="${1:?usage: ollama_review.sh target best candidate}"
BEST="${2:?need best.png}"
CAND="${3:?need candidate.png}"

HOST="${OLLAMA_HOST:-https://ollama.com}"
MODEL="${OLLAMA_VL_MODEL:-qwen3-vl:235b-instruct}"
JUDGES="${JUDGES:-3}"
command -v jq  >/dev/null 2>&1 || { echo "ERROR: jq required"; exit 2; }
for f in "$TARGET" "$BEST" "$CAND"; do [[ -f "$f" ]] || { echo "ERROR: missing image $f"; exit 2; }; done

# base64 images are ~400KB each — far past ARG_MAX, so stage them in temp files
# and feed jq via --rawfile / curl via --data @file (never on the command line).
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
base64 < "$TARGET" | tr -d '\n' > "$TMPD/t"
base64 < "$BEST"   | tr -d '\n' > "$TMPD/b"
base64 < "$CAND"   | tr -d '\n' > "$TMPD/c"

RUBRIC='You are a STRICT, HONEST art director judging a Godot render against a concept image. Three images are attached IN ORDER: (1) TARGET concept (the goal), (2) BEST (previous render), (3) CANDIDATE (new render). Score similarity-to-TARGET on: tonality (dark high-contrast, not a black void, not a flat wash), cool steel+black palette with selective blue, dim-but-readable ribbed architecture + tiered ceiling dome, a thick segmented dark gate ring with glowing triangular chevrons, a near-circular churning blue plasma vortex with a small dark eye, foreground console banks both sides, subtle wet floor reflections, symmetric one-point composition.'

declare -a LENS=(
  'Focus on overall tonality, palette and gestalt resemblance.'
  'Focus on the gate ring + vortex (segmented dark ring, triangular chevrons, churning plasma with a small dark eye).'
  'Focus on architecture depth, console banks, floor reflections and composition.'
)

ask_judge() {
	local lens="$1"
	local prompt="$RUBRIC $lens Decide whether the CANDIDATE (image 3) is GENUINELY closer to the TARGET (image 1) than the BEST (image 2) is — a real, visible improvement with no clear regression. A lateral move or merely-different ⇒ closer=false; when unsure, false. Respond with ONLY strict JSON: {\"closer\": <true|false>, \"candidate_score\": <0-100>, \"best_score\": <0-100>, \"gap\": \"<biggest remaining gap vs target, <=12 words>\"}"
	local bodyf; bodyf="$(mktemp "$TMPD/body.XXXXXX")"
	jq -n --arg m "$MODEL" --arg p "$prompt" \
		--rawfile t "$TMPD/t" --rawfile b "$TMPD/b" --rawfile c "$TMPD/c" \
		'{model:$m, stream:false, format:"json", options:{temperature:0.2},
		  messages:[{role:"user", content:$p, images:[$t,$b,$c]}]}' > "$bodyf"
	local auth=()
	[[ -n "${OLLAMA_API_KEY:-}" ]] && auth=(-H "Authorization: Bearer ${OLLAMA_API_KEY}")
	curl -fsS --max-time 180 "${auth[@]+"${auth[@]}"}" \
		-H "Content-Type: application/json" \
		"$HOST/api/chat" --data @"$bodyf" 2>/dev/null | jq -r '.message.content // empty'
}

closer_votes=0; valid=0; sum_c=0; sum_b=0; gaps=""
for ((j=1; j<=JUDGES; j++)); do
	lens="${LENS[$(( (j-1) % ${#LENS[@]} ))]}"
	raw="$(ask_judge "$lens")"
	# The content should itself be JSON (format:json). Extract fields defensively.
	verdict="$(printf '%s' "$raw" | jq -rc '{closer: (.closer==true), cs: (.candidate_score // 0), bs: (.best_score // 0), gap: (.gap // "")}' 2>/dev/null)"
	if [[ -z "$verdict" ]]; then echo "judge $j: NO/!JSON RESPONSE"; continue; fi
	valid=$((valid+1))
	c="$(jq -r '.closer' <<<"$verdict")"; cs="$(jq -r '.cs' <<<"$verdict")"; bs="$(jq -r '.bs' <<<"$verdict")"; gap="$(jq -r '.gap' <<<"$verdict")"
	[[ "$c" == "true" ]] && closer_votes=$((closer_votes+1))
	sum_c=$((sum_c + ${cs%.*})); sum_b=$((sum_b + ${bs%.*}))
	gaps="$gaps; $gap"
	echo "judge $j: closer=$c cand=$cs best=$bs gap=$gap"
done

if (( valid < 2 )); then echo "VERDICT=REJECT (panel too thin: $valid/$JUDGES valid)"; exit 10; fi
avg_c=$(( sum_c / valid )); avg_b=$(( sum_b / valid ))
echo "PANEL: closer=$closer_votes/$valid  avg_cand=$avg_c  avg_best=$avg_b"
echo "GAPS:$gaps"
if (( closer_votes * 2 > valid )) && (( avg_c > avg_b )); then
	echo "VERDICT=ACCEPT score=$avg_c"; exit 0
else
	echo "VERDICT=REJECT score=$avg_c"; exit 10
fi
