extends RefCounted
class_name VrmGearLibrary

# WoW-style gear item registry for VRoid characters.
#
# Every VRoid export is built on the same standard base body, so any garment
# authored on ANY character fits every other one: VRoid Studio is the gear
# authoring tool. Items are harvested at runtime from "donor" VRMs by surface
# material name — VRoid names materials by garment class
# (..._Tops_..._CLOTH, ..._Bottoms_..., ..._Shoes_..., ..._Onepiece_...),
# so a slot is just a set of material-name keywords.
#
# Two item kinds:
#   - mesh items: skinned garment surfaces extracted from a donor VRM's Body
#     mesh (Skin binds are name-based humanoid bones -> they bind to any crew
#     skeleton and follow animation automatically)
#   - rigid items: procedural/GLB props on BoneAttachment3D snap points
#     (helmet, rifle, sidearm) — handled by VrmCharacter.attach_gear
#
# To add gear: dress a throwaway character in VRoid Studio, export
# models/vrm/outfits/<name>.vrm, add an ITEMS entry. No other wiring.
#
# Preload as a const Script and call statics — class_name lookup can lag in
# headless `-s` runs.

# Mesh slots -> the VRoid material keywords that slot occupies on a body.
const SLOT_KEYWORDS: Dictionary = {
	"chest": ["Tops", "Onepiece"],
	"legs": ["Bottoms"],
	"feet": ["Shoes"],
}

# item id -> definition.
#   mesh item: {"slot": chest|legs|feet, "donor": vrm path, "match": [keywords]}
#   rigid item: {"slot": head_wear|weapon|sidearm, "rigid": gear id}
const ITEMS: Dictionary = {
	# -- harvested from the crew VRMs themselves --
	"tee_red":        {"slot": "chest", "donor": "res://models/vrm/eli.vrm", "match": ["Tops"]},
	"jeans":          {"slot": "legs", "donor": "res://models/vrm/eli.vrm", "match": ["Bottoms"]},
	"sneakers":       {"slot": "feet", "donor": "res://models/vrm/eli.vrm", "match": ["Shoes"]},
	"tactical_top":   {"slot": "chest", "donor": "res://models/vrm/scott.vrm", "match": ["Tops", "Onepiece"]},
	"tactical_boots": {"slot": "feet", "donor": "res://models/vrm/scott.vrm", "match": ["Shoes"]},
	# -- rigid props on bone snap points --
	"helmet":  {"slot": "head_wear", "rigid": "helmet"},
	"rifle":   {"slot": "weapon", "rigid": "rifle"},
	"sidearm": {"slot": "sidearm", "rigid": "sidearm"},
}

# item id -> {"mesh": ArrayMesh, "skin": Skin}; donors instanced once.
static var _piece_cache: Dictionary = {}


static func item_def(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


static func is_rigid(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).has("rigid")


static func items_for_slot(slot: String) -> Array:
	var out: Array = []
	for id in ITEMS:
		if String(ITEMS[id]["slot"]) == slot:
			out.append(id)
	return out


# Extract (and cache) a mesh item's garment surfaces + skin from its donor VRM.
# Returns {} for unknown/rigid items or extraction failure.
static func piece(item_id: String) -> Dictionary:
	if _piece_cache.has(item_id):
		return _piece_cache[item_id]
	var def: Dictionary = ITEMS.get(item_id, {})
	if def.is_empty() or def.has("rigid"):
		return {}
	var packed: PackedScene = load(String(def["donor"]))
	if packed == null:
		return {}
	var donor: Node = packed.instantiate()
	var body: MeshInstance3D = _find_body(donor)
	var out: Dictionary = {}
	if body != null and body.mesh != null:
		var mesh: ArrayMesh = filtered_mesh(body.mesh, def["match"], false)
		if mesh.get_surface_count() > 0:
			out = {"mesh": mesh, "skin": body.skin}
	donor.free()
	_piece_cache[item_id] = out
	return out


static func _find_body(node: Node) -> MeshInstance3D:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.name == "Body":
			return n
		for c in n.get_children():
			stack.append(c)
	return null


# New ArrayMesh keeping only surfaces whose material name contains any keyword
# (exclude=true inverts: keep everything EXCEPT matches). Garment surfaces
# carry no blend shapes in VRoid exports, so plain array copies suffice.
static func filtered_mesh(src: Mesh, keywords: Array, exclude: bool) -> ArrayMesh:
	var out: ArrayMesh = ArrayMesh.new()
	for s in range(src.get_surface_count()):
		var mat: Material = src.surface_get_material(s)
		var mat_name: String = mat.resource_name if mat != null else ""
		var hit: bool = false
		for k in keywords:
			if mat_name.contains(String(k)):
				hit = true
		if hit == exclude:
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (src as ArrayMesh).surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
