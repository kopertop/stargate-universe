#!/usr/bin/env bash
# Teach `sparky` (or any Linux build host) to run the gate-room hero
# self-improvement loop CONTINUALLY via the hermes agent — using hermes'
# own (Nous Portal) inference, so it burns ZERO Claude Code credits.
#
# Idempotent. Run it ON the host (e.g. `ssh sparky 'bash -s' < this`, or copy &
# run). Safe to re-run; it converges to the desired state.
#
#   REPO=~/stargate-universe SCHEDULE=30m bash tools/hermes/install_on_sparky.sh
#
# What it does:
#   1. Clone/refresh the repo on the host, on feature/gate-room-hero-portal.
#   2. Verify the render path (Godot + GPU/Xvfb) and the agent (hermes + Nous auth).
#   3. Flip hermes cron approvals to AUTO-ALLOW (else the loop's git/terminal
#      calls get auto-denied in cron context — approvals.cron_mode defaults to deny).
#   4. Register a hermes cron job that runs ONE loop iteration per tick from the
#      repo (--workdir), following tools/hermes/gate_loop_iteration.md.
#   5. Install a system-crontab line driving `hermes cron tick` so jobs actually
#      fire on a headless box (no long-lived hermes daemon required).

set -euo pipefail

REPO="${REPO:-$HOME/stargate-universe}"
BRANCH="feature/gate-room-hero-portal"
REMOTE="${REMOTE:-git@github.com:kopertop/stargate-universe.git}"
SCHEDULE="${SCHEDULE:-every 30m}"    # RECURRING hermes schedule ('30m' alone = one-shot!)
JOB_NAME="gate-hero-loop"
TICK_EVERY_MIN="${TICK_EVERY_MIN:-5}" # system-cron cadence that calls `hermes cron tick`

say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. repo ---------------------------------------------------------------
say "Repo at $REPO on branch $BRANCH"
if [[ ! -d "$REPO/.git" ]]; then
	git clone "$REMOTE" "$REPO"
