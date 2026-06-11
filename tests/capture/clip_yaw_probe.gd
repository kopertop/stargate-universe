extends SceneTree

# Numeric probe: does a clip carry a BAKED HIPS YAW? Compares the hips'
# global forward between "idle" and each candidate clip on a node with
# rotation 0 — a big delta means the ANIMATION rotates the visual body away
# from the node's facing (the "aims 90 degrees off" bug class).
#   godot --headless --quit-after 300 -s res://tests/capture/clip_yaw_probe.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")
const CLIPS: Array = ["idle", "rifle_aim", "rifle_walk", "rifle_run_aim", "pistol_aim", "argue", "walk"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var c: Node3D = ModularScript.create("Male")
	root.add_child(c)
	var skel: Skeleton3D = c.call("skeleton")
	var hips: int = skel.find_bone("Hips")
	var base_yaw: float = 0.0
	for clip in CLIPS:
		c.call("freeze_clip_at", String(clip), 0.5)
		# Force the skeleton to apply the pose this frame.
		await process_frame
		await process_frame
		var fwd: Vector3 = -skel.get_bone_global_pose(hips).basis.z
		var yaw: float = rad_to_deg(atan2(-fwd.x, -fwd.z))
		if String(clip) == "idle":
			base_yaw = yaw
		print("[yaw] %-14s hips_yaw=%7.1f  delta_vs_idle=%7.1f" % [clip, yaw, yaw - base_yaw])
	quit()
