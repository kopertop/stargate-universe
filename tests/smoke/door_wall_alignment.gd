extends SceneTree

# Regression test: every Door interactable inside a kenney_room scene must
# sit on (or just inside) one of its room's wall planes. A door whose origin
# floats too far from the wall leaves a visible floating box where the
# doorway should read as a recessed panel (see godot-kenney-doorway-void-fix
# skill).
#
# Invariant: for a kenney_room with floor_size = Vector2i(w, d), walls sit
# at x = ±w/2 and z = ±d/2. Every Door child of that scene must have its
# origin within MAX_INSET of one of those four planes, on the interior side.
#
# Run with:
#   godot --headless --quit-after 200 -s res://tests/smoke/door_wall_alignment.gd

const MAX_INSET: float = 0.3
const OUTSIDE_EPS: float = 0.05

const SCENES: Array[String] = [
	"res://scenes/destiny_corridor.tscn",
	"res://scenes/corridor_crew.tscn",
	"res://scenes/corridor_mess.tscn",
	"res://scenes/crew_quarters.tscn",
	"res://scenes/mess_hall.tscn",
	"res://scenes/control_room.tscn",
	"res://scenes/observation_room.tscn",
	"res://scenes/eli_quarters.tscn",
	"res://scenes/hull_breach.tscn",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== door_wall_alignment smoke test ===")
	for path in SCENES:
		test_door_alignment_doors_are_within_inset_of_wall_plane(path)
	_report()


func test_door_alignment_doors_are_within_inset_of_wall_plane(path: String) -> void:
	# Arrange — load and instantiate the scene.
	var packed := load(path) as PackedScene
	if packed == null:
		_fail(path, "<scene>", "load() returned null")
		return
	var inst := packed.instantiate()
	root.add_child(inst)

	var room := inst.get_node_or_null("Room") as Node3D
	if room == null:
		_fail(path, "<scene>", "no Room node — cannot infer wall planes")
		_cleanup(inst)
		return
	var floor_size: Vector2i = room.get("floor_size")
	if floor_size == Vector2i.ZERO:
		_fail(path, "<scene>", "Room.floor_size is zero")
		_cleanup(inst)
		return

	var x_plane: float = float(floor_size.x) / 2.0
	var z_plane: float = float(floor_size.y) / 2.0

	# Act — collect every Door interactable inside the scene.
	var doors := _collect_doors(inst)
	if doors.is_empty():
		_fail(path, "<scene>", "no Door interactables found")
		_cleanup(inst)
		return

	# Assert — each door origin sits within MAX_INSET of a wall plane on
	# the interior side (negative distance = outside wall, only OUTSIDE_EPS
	# of leniency allowed there). Use local `position` because in headless
	# SceneTree scripts the tree has not ticked yet, so global_transform
	# is still zero — and every door is a direct sibling of Room under an
	# identity-transform scene root, so local == effective world here.
	for door in doors:
		var pos: Vector3 = door.position
		var insets: Array[float] = [
			x_plane - pos.x,   # +x wall: positive = inside, negative = outside
			x_plane + pos.x,   # -x wall
			z_plane - pos.z,   # +z wall
			z_plane + pos.z,   # -z wall
		]
		var best_inset: float = insets[0]
		for value in insets:
			if absf(value) < absf(best_inset):
				best_inset = value
		if best_inset >= -OUTSIDE_EPS and best_inset <= MAX_INSET:
			print("  PASS  ", path, " :: ", door.name,
				" inset=%.3fm from nearest wall (pos=%s)" % [best_inset, pos])
			_passes += 1
		else:
			_fail(path, String(door.name),
				"inset %.3fm not in [-%.2f, %.2f] for walls ±%.2f (x) / ±%.2f (z) at %s"
				% [best_inset, OUTSIDE_EPS, MAX_INSET, x_plane, z_plane, pos])

	_cleanup(inst)


func _collect_doors(root_node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in root_node.get_children():
		if child is Node3D and child.is_in_group("interactable") and String(child.name).ends_with("Door"):
			out.append(child)
	return out


func _cleanup(inst: Node) -> void:
	root.remove_child(inst)
	inst.free()


func _fail(scene: String, node_name: String, reason: String) -> void:
	print("  FAIL  ", scene, " :: ", node_name, " — ", reason)
	_failures.append("%s :: %s — %s" % [scene, node_name, reason])


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	print("fails:  ", _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
