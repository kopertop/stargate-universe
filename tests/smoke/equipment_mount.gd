extends SceneTree

# Smoke test for the character equipment mount (#72).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/equipment_mount.gd
#
# Builds a character model + an EquipmentMount node wired to the live Inventory
# autoload, drives the loadout through Inventory.equip/unequip, and asserts that
# gear nodes appear under the right skeleton sockets, swap cleanly with no
# duplicates, and disappear on unequip. Also covers the Step-0 skeleton finding,
# colormap application, and headless / no-model graceful no-op.
#
# Uses the live Inventory autoload like inventory.gd / e1_flow.gd. Duck-types the
# mount via load() (a freshly-added class_name may parse-error in the same run).

const MOUNT_SCRIPT_PATH: String = "res://scripts/equipment_mount.gd"
const CHARACTER_SCENE: String = "res://objects/character.tscn"

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== equipment_mount smoke test ===")

	var inv: Node = root.get_node_or_null("Inventory")
	_expect(inv != null, "Inventory autoload attached")
	if inv == null:
		_report()
		return
	inv.call("reset")

	# --- Step 0: skeleton finding ------------------------------------------
	var model: Node3D = (load(CHARACTER_SCENE) as PackedScene).instantiate()
	root.add_child(model)
	var skel: Skeleton3D = _find_skeleton(model)
	_expect(skel != null, "character model exposes a Skeleton3D (Step 0)")
	if skel != null:
		var names: Array[String] = []
		for i in range(skel.get_bone_count()):
			names.append(skel.get_bone_name(i))
		_expect(names.has("head"), "skeleton has a 'head' bone")
		_expect(names.has("torso"), "skeleton has a 'torso' bone")

	# --- build the mount, wired to the live Inventory ----------------------
	var MountScript: Script = load(MOUNT_SCRIPT_PATH)
	_expect(MountScript != null, "equipment_mount.gd loads")
	var mount: Node3D = MountScript.new()
	mount.name = "EquipmentMount"
	mount.call("setup", model, inv)
	model.add_child(mount)   # in real play _ready fires here; headless defers it
	# Headless: no frame has ticked so _ready did not run (SceneTree-script
	# gotcha). reconcile() self-heals — resolves the skeleton + wires the
	# equipment_changed signal — so subsequent equip/unequip drive the mount.
	mount.call("reconcile")

	_expect(_gear_count(mount) == 0, "no gear mounted with an empty loadout")

	# --- equip head: gear appears under a head socket ----------------------
	inv.call("add_item", "marine_helmet", 1, "test")
	_expect(bool(inv.call("equip", "marine_helmet")), "equip marine_helmet (head)")
	var head_gear: Node = _gear_for_item(mount, "marine_helmet")
	_expect(head_gear != null, "equipping marine_helmet mounts a gear node")
	_expect(_gear_count(mount) == 1, "exactly one gear node after equipping one item")
	if head_gear != null:
		_expect(_attach_bone(head_gear) == "head", "head gear is parented to the 'head' bone socket")
		_expect(_has_colormap(head_gear), "gear has the colormap material applied (not white)")

	# --- equip a second slot: independent, no duplicates -------------------
	inv.call("add_item", "combat_boots", 1, "test")
	_expect(bool(inv.call("equip", "combat_boots")), "equip combat_boots (legs)")
	_expect(_gear_count(mount) == 2, "two gear nodes for a two-slot loadout")
	_expect(_gear_for_item(mount, "marine_helmet") != null, "head gear still present after equipping legs")
	var legs_gear: Node = _gear_for_item(mount, "combat_boots")
	_expect(legs_gear != null, "legs gear mounted")
	if legs_gear != null:
		# legs falls back to the 'root' bone (no Hips on the Kenney rig).
		_expect(_attach_bone(legs_gear) == "root", "legs gear binds to the 'root' bone (Hips fallback)")

	# --- swap the head slot: replaces, never stacks ------------------------
	inv.call("add_item", "recon_cap", 1, "test")
	_expect(bool(inv.call("equip", "recon_cap")), "equip recon_cap into the occupied head slot")
	_expect(_gear_for_item(mount, "marine_helmet") == null, "swapped-out marine_helmet gear removed")
	_expect(_gear_for_item(mount, "recon_cap") != null, "swapped-in recon_cap gear mounted")
	_expect(_gear_count(mount) == 2, "swap keeps the gear count at 2 (no duplicate head gear)")

	# --- idempotent reconcile: re-running never stacks ---------------------
	mount.call("reconcile")
	mount.call("reconcile")
	_expect(_gear_count(mount) == 2, "repeated reconcile() does not duplicate gear")

	# --- unequip: gear disappears ------------------------------------------
	inv.call("unequip", "head")
	_expect(_gear_for_item(mount, "recon_cap") == null, "unequipping head removes its gear")
	_expect(_gear_count(mount) == 1, "one gear node left after unequipping head")
	inv.call("unequip", "legs")
	_expect(_gear_count(mount) == 0, "unequipping all slots leaves no gear")

	# --- back slot uses the torso bone (no Spine on the rig) ---------------
	inv.call("add_item", "field_backpack", 1, "test")
	_expect(bool(inv.call("equip", "field_backpack")), "equip field_backpack (back)")
	var back_gear: Node = _gear_for_item(mount, "field_backpack")
	_expect(back_gear != null, "back gear mounted")
	if back_gear != null:
		_expect(_attach_bone(back_gear) == "torso", "back gear binds to the 'torso' bone (Spine fallback)")

	# --- headless / no-model graceful no-op --------------------------------
	var orphan: Node3D = MountScript.new()
	orphan.call("setup", null, inv)
	# reconcile with no model must not crash and must mount nothing.
	orphan.call("reconcile")
	_expect(_gear_count(orphan) == 0, "mount with no model no-ops gracefully (no gear, no crash)")
	orphan.free()

	model.queue_free()
	_report()


# --- helpers -----------------------------------------------------------------

# Count mounted gear nodes across all sockets (BoneAttachment3D + fallback Node3D
# children that carry the equip_item_id meta).
func _gear_count(mount: Node) -> int:
	var n: int = 0
	for g in _all_gear(mount):
		n += 1
	return n


func _all_gear(mount: Node) -> Array:
	var out: Array = []
	var stack: Array = [mount]
	# The mount parents gear under sockets it creates on the skeleton (outside
	# the mount node's own subtree) AND under fallback offset nodes on the model.
	# Walk the whole model subtree from the mount's parent to find every gear.
	var search_root: Node = mount.get_parent() if mount.get_parent() != null else mount
	stack = [search_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("equip_item_id"):
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


func _gear_for_item(mount: Node, item_id: String) -> Node:
	for g in _all_gear(mount):
		if String((g as Node).get_meta("equip_item_id", "")) == item_id:
			return g
	return null


# The bone name a gear node is attached to (via its BoneAttachment3D parent), or
# "" if it sits on a fallback offset node.
func _attach_bone(gear: Node) -> String:
	var parent: Node = gear.get_parent()
	if parent is BoneAttachment3D:
		return (parent as BoneAttachment3D).bone_name
	return ""


func _has_colormap(gear: Node) -> bool:
	var stack: Array = [gear]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).material_override != null:
			return true
		for c in node.get_children():
			stack.append(c)
	return false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found: Skeleton3D = _find_skeleton(c)
		if found != null:
			return found
	return null


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
