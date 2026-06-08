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
SCHEDULE="${SCHEDULE:-30m}"          # hermes schedule: '30m', 'every 2h', or cron expr
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
command -v hermes >/dev/null 2>&1 || die "hermes not installed on this host. Install it, then 'hermes login' (Nous Portal)."
if ! hermes status 2>/dev/null | grep -qiE "Nous Portal.*logged in"; then
	die "hermes is not authenticated to Nous Portal on this host. Run 'hermes login' (or 'hermes model') first."
fi
echo "  hermes: $(hermes --version 2>/dev/null | head -1) · Nous Portal ✓"

# --- 2c. reviewer: jq + Ollama Cloud vision -------------------------------
say "Checking reviewer panel deps (jq + Ollama Cloud qwen3-vl)"
command -v jq >/dev/null 2>&1 || { command -v apt-get >/dev/null 2>&1 && sudo apt-get install -y jq || die "install jq"; }
OLLAMA_HOST="${OLLAMA_HOST:-https://ollama.com}"
[[ -n "${OLLAMA_API_KEY:-}" ]] || die "OLLAMA_API_KEY not set in this shell. Export your Ollama Cloud key (and OLLAMA_HOST=https://ollama.com) before running."
if curl -fsS --max-time 20 -H "Authorization: Bearer ${OLLAMA_API_KEY}" "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
	echo "  Ollama Cloud reachable ✓ (model: ${OLLAMA_VL_MODEL:-qwen3-vl:235b-instruct})"
else
	warn "Could not reach $OLLAMA_HOST/api/tags with the given key — verify OLLAMA_HOST/OLLAMA_API_KEY. The reviewer will fail without it."
fi

# --- 3. auto-approve in cron context --------------------------------------
say "Setting hermes cron approvals to auto-allow (else loop git/terminal calls get denied)"
hermes config set approvals.cron_mode allow || warn "Could not set approvals.cron_mode — set it manually (hermes config edit)."

# --- 3b. install the hermes skill so the host 'knows' the loop ------------
say "Installing the gate-hero-loop hermes skill"
SKILLS_DIR="$HOME/.hermes/skills/gate-hero-loop"
mkdir -p "$SKILLS_DIR"
cp tools/hermes/skills/gate-hero-loop/SKILL.md "$SKILLS_DIR/SKILL.md"
hermes skills list 2>/dev/null | grep -i "gate-hero-loop" && echo "  skill registered" || warn "skill copied to $SKILLS_DIR (verify with: hermes skills list)"

# --- 3c. stash reviewer creds in a chmod-600 env file (NOT in git/crontab) -
say "Writing reviewer env file ~/.config/gate-hero-loop.env (chmod 600)"
mkdir -p "$HOME/.config"
ENVF="$HOME/.config/gate-hero-loop.env"
umask 077
{
	echo "export OLLAMA_HOST='${OLLAMA_HOST}'"
	echo "export OLLAMA_API_KEY='${OLLAMA_API_KEY}'"
	echo "export OLLAMA_VL_MODEL='${OLLAMA_VL_MODEL:-qwen3-vl:235b-instruct}'"
	[[ -n "${GODOT_BIN:-}" ]] && echo "export GODOT_BIN='${GODOT_BIN}'"
} > "$ENVF"
chmod 600 "$ENVF"; umask 022
echo "  wrote $ENVF (ollama_review.sh self-sources it)"

# --- 4. register the hermes cron job --------------------------------------
say "Registering hermes cron job '$JOB_NAME' (schedule: $SCHEDULE)"
PROMPT="You are the PM for the gate-room hero studio. Run EXACTLY ONE improvement cycle by following tools/hermes/roles/project_manager.md in this repo precisely (developer makes one change → render → independent Ollama reviewer panel → obey its verdict → commit/push or revert → journal), then STOP. Do not loop; the scheduler will call you again."
# Remove any prior job of the same name so re-runs don't stack duplicates.
hermes cron remove "$JOB_NAME" >/dev/null 2>&1 || true
hermes cron create "$SCHEDULE" \
	--name "$JOB_NAME" \
	--workdir "$REPO" \
	--skill "$JOB_NAME" \
	--deliver local \
	"$PROMPT"
hermes cron list 2>/dev/null | grep -i "$JOB_NAME" || warn "Job not visible in 'hermes cron list' — check manually."

# --- 5. drive ticks from system cron (no long-lived hermes daemon) --------
say "Installing system-cron tick every ${TICK_EVERY_MIN}m so jobs actually fire"
TICK_LINE="*/${TICK_EVERY_MIN} * * * * . $HOME/.config/gate-hero-loop.env 2>/dev/null; cd $REPO && HERMES_ACCEPT_HOOKS=1 $(command -v hermes) cron tick >> $HOME/.hermes/logs/gate-loop-tick.log 2>&1"
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
