extends SceneTree

# Build the shared crew AnimationLibrary from retargeted Mixamo imports.
# Each imported FBX (with humanoid BoneMap) carries a 'mixamo_com' clip whose
# tracks address %GeneralSkeleton:<HumanoidBone> — playable on ANY VRM
# character. This collects them under friendly names, sets loop flags, and
# saves res://models/vrm/anim/crew_body.res.
#   godot --headless --quit-after 240 -s res://tools/extract_anim_library.gd

# friendly name -> [fbx stem, loops]
const MANIFEST: Dictionary = {
	"idle": ["standingidle", true],
	"walk": ["walking", true],
	"run": ["runningfast", true],
	"idle_happy": ["happy-idle", true],
	"idle_sad": ["sad-idle", true],
	"wave": ["ajwavinggesture", false],
	"nod": ["hardheadnodyes", false],
	"point": ["pointingwitharmbent", false],
	"argue": ["standingarguingwithanotherperson", true],
	"rifle_walk": ["riflewalkforward", true],
	"rifle_run": ["runningwithrifledown", true],
	"rifle_run_aim": ["runningwithrifleaimed", true],
	"rifle_draw": ["standingtoreadyposegrabbingriflefromtheback", false],
	"rifle_fire_walk": ["firingwhilewalkingwithrifle", true],
	"death": ["deathfromstandingidle", false],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lib: AnimationLibrary = AnimationLibrary.new()
	var ok: int = 0
	for clip_name in MANIFEST:
		var stem: String = MANIFEST[clip_name][0]
		var loops: bool = MANIFEST[clip_name][1]
		var packed: PackedScene = load("res://models/vrm/anim_src/%s.fbx" % stem)
		if packed == null:
			print("[extract] MISSING %s.fbx" % stem)
			continue
		var inst: Node = packed.instantiate()
		var ap: AnimationPlayer = _find_anim(inst)
		if ap == null or not ap.has_animation("mixamo_com"):
			print("[extract] no mixamo_com clip in %s" % stem)
			inst.free()
			continue
		var anim: Animation = ap.get_animation("mixamo_com").duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		lib.add_animation(clip_name, anim)
		ok += 1
		print("[extract] %s <- %s (%.2fs, %d tracks, loop=%s)" % [
			clip_name, stem, anim.length, anim.get_track_count(), loops])
		inst.free()
	var err: int = ResourceSaver.save(lib, "res://models/vrm/anim/crew_body.res")
	print("[extract] saved crew_body.res with %d clips (err=%d)" % [ok, err])
	quit(0 if (err == OK and ok == MANIFEST.size()) else 1)


func _find_anim(node: Node) -> AnimationPlayer:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
