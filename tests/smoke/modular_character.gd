extends SceneTree

# Smoke test for the Quaternius ModularCharacter pipeline (WoW-style slots).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/modular_character.gd
#
# Asserts:
#   1. Base imports humanoid-renamed; both genders build.
#   2. Body splitting: FullBody hidden, five BaseRegion_* meshes exist, all
#      visible when naked.
#   3. Equipment: set_slot equips part meshes onto the skeleton AND hides the
#      covered region (the anti-clipping fix); clearing restores the region;
#      mixed outfits occupy multiple slots; equipped() reports.
#   4. parts_for_slot scans per gender; hair slot lists rigged hairstyles.
#   5. Rifle: aimed = RightHand mount with corrected rotation (Rx -90);
#      slung = Chest mount; set_rifle(false) removes.
#   6. Animation: shared crew_body library loads (16 clips); play_clip works.

const ModularScript: Script = preload("res://scripts/modular_character.gd")

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== modular_character smoke test ===")
	call_deferred("_run")


func _run() -> void:
	_test_base_and_regions()
	_test_equipment_slots()
	_test_part_scan()
	_test_rifle_mounts()
	_test_animation()
	_report()


func _make(gender: String = "Male") -> Node3D:
	var c: Node3D = ModularScript.create(gender)
	root.add_child(c)
	return c


func _regions(c: Node3D) -> Dictionary:
	var out: Dictionary = {}
	var skel: Skeleton3D = c.call("skeleton")
	for n in skel.get_children():
		if String(n.name).begins_with("BaseRegion_"):
			out[String(n.name).replace("BaseRegion_", "")] = n
	return out


func _test_base_and_regions() -> void:
	for gender in ["Male", "Female"]:
		var c: Node3D = _make(gender)
		var skel: Skeleton3D = c.call("skeleton")
		_expect(skel != null and skel.find_bone("Hips") >= 0,
			"%s base has humanoid skeleton" % gender)
		var regions: Dictionary = _regions(c)
		_expect(regions.size() == 5, "%s body split into 5 regions (got %d)" % [gender, regions.size()])
		var all_visible: bool = true
		for r in regions:
			if not (regions[r] as MeshInstance3D).visible:
				all_visible = false
		_expect(all_visible, "%s: all regions visible when naked" % gender)
		c.queue_free()


func _test_equipment_slots() -> void:
	var c: Node3D = _make("Male")
	var regions: Dictionary = _regions(c)

	_expect(bool(c.call("set_slot", "Body", "Male_Ranger_Body")), "equip Ranger body")
	_expect(String(c.call("equipped", "Body")) == "Male_Ranger_Body", "Body slot reports item")
	_expect(not (regions["torso"] as MeshInstance3D).visible,
		"torso region hidden under equipped Body (anti-clipping)")
	_expect((regions["legs"] as MeshInstance3D).visible, "legs region still visible")

	_expect(bool(c.call("set_slot", "Legs", "Male_Peasant_Legs")), "mixed outfit: Peasant legs")
	_expect(not (regions["legs"] as MeshInstance3D).visible, "legs region hidden too")

	var skel: Skeleton3D = c.call("skeleton")
	var part_count: int = 0
	for n in skel.get_children():
		if String(n.name).begins_with("Part_"):
			part_count += 1
	_expect(part_count >= 2, "part meshes live on the skeleton (%d)" % part_count)

	c.call("set_slot", "Body", "")
	_expect(String(c.call("equipped", "Body")) == "", "clearing Body slot unequips")
	_expect((regions["torso"] as MeshInstance3D).visible, "torso region restored on unequip")
	c.queue_free()


func _test_part_scan() -> void:
	var body_parts: Array = ModularScript.parts_for_slot("Body", "Male")
	_expect(body_parts.has("Male_Ranger_Body") and body_parts.has("Male_Peasant_Body"),
		"Body slot scan finds both outfits")
	_expect(not body_parts.has("Female_Ranger_Body"), "gender filter applies")
	var hair: Array = ModularScript.parts_for_slot("Hair", "Male")
	_expect(hair.has("Hair_Buzzed") and hair.has("Hair_Beard"), "hair slot lists rigged hairstyles")


func _test_rifle_mounts() -> void:
	var c: Node3D = _make("Male")
	var skel: Skeleton3D = c.call("skeleton")

	c.call("set_rifle", true, true)
	var hand: BoneAttachment3D = skel.get_node_or_null("RifleHand")
	_expect(hand != null and hand.bone_name == "RightHand", "aimed rifle on the RightHand bone")
	if hand != null and hand.get_child_count() > 0:
		var rifle: Node3D = hand.get_child(0)
		_expect(absf(rifle.rotation.x + 1.57) < 0.01,
			"aimed rifle uses corrected Rx(-90) (was mounted backwards)")

	c.call("set_rifle", true, false)
	_expect(skel.get_node_or_null("RifleHand") == null, "re-mount removes the hand rifle")
	var back: BoneAttachment3D = skel.get_node_or_null("RifleBack")
	_expect(back != null and back.bone_name == "Chest", "slung rifle on the Chest bone")

	c.call("set_rifle", false)
	_expect(skel.get_node_or_null("RifleBack") == null, "set_rifle(false) removes the rifle")
	c.queue_free()


func _test_animation() -> void:
	var c: Node3D = _make("Male")
	var clips: PackedStringArray = c.call("clip_names")
	_expect(clips.size() >= 41, "shared crew library on Quaternius rig (41+ clips, got %d)" % clips.size())
	c.call("play_clip", "walk")
	var ap: AnimationPlayer = _find_anim(c)
	_expect(ap != null and ap.current_animation == "body/walk",
		"play_clip drives the shared Mixamo library")
	c.queue_free()


func _find_anim(node: Node) -> AnimationPlayer:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("---")
	print("%d passed, %d failed" % [_passes, _failures.size()])
	print("RESULT: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
