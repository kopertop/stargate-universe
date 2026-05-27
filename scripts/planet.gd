extends Node3D

# Runtime shell for the generated Air lime planet. The scene owns common player,
# camera, and HUD nodes; PlanetGenerator owns deterministic world contents.

const PLANETS_PATH: String = "res://data/planets.json"
const PLANET_ID: String = "air_lime_world"
const PlanetGeneratorRef: Script = preload("res://scripts/planet_generator.gd")
const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")

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

# Replace the third-person player rig with a pilotable Kino. The drone owns its
# own camera + overlay; freeing the player/view rig stops their camera and
# input from competing. Hides the normal HUD so the kino-cam reads clean.
func _start_kino_recon(planet_data: Dictionary) -> void:
	var marker: Node3D = $FromShipGate
	# Start a few metres up so the orb hovers over the landing zone, not on it.
	var spawn: Vector3 = marker.global_position + Vector3.UP * 4.0
	var spawn_yaw: float = marker.global_transform.basis.get_euler().y
	# The Kino just came THROUGH the gate, so frame it on arrival: push the spawn
	# a few metres out from the return gate and face the drone back at it, so the
	# player clearly sees the gate they emerged from before scouting.
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
	drone.add_to_group("player")  # SceneRouter / camera lookups expect this group
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
