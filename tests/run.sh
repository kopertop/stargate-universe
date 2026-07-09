#!/usr/bin/env bash
# Smoke + flow + playthrough test runner for Stargate Universe (Godot 4.6).
# Validates the E1 vertical slice at multiple levels:
#   1. scene_boot   — every gameplay scene loads with critical nodes intact
#   2. e1_flow      — GameState mutators + win-condition logic
#   3. quest        — quest-tracker BFS + GameState.quest_target + Kino route
#   4. playthrough  — real cross-scene transitions via SceneRouter +
#                     Interactable.interact() pipelines, end-to-end
#   5. autopilot    — Kino-drone auto-search patrol (1/2/3 drone coordination)
#   6. questlog     — data-driven QuestLog autoload (predicate + event advance,
#                     save round-trip, old-format migration)
#
# Usage: tests/run.sh [lint|scene|flow|quest|playthrough|resume|autopilot|questlog|inventory|atmosphere|kino-doors|kino-autoexplore|gamepad|footfall|npc-chat|shaders|ancient-text|discovery-toast|door-plaque|crate|unit-frame|quest-tracker|hud-wow|gate-two-way|equip-mount|equip-assets|char-panel|equip-integration|planet-gen|planet-resources|planet-integration|biome-desert|biome-jungle|biome-toxic|biome-urban|biome-alien-tech|knockout|ftl-loop|music|save|save-integration|elevator-power|bridge-loop|consumption|repair-robot|setdressing|e1-opening|cold-open|away-split|char-gen|vrm|modular|deck|economy|all]
#                                                                          (default: all)
#
# Pre-commit hook: .githooks/pre-commit invokes the lint subset via
# tests/lint/check_save_registration.sh --staged. Install once with:
#   git config core.hooksPath .githooks

set -u
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	# Fall back to PATH lookup.
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "ERROR: cannot find Godot. Set GODOT_BIN or add 'godot' to PATH." >&2
		exit 2
	fi
fi

MODE="${1:-all}"
RAN_SCENE=0
RAN_FLOW=0
RAN_QUEST=0
RAN_PLAY=0
RAN_LINT=0
RAN_RESUME=0
RAN_AUTOPILOT=0
RAN_QUESTLOG=0
RAN_INV=0
RAN_SAVE=0
RAN_ATMO=0
RAN_KINODOORS=0
RAN_KINOEXPLORE=0
RAN_KINODISC=0
RAN_GAMEPAD=0
RAN_NPCCHAT=0
RAN_SHADER=0
RAN_ANCIENTTEXT=0
RAN_DISCTOAST=0
RAN_DOORPLAQUE=0
RAN_CRATE=0
RAN_UNITFRAME=0
RAN_QUESTTRACKER=0
RAN_HUDWOW=0
RAN_HUDSCALE=0
RAN_HUDCHAT=0
RAN_GATETWOWAY=0
RAN_EQUIPMOUNT=0
RAN_EQUIPASSETS=0
RAN_CHARPANEL=0
RAN_EQUIPINT=0
RAN_PLANETGEN=0
RAN_PLANETRES=0
RAN_PLANETINT=0
RAN_BIOMEDESERT=0
RAN_BIOMEJUNGLE=0
RAN_BIOMETOXIC=0
RAN_BIOMEURBAN=0
RAN_BIOMEALIENTECH=0
RAN_KNOCKOUT=0
RAN_SCRUBBERS=0
RAN_PROCSHIP=0
RAN_FTLLOOP=0
RAN_MUSIC=0
RAN_DECK=0
RAN_ECONOMY=0
RAN_FOOTFALL=0
RAN_ELEVPOWER=0
RAN_BRIDGELOOP=0
RAN_CONSUMPTION=0
RAN_REPAIR=0
RC_FOOTFALL=0
RC_SCENE=0
RC_FLOW=0
RC_QUEST=0
RC_PLAY=0
RC_LINT=0
RC_FORKS=0
RC_INV=0
RC_RESUME=0
RC_AUTOPILOT=0
RC_QUESTLOG=0
RC_SAVE_UNIT=0
RC_SAVE_RESUME=0
RC_SAVE_ORCH=0
RC_SAVE_BROWSER=0
RC_SAVE_INGAME=0
RC_SAVE_INTEGRATION=0
RAN_SAVE_INTEGRATION=0
RC_ATMO=0
RC_KINODOORS=0
RC_KINOEXPLORE=0
RC_KINODISC=0
RC_GAMEPAD=0
RC_NPCCHAT=0
RC_SHADER=0
RC_ANCIENTTEXT=0
RC_DISCTOAST=0
RC_DOORPLAQUE=0
RC_CRATE=0
RC_UNITFRAME=0
RC_QUESTTRACKER=0
RC_HUDWOW=0
RC_HUDSCALE=0
RC_HUDCHAT=0
RC_GATETWOWAY=0
RC_EQUIPMOUNT=0
RC_EQUIPASSETS=0
RC_CHARPANEL=0
RC_EQUIPINT=0
RC_PLANETGEN=0
RC_PLANETRES=0
RC_PLANETINT=0
RC_BIOMEDESERT=0
RC_BIOMEJUNGLE=0
RC_BIOMETOXIC=0
RC_BIOMEURBAN=0
RC_BIOMEALIENTECH=0
RC_KNOCKOUT=0
RC_SCRUBBERS=0
RC_PROCSHIP=0
RC_FTLLOOP=0
RC_MUSIC=0
RC_ELEVPOWER=0
RC_BRIDGELOOP=0
RC_CONSUMPTION=0
RC_REPAIR=0
RAN_SETDRESS=0
RC_SETDRESS=0
RAN_E1OPEN=0
RC_E1OPEN=0
RAN_COLDOPEN=0
RC_COLDOPEN=0
RAN_AWAYSPLIT=0
RC_AWAYSPLIT=0
RAN_CHARGEN=0
RC_CHARGEN=0
RAN_VRM=0
RC_VRM=0
RAN_MODULAR=0
RC_MODULAR=0

