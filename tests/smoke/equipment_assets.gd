extends SceneTree

# Asset-validation smoke test for the first equipment gear set (#73).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/equipment_assets.gd
#
# Proves the issue's acceptance criteria for the art/content track:
#   1. Every `equipment`-category item in data/items.json carries slot + model +
#      icon (registered correctly).
#   2. Each model GLB exists, imports, and instantiates to a Node3D that contains
#      real mesh geometry (a non-empty AABB) — i.e. not a stub.
#   3. Each icon PNG exists and loads as a Texture2D with non-zero dimensions.
#   4. Every first-pass slot (head, torso, back, legs) is covered by at least one
#      registered item, and the gear is sized to the mini-char (model fits inside
#      a small bounding box so it reads on the ~0.37u-tall rig).
#
# Reads items.json directly (no Inventory autoload needed) so it stays a pure
# content check. Duck-types nothing — just JSON + ResourceLoader.

const ITEMS_PATH: String = "res://data/items.json"

# The first-pass slots the issue requires coverage for.
const REQUIRED_SLOTS: Array[String] = ["head", "torso", "back", "legs"]

# Gear is authored in bone-local space on a ~0.37u-tall rig; a single piece must
# fit comfortably within this box or it will visibly clip/oversize on the char.
const MAX_GEAR_EXTENT: float = 0.6

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== equipment_assets smoke test ===")

	var items: Array = _load_items()
	_expect(not items.is_empty(), "data/items.json parses to a non-empty array")
	if items.is_empty():
		_report()
		return

	var covered_slots: Dictionary = {}
	var equipment_count: int = 0

	for entry in items:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = entry
		if String(def.get("category", "")) != "equipment":
			continue
		equipment_count += 1
		var id: String = String(def.get("id", "?"))

		# --- 1. registration: slot + model + icon present --------------------
		var slot: String = String(def.get("slot", ""))
		var model_path: String = String(def.get("model", ""))
		var icon_path: String = String(def.get("icon", ""))
		_expect(slot != "", "%s registers a slot" % id)
		_expect(model_path != "", "%s registers a model path" % id)
		_expect(icon_path != "", "%s registers an icon path" % id)
		if slot != "":
			covered_slots[slot] = true

		# --- 2. model GLB exists, imports, has mesh geometry -----------------
		if model_path != "":
			_expect(ResourceLoader.exists(model_path), "%s model imports cleanly (%s)" % [id, model_path])
			var packed: PackedScene = load(model_path) as PackedScene
			_expect(packed != null, "%s model loads as a PackedScene" % id)
			if packed != null:
				var inst: Node = packed.instantiate()
				var node3d: Node3D = inst as Node3D
				_expect(node3d != null, "%s model instantiates to a Node3D" % id)
				if node3d != null:
					var aabb: AABB = _merged_aabb(node3d)
					var has_geo: bool = aabb.size.length() > 0.0001
					_expect(has_geo, "%s model contains mesh geometry (non-empty AABB)" % id)
					var fits: bool = aabb.size.x <= MAX_GEAR_EXTENT \
						and aabb.size.y <= MAX_GEAR_EXTENT \
						and aabb.size.z <= MAX_GEAR_EXTENT
					_expect(fits, "%s gear is mini-char scale (<= %0.2fu) got %s" % [id, MAX_GEAR_EXTENT, str(aabb.size)])
				inst.queue_free()

		# --- 3. icon PNG exists and loads ------------------------------------
		if icon_path != "":
			_expect(ResourceLoader.exists(icon_path), "%s icon imports cleanly (%s)" % [id, icon_path])
			var tex: Texture2D = load(icon_path) as Texture2D
			_expect(tex != null, "%s icon loads as a Texture2D" % id)
			if tex != null:
				_expect(tex.get_width() > 0 and tex.get_height() > 0, "%s icon has non-zero dimensions" % id)

	# --- 4. all four first-pass slots covered --------------------------------
	_expect(equipment_count >= 4, "at least four equipment items registered (got %d)" % equipment_count)
	for s in REQUIRED_SLOTS:
		_expect(covered_slots.has(s), "slot '%s' has at least one registered item" % s)

	_report()


# --- helpers -----------------------------------------------------------------

func _load_items() -> Array:
	if not FileAccess.file_exists(ITEMS_PATH):
		return []
	var f: FileAccess = FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		return []
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	return []


# Merge the AABBs of every VisualInstance3D in the subtree, in the root's local
# space, so we measure the gear's true authored extent.
func _merged_aabb(root: Node3D) -> AABB:
	var out: AABB = AABB()
	var have: bool = false
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is VisualInstance3D:
			var vi: VisualInstance3D = node
			var local: AABB = vi.get_aabb()
			# Transform the local AABB into root space via the node's transform
			# relative to root (kept simple: gear hierarchies are shallow).
			var xf: Transform3D = vi.transform
			var p: Node = vi.get_parent()
			while p != null and p != root:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var world_aabb: AABB = xf * local
			if not have:
				out = world_aabb
				have = true
			else:
				out = out.merge(world_aabb)
		for c in node.get_children():
			stack.append(c)
	return out


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
