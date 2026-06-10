extends Node3D

# Runtime shell for the generated Air lime planet. The scene owns common player,
# camera, and HUD nodes; PlanetGenerator owns deterministic world contents.

const PlanetGeneratorRef: Script = preload("res://scripts/planet_generator.gd")
const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")
const PlanetTimerScript: Script = preload("res://scripts/planet_timer.gd")
const CompanionScript: Script = preload("res://scripts/companion.gd")
const FootstepLib: Script = preload("res://scripts/footstep_library.gd")

@onready var _world: Node3D = $World
@onready var _player: Node3D = $Player
@onready var _view: Node3D = $View

# Set by build from the active PlanetSpec — handed the tracked body so terrain
# streams around it. Held so _start_kino_recon can retarget it onto the drone.
var _chunk_manager: Node3D = null

func _ready() -> void:
	GameState.current_scene_path = "res://scenes/planet.tscn"
	# Build from the active PlanetSpec (issue #85). If none is set (direct boot /
	# smoke test), seed + persist a default desert spec from planets.json so the
	# world is deterministic and survives save/load like a dialed planet.
	var spec: Dictionary = _active_spec()
	_chunk_manager = PlanetGeneratorRef.build(_world, spec)
	var planet_name: String = String(spec.get("name", "Lime Planet"))
	var planet_key: String = "planet_%s_%d" % [String(spec.get("biome", "desert")), int(spec.get("seed", 0))]
	GameState.discover_room(planet_key, planet_name)
	# Stream terrain around the player by default; kino recon retargets below.
	if _chunk_manager != null and _chunk_manager.has_method("configure"):
		_chunk_manager.set("tracked", _player)
	# Scout beat: the player launched an unmanned Kino through the gate. Hand
	# the planet to a pilotable recon drone instead of the third-person player.
	if GameState.kino_pilot_mode:
		_start_kino_recon(spec)
		return
	# On-foot landing (past the Kino-recon early-return): decipher the planet so
	# its name reads plainly and the arrival toast fires. A Kino recon scout only
	# discovers it (above), leaving it encrypted until the away team lands.
	GameState.decipher_room(planet_key)
	# On foot: push this planet's biome footstep surface (the ship stays metal).
	# Done here (parent _ready) AFTER the spec is resolved — the player's own
	# _ready already ran (child first) and only set the metal default.
	if is_instance_valid(_player) and _player.has_method("set_footstep_surface"):
		_player.call("set_footstep_surface", FootstepLib.surface_for_spec(spec))
	if GameState.pending_spawn_position != null:
		_player.global_position = GameState.pending_spawn_position
		_player.rotation.y = GameState.pending_spawn_yaw
		GameState.pending_spawn_position = null
	if _view.has_method("snap_to_target"):
		_view.snap_to_target()
	# The on-foot mining run spans MINE_LIME (collect) → RETURN_DESTINY (carry it
	# back), ending only when the team actually crosses back through the gate
	# (returned_from_lime_planet + scene → gate room). Collecting the required
	# lime auto-advances MINE_LIME → RETURN_DESTINY WHILE STILL ON THE PLANET
	# (mine_lime's complete_when is has_required_lime), so a save taken then must
	# STILL rebuild the departure timer + away team on load. Keying only on
	# MINE_LIME dropped both — the "gate clock + crew gone after load" bug.
	var on_planet_run: bool = (GameState.quest_step == GameState.QUEST_MINE_LIME \
			or GameState.quest_step == GameState.QUEST_RETURN_DESTINY) \
			and not GameState.returned_from_lime_planet
	if on_planet_run:
		# Departure-countdown view. start_gate_window (in its _ready) is idempotent:
		# a fresh MINE_LIME entry starts the clock; a save-resume (incl. at
		# RETURN_DESTINY) resumes the saved remaining time. Inert in instant_mode.
		var timer: Node = PlanetTimerScript.new()
		timer.name = "DepartureTimer"
		add_child(timer)
		# Lime "X/N" counter objective + live refresh are MINE_LIME-only; at
		# RETURN_DESTINY the quest objective is already "carry it back through the
		# gate", so we don't clobber it.
		if GameState.quest_step == GameState.QUEST_MINE_LIME:
			GameState.add_log("Planet scan confirmed lime deposits near the active gate.")
			_refresh_lime_objective()
			if not GameState.resource_changed.is_connected(_on_resource_changed):
				GameState.resource_changed.connect(_on_resource_changed)
		# The away team (Greer, Park, Scott) is on the surface with Eli for the
		# whole run. Live play only — headless must not have companions auto-mining
		# lime and skewing resource assertions.
		if not SceneRouter.instant_mode:
			_play_split_dialogue()
			_spawn_away_team(_player.global_position)