# Run a SceneTree-extending script (synchronous, no autoloads).
#
# --quit-after is a frame-count ceiling, not a target. Scripts call quit(0|1)
# explicitly so a higher ceiling only matters when the test silently hangs.
# Per memory feedback_godot_quit_after_frames.md, truncated runs exit code 0
# and masquerade as PASS — keep generous so growing scene lists do not slip
# into that failure mode.
run_script_test() {
	local label="$1"
	local script="$2"
	echo
	echo "==============================="
	echo " $label"
	echo "==============================="
	"$GODOT_BIN" --headless --quit-after 600 -s "$script" 2>&1
	return $?
}

# Run a regular scene with autoloads active (used for the playthrough).
# The scene's script is responsible for calling get_tree().quit(0|1). The
# --quit-after value is a fail-safe ceiling; if it fires we lose visibility
# into PASS/FAIL so it must stay generous and the runner must self-time-out
# below it (see TIMEOUT_SEC in playthrough_runner.gd).
run_scene_test() {
	local label="$1"
	local scene="$2"
	echo
	echo "==============================="
	echo " $label"
	echo "==============================="
	"$GODOT_BIN" --headless --quit-after 100000 "$scene" 2>&1
	return $?
}

if [[ "$MODE" == "lint" || "$MODE" == "all" ]]; then
	echo
	echo "==============================="
	echo " save-registration lint"
	echo "==============================="
	tests/lint/check_save_registration.sh
	RC_LINT=$?
	echo
	echo "==============================="
	echo " collection-fork lint"
	echo "==============================="
	tests/lint/check_collection_forks.sh
	RC_FORKS=$?
	RAN_LINT=1
fi

if [[ "$MODE" == "scene" || "$MODE" == "all" ]]; then
	run_script_test "scene_boot" "res://tests/smoke/scene_boot.gd"
	RC_SCENE=$?
	RAN_SCENE=1
fi

if [[ "$MODE" == "flow" || "$MODE" == "all" ]]; then
	run_script_test "e1_flow" "res://tests/smoke/e1_flow.gd"
	RC_FLOW=$?
	RAN_FLOW=1
fi

if [[ "$MODE" == "quest" || "$MODE" == "all" ]]; then
	run_script_test "quest_waypoint" "res://tests/smoke/quest_waypoint.gd"
	RC_QUEST=$?
	RAN_QUEST=1
fi

if [[ "$MODE" == "playthrough" || "$MODE" == "all" ]]; then
	run_scene_test "e1_playthrough" "res://tests/playthrough/playthrough.tscn"
	RC_PLAY=$?
	RAN_PLAY=1
fi

if [[ "$MODE" == "resume" || "$MODE" == "all" ]]; then
	run_scene_test "resume_probe" "res://tests/resume/probe.tscn"
	RC_RESUME=$?
	RAN_RESUME=1
fi

if [[ "$MODE" == "autopilot" || "$MODE" == "all" ]]; then
	run_script_test "kino_autopilot" "res://tests/smoke/kino_autopilot.gd"
	RC_AUTOPILOT=$?
	RAN_AUTOPILOT=1
fi

if [[ "$MODE" == "questlog" || "$MODE" == "all" ]]; then
	run_script_test "quest_log" "res://tests/smoke/quest_log.gd"
	RC_QUESTLOG=$?
	RAN_QUESTLOG=1
fi

if [[ "$MODE" == "inventory" || "$MODE" == "all" ]]; then
	run_script_test "inventory" "res://tests/smoke/inventory.gd"
	RC_INV=$?
	RAN_INV=1
fi

if [[ "$MODE" == "atmosphere" || "$MODE" == "all" ]]; then
	run_script_test "atmosphere" "res://tests/smoke/atmosphere.gd"
	RC_ATMO=$?
	RAN_ATMO=1
fi

if [[ "$MODE" == "kino-doors" || "$MODE" == "all" ]]; then
	run_script_test "kino_doors" "res://tests/smoke/kino_doors.gd"
	RC_KINODOORS=$?
	RAN_KINODOORS=1
fi

if [[ "$MODE" == "kino-autoexplore" || "$MODE" == "all" ]]; then
	run_script_test "kino_autoexplore" "res://tests/smoke/kino_autoexplore.gd"
	RC_KINOEXPLORE=$?
	RAN_KINOEXPLORE=1
fi

if [[ "$MODE" == "kino-discovery" || "$MODE" == "all" ]]; then
	run_script_test "kino_discovery" "res://tests/smoke/kino_discovery.gd"
	RC_KINODISC=$?
	RAN_KINODISC=1
fi

if [[ "$MODE" == "gamepad" || "$MODE" == "all" ]]; then
	run_script_test "gamepad" "res://tests/smoke/gamepad.gd"
	RC_GAMEPAD=$?
	RAN_GAMEPAD=1
fi

if [[ "$MODE" == "footfall" || "$MODE" == "all" ]]; then
	run_script_test "footfall" "res://tests/smoke/footfall.gd"
	RC_FOOTFALL=$?
	RAN_FOOTFALL=1
fi

if [[ "$MODE" == "shaders" || "$MODE" == "all" ]]; then
	run_script_test "ancient_metal_shader" "res://tests/smoke/ancient_metal_shader.gd"
	RC_SHADER=$?
	RAN_SHADER=1
fi

if [[ "$MODE" == "ancient-text" || "$MODE" == "all" ]]; then
	run_script_test "ancient_text" "res://tests/smoke/ancient_text.gd"
	RC_ANCIENTTEXT=$?
	RAN_ANCIENTTEXT=1
fi

if [[ "$MODE" == "discovery-toast" || "$MODE" == "all" ]]; then
	run_script_test "discovery_toast" "res://tests/smoke/discovery_toast.gd"
	RC_DISCTOAST=$?
	RAN_DISCTOAST=1
