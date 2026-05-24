extends Node3D

# Runtime shell for the generated Air lime planet. The scene owns common player,
# camera, and HUD nodes; PlanetGenerator owns deterministic world contents.

const PLANETS_PATH: String = "res://data/planets.json"
const PLANET_ID: String = "air_lime_world"
const PlanetGeneratorRef: Script = preload("res://scripts/planet_generator.gd")

@onready var _world: Node3D = $World
@onready var _player: Node3D = $Player
@onready var _view: Node3D = $View

func _ready() -> void:
	GameState.current_scene_path = "res://scenes/planet.tscn"
	var planet_data: Dictionary = _load_planet(PLANET_ID)
	PlanetGeneratorRef.build(_world, planet_data)
	GameState.discover_room("planet_" + PLANET_ID, String(planet_data.get("name", "Lime Planet")))
	if GameState.pending_spawn_position != null:
		_player.global_position = GameState.pending_spawn_position
		_player.rotation.y = GameState.pending_spawn_yaw
		GameState.pending_spawn_position = null
	if _view.has_method("snap_to_target"):
		_view.snap_to_target()
	if GameState.quest_step == GameState.QUEST_MINE_LIME:
		GameState.add_log("Planet scan confirmed lime deposits near the active gate.")

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
