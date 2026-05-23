extends Node3D

# Generic data-driven room scene. Reads room_id from GameState (set by the
# door that ferried us here), looks up the row via ShipLayout, and dispatches
# to RoomBuilder for floor/walls/ceiling + per-template accents.
#
# gate_room is the artisan exception: its template_id is a RoomBuilder no-op
# and gate_room.tscn is hand-authored.

const DOOR_SCENE: PackedScene = preload("res://objects/door.tscn")
const CONNECTIONS_PATH: String = "res://data/room_connections.json"
# Preload to sidestep `class_name RoomBuilder` not always being registered in
# `-s` headless runs.
const RoomBuilderRef: Script = preload("res://scripts/room_builder.gd")
const BedScript: Script = preload("res://scripts/bed.gd")
const KinoPickupScript: Script = preload("res://scripts/kino_pickup.gd")
const HullSealSwitchScript: Script = preload("res://scripts/hull_seal_switch.gd")

# Set this in the editor to preview a specific room when running the scene
# standalone (F6). At runtime, GameState.next_room_id takes precedence.
@export var room_id: String = ""

@onready var world: Node3D = $World
@onready var markers: Node3D = $Markers
@onready var player: Node3D = $Player
@onready var view: Node3D = $View

var _room_data: Dictionary = {}


func _ready() -> void:
	# Resolve which room we are. Door-set baton wins over @export.
	if GameState.next_room_id != "":
		room_id = GameState.next_room_id
		GameState.next_room_id = ""
	if room_id == "":
		push_error("room.gd: no room_id provided (GameState.next_room_id and @export both empty)")
		return

	_room_data = ShipLayout.room(room_id)
	if _room_data.is_empty():
		push_error("room.gd: ShipLayout has no row for '%s'" % room_id)
		return

	# Geometry first so doors can sit against real walls.
	RoomBuilderRef.build(world, _room_data)
	_setup_doors()
	_spawn_interactables()
	_place_player()

	# Persist for save/load — F5 reloads this scene with the same room_id.
	GameState.current_scene_path = "res://scenes/room.tscn"


# Stamp door + matching spawn Marker3D for each connection that originates at
# this room (and the reverse-edge stamp from any other room that points here).
# Reads data/room_connections.json on demand — no preload cost when running
# the gate-room scene.
func _setup_doors() -> void:
	var connections: Dictionary = _load_connections()
	if connections.is_empty():
		return
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5

	# Edges originating at THIS room — stamp doors that exit here.
	for edge: Dictionary in connections.get(room_id, []) as Array:
		_stamp_door(edge, half_x, half_z)
	# Edges where ANOTHER room points at us — flip the direction and stamp
	# matching doors on this side so the trip is two-way without requiring
	# the connection table to list every edge twice.
	for from_id: String in connections.keys():
		for edge: Dictionary in connections[from_id] as Array:
			if String(edge.get("to", "")) == room_id:
				var reverse: Dictionary = edge.duplicate()
				reverse["to"] = from_id
				reverse["dir"] = _flip_direction(String(edge.get("dir", "")))
				# Plaque on the return-side door should name the destination
				# (i.e. the room we came from), not whatever the outgoing
				# plaque said. _stamp_door auto-derives that from `to`.
				reverse.erase("plaque")
				_stamp_door(reverse, half_x, half_z)