fi

if [[ "$MODE" == "door-plaque" || "$MODE" == "all" ]]; then
	run_script_test "door_plaque" "res://tests/smoke/door_plaque.gd"
	RC_DOORPLAQUE=$?
	RAN_DOORPLAQUE=1
fi

if [[ "$MODE" == "crate" || "$MODE" == "all" ]]; then
	run_script_test "shuttle_crate" "res://tests/smoke/shuttle_crate.gd"
	RC_CRATE=$?
	RAN_CRATE=1
fi

if [[ "$MODE" == "unit-frame" || "$MODE" == "all" ]]; then
	run_script_test "unit_frame" "res://tests/smoke/unit_frame.gd"
	RC_UNITFRAME=$?
	RAN_UNITFRAME=1
fi

if [[ "$MODE" == "quest-tracker" || "$MODE" == "all" ]]; then
	run_script_test "quest_tracker" "res://tests/smoke/quest_tracker.gd"
	RC_QUESTTRACKER=$?
	RAN_QUESTTRACKER=1
fi

if [[ "$MODE" == "hud-wow" || "$MODE" == "all" ]]; then
	run_script_test "hud_wow" "res://tests/smoke/hud_wow.gd"
	RC_HUDWOW=$?
	RAN_HUDWOW=1
fi

if [[ "$MODE" == "hud-scale" || "$MODE" == "all" ]]; then
	run_script_test "hud_scale" "res://tests/smoke/hud_scale.gd"
	RC_HUDSCALE=$?
	RAN_HUDSCALE=1
fi

if [[ "$MODE" == "hud-chat" || "$MODE" == "all" ]]; then
	run_script_test "hud_chat" "res://tests/smoke/hud_chat.gd"
	RC_HUDCHAT=$?
	RAN_HUDCHAT=1
fi

if [[ "$MODE" == "gate-two-way" || "$MODE" == "all" ]]; then
	run_script_test "gate_two_way" "res://tests/smoke/gate_two_way.gd"
	RC_GATETWOWAY=$?
	RAN_GATETWOWAY=1
fi

if [[ "$MODE" == "equip-mount" || "$MODE" == "all" ]]; then
	run_script_test "equipment_mount" "res://tests/smoke/equipment_mount.gd"
	RC_EQUIPMOUNT=$?
	RAN_EQUIPMOUNT=1
fi

if [[ "$MODE" == "equip-assets" || "$MODE" == "all" ]]; then
	run_script_test "equipment_assets" "res://tests/smoke/equipment_assets.gd"
	RC_EQUIPASSETS=$?
	RAN_EQUIPASSETS=1
fi

if [[ "$MODE" == "char-panel" || "$MODE" == "all" ]]; then
	run_script_test "character_panel" "res://tests/smoke/character_panel.gd"
	RC_CHARPANEL=$?
	RAN_CHARPANEL=1
fi

if [[ "$MODE" == "equip-integration" || "$MODE" == "all" ]]; then
	run_script_test "equipment_integration" "res://tests/smoke/equipment_integration.gd"
	RC_EQUIPINT=$?
	RAN_EQUIPINT=1
fi

if [[ "$MODE" == "planet-gen" || "$MODE" == "all" ]]; then
	run_script_test "planet_generator" "res://tests/smoke/planet_generator.gd"
	RC_PLANETGEN=$?
	RAN_PLANETGEN=1
fi

if [[ "$MODE" == "planet-resources" || "$MODE" == "all" ]]; then
	run_script_test "planet_resources" "res://tests/smoke/planet_resources.gd"
	RC_PLANETRES=$?
	RAN_PLANETRES=1
fi

if [[ "$MODE" == "planet-integration" || "$MODE" == "all" ]]; then
	run_script_test "planet_integration" "res://tests/smoke/planet_integration.gd"
	RC_PLANETINT=$?
	RAN_PLANETINT=1
fi

if [[ "$MODE" == "biome-desert" || "$MODE" == "all" ]]; then
	run_script_test "biome_desert" "res://tests/smoke/biome_desert.gd"
	RC_BIOMEDESERT=$?
	RAN_BIOMEDESERT=1
fi

if [[ "$MODE" == "biome-jungle" || "$MODE" == "all" ]]; then
	run_script_test "biome_jungle" "res://tests/smoke/biome_jungle.gd"
	RC_BIOMEJUNGLE=$?
	RAN_BIOMEJUNGLE=1
fi

if [[ "$MODE" == "biome-toxic" || "$MODE" == "all" ]]; then
	run_script_test "biome_toxic" "res://tests/smoke/biome_toxic.gd"
	RC_BIOMETOXIC=$?
	RAN_BIOMETOXIC=1
fi

if [[ "$MODE" == "biome-urban" || "$MODE" == "all" ]]; then
	# Scene-based (autoloads active) because npc.gd references the GameState
	# autoload singleton, and the negotiation trade grants via GameState.
	run_scene_test "biome_urban" "res://tests/smoke/biome_urban.tscn"
	RC_BIOMEURBAN=$?
	RAN_BIOMEURBAN=1
fi

if [[ "$MODE" == "biome-alien-tech" || "$MODE" == "all" ]]; then
	run_script_test "biome_alien_tech" "res://tests/smoke/biome_alien_tech.gd"
	RC_BIOMEALIENTECH=$?
	RAN_BIOMEALIENTECH=1
fi

if [[ "$MODE" == "knockout" || "$MODE" == "all" ]]; then
	run_script_test "knockout" "res://tests/smoke/knockout.gd"
	RC_KNOCKOUT=$?
	RAN_KNOCKOUT=1
fi

if [[ "$MODE" == "scrubbers" || "$MODE" == "all" ]]; then
	run_script_test "scrubber_units" "res://tests/smoke/scrubber_units.gd"
	RC_SCRUBBERS=$?
	RAN_SCRUBBERS=1
fi

