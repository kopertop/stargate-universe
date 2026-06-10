extends SceneTree

# Smoke test for the VRM character pipeline (VrmCharacter + godot-vrm import
# + retargeted Mixamo AnimationLibrary).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/vrm_character.gd
#
# Asserts:
#   1. Imported VRMs load; humanoid skeleton present with finger bones.
#   2. Shared body library loads with all 15 clips; tracks address
#      %GeneralSkeleton humanoid bones; loop flags correct.
#   3. play_clip plays body/walk on a VRM's own AnimationPlayer.
#   4. Expression clips imported (emotions, visemes, blink, look*);
#      mixing channels writes blend-shape values; accumulation caps at 1;
#      clearing resets the face.
#   5. Gear snaps to humanoid bones: rifle->Chest (back), aimed->RightHand,
#      helmet->Head, sidearm->Hips; idempotent; removal works.

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== vrm_character smoke test ===")
	call_deferred("_run")


func _run() -> void:
	_test_models_and_skeletons()
	_test_body_library()
	_test_expressions()
	_test_gear_snapping()
	_report()


func _make(vrm: String) -> Node3D:
	var c: Node3D = VrmCharacterScript.create("res://models/vrm/%s.vrm" % vrm, vrm)
	c.set("auto_blink", false)   # no frame loop in headless tests
	root.add_child(c)
	return c


func _test_models_and_skeletons() -> void:
	for stem in ["eli", "scott"]:
		var c: Node3D = _make(stem)
		var skel: Skeleton3D = c.call("skeleton")
		_expect(skel != null, "%s: humanoid skeleton found" % stem)
		if skel != null:
			_expect(skel.find_bone("Hips") >= 0 and skel.find_bone("Head") >= 0,
				"%s: core humanoid bones present" % stem)
			_expect(skel.find_bone("RightIndexProximal") >= 0,
				"%s: finger bones present (full hand rig)" % stem)
		c.queue_free()


func _test_body_library() -> void:
	var lib: AnimationLibrary = load("res://models/vrm/anim/crew_body.res")
	_expect(lib != null, "crew_body.res loads")
	if lib == null:
		return
	var clips: PackedStringArray = lib.get_animation_list()
	_expect(clips.size() == 15, "library has 15 clips (got %d)" % clips.size())
	for required in ["idle", "walk", "run", "rifle_walk", "rifle_draw", "death", "wave", "argue"]:
		_expect(lib.has_animation(required), "library has '%s'" % required)
	var walk: Animation = lib.get_animation("walk")
	_expect(walk.loop_mode == Animation.LOOP_LINEAR, "walk loops")
	_expect(lib.get_animation("death").loop_mode == Animation.LOOP_NONE, "death does not loop")
	var found_humanoid: bool = false
	for t in range(walk.get_track_count()):
		if String(walk.track_get_path(t)).begins_with("%GeneralSkeleton:Hips"):
			found_humanoid = true
	_expect(found_humanoid, "walk tracks address %GeneralSkeleton humanoid bones")

	var c: Node3D = _make("eli")
	c.call("play_clip", "walk")
	var ap: AnimationPlayer = c.get_node_or_null("eli/AnimationPlayer")
	_expect(ap != null and ap.current_animation == "body/walk",
		"play_clip('walk') plays body/walk (got '%s')" % (ap.current_animation if ap != null else "null"))
	c.queue_free()


func _test_expressions() -> void:
	var c: Node3D = _make("eli")
	var exprs: Array = c.call("expression_names")
	for required in ["happy", "angry", "sad", "blink", "aa", "ou", "lookLeft", "lookUp"]:
		_expect(exprs.has(required), "expression '%s' imported" % required)

	# Mixing: happy at full weight must move at least one blend shape.
	c.call("set_emotion", "happy", 1.0)
	c.call("_mix_face")
	_expect(_max_blendshape(c) > 0.1, "set_emotion(happy) drives blend shapes (max %.2f)" % _max_blendshape(c))

	# Blink on top accumulates without exceeding 1.
	c.call("set_blink", 1.0)
	c.call("_mix_face")
	_expect(_max_blendshape(c) <= 1.0, "channel accumulation caps at 1.0")

	c.call("clear_expressions")
	c.call("_mix_face")
	_expect(_max_blendshape(c) < 0.001, "clear_expressions resets the face")

	# Gaze channel routes to look* clips.
	c.call("set_gaze", -0.7, 0.0)
	var channels: Dictionary = c.get("_channels")
	_expect(String(channels["gaze_h"]["expr"]) == "lookLeft", "negative horizontal gaze -> lookLeft")
	c.queue_free()


func _test_gear_snapping() -> void:
	var c: Node3D = _make("scott")
	var skel: Skeleton3D = c.call("skeleton")

	c.call("attach_gear", "rifle", false)
	_expect(_mount_bone(skel, "Rifle") == "Chest", "stowed rifle snaps to Chest (back)")
	c.call("attach_gear", "rifle", true)
	_expect(_mount_bone(skel, "Rifle") == "RightHand", "aimed rifle snaps to RightHand")
	c.call("attach_gear", "helmet", false)
	_expect(_mount_bone(skel, "Helmet") == "Head", "helmet snaps to Head")
	c.call("attach_gear", "sidearm", false)
	_expect(_mount_bone(skel, "Sidearm") == "Hips", "sidearm holsters on Hips")

	var h1: Node3D = c.call("attach_gear", "helmet", false)
	var h2: Node3D = c.call("attach_gear", "helmet", false)
	_expect(h1 == h2, "attach_gear is idempotent")
	c.call("remove_gear", "rifle")
	_expect(not bool(c.call("has_gear", "rifle")), "remove_gear detaches the rifle")
	c.queue_free()


func _mount_bone(skel: Skeleton3D, node_name: String) -> String:
	if skel == null:
		return ""
	for ba in skel.get_children():
		if ba is BoneAttachment3D and ba.get_node_or_null(node_name) != null:
			return (ba as BoneAttachment3D).bone_name
	return ""


func _max_blendshape(c: Node3D) -> float:
	var top: float = 0.0
	for mesh in c.get("_face_meshes"):
		var mi: MeshInstance3D = mesh
		for i in range((mi.mesh as ArrayMesh).get_blend_shape_count()):
			top = maxf(top, mi.get_blend_shape_value(i))
	return top


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