# Stamps one door + matching arrival marker on the wall indicated by `edge.dir`.
# Spawn-key convention: target_spawn = "From" + camel(THIS room) so the
# receiving side knows which marker to use; local marker name = "From" +
# camel(OTHER room) so when the player comes BACK, they arrive at our wall.
func _stamp_door(edge: Dictionary, half_x: float, half_z: float) -> void:
	var dir: String = String(edge.get("dir", ""))
	var target_id: String = String(edge.get("to", ""))
	if target_id == "":
		return
	# Elevator pairs aren't physically adjacent — present them as a lift door on
	# the -Z wall (deterministic so the reverse edge lands on the matching wall
	# in the other elevator). Everything else follows wall-axis literally.
	if dir == "elevator":
		dir = "-z"

	var pos: Vector3 = Vector3.ZERO
	var face_yaw: float = 0.0
	match dir:
		"+x":
			pos = Vector3(half_x, 0.0, 0.0)
			face_yaw = -PI * 0.5
		"-x":
			pos = Vector3(-half_x, 0.0, 0.0)
			face_yaw = PI * 0.5
		"+z":
			pos = Vector3(0.0, 0.0, half_z)
			face_yaw = PI
		"-z":
			pos = Vector3(0.0, 0.0, -half_z)
			face_yaw = 0.0
		_:
			return

	# Spawn keys identify "who I came from" — symmetric across both ends.
	var outgoing_spawn: String = "From" + _to_camel(room_id)
	var local_marker_name: String = "From" + _to_camel(target_id)
	var plaque: String = String(edge.get("plaque", _humanize(target_id)))

	var door: Node = DOOR_SCENE.instantiate()
	door.position = pos
	door.rotation.y = face_yaw
	door.set("target_room_id", target_id)
	door.set("target_spawn", outgoing_spawn)
	door.set("plaque_label", plaque)
	door.set("open_prompt", "Step through to %s" % plaque)
	door.set("transition_prompt", "Step through to %s" % plaque)
	door.add_to_group("interactable")
	add_child(door)

	# Arrival marker: place 1.2 m into the room from the door so SceneRouter
	# can land the player clear of the doorway when they return.
	var marker: Marker3D = Marker3D.new()
	marker.name = local_marker_name
	var inset: float = 1.2
	var inset_pos: Vector3 = pos
	match dir:
		"+x": inset_pos.x -= inset
		"-x": inset_pos.x += inset
		"+z": inset_pos.z -= inset
		"-z": inset_pos.z += inset
	inset_pos.y = 0.0
	marker.position = inset_pos
	marker.rotation.y = face_yaw + PI
	markers.add_child(marker)


func _place_player() -> void:
	# Save-restored spawn wins. SceneRouter handles marker-by-name placement
	# AFTER _ready() returns (it walks the tree looking for the spawn key it
	# was passed), so we only set a sensible default here.
	if GameState.pending_spawn_position != null:
		player.global_position = GameState.pending_spawn_position
		player.rotation.y = GameState.pending_spawn_yaw
		GameState.pending_spawn_position = null
		if view.has_method("snap_to_target"):
			view.snap_to_target()
		return

	# Default: room centre, looking +Z. SceneRouter will overwrite this if a
	# matching Marker3D was found.
	player.global_position = Vector3.ZERO
	player.rotation.y = 0.0
	if view.has_method("snap_to_target"):
		view.snap_to_target()


func _spawn_interactables() -> void:
	match room_id:
		"quarters_room_1":
			_spawn_quarters_bed()
		"kino_room":
			_spawn_kino_pickup()
		"east_corridor":
			_spawn_hull_breach()


# Bed against the -Z wall, matching the position used by RoomBuilder._accent_quarters.
func _spawn_quarters_bed() -> void:
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5
	var bunk_w: float = min(w_m - 1.0, 2.0)
	var bunk_x: float = -half_x * 0.3
	var bunk_pos: Vector3 = Vector3(bunk_x, 0.5, -half_z + 1.1)

	var bed: StaticBody3D = StaticBody3D.new()
	bed.set_script(BedScript)
	bed.name = "Bed"
	bed.position = bunk_pos
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	# Match the visible bunk footprint so the interact ray hits anywhere on it.
	box.size = Vector3(bunk_w + 0.2, 1.0, 2.0)
	cs.shape = box
	bed.add_child(cs)
	add_child(bed)


# Kino remote sits on the centre pedestal built by RoomBuilder._accent_kino_room.
# A visible kino sphere is parented to the room (NOT the pickup) so the pickup
# can hide it via NodePath after acquisition.
func _spawn_kino_pickup() -> void:
	var pedestal_top: Vector3 = Vector3(0.0, 1.05, 0.0)
	var holder: Node3D = Node3D.new()
	holder.name = "KinoProp"
	holder.position = pedestal_top + Vector3(0.0, 0.18, 0.0)
	add_child(holder)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.20, 0.24)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.35
	var eye_mat: StandardMaterial3D = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.95, 0.85, 0.55)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.95, 0.85, 0.55)
	eye_mat.emission_energy_multiplier = 3.5

	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: SphereMesh = SphereMesh.new()
	body_mesh.radius = 0.16
	body_mesh.height = 0.32
	body_mesh.radial_segments = 20
	body_mesh.rings = 10
	body_mi.mesh = body_mesh
	body_mi.material_override = body_mat
	holder.add_child(body_mi)

	var eye_mi: MeshInstance3D = MeshInstance3D.new()
	var iris: SphereMesh = SphereMesh.new()
	iris.radius = 0.06
	iris.height = 0.12
	iris.radial_segments = 12
	iris.rings = 6
	eye_mi.mesh = iris
	eye_mi.material_override = eye_mat
	eye_mi.position = Vector3(0.0, 0.0, 0.13)
	holder.add_child(eye_mi)

	var pickup: StaticBody3D = StaticBody3D.new()
	pickup.set_script(KinoPickupScript)
	pickup.name = "KinoPickup"
	pickup.position = holder.position
	# Path is relative to pickup itself, which will sit alongside KinoProp.
	pickup.set("prop_to_hide", NodePath("../KinoProp"))
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.7, 0.6, 0.7)
	cs.shape = box
	pickup.add_child(cs)
	add_child(pickup)