if [[ "$MODE" == "procship" || "$MODE" == "all" ]]; then
	# 900 frames (~15 s at 60 fps) — enough headroom for two floor generations
	# plus the save round-trip without the ceiling truncating and false-PASSing.
	"$GODOT_BIN" --headless --quit-after 900 -s "res://tests/smoke/test_procedural_ship.gd" 2>&1
	RC_PROCSHIP=$?
	RAN_PROCSHIP=1
fi

if [[ "$MODE" == "ftl-loop" || "$MODE" == "all" ]]; then
	run_script_test "ftl_loop" "res://tests/smoke/ftl_loop.gd"
	RC_FTLLOOP=$?
	RAN_FTLLOOP=1
fi

if [[ "$MODE" == "music" || "$MODE" == "all" ]]; then
	# 900 frames — headroom for the per-file stem load loop without truncating.
	"$GODOT_BIN" --headless --quit-after 900 -s "res://tests/smoke/music_director.gd" 2>&1
	RC_MUSIC=$?
	RAN_MUSIC=1
fi

if [[ "$MODE" == "elevator-power" || "$MODE" == "all" ]]; then
	run_script_test "elevator_power" "res://tests/smoke/elevator_power.gd"
	RC_ELEVPOWER=$?
	RAN_ELEVPOWER=1
fi

if [[ "$MODE" == "deck" || "$MODE" == "all" ]]; then
	run_script_test "deck_boot" "res://tests/smoke/deck_boot.gd"
	RC_DECK=$?
	RAN_DECK=1
fi

if [[ "$MODE" == "economy" || "$MODE" == "all" ]]; then
	run_script_test "build_economy" "res://tests/smoke/build_economy.gd"
	RC_ECONOMY=$?
	RAN_ECONOMY=1
fi

if [[ "$MODE" == "npc-chat" || "$MODE" == "all" ]]; then
	# Scene-based (autoloads active) because npc.gd references the GameState
	# autoload singleton, which won't compile under a bare -s script.
	run_scene_test "npc_chat" "res://tests/smoke/npc_chat.tscn"
	RC_NPCCHAT=$?
	RAN_NPCCHAT=1
fi

if [[ "$MODE" == "save" || "$MODE" == "all" ]]; then
	run_script_test "save_store" "res://tests/save/save_store_test.gd"
	RC_SAVE_UNIT=$?
	run_scene_test "save_slot_resume" "res://tests/save/slot_resume.tscn"
	RC_SAVE_RESUME=$?
	run_scene_test "save_profile_orchestration" "res://tests/save/profile_orchestration.tscn"
	RC_SAVE_ORCH=$?
	run_scene_test "save_load_browser" "res://tests/save/load_browser.tscn"
	RC_SAVE_BROWSER=$?
	run_scene_test "save_ingame_ui" "res://tests/save/ingame_ui.tscn"
	RC_SAVE_INGAME=$?
	RAN_SAVE=1
fi

if [[ "$MODE" == "save-integration" || "$MODE" == "save" || "$MODE" == "all" ]]; then
	run_scene_test "save_integration" "res://tests/save/integration.tscn"
	RC_SAVE_INTEGRATION=$?
	RAN_SAVE_INTEGRATION=1
fi

if [[ "$MODE" == "bridge-loop" || "$MODE" == "all" ]]; then
	run_script_test "bridge_loop_config" "res://tests/smoke/bridge_loop_config.gd"
	RC_BRIDGELOOP=$?
	RAN_BRIDGELOOP=1
fi

if [[ "$MODE" == "consumption" || "$MODE" == "all" ]]; then
	run_script_test "consumption" "res://tests/smoke/consumption.gd"
	RC_CONSUMPTION=$?
	RAN_CONSUMPTION=1
fi

if [[ "$MODE" == "repair-robot" || "$MODE" == "all" ]]; then
	# 900 frames (~15 s at 60 fps) — enough headroom for the save round-trip
	# and signal assertions without the ceiling truncating and false-PASSing.
	"$GODOT_BIN" --headless --quit-after 900 -s "res://tests/smoke/repair_robot.gd" 2>&1
	RC_REPAIR=$?
	RAN_REPAIR=1
fi

if [[ "$MODE" == "setdressing" || "$MODE" == "all" ]]; then
	run_script_test "setdressing" "res://tests/smoke/setdressing.gd"
	RC_SETDRESS=$?
	RAN_SETDRESS=1
fi

if [[ "$MODE" == "e1-opening" || "$MODE" == "all" ]]; then
	run_script_test "e1_opening" "res://tests/smoke/e1_opening.gd"
	RC_E1OPEN=$?
	RAN_E1OPEN=1
fi

if [[ "$MODE" == "cold-open" || "$MODE" == "all" ]]; then
	run_script_test "cold_open_lines" "res://tests/smoke/cold_open_lines.gd"
	RC_COLDOPEN=$?
	RAN_COLDOPEN=1
fi

if [[ "$MODE" == "away-split" || "$MODE" == "all" ]]; then
	# 900 frames (~15 s at 60 fps) — enough for companion follow ticks + assertions.
	"$GODOT_BIN" --headless --quit-after 900 -s "res://tests/smoke/away_team_split.gd" 2>&1
	RC_AWAYSPLIT=$?
	RAN_AWAYSPLIT=1
fi

if [[ "$MODE" == "char-gen" || "$MODE" == "all" ]]; then
	run_script_test "character_gen" "res://tests/smoke/character_gen.gd"
	RC_CHARGEN=$?
	RAN_CHARGEN=1
fi

if [[ "$MODE" == "vrm" || "$MODE" == "all" ]]; then
	run_script_test "vrm_character" "res://tests/smoke/vrm_character.gd"
	RC_VRM=$?
	RAN_VRM=1
fi

if [[ "$MODE" == "modular" || "$MODE" == "all" ]]; then
	run_script_test "modular_character" "res://tests/smoke/modular_character.gd"
	RC_MODULAR=$?
	RAN_MODULAR=1
