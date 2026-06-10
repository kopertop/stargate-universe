extends RefCounted
class_name CharacterStyle

# Single source of truth for how named crew look across the WHOLE ship. Spawn
# sites (room.gd::_spawn_npc, the standoff, gate_room.gd tableaus) all route
# through here so a character can't look like a scientist in one room and a
# soldier in another (the "Greer in a suit" bug). Preload as a const Script and
# call the static methods — class_name lookup can lag in headless `-s` runs.

const COLORMAP_PATH: String = "res://models/characters/Textures/colormap.png"

# Base model per character — THE place to tweak who looks like what across the
# whole ship. Spawn sites resolve through model_for() so a model swap here (e.g.
# Park's skater-with-arm-pads → a clean scientist body) propagates everywhere.
const MODELS: Dictionary = {
	"Eli": "res://models/characters/eli.glb",
	"Dr Rush": "res://models/characters/rush.glb",
	"Lt Scott": "res://models/characters/scott.glb",
	"Sgt Greer": "res://models/characters/scott.glb",
	"Colonel Young": "res://models/characters/scott.glb",
	"Dr Park": "res://models/characters/park.glb",
	"Dr James": "res://models/characters/james.glb",
	"Lt James": "res://models/characters/lt_james.glb",
	"Chloe Armstrong": "res://models/characters/chloe.glb",
}

# Crew who wear army fatigues + always carry a sidearm, wherever they appear.
const MILITARY: Array[String] = ["Sgt Greer", "Lt Scott"]


# Surname/keyword-based so it matches every label variant a spawn site might use
# ("Greer", "Sgt Greer", "Scott", "Lt Scott", generic "Soldier").
static func is_military(character_name: String) -> bool:
	return character_name.contains("Greer") \
		or character_name.contains("Scott") \
		or character_name.contains("Soldier")


# Resolve a character's base model, falling back to a per-site default for any
# character not in the registry.
static func model_for(character_name: String, fallback: String = "") -> String:
	return String(MODELS.get(character_name, fallback))


# Dress a military crew member: olive-drab fatigues + a holstered sidearm. NO
# helmet here — that's standoff-only kit (see build_helmet). `model_root` is the
# scaled Model holder; the sidearm is added to `body` so it sits in body space.
static func dress_military(body: Node3D, model_root: Node) -> void:
	apply_fatigues(model_root)
	if body.get_node_or_null("Sidearm") == null:
		body.add_child(build_sidearm())


# Tint a Kenney mini-char into olive-drab fatigues: keep the colormap texture (so
# the face/skin still reads) but multiply albedo toward army green.
static func apply_fatigues(model_root: Node) -> void:
	var tex: Texture2D = load(COLORMAP_PATH)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.45, 0.52, 0.32)   # olive-drab multiply
	mat.roughness = 0.85
	mat.metallic = 0.0
	var stack: Array = [model_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)


# Dark-olive combat helmet — a squashed dome on the crown. Standoff-only kit.
static func build_helmet() -> MeshInstance3D:
	var helmet: MeshInstance3D = MeshInstance3D.new()
	helmet.name = "Helmet"
	var dome: SphereMesh = SphereMesh.new()
	dome.radius = 0.34
	dome.height = 0.46
	dome.is_hemisphere = true
	helmet.mesh = dome
	helmet.position = Vector3(0.0, 1.62, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.24, 0.16)   # dark olive
	mat.roughness = 0.7
	mat.metallic = 0.0
	helmet.material_override = mat
	return helmet


# Procedural sidearm on a pivot at the right hand. Starts barrel-down (holstered);
# the standoff raises it level (barrel along body-forward) on Greer's cue.
static func build_sidearm() -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = "Sidearm"
	pivot.position = Vector3(0.40, 1.28, 0.30)   # right hand, chest/aim height
	pivot.rotation.x = -PI * 0.5                  # barrel points down (holstered)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	mat.metallic = 0.6
	mat.roughness = 0.45
	var slide: MeshInstance3D = MeshInstance3D.new()
	var smesh: BoxMesh = BoxMesh.new()
	smesh.size = Vector3(0.11, 0.14, 0.54)        # barrel/slide along -Z (body-forward)
	slide.mesh = smesh
	slide.material_override = mat
	slide.position = Vector3(0.0, 0.0, -0.22)
	pivot.add_child(slide)
	var grip: MeshInstance3D = MeshInstance3D.new()
	var gmesh: BoxMesh = BoxMesh.new()
	gmesh.size = Vector3(0.08, 0.24, 0.11)
	grip.mesh = gmesh
	grip.material_override = mat
	grip.position = Vector3(0.0, -0.16, 0.06)
	pivot.add_child(grip)
	return pivot