# Hull breach in the east_corridor: jagged dark hole on the +X wall with red
# warning trim, plus an emergency seal switch on the opposite wall. If the
# breach is already sealed (loaded save), swap the hole for a clean patch panel
# and the switch's _ready() will leave itself disabled.
func _spawn_hull_breach() -> void:
	const BREACH_ID: String = "breach_a"
	var w_m: float = float(_room_data.get("width", 200)) * ShipLayout.SCALE
	var d_m: float = float(_room_data.get("height", 200)) * ShipLayout.SCALE
	var half_x: float = w_m * 0.5
	var half_z: float = d_m * 0.5
	# 14 m in from the -Z end — well past the south door's arrival marker so
	# the player has to walk a stretch of corridor before stumbling on it.
	var breach_z: float = -half_z + 14.0
	var sealed: bool = GameState.breaches_sealed.has(BREACH_ID)

	var wrap: Node3D = Node3D.new()
	wrap.name = "HullBreach"
	wrap.position = Vector3(half_x - 0.02, 1.6, breach_z)
	add_child(wrap)

	if sealed:
		var patch_mat: StandardMaterial3D = StandardMaterial3D.new()
		patch_mat.albedo_color = Color(0.55, 0.50, 0.42)
		patch_mat.metallic = 0.7
		patch_mat.roughness = 0.4
		var patch_mi: MeshInstance3D = MeshInstance3D.new()
		var patch_box: BoxMesh = BoxMesh.new()
		patch_box.size = Vector3(0.06, 1.6, 1.8)
		patch_mi.mesh = patch_box
		patch_mi.material_override = patch_mat
		wrap.add_child(patch_mi)
		# Rivet dots — small bright cylinders along the patch edges read as
		# "this was welded shut" without needing a separate model.
		var rivet_mat: StandardMaterial3D = StandardMaterial3D.new()
		rivet_mat.albedo_color = Color(0.8, 0.75, 0.6)
		rivet_mat.metallic = 0.9
		rivet_mat.roughness = 0.25
		for ry in [-0.6, 0.0, 0.6]:
			for rz in [-0.75, 0.75]:
				var rivet_mesh: SphereMesh = SphereMesh.new()
				rivet_mesh.radius = 0.04
				rivet_mesh.height = 0.08
				var rivet: MeshInstance3D = MeshInstance3D.new()
				rivet.mesh = rivet_mesh
				rivet.material_override = rivet_mat
				rivet.position = Vector3(-0.04, ry, rz)
				wrap.add_child(rivet)
	else:
		var hole_mat: StandardMaterial3D = StandardMaterial3D.new()
		hole_mat.albedo_color = Color(0.02, 0.02, 0.03)
		hole_mat.metallic = 0.0
		hole_mat.roughness = 1.0
		var hole_mi: MeshInstance3D = MeshInstance3D.new()
		var hole_box: BoxMesh = BoxMesh.new()
		hole_box.size = Vector3(0.10, 1.4, 1.6)
		hole_mi.mesh = hole_box
		hole_mi.material_override = hole_mat
		wrap.add_child(hole_mi)

		var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
		trim_mat.albedo_color = Color(1.0, 0.18, 0.10)
		trim_mat.emission_enabled = true
		trim_mat.emission = Color(1.0, 0.20, 0.10)
		trim_mat.emission_energy_multiplier = 3.5
		# Four warning bars framing the hole (top/bottom/left/right).
		for trim in [
			{"pos": Vector3(-0.03, 0.75, 0.0), "size": Vector3(0.04, 0.08, 1.7)},
			{"pos": Vector3(-0.03, -0.75, 0.0), "size": Vector3(0.04, 0.08, 1.7)},
			{"pos": Vector3(-0.03, 0.0, 0.85), "size": Vector3(0.04, 1.5, 0.08)},
			{"pos": Vector3(-0.03, 0.0, -0.85), "size": Vector3(0.04, 1.5, 0.08)},
		]:
			var bar_mi: MeshInstance3D = MeshInstance3D.new()
			var bar_box: BoxMesh = BoxMesh.new()
			bar_box.size = trim["size"]
			bar_mi.mesh = bar_box
			bar_mi.material_override = trim_mat
			bar_mi.position = trim["pos"]
			wrap.add_child(bar_mi)

		# Debris on the floor beneath the hole.
		var debris_mat: StandardMaterial3D = StandardMaterial3D.new()
		debris_mat.albedo_color = Color(0.18, 0.16, 0.14)
		debris_mat.metallic = 0.4
		debris_mat.roughness = 0.7
		for i in 5:
			var d_mi: MeshInstance3D = MeshInstance3D.new()
			var d_box: BoxMesh = BoxMesh.new()
			var s: float = 0.18 + float(i) * 0.05
			d_box.size = Vector3(s * 0.6, 0.10, s)
			d_mi.mesh = d_box
			d_mi.material_override = debris_mat
			d_mi.position = Vector3(-0.4 - float(i) * 0.05, -1.5, -0.4 + float(i) * 0.2)
			d_mi.rotation = Vector3(0.0, deg_to_rad(15.0 * float(i)), deg_to_rad(8.0 * float(i)))
			wrap.add_child(d_mi)

	# Switch on the -X wall, opposite the breach, at chest height. Even when
	# already sealed we still spawn it so the prompt reads "Hull integrity
	# holding." instead of leaving the panel missing entirely.
	var switch: StaticBody3D = StaticBody3D.new()
	switch.set_script(HullSealSwitchScript)
	switch.name = "HullSealSwitch"
	switch.position = Vector3(-half_x + 0.25, 1.4, breach_z)
	switch.set("breach_id", BREACH_ID)
	var s_cs: CollisionShape3D = CollisionShape3D.new()
	var s_box: BoxShape3D = BoxShape3D.new()
	s_box.size = Vector3(0.5, 0.6, 0.5)
	s_cs.shape = s_box
	switch.add_child(s_cs)
	add_child(switch)

	# Switch visual: dark housing + bright emissive button. Parent to the room
	# (not the switch body) so the visible mesh doesn't double-count as a
	# collision shape on layer 4.
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.20, 0.20, 0.22)
	housing_mat.metallic = 0.5
	housing_mat.roughness = 0.45
	var housing_mi: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.55, 0.45)
	housing_mi.mesh = housing_box
	housing_mi.material_override = housing_mat
	housing_mi.position = switch.position
	add_child(housing_mi)

	var btn_mat: StandardMaterial3D = StandardMaterial3D.new()
	var btn_color: Color = Color(0.30, 0.85, 1.0) if sealed else Color(1.0, 0.30, 0.10)
	btn_mat.albedo_color = btn_color
	btn_mat.emission_enabled = true
	btn_mat.emission = btn_color
	btn_mat.emission_energy_multiplier = 3.0
	var btn_mi: MeshInstance3D = MeshInstance3D.new()
	var btn_box: BoxMesh = BoxMesh.new()
	btn_box.size = Vector3(0.04, 0.22, 0.22)
	btn_mi.mesh = btn_box
	btn_mi.material_override = btn_mat
	btn_mi.position = switch.position + Vector3(0.02, 0.0, 0.0)
	add_child(btn_mi)


# -------- helpers ----------------------------------------------------------

func _load_connections() -> Dictionary:
	var f: FileAccess = FileAccess.open(CONNECTIONS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


func _flip_direction(dir: String) -> String:
	match dir:
		"+x": return "-x"
		"-x": return "+x"
		"+z": return "-z"
		"-z": return "+z"
		_: return dir


func _to_camel(snake: String) -> String:
	var out: String = ""
	for part in snake.split("_"):
		if part.length() == 0:
			continue
		out += part[0].to_upper() + part.substr(1)
	return out


func _humanize(id: String) -> String:
	# control_interface_room → "Control Interface Room"
	var parts: PackedStringArray = id.split("_")
	var out: PackedStringArray = []
	for p in parts:
		if p.length() == 0:
			continue
		out.append(p[0].to_upper() + p.substr(1))
	return " ".join(out)