fi

# Kino map visual captures — produces 4 PNGs under screenshots/result/ that
# can be eyeballed against the concept image (design/concept-art/sgu-map.png).
# Not part of `all` because it requires a headed Godot; opt-in via `visual`.
if [[ "$MODE" == "visual" || "$MODE" == "kino-map" ]]; then
	echo
	echo "==============================="
	echo " kino_map visual captures"
	echo "==============================="
	mkdir -p screenshots/result
	RC_VISUAL=0
	for s in fog partial locked full; do
		out_user="user://kino_map_${s}.png"
		"$GODOT_BIN" --rendering-driver opengl3 --quit-after 240 \
			res://scenes/title.tscn ++ kino_map_capture "scenario=${s}" "out=${out_user}" \
			2>&1 | grep -E "(\[kino_map_capture\]|ERROR.*kino)"
		# Find the abs path Godot resolved to (user:// → app_userdata).
		abs="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe/kino_map_${s}.png"
		if [[ -f "$abs" ]]; then
			cp "$abs" "screenshots/result/kino_map_${s}.png"
			echo "  ✓ screenshots/result/kino_map_${s}.png"
		else
			echo "  ✗ kino_map_${s} capture missing"
			RC_VISUAL=1
		fi
	done
fi

echo
echo "==============================="
echo " final"
echo "==============================="
[[ $RAN_LINT  -eq 1 ]] && echo "save_registration:   $([[ $RC_LINT  -eq 0 ]] && echo PASS || echo "FAIL ($RC_LINT)")"  || echo "save_registration:   SKIPPED"
[[ $RAN_LINT  -eq 1 ]] && echo "collection_forks:    $([[ $RC_FORKS -eq 0 ]] && echo PASS || echo "FAIL ($RC_FORKS)")" || echo "collection_forks:    SKIPPED"
[[ $RAN_SCENE -eq 1 ]] && echo "scene_boot:          $([[ $RC_SCENE -eq 0 ]] && echo PASS || echo "FAIL ($RC_SCENE)")" || echo "scene_boot:          SKIPPED"
[[ $RAN_FLOW  -eq 1 ]] && echo "e1_flow:             $([[ $RC_FLOW  -eq 0 ]] && echo PASS || echo "FAIL ($RC_FLOW)")"  || echo "e1_flow:             SKIPPED"
[[ $RAN_QUEST -eq 1 ]] && echo "quest_waypoint:      $([[ $RC_QUEST -eq 0 ]] && echo PASS || echo "FAIL ($RC_QUEST)")" || echo "quest_waypoint:      SKIPPED"
[[ $RAN_PLAY  -eq 1 ]] && echo "e1_playthrough:      $([[ $RC_PLAY  -eq 0 ]] && echo PASS || echo "FAIL ($RC_PLAY)")"  || echo "e1_playthrough:      SKIPPED"
[[ $RAN_RESUME -eq 1 ]] && echo "resume_probe:        $([[ $RC_RESUME -eq 0 ]] && echo PASS || echo "FAIL ($RC_RESUME)")" || echo "resume_probe:        SKIPPED"
[[ $RAN_AUTOPILOT -eq 1 ]] && echo "kino_autopilot:      $([[ $RC_AUTOPILOT -eq 0 ]] && echo PASS || echo "FAIL ($RC_AUTOPILOT)")" || echo "kino_autopilot:      SKIPPED"
[[ $RAN_QUESTLOG -eq 1 ]] && echo "quest_log:           $([[ $RC_QUESTLOG -eq 0 ]] && echo PASS || echo "FAIL ($RC_QUESTLOG)")" || echo "quest_log:           SKIPPED"
[[ $RAN_INV -eq 1 ]] && echo "inventory:           $([[ $RC_INV -eq 0 ]] && echo PASS || echo "FAIL ($RC_INV)")" || echo "inventory:           SKIPPED"
[[ $RAN_ATMO -eq 1 ]] && echo "atmosphere:          $([[ $RC_ATMO -eq 0 ]] && echo PASS || echo "FAIL ($RC_ATMO)")" || echo "atmosphere:          SKIPPED"
[[ $RAN_KINODOORS -eq 1 ]] && echo "kino_doors:          $([[ $RC_KINODOORS -eq 0 ]] && echo PASS || echo "FAIL ($RC_KINODOORS)")" || echo "kino_doors:          SKIPPED"
[[ $RAN_KINOEXPLORE -eq 1 ]] && echo "kino_autoexplore:    $([[ $RC_KINOEXPLORE -eq 0 ]] && echo PASS || echo "FAIL ($RC_KINOEXPLORE)")" || echo "kino_autoexplore:    SKIPPED"
[[ $RAN_KINODISC -eq 1 ]] && echo "kino_discovery:      $([[ $RC_KINODISC -eq 0 ]] && echo PASS || echo "FAIL ($RC_KINODISC)")" || echo "kino_discovery:      SKIPPED"
[[ $RAN_GAMEPAD -eq 1 ]] && echo "gamepad:             $([[ $RC_GAMEPAD -eq 0 ]] && echo PASS || echo "FAIL ($RC_GAMEPAD)")" || echo "gamepad:             SKIPPED"
[[ $RAN_FOOTFALL -eq 1 ]] && echo "footfall:            $([[ $RC_FOOTFALL -eq 0 ]] && echo PASS || echo "FAIL ($RC_FOOTFALL)")" || echo "footfall:            SKIPPED"
[[ $RAN_NPCCHAT -eq 1 ]] && echo "npc_chat:            $([[ $RC_NPCCHAT -eq 0 ]] && echo PASS || echo "FAIL ($RC_NPCCHAT)")" || echo "npc_chat:            SKIPPED"
[[ $RAN_SHADER -eq 1 ]] && echo "ancient_metal_shader: $([[ $RC_SHADER -eq 0 ]] && echo PASS || echo "FAIL ($RC_SHADER)")" || echo "ancient_metal_shader: SKIPPED"
[[ $RAN_ANCIENTTEXT -eq 1 ]] && echo "ancient_text:        $([[ $RC_ANCIENTTEXT -eq 0 ]] && echo PASS || echo "FAIL ($RC_ANCIENTTEXT)")" || echo "ancient_text:        SKIPPED"
[[ $RAN_DISCTOAST -eq 1 ]] && echo "discovery_toast:     $([[ $RC_DISCTOAST -eq 0 ]] && echo PASS || echo "FAIL ($RC_DISCTOAST)")" || echo "discovery_toast:     SKIPPED"
[[ $RAN_DOORPLAQUE -eq 1 ]] && echo "door_plaque:         $([[ $RC_DOORPLAQUE -eq 0 ]] && echo PASS || echo "FAIL ($RC_DOORPLAQUE)")" || echo "door_plaque:         SKIPPED"
[[ $RAN_CRATE -eq 1 ]] && echo "shuttle_crate:       $([[ $RC_CRATE -eq 0 ]] && echo PASS || echo "FAIL ($RC_CRATE)")" || echo "shuttle_crate:       SKIPPED"
[[ $RAN_UNITFRAME -eq 1 ]] && echo "unit_frame:          $([[ $RC_UNITFRAME -eq 0 ]] && echo PASS || echo "FAIL ($RC_UNITFRAME)")" || echo "unit_frame:          SKIPPED"
[[ $RAN_QUESTTRACKER -eq 1 ]] && echo "quest_tracker:       $([[ $RC_QUESTTRACKER -eq 0 ]] && echo PASS || echo "FAIL ($RC_QUESTTRACKER)")" || echo "quest_tracker:       SKIPPED"
[[ $RAN_HUDWOW -eq 1 ]] && echo "hud_wow:             $([[ $RC_HUDWOW -eq 0 ]] && echo PASS || echo "FAIL ($RC_HUDWOW)")" || echo "hud_wow:             SKIPPED"
[[ $RAN_HUDSCALE -eq 1 ]] && echo "hud_scale:           $([[ $RC_HUDSCALE -eq 0 ]] && echo PASS || echo "FAIL ($RC_HUDSCALE)")" || echo "hud_scale:           SKIPPED"
[[ $RAN_HUDCHAT -eq 1 ]] && echo "hud_chat:            $([[ $RC_HUDCHAT -eq 0 ]] && echo PASS || echo "FAIL ($RC_HUDCHAT)")" || echo "hud_chat:            SKIPPED"
[[ $RAN_GATETWOWAY -eq 1 ]] && echo "gate_two_way:        $([[ $RC_GATETWOWAY -eq 0 ]] && echo PASS || echo "FAIL ($RC_GATETWOWAY)")" || echo "gate_two_way:        SKIPPED"
[[ $RAN_EQUIPMOUNT -eq 1 ]] && echo "equipment_mount:     $([[ $RC_EQUIPMOUNT -eq 0 ]] && echo PASS || echo "FAIL ($RC_EQUIPMOUNT)")" || echo "equipment_mount:     SKIPPED"
[[ $RAN_EQUIPASSETS -eq 1 ]] && echo "equipment_assets:    $([[ $RC_EQUIPASSETS -eq 0 ]] && echo PASS || echo "FAIL ($RC_EQUIPASSETS)")" || echo "equipment_assets:    SKIPPED"
[[ $RAN_CHARPANEL -eq 1 ]] && echo "character_panel:     $([[ $RC_CHARPANEL -eq 0 ]] && echo PASS || echo "FAIL ($RC_CHARPANEL)")" || echo "character_panel:     SKIPPED"
[[ $RAN_EQUIPINT -eq 1 ]] && echo "equipment_integration: $([[ $RC_EQUIPINT -eq 0 ]] && echo PASS || echo "FAIL ($RC_EQUIPINT)")" || echo "equipment_integration: SKIPPED"
[[ $RAN_PLANETGEN -eq 1 ]] && echo "planet_generator:    $([[ $RC_PLANETGEN -eq 0 ]] && echo PASS || echo "FAIL ($RC_PLANETGEN)")" || echo "planet_generator:    SKIPPED"
[[ $RAN_PLANETRES -eq 1 ]] && echo "planet_resources:    $([[ $RC_PLANETRES -eq 0 ]] && echo PASS || echo "FAIL ($RC_PLANETRES)")" || echo "planet_resources:    SKIPPED"
[[ $RAN_PLANETINT -eq 1 ]] && echo "planet_integration:  $([[ $RC_PLANETINT -eq 0 ]] && echo PASS || echo "FAIL ($RC_PLANETINT)")" || echo "planet_integration:  SKIPPED"
[[ $RAN_BIOMEDESERT -eq 1 ]] && echo "biome_desert:        $([[ $RC_BIOMEDESERT -eq 0 ]] && echo PASS || echo "FAIL ($RC_BIOMEDESERT)")" || echo "biome_desert:        SKIPPED"
[[ $RAN_BIOMEJUNGLE -eq 1 ]] && echo "biome_jungle:        $([[ $RC_BIOMEJUNGLE -eq 0 ]] && echo PASS || echo "FAIL ($RC_BIOMEJUNGLE)")" || echo "biome_jungle:        SKIPPED"
[[ $RAN_BIOMETOXIC -eq 1 ]] && echo "biome_toxic:         $([[ $RC_BIOMETOXIC -eq 0 ]] && echo PASS || echo "FAIL ($RC_BIOMETOXIC)")" || echo "biome_toxic:         SKIPPED"
[[ $RAN_BIOMEURBAN -eq 1 ]] && echo "biome_urban:         $([[ $RC_BIOMEURBAN -eq 0 ]] && echo PASS || echo "FAIL ($RC_BIOMEURBAN)")" || echo "biome_urban:         SKIPPED"
[[ $RAN_BIOMEALIENTECH -eq 1 ]] && echo "biome_alien_tech:    $([[ $RC_BIOMEALIENTECH -eq 0 ]] && echo PASS || echo "FAIL ($RC_BIOMEALIENTECH)")" || echo "biome_alien_tech:    SKIPPED"
[[ $RAN_KNOCKOUT -eq 1 ]] && echo "knockout:            $([[ $RC_KNOCKOUT -eq 0 ]] && echo PASS || echo "FAIL ($RC_KNOCKOUT)")" || echo "knockout:            SKIPPED"
[[ $RAN_SCRUBBERS -eq 1 ]] && echo "scrubber_units:      $([[ $RC_SCRUBBERS -eq 0 ]] && echo PASS || echo "FAIL ($RC_SCRUBBERS)")" || echo "scrubber_units:      SKIPPED"
[[ $RAN_PROCSHIP -eq 1 ]] && echo "test_procedural_ship: $([[ $RC_PROCSHIP -eq 0 ]] && echo PASS || echo "FAIL ($RC_PROCSHIP)")" || echo "test_procedural_ship: SKIPPED"
[[ $RAN_FTLLOOP -eq 1 ]] && echo "ftl_loop:            $([[ $RC_FTLLOOP -eq 0 ]] && echo PASS || echo "FAIL ($RC_FTLLOOP)")" || echo "ftl_loop:            SKIPPED"
[[ $RAN_MUSIC -eq 1 ]] && echo "music_director:      $([[ $RC_MUSIC -eq 0 ]] && echo PASS || echo "FAIL ($RC_MUSIC)")" || echo "music_director:      SKIPPED"
[[ $RAN_ELEVPOWER -eq 1 ]] && echo "elevator_power:      $([[ $RC_ELEVPOWER -eq 0 ]] && echo PASS || echo "FAIL ($RC_ELEVPOWER)")" || echo "elevator_power:      SKIPPED"
[[ $RAN_BRIDGELOOP -eq 1 ]] && echo "bridge_loop_config:  $([[ $RC_BRIDGELOOP -eq 0 ]] && echo PASS || echo "FAIL ($RC_BRIDGELOOP)")" || echo "bridge_loop_config:  SKIPPED"
[[ $RAN_CONSUMPTION -eq 1 ]] && echo "consumption:         $([[ $RC_CONSUMPTION -eq 0 ]] && echo PASS || echo "FAIL ($RC_CONSUMPTION)")" || echo "consumption:         SKIPPED"
[[ $RAN_REPAIR -eq 1 ]] && echo "repair_robot:        $([[ $RC_REPAIR -eq 0 ]] && echo PASS || echo "FAIL ($RC_REPAIR)")" || echo "repair_robot:        SKIPPED"
[[ $RAN_SETDRESS -eq 1 ]] && echo "setdressing:         $([[ $RC_SETDRESS -eq 0 ]] && echo PASS || echo "FAIL ($RC_SETDRESS)")" || echo "setdressing:         SKIPPED"
[[ $RAN_E1OPEN  -eq 1 ]] && echo "e1_opening:          $([[ $RC_E1OPEN  -eq 0 ]] && echo PASS || echo "FAIL ($RC_E1OPEN)")"  || echo "e1_opening:          SKIPPED"
[[ $RAN_COLDOPEN -eq 1 ]] && echo "cold_open_lines:     $([[ $RC_COLDOPEN -eq 0 ]] && echo PASS || echo "FAIL ($RC_COLDOPEN)")"  || echo "cold_open_lines:     SKIPPED"
[[ $RAN_AWAYSPLIT -eq 1 ]] && echo "away_team_split:     $([[ $RC_AWAYSPLIT -eq 0 ]] && echo PASS || echo "FAIL ($RC_AWAYSPLIT)")" || echo "away_team_split:     SKIPPED"
[[ $RAN_CHARGEN -eq 1 ]] && echo "character_gen:       $([[ $RC_CHARGEN -eq 0 ]] && echo PASS || echo "FAIL ($RC_CHARGEN)")" || echo "character_gen:       SKIPPED"
[[ $RAN_VRM -eq 1 ]] && echo "vrm_character:       $([[ $RC_VRM -eq 0 ]] && echo PASS || echo "FAIL ($RC_VRM)")" || echo "vrm_character:       SKIPPED"
[[ $RAN_MODULAR -eq 1 ]] && echo "modular_character:   $([[ $RC_MODULAR -eq 0 ]] && echo PASS || echo "FAIL ($RC_MODULAR)")" || echo "modular_character:   SKIPPED"
[[ $RAN_DECK -eq 1 ]] && echo "deck_boot:           $([[ $RC_DECK -eq 0 ]] && echo PASS || echo "FAIL ($RC_DECK)")" || echo "deck_boot:           SKIPPED"
[[ $RAN_ECONOMY -eq 1 ]] && echo "build_economy:       $([[ $RC_ECONOMY -eq 0 ]] && echo PASS || echo "FAIL ($RC_ECONOMY)")" || echo "build_economy:       SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_store:          $([[ $RC_SAVE_UNIT -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_UNIT)")" || echo "save_store:          SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_slot_resume:    $([[ $RC_SAVE_RESUME -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_RESUME)")" || echo "save_slot_resume:    SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_profile_orch:   $([[ $RC_SAVE_ORCH -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_ORCH)")" || echo "save_profile_orch:   SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_load_browser:   $([[ $RC_SAVE_BROWSER -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_BROWSER)")" || echo "save_load_browser:   SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_ingame_ui:      $([[ $RC_SAVE_INGAME -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_INGAME)")" || echo "save_ingame_ui:      SKIPPED"
[[ $RAN_SAVE_INTEGRATION -eq 1 ]] && echo "save_integration:    $([[ $RC_SAVE_INTEGRATION -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_INTEGRATION)")" || echo "save_integration:    SKIPPED"

if [[ ( $RAN_LINT -eq 1 && $RC_LINT -ne 0 ) || ( $RAN_LINT -eq 1 && $RC_FORKS -ne 0 ) || ( $RAN_SCENE -eq 1 && $RC_SCENE -ne 0 ) || ( $RAN_FLOW -eq 1 && $RC_FLOW -ne 0 ) || ( $RAN_QUEST -eq 1 && $RC_QUEST -ne 0 ) || ( $RAN_PLAY -eq 1 && $RC_PLAY -ne 0 ) || ( $RAN_RESUME -eq 1 && $RC_RESUME -ne 0 ) || ( $RAN_AUTOPILOT -eq 1 && $RC_AUTOPILOT -ne 0 ) || ( $RAN_QUESTLOG -eq 1 && $RC_QUESTLOG -ne 0 ) || ( $RAN_INV -eq 1 && $RC_INV -ne 0 ) || ( $RAN_ATMO -eq 1 && $RC_ATMO -ne 0 ) || ( $RAN_KINODOORS -eq 1 && $RC_KINODOORS -ne 0 ) || ( $RAN_KINOEXPLORE -eq 1 && $RC_KINOEXPLORE -ne 0 ) || ( $RAN_KINODISC -eq 1 && $RC_KINODISC -ne 0 ) || ( $RAN_GAMEPAD -eq 1 && $RC_GAMEPAD -ne 0 ) || ( $RAN_FOOTFALL -eq 1 && $RC_FOOTFALL -ne 0 ) || ( $RAN_NPCCHAT -eq 1 && $RC_NPCCHAT -ne 0 ) || ( $RAN_SHADER -eq 1 && $RC_SHADER -ne 0 ) || ( $RAN_ANCIENTTEXT -eq 1 && $RC_ANCIENTTEXT -ne 0 ) || ( $RAN_DISCTOAST -eq 1 && $RC_DISCTOAST -ne 0 ) || ( $RAN_DOORPLAQUE -eq 1 && $RC_DOORPLAQUE -ne 0 ) || ( $RAN_CRATE -eq 1 && $RC_CRATE -ne 0 ) || ( $RAN_UNITFRAME -eq 1 && $RC_UNITFRAME -ne 0 ) || ( $RAN_QUESTTRACKER -eq 1 && $RC_QUESTTRACKER -ne 0 ) || ( $RAN_HUDWOW -eq 1 && $RC_HUDWOW -ne 0 ) || ( $RAN_HUDSCALE -eq 1 && $RC_HUDSCALE -ne 0 ) || ( $RAN_HUDCHAT -eq 1 && $RC_HUDCHAT -ne 0 ) || ( $RAN_GATETWOWAY -eq 1 && $RC_GATETWOWAY -ne 0 ) || ( $RAN_EQUIPMOUNT -eq 1 && $RC_EQUIPMOUNT -ne 0 ) || ( $RAN_EQUIPASSETS -eq 1 && $RC_EQUIPASSETS -ne 0 ) || ( $RAN_CHARPANEL -eq 1 && $RC_CHARPANEL -ne 0 ) || ( $RAN_EQUIPINT -eq 1 && $RC_EQUIPINT -ne 0 ) || ( $RAN_PLANETGEN -eq 1 && $RC_PLANETGEN -ne 0 ) || ( $RAN_PLANETRES -eq 1 && $RC_PLANETRES -ne 0 ) || ( $RAN_PLANETINT -eq 1 && $RC_PLANETINT -ne 0 ) || ( $RAN_BIOMEDESERT -eq 1 && $RC_BIOMEDESERT -ne 0 ) || ( $RAN_BIOMEJUNGLE -eq 1 && $RC_BIOMEJUNGLE -ne 0 ) || ( $RAN_BIOMETOXIC -eq 1 && $RC_BIOMETOXIC -ne 0 ) || ( $RAN_BIOMEURBAN -eq 1 && $RC_BIOMEURBAN -ne 0 ) || ( $RAN_KNOCKOUT -eq 1 && $RC_KNOCKOUT -ne 0 ) || ( $RAN_SCRUBBERS -eq 1 && $RC_SCRUBBERS -ne 0 ) || ( $RAN_PROCSHIP -eq 1 && $RC_PROCSHIP -ne 0 ) || ( $RAN_FTLLOOP -eq 1 && $RC_FTLLOOP -ne 0 ) || ( $RAN_MUSIC -eq 1 && $RC_MUSIC -ne 0 ) || ( $RAN_ELEVPOWER -eq 1 && $RC_ELEVPOWER -ne 0 ) || ( $RAN_BRIDGELOOP -eq 1 && $RC_BRIDGELOOP -ne 0 ) || ( $RAN_CONSUMPTION -eq 1 && $RC_CONSUMPTION -ne 0 ) || ( $RAN_REPAIR -eq 1 && $RC_REPAIR -ne 0 ) || ( $RAN_DECK -eq 1 && $RC_DECK -ne 0 ) || ( $RAN_ECONOMY -eq 1 && $RC_ECONOMY -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_UNIT -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_RESUME -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_ORCH -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_BROWSER -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_INGAME -ne 0 ) || ( $RAN_SAVE_INTEGRATION -eq 1 && $RC_SAVE_INTEGRATION -ne 0 ) || ( $RAN_E1OPEN -eq 1 && $RC_E1OPEN -ne 0 ) || ( $RAN_COLDOPEN -eq 1 && $RC_COLDOPEN -ne 0 ) || ( $RAN_AWAYSPLIT -eq 1 && $RC_AWAYSPLIT -ne 0 ) || ( $RAN_CHARGEN -eq 1 && $RC_CHARGEN -ne 0 ) || ( $RAN_VRM -eq 1 && $RC_VRM -ne 0 ) || ( $RAN_MODULAR -eq 1 && $RC_MODULAR -ne 0 ) ]]; then
	exit 1
fi
exit 0
