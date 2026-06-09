class_name Companion
extends Node3D

# Phase F away-team companion on the lime planet (Greer, Park, Scott). Follows
# the player at a loose distance and, when there's lime to gather, fans out to
# the nearest un-depleted deposit and mines it — genuinely helping with the run.
# During the departure cutscene it rushes to the gate via rush_to().
#
# A cosmetic actor: moves by direct global_position + a downward ground ray (no
# physics body), so it can't snag on the noisy heightmap terrain — the same
# trick the cinematic player dash uses. Joins group "away_team" so the departure
# timer can muster it, and "companion" so the compass HUD (F3) can mark it.

# Preloaded (not class_name) so this script never depends on another global
# class being registered first in a headless load — same reason we avoid
# referencing our own class_name in a factory.
const NpcScript: Script = preload("res://scripts/npc.gd")

const COLORMAP_PATH: String = "res://models/characters/Textures/colormap.png"
const GROUND_MASK: int = 1          # terrain collides on layer 1
const FOLLOW_DIST: float = 3.2      # idle leash distance from the player
const MOVE_SPEED: float = 3.6
const RUSH_SPEED: float = 6.5       # cutscene sprint
const MINE_RANGE: float = 1.7       # close enough to harvest a deposit
const MINE_COOLDOWN: float = 5.0    # paced help — one deposit every few seconds
const MINE_SEARCH: float = 70.0     # how far a companion will roam for lime
const ARRIVE: float = 0.3

# Index in the away team — spreads idle follow offsets so companions don't stack.
var slot: int = 0
# Stationary companions (e.g. the team posted at the ship gate before they go
# through to the planet) skip the follow / mine state machine and just hold
# their pose until a rush_to() coroutine moves them. Set this before adding to
# the tree (or any time before _process actually decides what to do).
var stationary: bool = false
# Peeled-off companions (Scott + Park on the south team) hold their spawn
# position and do not follow or mine. They still rush_to() on departure muster
# because the peeled_off check sits AFTER the _rushing check in _process().
# Set this before setup() via c.set("peeled_off", entry.team == "south").
var peeled_off: bool = false

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _rushing: bool = false
var _rush_target: Vector3 = Vector3.ZERO
var _mine_cd: float = 0.0
var _mine_target: Node3D = null
var _moving: bool = false

# Build this companion's body (Kenney mini-char + nametag). Called by the caller
# right after instancing the preloaded script and adding it to the tree — kept
# as an instance method so the script never references its own class_name (which
# fails to resolve during a headless load).
func setup(display_name: String, glb_path: String, idx: int, tint: Color = Color.WHITE) -> void:
	slot = idx
	# Join here too (not just _enter_tree): the headless harness defers tree
	# callbacks, and the cutscene muster / compass need membership immediately.
	add_to_group("away_team")
	add_to_group("companion")
	_build_body(display_name, glb_path, tint)

# Join on _enter_tree (fires synchronously on add_child) rather than _ready, so
# group membership is set the instant a companion is parented — including in the
# synchronous headless test harness where _ready is deferred until a frame ticks.
func _enter_tree() -> void:
	add_to_group("away_team")
	add_to_group("companion")

func _build_body(display_name: String, glb_path: String, tint: Color = Color.WHITE) -> void:
	_model = Node3D.new()
	_model.name = "Model"
	_model.scale = Vector3(2.2, 2.2, 2.2)
	_model.rotation.y = PI   # Kenney mini-chars export +Z forward; flip to -Z
	add_child(_model)
	var glb: PackedScene = load(glb_path) as PackedScene if ResourceLoader.exists(glb_path) else null
	if glb != null:
		var inst: Node = glb.instantiate()
		_model.add_child(inst)
		var colormap: Texture2D = load(COLORMAP_PATH) as Texture2D
		NpcScript.apply_kenney_colormap(inst, colormap)
		if tint != Color.WHITE:
			# Re-tint the just-applied colormap material per-instance — the atlas
			# colour × tint shifts the (peach) skin column toward brown without
			# touching the GLB itself, so Greer can share Scott's body model and
			# still read as a different character.
			_apply_tint(inst, tint)
		_anim = _find_anim(inst)
		_play_clip("idle")
	var tag: Label3D = Label3D.new()
	tag.text = display_name
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.78, 0.92, 1.0, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.position = Vector3(0.0, 2.0, 0.0)
	add_child(tag)

# Cutscene hook: drop everything and sprint to the gate. The departure timer
# calls this on every node in group "away_team".
func rush_to(target: Vector3) -> void:
	_rush_target = target
	_rushing = true
	_mine_target = null

