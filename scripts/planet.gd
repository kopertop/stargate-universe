extends Node3D

# Runtime shell for the generated Air lime planet. The scene owns common player,
# camera, and HUD nodes; PlanetGenerator owns deterministic world contents.

const PLANETS_PATH: String = "res://data/planets.json"
const PLANET_ID: String = "air_lime_world"
const PlanetGeneratorRef: Script = preload("res://scripts/planet_generator.gd")
const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")
const PlanetTimerScript: Script = preload("res://scripts/planet_timer.gd")
const CompanionScript: Script = preload("res://scripts/companion.gd")

@onready var _world: Node3D = $World
@onready var _player: Node3D = $Player
@onready var _view: Node3D = $View

func _ready() -> void:
	GameState.current_scene_path = "res://scenes/planet.tscn"
	var planet_data: Dictionary = _load_planet(PLANET_ID)
	PlanetGeneratorRef.build(_world, planet_data)
	GameState.discover_room("planet_" + PLANET_ID, String(planet_data.get("name", "Lime Planet")))
	# Scout beat: the player launched an unmanned Kino through the gate. Hand
	# the planet to a pilotable recon drone instead of the third-person player.
	if GameState.kino_pilot_mode:
		_start_kino_recon(planet_data)
		return
	if GameState.pending_spawn_position != null:
		_player.global_position = GameState.pending_spawn_position
		_player.rotation.y = GameState.pending_spawn_yaw
		GameState.pending_spawn_position = null
	if _view.has_method("snap_to_target"):
		_view.snap_to_target()
	if GameState.quest_step == GameState.QUEST_MINE_LIME:
		GameState.add_log("Planet scan confirmed lime deposits near the active gate.")
		# Start the gate-window countdown for the on-foot mining run (the Kino
		# scout already returned above). Inert in instant_mode (headless tests).
		var timer: Node = PlanetTimerScript.new()
		timer.name = "DepartureTimer"
		add_child(timer)
		# Replace the top-left objective with a live "X/N lime" counter while
		# the player is on the planet. This is the same string the now-removed
		# planet_timer sub-label used to render, but lifted into the existing
		# objective slot so it doesn't overlap the compass strip. Refreshed on
		# every resource_changed; restored to the canonical quest-step text in
		# _exit_tree so the gate room reads its normal objective again.
		_refresh_lime_objective()
		if not GameState.resource_changed.is_connected(_on_resource_changed):
			GameState.resource_changed.connect(_on_resource_changed)
		# The away team (Greer, Park, Scott) lands with Eli to help mine. Live
		# play only — headless playthrough must not have companions auto-mining
		# lime and skewing resource assertions.
		if not SceneRouter.instant_mode:
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
# departure timer fires (group "away_team"). Greer reuses Scott's GLB (Kenney
# `character-male-d`, beret + uniform — the most military-looking of the six
# Mini-Characters males) with a warm-brown tint applied per-instance, so on
# screen the away team reads as two same-silhouette soldiers with different
# skin tones (none of the Kenney mini-chars ship with a darker-skin variant).
const SCOTT_GLB: String = "res://models/characters/scott.glb"
const GREER_TINT: Color = Color(0.66, 0.50, 0.38)   # warm brown — skin reads as brown, uniform as olive-drab
func _spawn_away_team(near: Vector3) -> void:
	var roster: Array = [
		{"name": "Greer", "glb": SCOTT_GLB, "tint": GREER_TINT},
		{"name": "Park", "glb": "res://models/characters/park.glb", "tint": Color.WHITE},
		{"name": "Lt Scott", "glb": SCOTT_GLB, "tint": Color.WHITE},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var at: Vector3 = near + Vector3(-2.4 + float(i) * 2.4, 0.0, 2.4)
		var c: Node3D = CompanionScript.new()
		c.name = "Companion_" + String(entry["name"]).replace(" ", "")
		add_child(c)
		c.global_position = at
		c.call("setup", String(entry["name"]), String(entry["glb"]), i, entry["tint"])

# Replace the third-person player rig with a pilotable Kino. The drone owns its
# own camera + overlay; freeing the player/view rig stops their camera and
# input from competing. Hides the normal HUD so the kino-cam reads clean.
func _start_kino_recon(planet_data: Dictionary) -> void:
	var marker: Node3D = $FromShipGate
	# Start a few metres up so the orb hovers over the landing zone, not on it.
	var spawn: Vector3 = marker.global_position + Vector3.UP * 4.0
	var spawn_yaw: float = marker.global_transform.basis.get_euler().y
	# Re-taking control of a Kino already left on the planet → spawn it AT that
	# tracked spot. A fresh scout arrival (no target) → frame it emerging from the
	# return gate (pushed back a few metres, facing the gate it came through).
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
				var toward: Vector3 = return_gate.global_position - spawn
				toward.y = 0.0
				spawn_yaw = atan2(-toward.x, -toward.z)
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
	var atmo: Variant = planet_data.get("atmosphere", {})
	drone.set("atmosphere", atmo if atmo is Dictionary else {})
	# Set yaw BEFORE add_child: the drone caches its initial heading in _ready,
	# which fires during add_child. Setting it after would leave the cache at 0
	# and the first mouse-look would snap the drone back to facing the gate.
	drone.rotation.y = spawn_yaw
	add_child(drone)
	drone.global_position = spawn

func _load_planet(id: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(PLANETS_PATH, FileAccess.READ)
	if f == null:
		push_error("planet.gd: cannot open %s" % PLANETS_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		push_error("planet.gd: %s did not parse to an array" % PLANETS_PATH)
		return {}
	for entry in parsed:
		if entry is Dictionary and String(entry.get("id", "")) == id:
			return entry
	return {}
