class_name CameraXRay
extends Node3D

## Camera X-ray occlusion system (issue #139). Raycasts from the active camera
## toward tracked subjects and fades occluding geometry to ~25% alpha so the
## subject stays readable behind walls, consoles, and props.
##
## Integration:
##   Gameplay camera (view.gd): created dynamically in _ready, calls
##   setup(camera) and track_subject(player).
##   Standoff camera (standoff_camera.gd): created in _ready, calls
##   setup(_cam), and track_subject is called each frame with the current
##   tracking target.
##
## Subjects: add nodes to the "camera_subjects" group for auto-discovery,
## or manage them explicitly via track_subject() / untrack_subject().
##
## Excluded from fading (checked via groups, node metadata, or Door state):
##   - "no_xray" group or metadata flag (manual opt-out)
##   - "floor" group (so the deck never vanishes under the camera)
##   - "skybox" / "hull" groups
##   - "gate" group (the Stargate ring)
##   - Doors mid-transition (Door with an active tween — fading a moving
##     leaf reads worse than the brief occlusion)
##
## Headless / instant_mode: processing is skipped entirely when
## SceneRouter.instant_mode is true (no raycasts, no material mutations).
## This keeps headless smoke tests and Movie Maker captures deterministic.

# --- Tuning -----------------------------------------------------------------

# Godot 4 GeometryInstance3D.transparency: 0.0 = opaque, 1.0 = invisible.
# 25% alpha = 0.75 transparency.
const FADE_TARGET_TRANSPARENCY: float = 0.75
# Seconds to reach the target fade level (≈0.15 s).
const FADE_DURATION: float = 0.15
# Seconds to restore to opaque (slightly slower so re-occlusion reads smooth).
const RESTORE_DURATION: float = 0.25
# Consecutive clear frames before a mesh starts restoring (hysteresis so
# brief ray-clears from head-bobbing don't strobe the geometry).
const RESTORE_HYSTERESIS: int = 3
# World geometry collision layer (same as _pull_clear in standoff_camera.gd).
const RAY_COLLISION_MASK: int = 1
# Safety cap on the exclude-accumulation loop so a pathological scene can't
# spin forever.
const MAX_RAY_HOPS: int = 32

# Groups that are always excluded from fading.
const EXCLUDE_GROUPS: PackedStringArray = [
	"no_xray", "floor", "skybox", "hull", "gate",
]

# --- State ------------------------------------------------------------------

var _camera: Camera3D = null
# Explicitly-tracked subjects (supplements "camera_subjects" group discovery).
var _subjects: Array[Node3D] = []
# Collider → MeshInstance3D lookup (populated lazily; the visual mesh for a
# physics collider is typically a sibling under the same prop parent).
var _collider_mesh: Dictionary = {}
# MeshInstance3D → { "ref": int, "clear": int, "orig": float }.
# ref   = how many rays are currently hitting this mesh (overlapping subjects).
# clear = consecutive frames the mesh has been clear of all rays.
# orig  = original transparency value to restore to.
var _active: Dictionary = {}
# Cached instant_mode flag (re-checked each frame in case it flips mid-scene).
var _instant_mode: bool = false


func _ready() -> void:
	_update_instant_mode()
	if _instant_mode:
		set_process(false)


func _process(delta: float) -> void:
	# Re-check each frame — instant_mode may have been toggled after _ready.
	_update_instant_mode()
	if _instant_mode:
		return
	if _camera == null or not is_instance_valid(_camera):
		return

	# Auto-discover group subjects each frame (handles dynamic spawns / frees).
	_discover_group_subjects()

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		_tick_restore(delta)
		return

	# Raycast to each subject; collect currently-occluding meshes with refcounts.
	# now_occluding: MeshInstance3D → int (number of rays hitting it).
	var now_occluding: Dictionary = {}
	for subject in _subjects:
		if not is_instance_valid(subject):
			continue
		for mesh: MeshInstance3D in _ray_occluders(space, subject):
			now_occluding[mesh] = int(now_occluding.get(mesh, 0)) + 1

	# Reconcile _active with now_occluding.
	var to_erase: Array = []

	# Fade currently-occluding meshes toward target, and (re)register them.
	for mesh: MeshInstance3D in now_occluding.keys():
		if not is_instance_valid(mesh):
			continue
		if _active.has(mesh):
			var state: Dictionary = _active[mesh]
			state["ref"] = int(now_occluding[mesh])
			state["clear"] = 0
		else:
			_active[mesh] = {
				"ref": int(now_occluding[mesh]),
				"clear": 0,
				"orig": mesh.transparency,
			}
		_fade_toward(mesh, FADE_TARGET_TRANSPARENCY, delta, FADE_DURATION)

	# Handle meshes that were active but are no longer occluded by any ray.
	for mesh: MeshInstance3D in _active.keys():
		if now_occluding.has(mesh):
			continue
		if not is_instance_valid(mesh):
			to_erase.append(mesh)
			continue
		var state: Dictionary = _active[mesh]
		state["ref"] = 0
		state["clear"] = int(state["clear"]) + 1
		if int(state["clear"]) >= RESTORE_HYSTERESIS:
			var orig: float = float(state.get("orig", 0.0))
			_fade_toward(mesh, orig, delta, RESTORE_DURATION)
			if absf(mesh.transparency - orig) < 0.01:
				mesh.transparency = orig
				to_erase.append(mesh)

	for mesh in to_erase:
		_active.erase(mesh)