func _exit_tree() -> void:
	# GameState autoload outlives the planet scene — disconnect explicitly so
	# the signal can't hold a callable into a freed object after the planet
	# tears down. Restoring the canonical objective text means the gate room
	# (or wherever we return to) sees the right top-left line on arrival.
	if GameState.resource_changed.is_connected(_on_resource_changed):
		GameState.resource_changed.disconnect(_on_resource_changed)
	# Re-emit the canonical objective text via QuestLog so the gate room
	# sees the standard step copy on arrival. QuestLog.objective() returns
	# the data-driven text for the active step (post-#36 quest rewrite).
	if GameState.quest_step == GameState.QUEST_MINE_LIME:
		var ql: Node = get_node_or_null("/root/QuestLog")
		if ql != null and ql.has_method("objective"):
			GameState.set_objective(String(ql.call("objective", GameState.E1_QUEST_ID)))


func _on_resource_changed(type: String, _count: int) -> void:
	# Skip when MINE_LIME has already auto-advanced to QUEST_RETURN_DESTINY:
	# `add_resource` emits resource_changed BEFORE advance_air_quest fires,
	# but it also fires for any over-cap pickups afterwards. Without this
	# guard a 4th lime would clobber the "Return through the gate" line with
	# our counter again.
	if type == GameState.AIR_LIME_RESOURCE and GameState.quest_step == GameState.QUEST_MINE_LIME:
		_refresh_lime_objective()


func _refresh_lime_objective() -> void:
	var have: int = GameState.resource_count(GameState.AIR_LIME_RESOURCE)
	GameState.set_objective(GameState.lime_objective_text(have, GameState.AIR_LIME_REQUIRED))

# Greer, Park and Scott followed Eli through the gate. They follow him on the
# surface and fan out to mine lime, then rush back through the gate when the
# departure timer fires (group "away_team"). Appearance (base model, mission
# fatigues, Greer's skin tone, rifles for military) comes from
# CharacterFactory — companions dress for CTX_MISSION in _build_body.
#
# On arrival Scott splits the team: Greer (north, -Z) follows + mines with the
# player; Scott + Park (south, +Z) peel off and hold position. "north"=-Z per
# project convention (planet.gd coordinate frame). Both teams are still members
# of group "away_team" so the departure muster (planet_timer.gd rush_to()) and
# compass HUD behave identically. Issue #137.
func _spawn_away_team(near: Vector3) -> void:
	# team attribute: "north" = -Z (follows + mines), "south" = +Z (peeled off).
	# glb is a fallback only — the factory resolves registered crew models.
	var roster: Array = [
		{"name": "Greer",    "glb": "res://models/characters/greer.glb", "team": "north"},
		{"name": "Park",     "glb": "res://models/characters/park.glb",  "team": "south"},
		{"name": "Lt Scott", "glb": "res://models/characters/scott.glb", "team": "south"},
	]
	var north_idx: int = 0   # X spread within each team
	var south_idx: int = 0
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var is_south: bool = entry["team"] == "south"
		var at: Vector3
		if is_south:
			# South team: offset clearly to +Z so Scott + Park visibly peel off.
			at = near + Vector3(-1.2 + float(south_idx) * 2.4, 0.0, 6.0)
			south_idx += 1
		else:
			# North team: near the player on the -Z side (same side as the gate).
			at = near + Vector3(-1.2 + float(north_idx) * 2.4, 0.0, -2.4)
			north_idx += 1
		var c: Node3D = CompanionScript.new()
		c.name = "Companion_" + String(entry["name"]).replace(" ", "")
		# Set peeled_off BEFORE setup() so _process sees the correct value as
		# soon as the first frame ticks — mirrors gate_room's stationary pattern.
		c.set("peeled_off", is_south)
		add_child(c)
		c.global_position = at
		c.call("setup", String(entry["name"]), String(entry["glb"]), i)
	# Radio report: Scott's south team found lime on their ridge. Log only —
	# must NOT call add_resource (would skew the mine_lime count and potentially
	# auto-advance the quest step). Live play only (whole block is inside the
	# not instant_mode guard in _ready).
	GameState.add_log("Lt Scott (radio): South ridge's got lime too — we're pulling some. You grab what's near the gate.")


# Arrival split dialogue (issue #137). Scott calls the north/south split on
# landing. Single beat, emitted via GameState.dialog_started exactly as
# _play_gate_dialog does in gate_room.gd. Double instant_mode guard: the outer
# guard in _ready already skips the whole live-play block, but this inner guard
# is an explicit contract so the function is safe to call standalone in tests.
func _play_split_dialogue() -> void:
	if SceneRouter.instant_mode:
		return
	GameState.add_log("Lt Scott: Okay, let's split up. Greer and Eli, you head north. Park and I will head south.")
	# Defer the dialog emit until the arrival transition has finished. The WoW
	# dialog pauses the scene tree (dialog_screen.gd::start), and SceneRouter's
	# fade-OUT is a tween bound to the (now-paused) autoload — opening the dialog
	# mid-fade freezes the full-screen black fade rect up forever, so the planet
	# "never loads" (it has; the black curtain just never lifts). gate_room.gd's
	# _play_gate_dialog dodges this by waiting past the fade before emitting; do
	# the same, polling the router rather than racing a hard-coded timer.
	var guard: int = 0
	while SceneRouter.is_transitioning and guard < 120:
		await get_tree().process_frame
		guard += 1
	if not is_inside_tree():
		return
	var tree: Array = _split_dialog_tree()
	var player: Node = get_tree().get_first_node_in_group("player")
	GameState.dialog_started.emit(player, tree)