func _process(delta: float) -> void:
	if _rushing:
		_step_toward(_rush_target, RUSH_SPEED, delta)
		return
	if stationary:
		_set_moving(false)
		return
	# Scott + Park (south team): hold spawn position, never follow or mine.
	# Placed AFTER the _rushing check so they still rush_to() the gate on
	# departure muster (planet_timer.gd calls rush_to on all "away_team" nodes).
	if peeled_off:
		_set_moving(false)
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		_set_moving(false)
		return
	_mine_cd = maxf(0.0, _mine_cd - delta)
	# Already heading to a deposit? Keep going until we reach + harvest it.
	if _mine_target != null and is_instance_valid(_mine_target) and not _is_depleted(_mine_target):
		var d: float = _planar(global_position, _mine_target.global_position)
		if d <= MINE_RANGE:
			# Re-check at the moment of harvest so two companions arriving at once
			# can't push the count past REQUIRED-1 (the player mines the last unit).
			if _should_help():
				_harvest(_mine_target)
			_mine_target = null
			_mine_cd = MINE_COOLDOWN
			_set_moving(false)
		else:
			_step_toward(_mine_target.global_position, MOVE_SPEED, delta)
		return
	# Look for lime to help with when off cooldown; otherwise follow the player.
	if _mine_cd <= 0.0 and _should_help():
		_mine_target = _pick_lime(player)
	if _mine_target != null:
		_step_toward(_mine_target.global_position, MOVE_SPEED, delta)
		return
	_follow(player, delta)

# Stay loosely behind the player, fanning out by slot so the team doesn't stack.
func _follow(player: Node3D, delta: float) -> void:
	var offset: Vector3 = Vector3(-1.6 + float(slot) * 1.6, 0.0, 1.8)
	var goal: Vector3 = player.global_position + offset
	if _planar(global_position, goal) <= FOLLOW_DIST:
		_set_moving(false)
		return
	_step_toward(goal, MOVE_SPEED, delta)

# Nearest un-depleted lime deposit within roaming range, preferring ones the
# player isn't already standing on (so we split the work rather than racing them).
func _pick_lime(player: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d: float = MINE_SEARCH
	for n in get_tree().get_nodes_in_group("lime_node"):
		if not (n is Node3D) or _is_depleted(n):
			continue
		var node3d: Node3D = n as Node3D
		if _planar(player.global_position, node3d.global_position) < MINE_RANGE * 1.5:
			continue   # leave the one the player is mining for them
		var d: float = _planar(global_position, node3d.global_position)
		if d < best_d:
			best_d = d
			best = node3d
	return best

# Companions only top the lime count up to REQUIRED-1 — the away team helps, but
# the player always mines the final unit so the mission's core loop isn't fully
# automated.
func _should_help() -> bool:
	var have: int = GameState.resource_count(GameState.AIR_LIME_RESOURCE)
	return have < GameState.AIR_LIME_REQUIRED - 1

func _harvest(node: Node3D) -> void:
	if node.has_method("_on_interact"):
		node.call("_on_interact", self)

func _is_depleted(node: Node3D) -> bool:
	return node.get("depleted") == true

# Move toward a world point, follow the ground, face travel, animate.
func _step_toward(target: Vector3, speed: float, delta: float) -> void:
	var to_t: Vector3 = target - global_position
	to_t.y = 0.0
	var dist: float = to_t.length()
	if dist <= ARRIVE:
		if _rushing:
			_rushing = false
		_set_moving(false)
		return
	var dir: Vector3 = to_t.normalized()
	var np: Vector3 = global_position + dir * speed * delta
	np.y = _ground_y(np, global_position.y)
	global_position = np
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), delta * 12.0)
	_set_moving(true, speed >= RUSH_SPEED)

func _set_moving(moving: bool, fast: bool = false) -> void:
	if moving == _moving and not moving:
		return
	_moving = moving
	if moving:
		_play_clip("sprint" if fast else "walk")
	else:
		_play_clip("idle")

func _ground_y(at: Vector3, fallback: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return fallback
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(at.x, at.y + 30.0, at.z), Vector3(at.x, at.y - 80.0, at.z), GROUND_MASK)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.has("position"):
		return (hit["position"] as Vector3).y
	return fallback

func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _play_clip(clip: String) -> void:
	if _anim == null:
		return
	for nm in _anim.get_animation_list():
		if String(nm).to_lower().contains(clip):
			if _anim.current_animation != String(nm):
				_anim.play(String(nm))
			return

func _apply_tint(root: Node, tint: Color) -> void:
	# apply_kenney_colormap above set the SAME StandardMaterial3D as
	# material_override on every MeshInstance3D, so we have to duplicate before
	# mutating albedo_color or every Kenney character on screen would tint.
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.albedo_color = tint
				mi.material_override = mat
		for c in n.get_children():
			stack.append(c)


func _find_anim(root: Node) -> AnimationPlayer:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n as AnimationPlayer
		for c in n.get_children():
			stack.append(c)
	return null