# --- Public API -------------------------------------------------------------

## Bind the camera that rays originate from. Required before processing.
func setup(camera: Camera3D) -> void:
	_camera = camera


## Add a subject to track. Rays will be cast from the camera toward each
## tracked subject (plus any node in the "camera_subjects" group).
func track_subject(subject: Node3D) -> void:
	if subject != null and not _subjects.has(subject):
		_subjects.append(subject)


## Stop tracking a subject.
func untrack_subject(subject: Node3D) -> void:
	_subjects.erase(subject)


## Clear all explicitly-tracked subjects.
func clear_subjects() -> void:
	_subjects.clear()


## Full reset: clear subjects, restore all fades immediately, clear registry.
func clear_all() -> void:
	_subjects.clear()
	for mesh: MeshInstance3D in _active.keys():
		if is_instance_valid(mesh):
			var state: Dictionary = _active[mesh]
			mesh.transparency = float(state.get("orig", 0.0))
	_active.clear()
	_collider_mesh.clear()


## Register a collider → mesh mapping manually (for room builders / set
## dressing that know the visual mesh for a physics body ahead of time).
func register_collider_mesh(collider: Node, mesh: MeshInstance3D) -> void:
	if collider != null and mesh != null:
		_collider_mesh[collider] = mesh


# --- Internal: raycasting ---------------------------------------------------

## Cast a ray from the camera toward `subject`, accumulating exclusions so we
## pierce through multiple occluders (e.g. a console behind a railing). Returns
## a list of unique MeshInstance3D nodes that should be faded.
func _ray_occluders(space: PhysicsDirectSpaceState3D, subject: Node3D) -> Array:
	var start: Vector3 = _camera.global_position
	var end: Vector3 = subject.global_position
	var excludes: Array[RID] = []
	var occluders: Array = []
	var seen: Dictionary = {}  # MeshInstance3D → true (dedup)
	var hops: int = 0
	while hops < MAX_RAY_HOPS:
		hops += 1
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			start, end, RAY_COLLISION_MASK)
		if not excludes.is_empty():
			q.exclude = excludes
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider == null:
			break
		# Reached the subject itself (or a child of it) — ray is clear from here.
		if _is_subject_or_descendant(collider, subject):
			break
		# Excluded category — skip but keep accumulating past it.
		if _is_excluded(collider):
			excludes.append(collider.get_rid())
			continue
		# Find the visual mesh for this collider and record it.
		var mesh: MeshInstance3D = _resolve_mesh(collider)
		if mesh != null and is_instance_valid(mesh) and not seen.has(mesh):
			seen[mesh] = true
			occluders.append(mesh)
		excludes.append(collider.get_rid())
	return occluders


## Returns true if `node` is `subject` itself or a descendant of `subject`.
## Used to stop the ray loop once we reach the tracked character.
func _is_subject_or_descendant(node: Object, subject: Node3D) -> bool:
	if node == subject:
		return true
	var p: Node = (node as Node).get_parent() if node is Node else null
	while p != null:
		if p == subject:
			return true
		p = p.get_parent()
	return false