func _split_dialog_tree() -> Array:
	return [
		{
			"speaker": "Lt Scott",
			"text": "Okay, let's split up. Greer and Eli, you head north. Park and I will head south.",
			"choices": [{"text": "...", "next": "exit"}],
		},
	]

# Replace the third-person player rig with a pilotable Kino. The drone owns its
# own camera + overlay; freeing the player/view rig stops their camera and
# input from competing. Hides the normal HUD so the kino-cam reads clean.
func _start_kino_recon(spec: Dictionary) -> void:
	var marker: Node3D = $FromShipGate
	# Start a few metres up so the orb hovers over the landing zone, not on it.
	var spawn: Vector3 = marker.global_position + Vector3.UP * 4.0
	var spawn_yaw: float = marker.global_transform.basis.get_euler().y
	# Re-taking control of a Kino already left on the planet → spawn it AT that
	# tracked spot. A fresh scout arrival (no target) → frame it emerging from the
	# return gate (pushed back a few metres, looking out into the planet — the gate
	# is BEHIND it, since it just flew through).
	var target: Variant = GameState.kino_pilot_target_pos
	if target is Vector3 and GameState.kino_pilot_target_scene == "res://scenes/planet.tscn":
		spawn = target
		GameState.kino_pilot_target_pos = null
		GameState.kino_pilot_target_scene = ""
	else:
		var return_gate: Node3D = _world.get_node_or_null("PlanetReturnStargate") as Node3D
		if return_gate != null:
			var away: Vector3 = spawn - return_gate.global_position
			away.y = 0.0
			if away.length() > 0.5:
				spawn += away.normalized() * 5.0
				# Face AWAY from the gate (forward = -basis.z must point along
				# `away`): you pass THROUGH a gate, so it ends up behind you.
				spawn_yaw = atan2(-away.x, -away.z)
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_view):
		_view.queue_free()
	var hud_layer: Node = get_node_or_null("HUDLayer")
	if hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	var drone: CharacterBody3D = KinoDroneScript.new()
	drone.name = "KinoDrone"
	# Not in group "player": the recon drone is a camera, not the player body.
	drone.set("launch_in_ship", false)
	# Atmosphere lives in the spec's hazard_params (carried from the dialed
	# biome / legacy planets.json "atmosphere" block via _normalize_spec). The
	# Kino scan profile (issue #93) layers the upcoming planet's biome label +
	# hazard + resource summary on top so the recon HUD reads "what's down there"
	# before/while the player chooses to cross.
	var atmo: Dictionary = spec.get("hazard_params", {}).duplicate(true) \
		if spec.get("hazard_params", {}) is Dictionary else {}
	var profile: Dictionary = GameState.planet_scan_profile(spec)
	atmo["biome_label"] = String(profile.get("label", ""))
	atmo["hazard"] = String(profile.get("hazard", "NONE"))
	atmo["resources"] = profile.get("resources", [])
	# Surface the derived breathability / readings so the readout colours correctly
	# even when hazard_params omits them (e.g. a fresh dialed biome).
	atmo["breathable"] = profile.get("breathable", true)
	atmo["composition"] = String(profile.get("composition", "BREATHABLE"))
	atmo["temperature_c"] = int(profile.get("temperature_c", 20))
	atmo["temperature_note"] = String(profile.get("temperature_note", ""))
	atmo["radiation"] = String(profile.get("radiation", "LOW"))
	atmo["toxins"] = String(profile.get("toxins", "NONE"))
	drone.set("atmosphere", atmo)
	# Stream terrain around the DRONE now that the player rig is gone.
	if _chunk_manager != null and is_instance_valid(_chunk_manager):
		_chunk_manager.set("tracked", drone)
	# Set yaw BEFORE add_child: the drone caches its initial heading in _ready,
	# which fires during add_child. Setting it after would leave the cache at 0
	# and the first mouse-look would snap the drone back to facing the gate.
	drone.rotation.y = spawn_yaw
	add_child(drone)
	drone.global_position = spawn

# Resolve the PlanetSpec to build. Priority: the active spec set by the dial /
# selection flow (persisted across save/load); else seed + persist a default
# desert spec from the planets.json default row so a direct boot is deterministic
# and survives reload identically (acceptance: spec persists + rebuilds).
func _active_spec() -> Dictionary:
	var active: Dictionary = GameState.active_planet_spec
	if active is Dictionary and not active.is_empty():
		return active
	# No spec set (direct boot / scene_boot smoke test): defer to the SINGLE
	# authored-spec builder in GameState so the layout matches a real dialed lime
	# run byte-for-byte (no forked copy of the air-lime layout here).
	return GameState.build_air_lime_spec()
