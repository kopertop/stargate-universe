extends SceneTree

# Smoke test for the equipment system (issue #75).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/equipment_system.gd
#
# Asserts (acceptance criteria):
#   • EquipmentSystem.equip/unequip work for all 5 slots.
#   • Stat modifiers are applied additively on equip and removed on unequip.
#   • equip_swap returns the previously-equipped item id.
#   • Socket attachment: gear nodes appear under the right bone socket (head
#     → Head, vest → Spine/torso fallback, boots → Hips/root fallback).
#   • unequip_all clears every slot.
#   • Save round-trip preserves the loadout.
#   • PASS count is asserted at the end.

const EQUIP_SYSTEM_PATH: String = "res://scripts/equipment_system.gd"
const EQUIP_SOCKET_PATH: String = "res://scripts/equipment_socket.gd"
const EQUIP_DEFS_PATH: String = "res://scripts/data/equipment.gd"
const CHARACTER_SCENE: String = "res://objects/character.tscn"

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== equipment system smoke test (issues #72-75, #32) ===")

	# --- 0. Load scripts ---------------------------------------------------
	var SysScript: Script = load(EQUIP_SYSTEM_PATH)
	_expect(SysScript != null, "equipment_system.gd loads")
	var SocketScript: Script = load(EQUIP_SOCKET_PATH)
	_expect(SocketScript != null, "equipment_socket.gd loads")
	var DefsScript: Script = load(EQUIP_DEFS_PATH)
	_expect(DefsScript != null, "data/equipment.gd loads")
	if SysScript == null or SocketScript == null or DefsScript == null:
		_report()
		return

	var defs: RefCounted = DefsScript.new()
	_expect(defs.call("all").size() >= 6, "EquipmentDefs has at least 6 gear pieces")
	_expect(defs.call("by_id", "standard_helmet").get("slot", "") == "helmet",
		"standard_helmet def has slot == helmet")
	_expect(defs.call("by_id", "tactical_vest").get("slot", "") == "vest",
		"tactical_vest def has slot == vest")
	_expect(defs.call("by_id", "field_backpack").get("slot", "") == "backpack",
		"field_backpack def has slot == backpack")
	_expect(defs.call("by_id", "fatigue_pants").get("slot", "") == "pants",
		"fatigue_pants def has slot == pants")
	_expect(defs.call("by_id", "combat_boots").get("slot", "") == "boots",
		"combat_boots def has slot == boots")

	# --- 1. Equip / unequip + stat modifiers (no 3D model, headless) -------
	var sys: Node = SysScript.new()
	root.add_child(sys)
	sys.call("_ready")

	# Base stats: max_health = 100, armor = 0
	_expect(float(sys.call("stat", "max_health")) == 100.0,
		"base max_health == 100")
	_expect(float(sys.call("stat", "armor")) == 0.0,
		"base armor == 0")

	# Equip standard_helmet: +10 health, +5 armor
	_expect(sys.call("equip", "standard_helmet") == true,
		"equip standard_helmet succeeds")
	_expect(sys.call("equipped_in", "helmet") == "standard_helmet",
		"helmet slot has standard_helmet")
	_expect(float(sys.call("stat", "max_health")) == 110.0,
		"after helmet: max_health == 110 (100 + 10)")
	_expect(float(sys.call("stat", "armor")) == 5.0,
		"after helmet: armor == 5")

	# Equip tactical_vest: +20 health, +15 armor, +4 carry
	_expect(sys.call("equip", "tactical_vest") == true,
		"equip tactical_vest succeeds")
	_expect(float(sys.call("stat", "max_health")) == 130.0,
		"after vest: max_health == 130 (110 + 20)")
	_expect(float(sys.call("stat", "armor")) == 20.0,
		"after vest: armor == 20 (5 + 15)")
	_expect(float(sys.call("stat", "carry_capacity")) == 14.0,
		"after vest: carry_capacity == 14 (10 + 4)")

	# Equip field_backpack: +8 carry, +10 oxygen
	_expect(sys.call("equip", "field_backpack") == true,
		"equip field_backpack succeeds")
	_expect(float(sys.call("stat", "carry_capacity")) == 22.0,
		"after backpack: carry_capacity == 22 (14 + 8)")
	_expect(float(sys.call("stat", "max_oxygen")) == 110.0,
		"after backpack: max_oxygen == 110 (100 + 10)")

	# Equip fatigue_pants: +5 armor, +0.5 move_speed
	_expect(sys.call("equip", "fatigue_pants") == true,
		"equip fatigue_pants succeeds")
	_expect(float(sys.call("stat", "armor")) == 25.0,
		"after pants: armor == 25 (20 + 5)")
	_expect(float(sys.call("stat", "move_speed")) == 8.5,
		"after pants: move_speed == 8.5 (8.0 + 0.5)")

	# Equip combat_boots: +3 armor, +0.5 move_speed, +0.1 sprint
	_expect(sys.call("equip", "combat_boots") == true,
		"equip combat_boots succeeds")
	_expect(float(sys.call("stat", "armor")) == 28.0,
		"after boots: armor == 28 (25 + 3)")
	_expect(float(sys.call("stat", "move_speed")) == 9.0,
		"after boots: move_speed == 9.0 (8.5 + 0.5)")
	_expect(is_equal_approx(float(sys.call("stat", "sprint_multiplier")), 1.8),
		"after boots: sprint_multiplier == 1.8 (1.7 + 0.1)")

	_expect(sys.call("filled_count") == 5, "all 5 slots filled")

	# --- 2. Unequip removes stat modifiers -------------------------------
	sys.call("unequip", "helmet")
	_expect(sys.call("equipped_in", "helmet") == "",
		"helmet slot empty after unequip")
	_expect(float(sys.call("stat", "max_health")) == 120.0,
		"after unequip helmet: max_health == 120 (130 - 10)")
	_expect(float(sys.call("stat", "armor")) == 23.0,
		"after unequip helmet: armor == 23 (28 - 5)")

	sys.call("unequip", "boots")
	_expect(float(sys.call("stat", "move_speed")) == 8.5,
		"after unequip boots: move_speed back to 8.5 (9.0 - 0.5)")
	_expect(float(sys.call("stat", "armor")) == 20.0,
		"after unequip boots: armor == 20 (23 - 3)")

	# --- 3. equip_swap returns previous item ------------------------------
	# Re-equip standard_helmet, then swap to recon_cap
	sys.call("equip", "standard_helmet")
	var prev: String = sys.call("equip_swap", "recon_cap")
	_expect(prev == "standard_helmet",
		"equip_swap returns previous item id (standard_helmet)")
	_expect(sys.call("equipped_in", "helmet") == "recon_cap",
		"after swap: helmet slot has recon_cap")
	_expect(float(sys.call("stat", "max_health")) == 120.0,
		"after swap to recon_cap: max_health == 120 (base 100 + vest 20, cap has no health)")
	# recon_cap: move_speed +1.0, no armor.
	_expect(float(sys.call("stat", "armor")) == 20.0,
		"after swap to recon_cap: armor == 20 (vest 15 + pants 5, cap has no armor)")

	# --- 4. unequip_all clears everything ---------------------------------
	var cleared: Dictionary = sys.call("unequip_all")
	_expect(cleared.size() == 4,
		"unequip_all cleared 4 slots (helmet was swapped, vest+backpack+pants+helmet)")
	_expect(sys.call("filled_count") == 0, "no slots filled after unequip_all")
	_expect(float(sys.call("stat", "max_health")) == 100.0,
		"after unequip_all: max_health back to base 100")
	_expect(float(sys.call("stat", "armor")) == 0.0,
		"after unequip_all: armor back to base 0")

	# --- 5. Boolean effect flags (atmosphere protection) ------------------
	sys.call("equip", "pressure_suit_helmet")
	_expect(sys.call("has_effect", "atmosphere_protection") == true,
		"pressure_suit_helmet grants atmosphere_protection")
	sys.call("unequip", "helmet")
	_expect(sys.call("has_effect", "atmosphere_protection") == false,
		"atmosphere_protection gone after unequip")

	# --- 6. Save round-trip ----------------------------------------------
	sys.call("equip", "standard_helmet")
	sys.call("equip", "tactical_vest")
	var snap: Dictionary = sys.call("serialize")
	_expect(String(snap.get("equipped", {}).get("helmet", "")) == "standard_helmet",
		"serialize captures helmet slot")
	_expect(String(snap.get("equipped", {}).get("vest", "")) == "tactical_vest",
		"serialize captures vest slot")

	sys.call("reset")
	_expect(sys.call("filled_count") == 0, "reset clears loadout")
	sys.call("deserialize", snap, 1)
	_expect(sys.call("equipped_in", "helmet") == "standard_helmet",
		"deserialize restores helmet slot")
	_expect(sys.call("equipped_in", "vest") == "tactical_vest",
		"deserialize restores vest slot")
	_expect(float(sys.call("stat", "max_health")) == 130.0,
		"after deserialize: stats recomputed (100 + 10 helmet + 20 vest = 130)")

	# --- 7. Socket attachment (3D model required) -------------------------
	var model: Node3D = null
	if ResourceLoader.exists(CHARACTER_SCENE):
		model = (load(CHARACTER_SCENE) as PackedScene).instantiate()
	if model != null:
		root.add_child(model)
		var sys2: Node = SysScript.new()
		root.add_child(sys2)
		sys2.call("setup", model)
		sys2.call("_ready")
		sys2.call("equip", "standard_helmet")
		var socket: Node3D = sys2.get("_socket")
		_expect(socket != null, "EquipmentSystem created a socket for 3D rendering")
		if socket != null:
			_expect(socket.call("has_gear", "helmet") == true,
				"socket has gear in helmet slot after equip")
			var gear: Node3D = socket.call("gear_in", "helmet")
			_expect(gear != null, "helmet gear node exists")
			if gear != null:
				var parent: Node = gear.get_parent()
				_expect(parent is BoneAttachment3D,
					"helmet gear parented to a BoneAttachment3D")
				if parent is BoneAttachment3D:
					_expect((parent as BoneAttachment3D).bone_name.to_lower() == "head",
						"helmet gear bound to the 'head' bone")
			# Equip boots → root bone fallback
			sys2.call("equip", "combat_boots")
			var boots_gear: Node3D = socket.call("gear_in", "boots")
			if boots_gear != null:
				var bp: Node = boots_gear.get_parent()
				if bp is BoneAttachment3D:
					var bone: String = (bp as BoneAttachment3D).bone_name.to_lower()
					_expect(bone == "root" or bone == "hips",
						"boots gear bound to root or hips bone (fallback)")
			# Unequip removes gear
			sys2.call("unequip", "helmet")
			_expect(socket.call("has_gear", "helmet") == false,
				"socket has no helmet gear after unequip")
			_expect(socket.call("mounted_count") == 1,
				"socket has 1 gear (boots) after unequipping helmet")
		sys2.queue_free()
		model.queue_free()
	else:
		print("  SKIP  3D socket attachment tests (character scene not found)")

	sys.queue_free()
	_report()


# --- helpers -----------------------------------------------------------------

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
	if _passes == 0:
		print("RESULT: FAIL (zero passes — harness ran no assertions)")
		quit(1)
		return
	if _failures.is_empty():
		print("PASS count asserted: %d" % _passes)
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - " + f)
		quit(1)