## Returns true if `collider` should never be faded (floors, skybox, gate,
## doors mid-transition, or anything tagged "no_xray").
func _is_excluded(collider: Object) -> bool:
	var node: Node = collider as Node
	if node == null:
		return false
	# Group-based exclusions.
	for g in EXCLUDE_GROUPS:
		if node.is_in_group(g):
			return true
	# Metadata flag (per-node opt-out without group membership).
	if node.has_meta("no_xray") and bool(node.get_meta("no_xray", false)):
		return true
	# Door mid-transition: a Door with an active tween (fading a moving leaf
	# reads worse than the brief occlusion). We walk up the collider's
	# ancestry because the ray may hit a child StaticBody3D of the Door.
	if _is_door_mid_transition(node):
		return true
	return false


## Checks whether `node` (or an ancestor) is a Door with an active tween.
func _is_door_mid_transition(node: Node) -> bool:
	var current: Node = node
	var hops: int = 0
	while current != null and hops < 8:
		hops += 1
		if _is_door_script(current):
			var tween: Tween = current.get("_tween")
			if tween != null and tween.is_valid() and tween.is_running():
				return true
		current = current.get_parent()
	return false


## Detects a Door node by script resource path (same pattern as
## scene_router.gd::_gather_doors — resilient to class_name cold-load timing).
func _is_door_script(node: Node) -> bool:
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("door.gd"):
		return true
	return false


# --- Internal: mesh resolution ----------------------------------------------

## Find the MeshInstance3D associated with a physics collider. Checks the
## instance registry first, then tries sibling/descendant/ancestor lookup
## (the common patterns: StaticBody3D + MeshInstance3D siblings under a prop,
## or a CharacterBody3D with a descendant mesh).
func _resolve_mesh(collider: Object) -> MeshInstance3D:
	if _collider_mesh.has(collider):
		var cached: MeshInstance3D = _collider_mesh[collider]
		if is_instance_valid(cached):
			return cached
		_collider_mesh.erase(collider)

	var node: Node = collider as Node
	if node == null:
		return null

	# 1. Collider itself is a mesh.
	if node is MeshInstance3D:
		_collider_mesh[collider] = node
		return node

	# 2. Sibling mesh under the same parent (StaticBody3D + MeshInstance3D).
	var parent: Node = node.get_parent()
	if parent != null:
		for c in parent.get_children():
			if c is MeshInstance3D:
				_collider_mesh[collider] = c
				return c

	# 3. Descendant mesh (CharacterBody3D with mesh children).
	var desc: MeshInstance3D = _find_mesh_descendant(node)
	if desc != null:
		_collider_mesh[collider] = desc
		return desc

	return null


## Depth-first search for the first MeshInstance3D descendant.
func _find_mesh_descendant(node: Node) -> MeshInstance3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			return c
		var found: MeshInstance3D = _find_mesh_descendant(c)
		if found != null:
			return found
	return null


# --- Internal: fade / restore -----------------------------------------------

## Smoothly interpolate `mesh.transparency` toward `target` at a rate defined
## by `duration` seconds for a full 0→1 transition.
func _fade_toward(mesh: MeshInstance3D, target: float, delta: float, duration: float) -> void:
	var rate: float = clampf(delta / maxf(duration, 0.001), 0.0, 1.0)
	mesh.transparency = lerpf(mesh.transparency, target, rate)


## Called when there are no subjects (or no physics space): all active meshes
## count clear frames and restore toward their original transparency.
func _tick_restore(delta: float) -> void:
	if _active.is_empty():
		return
	var to_erase: Array = []
	for mesh: MeshInstance3D in _active.keys():
		if not is_instance_valid(mesh):
			to_erase.append(mesh)
			continue
		var state: Dictionary = _active[mesh]
		state["clear"] = int(state["clear"]) + 1
		if int(state["clear"]) >= RESTORE_HYSTERESIS:
			var orig: float = float(state.get("orig", 0.0))
			_fade_toward(mesh, orig, delta, RESTORE_DURATION)
			if absf(mesh.transparency - orig) < 0.01:
				mesh.transparency = orig
				to_erase.append(mesh)
	for mesh in to_erase:
		_active.erase(mesh)


# --- Internal: subject discovery --------------------------------------------

## Merge nodes from the "camera_subjects" group into the explicit _subjects
## list (without duplicates).
func _discover_group_subjects() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("camera_subjects"):
		var n3: Node3D = n as Node3D
		if n3 != null and not _subjects.has(n3):
			_subjects.append(n3)


# --- Internal: instant_mode -------------------------------------------------

func _update_instant_mode() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var sr: Node = tree.root.get_node_or_null("SceneRouter")
	if sr != null:
		_instant_mode = bool(sr.get("instant_mode"))