fi
cd "$REPO"
git fetch origin
git checkout "$BRANCH"
# discard Godot import/bake churn so it doesn't block the pull
git checkout -- '*.import' 2>/dev/null || true
git ls-files -m | grep -E '\.res$' | xargs -r git checkout -- 2>/dev/null || true
git pull --ff-only origin "$BRANCH"
chmod +x tools/gate_hero_render.sh tools/hermes/*.sh 2>/dev/null || true

# --- 2a. render path: Godot + GPU/Xvfb ------------------------------------
say "Checking render path"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
	command -v godot  >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)"
	[[ -z "$GODOT_BIN" ]] && command -v godot4 >/dev/null 2>&1 && GODOT_BIN="$(command -v godot4)"
fi
[[ -n "$GODOT_BIN" ]] || die "No Godot binary on PATH. Install Godot 4.6 (Forward+) and/or set GODOT_BIN."
echo "  godot: $GODOT_BIN ($("$GODOT_BIN" --version 2>/dev/null | head -1))"

if command -v nvidia-smi >/dev/null 2>&1; then
	echo "  GPU:   $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1) (Vulkan/Forward+)"
else
	warn "No nvidia-smi — Forward+ may fall back to software. Set GODOT_BIN and verify a render."
fi
if [[ -z "${DISPLAY:-}" ]] && ! command -v xvfb-run >/dev/null 2>&1; then
	warn "Headless (no \$DISPLAY) and no xvfb-run. Installing xvfb…"
	if command -v apt-get >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y xvfb; \
	else warn "Install a virtual framebuffer (xvfb) yourself — render needs an X display."; fi
fi

say "Smoke-rendering the current best so best.png exists"
bash tools/gate_hero_render.sh best 220 || die "Render failed — fix the render path before scheduling the loop."
[[ -f screenshots/loop/best.png ]] || die "Render produced no screenshots/loop/best.png."
echo "  best.png OK"

# --- 2b. agent: hermes + Nous auth ----------------------------------------
say "Checking hermes agent"
command -v hermes >/dev/null 2>&1 || die "hermes not installed on this host. Install it and configure a model/provider first."
hermes status >/dev/null 2>&1 || die "'hermes status' failed — fix the hermes install/auth first."
echo "  hermes: $(hermes --version 2>/dev/null | head -1) — using its configured default model/provider"

# --- 2c. reviewer: hermes QA profiles (gd-qa-1/2/3, different models) ------
say "Setting up the reviewer panel (3 hermes profiles on different models)"
command -v jq >/dev/null 2>&1 || { command -v apt-get >/dev/null 2>&1 && sudo apt-get install -y jq || die "install jq"; }
bash tools/hermes/setup_reviewer_profiles.sh
echo "  reviewers use the ollama.com provider already configured in the cloned profiles"

# --- 3. auto-approve in cron context --------------------------------------
say "Setting hermes cron approvals to auto-allow (else loop git/terminal calls get denied)"
hermes config set approvals.cron_mode allow || warn "Could not set approvals.cron_mode — set it manually (hermes config edit)."
# The PM shells out to a render (~30s) and the parallel reviewer panel (~2min). The
# default terminal tool timeout (180s) can kill the reviewer — give it headroom.
hermes config set terminal.timeout 600 || warn "Could not raise terminal.timeout — set it manually."

# --- 3b. install the hermes skill so the host 'knows' the loop ------------
say "Installing the gate-hero-loop hermes skill"
SKILLS_DIR="$HOME/.hermes/skills/gate-hero-loop"
mkdir -p "$SKILLS_DIR"
cp tools/hermes/skills/gate-hero-loop/SKILL.md "$SKILLS_DIR/SKILL.md"
hermes skills list 2>/dev/null | grep -i "gate-hero-loop" && echo "  skill registered" || warn "skill copied to $SKILLS_DIR (verify with: hermes skills list)"

# --- 3c. env file for GODOT_BIN (so the render finds Godot under bare cron PATH).
# No secrets here — the reviewer profiles carry the ollama.com key in their own config.
say "Writing ~/.config/gate-hero-loop.env (GODOT_BIN for cron PATH)"
mkdir -p "$HOME/.config"
ENVF="$HOME/.config/gate-hero-loop.env"
GB="${GODOT_BIN:-$(command -v godot 2>/dev/null || command -v godot4 2>/dev/null || true)}"
{ [[ -n "$GB" ]] && echo "export GODOT_BIN='$GB'"; } > "$ENVF"
chmod 600 "$ENVF"
echo "  wrote $ENVF (gate_hero_render.sh self-sources it)"

# --- 4. register the hermes cron job --------------------------------------
say "Registering hermes cron job '$JOB_NAME' (schedule: $SCHEDULE)"
PROMPT="You are the PM for the gate-room hero studio. Run EXACTLY ONE improvement cycle by following tools/hermes/roles/project_manager.md in this repo precisely (developer makes one change, render, then the INDEPENDENT 3-agent hermes reviewer panel hermes_review.sh, obey its verdict, commit/push or revert, journal), then STOP. Do not loop; the scheduler will call you again."
# Remove any prior job of the same name so re-runs don't stack duplicates.
hermes cron remove "$JOB_NAME" >/dev/null 2>&1 || true
# prompt is the 2nd POSITIONAL — must come right after schedule, before the options.
hermes cron create "$SCHEDULE" "$PROMPT" \
	--name "$JOB_NAME" \
	--workdir "$REPO" \
	--skill "$JOB_NAME" \
	--deliver local
hermes cron list 2>/dev/null | grep -i "$JOB_NAME" || warn "Job not visible in 'hermes cron list' — check manually."

# --- 4b. daily develop re-sync job ----------------------------------------
say "Registering daily develop→feature sync job 'gate-hero-sync'"
SYNC_PROMPT="Run the daily develop re-sync by following tools/hermes/roles/sync_develop.md in this repo precisely: merge origin/develop into feature/gate-room-hero-portal, resolving conflicts per that brief (keep-ours for the loop's own files, abort + report if non-trivial), push on success. ONE pass, then STOP. Never push to develop/main."
hermes cron remove gate-hero-sync >/dev/null 2>&1 || true
# Daily needs a cron expression — hermes accepts 'every 30m'/'every 2h' but NOT 'every 24h'.
hermes cron create "${SYNC_SCHEDULE:-0 9 * * *}" "$SYNC_PROMPT" \
	--name gate-hero-sync \
	--workdir "$REPO" \
	--deliver local
hermes cron list 2>/dev/null | grep -i gate-hero-sync || warn "sync job not visible — check 'hermes cron list'."

# --- 5. drive ticks from system cron (no long-lived hermes daemon) --------
say "Installing system-cron tick every ${TICK_EVERY_MIN}m so jobs actually fire"
# flock -n prevents a new tick from starting while a long (~10 min) cycle is still
# running — overlapping PM cycles would race on the git tree.
TICK_LINE="*/${TICK_EVERY_MIN} * * * * . $HOME/.config/gate-hero-loop.env 2>/dev/null; cd $REPO && HERMES_ACCEPT_HOOKS=1 flock -n $HOME/.hermes/gate-loop.lock $(command -v hermes) cron tick >> $HOME/.hermes/logs/gate-loop-tick.log 2>&1"
mkdir -p "$HOME/.hermes/logs"
# Idempotent: drop any existing gate-loop tick line, then add the current one.
( crontab -l 2>/dev/null | grep -v "hermes cron tick.*gate-loop\|gate-loop-tick.log" ; echo "$TICK_LINE" ) | crontab -
echo "  crontab:"; crontab -l 2>/dev/null | grep "gate-loop-tick.log" || true

say "Done. The loop is live."
cat <<EOF

  • Inspect jobs:     hermes cron list
  • Run one now:      cd $REPO && hermes cron tick
  • Watch progress:   git -C $REPO log --oneline origin/$BRANCH | head
  • Tick log:         tail -f $HOME/.hermes/logs/gate-loop-tick.log
  • Pause:            hermes cron pause $JOB_NAME    (resume: hermes cron resume $JOB_NAME)
  • Stop entirely:    hermes cron remove $JOB_NAME ; crontab -e  (delete the gate-loop-tick line)

  Each tick: hermes (Nous Portal, free) makes ONE change, renders via Godot,
  judges vs the concept image, commits if closer / reverts if not, and pushes to
  origin/$BRANCH. It never touches main/develop. Zero Claude Code credits used.
EOF
