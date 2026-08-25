#!/usr/bin/env bash
# Create/refresh the three Godot art-QA reviewer profiles used by
# tools/hermes/hermes_review.sh. Each is a hermes profile cloned from the active
# one (so it inherits the ollama.com provider + key) but pinned to a DIFFERENT
# model, so the review panel is genuinely diverse. Idempotent.
#
#   bash tools/hermes/setup_reviewer_profiles.sh
#
# Override models with REVIEW_MODELS="m1 m2 m3" (must align with gd-qa-1/2/3).

set -euo pipefail
command -v hermes >/dev/null 2>&1 || { echo "ERROR: hermes not found"; exit 2; }

read -r -a NAMES  <<< "gd-qa-1 gd-qa-2 gd-qa-3"
read -r -a MODELS <<< "${REVIEW_MODELS:-qwen3-vl:235b-instruct qwen3-vl:235b glm-5.1}"
PROVIDER="${REVIEW_PROVIDER:-ollama.com}"

for idx in "${!NAMES[@]}"; do
	name="${NAMES[$idx]}"; model="${MODELS[$idx]}"
	if ! hermes profile list 2>/dev/null | grep -qE "(^|[^a-z])${name}([^a-z0-9]|$)"; then
		hermes profile create "$name" --clone \
			--description "Godot art-QA reviewer ($model) — judges renders vs the concept image, returns strict JSON." >/dev/null 2>&1 || true
	fi
	hermes --profile "$name" config set model.provider "$PROVIDER" >/dev/null 2>&1 || true
	hermes --profile "$name" config set model.default  "$model"   >/dev/null 2>&1 || true
	echo "  $name -> $model (provider $PROVIDER)"
done
echo "reviewer profiles ready."
