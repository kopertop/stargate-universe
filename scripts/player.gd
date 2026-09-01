extends CharacterBody3D

# SGU third-person player controller (Eli Wallace).
# Camera-relative WASD movement. Sprint toggle. Interact ray points where the
# camera looks. No double-jump or fall-respawn (kit platformer bits removed).

signal interact_target_changed(target: Node)
signal auto_walk_finished

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Avatar")
# Mixamo host (signed-off aim/fire). Falls back to modular when the local
# ToS-gitignored pack is missing. Mint character hosts were removed — props only.
@export var use_mixamo_avatar: bool = true
# Deprecated: Mint body GLBs are gone. Kept so old captures can force-off Mixamo
# without resurrecting MintCharacter.
@export var use_mint_avatar: bool = false

@export_subgroup("Movement")
@export var walk_speed: float = 8.0          # m/s
@export var sprint_multiplier: float = 1.7
@export var accel_smoothing: float = 12.0
@export var gravity_strength: float = 25.0
@export var jump_strength: float = 5.5

@export_subgroup("Interact")
@export var interact_reach: float = 3.5      # metres — general "look + E" range
# Clicking an interactable selects it and lets you interact from this larger
# range, so you can pick someone slightly further off and step in to talk.
@export var interact_reach_targeted: float = 6.0
@export var interact_origin_height: float = 1.1  # chest height
# Minimum facing alignment (dot of camera-forward vs direction to target) for a
# candidate to count — keeps us from grabbing something behind the player.
@export var interact_min_aim: float = 0.1

var _gravity_velocity: float = 0.0
var _move_velocity: Vector3 = Vector3.ZERO
var _facing_yaw: float = 0.0
var _current_interactable: Node = null
# Sticky target set by clicking an interactable. Wins over the look-based pick
# and is reachable from the extended range. Cleared when it leaves range, gets
# disabled, or the player clicks empty space / another interactable.
var _clicked_target: Node = null
var _input_locked: bool = false   # locked during cutscene / scene transitions
# When set, the locked idle pose plays this clip instead of "idle" (e.g.
# "holding-both" while Eli holds the Kino remote, piloting the drone).
var _pose_override: String = ""
var _auto_walking: bool = false
var _auto_walk_target: Vector3 = Vector3.ZERO
var _auto_walk_speed: float = 5.0
var _auto_walk_arrive_dist: float = 0.18
# Cinematic dash: collision-FREE sprint to a point (used by cutscenes so the
# actor can never snag on terrain/props). Moves by direct position + a ground
# ray, with body collision disabled — clipping is intentionally off here.
var _cinematic_dash: bool = false
var _dash_target: Vector3 = Vector3.ZERO
var _dash_speed: float = 12.0

# Footsteps — random individual samples played on a distance-based cadence: one
# step per ~FOOTSTEP_STRIDE metres of floor travel, so faster speeds produce
# faster steps without per-frame timing math. Pitch jitters per step so repeats
# don't sound mechanical. The SAMPLE SET is chosen per-environment by
# FootstepLibrary (issue #33): metal on the ship / alien-tech decks, dirt /
# desert / water / swamp on planet surfaces. LOCATION is authoritative — the
# player defaults to metal (so EVERY ship scene sounds metal regardless of any
# lingering active_planet_spec), and the planet scene PUSHES its biome surface
# via set_footstep_surface() once its spec is finalized. (Reading the persisted
# spec in _ready was the "clanky metal on the desert planet" bug: the player's
# _ready runs before the parent planet assigns the spec.) Per-surface gain keeps
# soft ground quieter than metal.
const _FOOTSTEP_LIBRARY: Script = preload("res://scripts/footstep_library.gd")
const FOOTSTEP_STRIDE: float = 1.9
var _footstep_surface: String = "metal"   # FootstepLibrary.DEFAULT_SURFACE
var _footstep_streams: Array = []
var _footstep_distance: float = 0.0
# The SoundFootsteps node's authored volume_db; the per-surface gain is added to it.
var _footstep_base_volume_db: float = 0.0

@onready var _particles_trail: GPUParticles3D = $ParticlesTrail
@onready var _sound_footsteps: AudioStreamPlayer = $SoundFootsteps
@onready var _model: Node3D = $Character
# AnimationPlayer lives inside the glTF root (e.g. Character/Model/AnimationPlayer
# for Kenney Mini Characters). Recursive find keeps player.gd resilient if the
# asset wrapper ever moves it around. Kept optional so static-mesh characters
# still boot without animation.
@onready var _animation: AnimationPlayer = _find_animation_player($Character)

# Kenney Mini Characters share a palette texture; the glTF import loses the
# embedded baseColorTexture binding so meshes render pure white. Re-apply the
# shared StandardMaterial3D to every surface in the character hierarchy.
const _COLORMAP_MAT: Material = preload("res://models/colormap.tres")
const _EQUIPMENT_MOUNT_SCRIPT: Script = preload("res://scripts/equipment_mount.gd")
const _CHARACTER_FACTORY: Script = preload("res://scripts/character_factory.gd")
const _MINT_CHARACTER: Script = preload("res://scripts/mint_character.gd")
const _MIXAMO_COMBAT: Script = preload("res://scripts/mixamo_combat_avatar.gd")

# Kit animation names -> modular crew_body.res clips. The library has no
# airborne clip, so jump/fall borrow the jog cycle; "holding-both" (Kino
# remote piloting) reads as Eli working the device via the talking gestures.
const MODULAR_CLIP: Dictionary = {
	"idle": "idle", "walk": "walk", "sprint": "sprint",
	"jump": "jog", "fall": "jog",
	"holding-both": "talk",
}

# Renders equipped gear (#72) on the character. Lives under $Character so its
# BoneAttachment3D sockets can find the Skeleton3D inside $Character/Model.
var _equipment_mount: Node3D = null
# The player's ModularCharacter body (primary pipeline). Null only if the Eli
# profile ever loses its "mod" key — then the legacy kit chibi stays.
var _mc: Node3D = null
# Mint-native body (when use_mint_avatar). Combat weapons via MintHeldWeapon.
var _mint: Node3D = null
var _mint_jump_requested: bool = false
# Mixamo Swat combat avatar (preferred play path).
var _mixamo: Node3D = null
var _mixamo_aiming: bool = false
var _mixamo_want_fire: bool = false
# Movie Maker / capture harness: drive aim+fire without real mouse buttons.
var _demo_combat_override: bool = false
var _demo_aim: bool = false
var _demo_fire: bool = false
var _aim_cross: Control = null
var _tool_use_label: Label = null
var _tool_use_token: int = 0
# Target Lock — soft-lock on nearest combat_target in view (T / MMB).
var _lock_target: Node3D = null
var _lock_label: Label = null
var _lock_ring: Control = null
# Last aim/lock combat-music state — only crossfade MusicDirector on edges.
var _combat_music_hot: bool = false

func _ready() -> void:
	if use_mixamo_avatar and _mixamo_pack_available():
		_setup_mixamo_avatar()
	elif use_mint_avatar:
		_setup_mint_avatar()
	else:
		_setup_modular_avatar()
		if _mc == null:
			_apply_colormap(_model)
	_setup_equipment_mount()
	_init_footsteps()
	_configure_combat_camera()
	_wire_combat_ui_hooks()


func _wire_combat_ui_hooks() -> void:
	# Drop aim when dialog/Kino opens so a held RMB cannot fire under the UI
	# once the tree unpauses. View already releases / re-captures the mouse.
	if GameState == null:
		return
	if GameState.has_signal("dialog_started") and not GameState.dialog_started.is_connected(_on_combat_ui_suspend):
		GameState.dialog_started.connect(_on_combat_ui_suspend)
	# KinoRemote / PauseMenu do not emit an "opened" signal; they pause the tree
	# and set mouse visible. dialog_started covers NPC talk; Esc pause restores
	# via saved mouse mode. Clear aim on any dialog_started is enough for talk.


func _on_combat_ui_suspend(_a: Variant = null, _b: Variant = null) -> void:
	_mixamo_aiming = false
	_mixamo_want_fire = false
	clear_target_lock()
	_update_aim_crosshair()
	_update_combat_camera_aim()


func _unhandled_input(event: InputEvent) -> void:
	if _input_locked or _auto_walking:
		return
	if _mixamo != null and event.is_action_pressed("target_lock"):
		toggle_target_lock()
		get_viewport().set_input_as_handled()
		return
	# Aim+fire owns LMB while Mixamo combat is aiming.
	if _mixamo != null and _mixamo_aiming:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_click_target(mb.position)


## Toggle soft Target Lock on the best combat_target in the camera cone.
func toggle_target_lock() -> void:
	if _lock_target != null and is_instance_valid(_lock_target):
		clear_target_lock()
		return
	var best: Node3D = _find_best_lock_target()
	if best == null:
		return
	_set_lock_target(best)


func clear_target_lock(play_sfx: bool = true) -> void:
	if _lock_target != null and is_instance_valid(_lock_target):
		if _lock_target.has_method("set_lock_highlighted"):
			_lock_target.call("set_lock_highlighted", false)
	var had_lock: bool = _lock_target != null
	_lock_target = null
	_update_lock_ui()
	if had_lock and play_sfx:
		Audio.play("res://sounds/menu_close.ogg")
	if had_lock:
		_refresh_combat_music()


func has_target_lock() -> bool:
	return _lock_target != null and is_instance_valid(_lock_target) and _lock_target_alive(_lock_target)


func get_lock_target() -> Node3D:
	return _lock_target if has_target_lock() else null


func get_lock_aim_point() -> Vector3:
	if not has_target_lock():
		return Vector3.ZERO
	if _lock_target.has_method("get_lock_point"):
		return _lock_target.call("get_lock_point") as Vector3
	return _lock_target.global_position


## Movie / tests: force lock onto a specific combat_target.
func set_demo_lock_target(target: Node3D) -> void:
	if target == null:
		clear_target_lock()
		return
	_set_lock_target(target)


func _set_lock_target(target: Node3D) -> void:
	# Silent clear so re-lock / acquire does not blip unlock then lock.
	clear_target_lock(false)
	_lock_target = target
	if _lock_target.has_method("set_lock_highlighted"):
		_lock_target.call("set_lock_highlighted", true)
	if _lock_target.has_signal("destroyed") and not _lock_target.destroyed.is_connected(_on_lock_target_destroyed):
		_lock_target.destroyed.connect(_on_lock_target_destroyed)
	_update_lock_ui()
	Audio.play("res://sounds/menu_click.ogg")
	_refresh_combat_music()


func _on_lock_target_destroyed() -> void:
	_lock_target = null
	_update_lock_ui()
	# Destroy SFX lives on the drone itself (break.ogg).
	_refresh_combat_music()


func _refresh_combat_music() -> void:
	# Subtle adaptive bed: combat stems while aiming/locked, otherwise leave
	# MusicDirector on the room mood (ship_calm in gate_room).
	var want_hot: bool = _mixamo_aiming or has_target_lock()
	if want_hot == _combat_music_hot:
		return
	_combat_music_hot = want_hot
	var md: Node = get_node_or_null("/root/MusicDirector")
	if md == null or not md.has_method("set_mood"):
		return
	if want_hot:
		md.call("set_mood", "combat", 1.2)
	elif md.has_method("refresh"):
		md.call("refresh", 2.0)


func _lock_target_alive(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t.has_method("is_alive"):
		return bool(t.call("is_alive"))
	return true


func _find_best_lock_target() -> Node3D:
	var cam: Camera3D = _interact_camera()
	if cam == null:
		return null
	var best: Node3D = null
	var best_score: float = -1.0
	var from: Vector3 = cam.global_position
	var forward: Vector3 = -cam.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("combat_target"):
		var t: Node3D = n as Node3D
		if t == null or not _lock_target_alive(t):
			continue
		var aim: Vector3 = t.global_position
		if t.has_method("get_lock_point"):
			aim = t.call("get_lock_point") as Vector3
		var to: Vector3 = aim - from
		var dist: float = to.length()
		if dist < 1.0 or dist > 28.0:
			continue
		var dir: Vector3 = to / dist
		var align: float = forward.dot(dir)
		if align < 0.35:
			continue
		# Prefer near screen-center and closer targets.
		var score: float = align * 2.0 + (1.0 - clampf(dist / 28.0, 0.0, 1.0))
		if score > best_score:
			best_score = score
			best = t
	return best


func _update_lock_ui() -> void:
	_ensure_aim_crosshair()
	if _lock_label != null:
		_lock_label.visible = has_target_lock() and not _input_locked
	if _lock_ring != null:
		_lock_ring.visible = false
	if not has_target_lock():
		return
	var cam: Camera3D = _interact_camera()
	if cam == null or _lock_ring == null:
		return
	var aim: Vector3 = get_lock_aim_point()
	if cam.is_position_behind(aim):
		return
	var screen: Vector2 = cam.unproject_position(aim)
	_lock_ring.visible = true
	_lock_ring.position = screen - _lock_ring.size * 0.5


func _mixamo_pack_available() -> bool:
	return _MIXAMO_COMBAT.combat_pack_available("Eli")


# Mixamo host for Eli (Eli_rifle_combat.glb; falls back per MixamoHostCatalog).
func _setup_mixamo_avatar() -> void:
	if _model == null:
		return
	for c in _model.get_children():
		_model.remove_child(c)
		c.queue_free()
	_model.transform = Transform3D.IDENTITY
	_mixamo = _MIXAMO_COMBAT.create("Eli") as Node3D
	_model.add_child(_mixamo)
	if not bool(_mixamo.call("mount")):
		_mixamo.queue_free()
		_mixamo = null
		push_warning("Player: Mixamo combat pack failed — falling back")
		if use_mint_avatar:
			_setup_mint_avatar()
		else:
			_setup_modular_avatar()
		return
	_mc = null
	_mint = null
	_animation = null
	_tune_mixamo_capsule()
<<<<<<< HEAD
	_sync_mixamo_weapon_visibility()
	_bind_inventory_wield_signals()
	call_deferred("_finish_mixamo_spawn_frames", 2)


func _bind_inventory_wield_signals() -> void:
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return
	if inv.has_signal("changed") and not inv.changed.is_connected(_on_inventory_changed_for_weapon):
		inv.changed.connect(_on_inventory_changed_for_weapon)
	if inv.has_signal("item_changed") and not inv.item_changed.is_connected(_on_item_changed_for_weapon):
		inv.item_changed.connect(_on_item_changed_for_weapon)
	if inv.has_signal("wield_changed") and not inv.wield_changed.is_connected(_on_wield_changed_for_weapon):
		inv.wield_changed.connect(_on_wield_changed_for_weapon)


func _on_inventory_changed_for_weapon() -> void:
	_sync_mixamo_weapon_visibility()


func _on_item_changed_for_weapon(_id: String, _count: int) -> void:
	_sync_mixamo_weapon_visibility()


func _on_wield_changed_for_weapon(_index: int, _item_id: String) -> void:
	_sync_mixamo_weapon_visibility()


## Rifle mesh is cosmetic until a weapon item is owned. Holster/draw still
## follows aim once carried. Active interface tools get a held slate prop.
func _sync_mixamo_weapon_visibility() -> void:
	if _mixamo == null:
		return
	var inv: Node = get_node_or_null("/root/Inventory")
	var carried: bool = inv != null and inv.has_method("has") and bool(inv.call("has", "sidearm"))
	if _mixamo.has_method("set_weapon_visible"):
		_mixamo.call("set_weapon_visible", carried)
	var wield: String = ""
	if inv != null and inv.has_method("active_wield_id"):
		wield = String(inv.call("active_wield_id"))
	if _mixamo.has_method("set_held_interface"):
		_mixamo.call("set_held_interface", wield)


func _finish_mixamo_spawn_frames(frames_left: int) -> void:
	# Avoid await — scene-boot frees the player mid-resume and logs engine errors.
	if not is_inside_tree() or not is_instance_valid(self) or _mixamo == null:
		return
	if frames_left > 0:
		call_deferred("_finish_mixamo_spawn_frames", frames_left - 1)
		return
	if _mixamo.has_method("align_feet_once"):
		_mixamo.call("align_feet_once")
	_ensure_aim_crosshair()


func _configure_combat_camera() -> void:
	if view == null or _mixamo == null:
		return
	# Showcase-scale follow height (Mixamo Swat ~1.8 m vs modular ~1.6 m).
	# ADS / crouch heights live on View (combat_*_follow_height) and blend live.
	if "follow_height" in view:
		view.set("follow_height", 1.28)
	if "combat_hip_follow_height" in view:
		view.set("combat_hip_follow_height", 1.28)
	if view.has_method("set_combat_look"):
		view.call("set_combat_look", true)
	elif "combat_look" in view:
		view.set("combat_look", true)


# Match showcase capsule radius; keep floor plant near y=0 (height/2 center).
func _tune_mixamo_capsule() -> void:
	var col: CollisionShape3D = get_node_or_null("Collider") as CollisionShape3D
	if col == null or not (col.shape is CapsuleShape3D):
		return
	var src: CapsuleShape3D = col.shape as CapsuleShape3D
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = src.height if src.height > 0.0 else 1.5
	col.shape = cap
	col.position.y = cap.height * 0.5


# Mint Eli from data/mint/characters.json — loco via set_move_blend, combat via
# MintHeldWeapon. Inventory gear still uses EquipmentMount on the same skeleton.
func _setup_mint_avatar() -> void:
	if _model == null:
		return
	for c in _model.get_children():
		_model.remove_child(c)
		c.queue_free()
	_model.transform = Transform3D.IDENTITY
	_mint = _MINT_CHARACTER.load_profile("eli") as Node3D
	if _mint == null:
		push_warning("Player: Mint Eli failed to load — falling back to modular")
		_setup_modular_avatar()
		return
	_mint.rotation.y = PI
	_model.add_child(_mint)
	_mc = null
	_animation = null
	if _mint.has_method("equip_weapon"):
		_mint.call("equip_weapon", "sidearm")


# Replace the kit chibi (eli.glb mini at 1.6x) with the Quaternius modular
# body every other character already uses: stubby build + red tee on the
# ship (profile-driven), fatigues on missions via set_dress_context().
func _setup_modular_avatar() -> void:
	if _model == null or not _CHARACTER_FACTORY.profile_for("Eli").has("mod"):
		return
	for c in _model.get_children():
		_model.remove_child(c)
		c.queue_free()
	# The kit wrapper bakes a 1.6x chibi scale + 180° flip; the modular body
	# is real-scale and supplies its own flip.
	_model.transform = Transform3D.IDENTITY
	_mc = _CHARACTER_FACTORY.build_modular("Eli")
	_mc.rotation.y = PI
	_model.add_child(_mc)
	_CHARACTER_FACTORY.dress_modular(_mc, "Eli", _CHARACTER_FACTORY.CTX_SHIP)
	_animation = _find_animation_player(_model)


# Re-dress the avatar for a context ("ship"/"mission"). Planet scenes push
# "mission" after placing the player, so Eli wears fatigues off-ship.
# Mint wardrobe is not wired yet — no-op when on Mint/Mixamo avatar.
func set_dress_context(context: String) -> void:
	if _mint != null or _mixamo != null:
		return
	if _mc != null:
		_CHARACTER_FACTORY.dress_modular(_mc, "Eli", context)

func _setup_equipment_mount() -> void:
	if _model == null:
		return
	var mount: Node3D = _EQUIPMENT_MOUNT_SCRIPT.new()
	mount.name = "EquipmentMount"
	var inv: Node = get_tree().root.get_node_or_null("Inventory") if get_tree() != null else null
	mount.call("setup", _model, inv)
	# Parent under the model wrapper so fallback offset nodes ride the body and
	# the mount can locate the skeleton. add_child triggers the mount's _ready,
	# which does the first reconcile against the current loadout.
	_model.add_child(mount)
	_equipment_mount = mount

func _apply_colormap(root: Node) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, _COLORMAP_MAT)
	for c in root.get_children():
		_apply_colormap(c)

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var found: AnimationPlayer = _find_animation_player(c)
		if found != null:
			return found
	return null

func _physics_process(delta: float) -> void:
	if _cinematic_dash:
		_drive_cinematic_dash(delta)
		return
	if _auto_walking:
		_drive_auto_walk(delta)
		return
	if _input_locked:
		_apply_idle(delta)
		return
	_handle_movement(delta)
	_handle_interact()

func _apply_idle(delta: float) -> void:
	_move_velocity = Vector3.ZERO
	_apply_gravity(delta)
	velocity = Vector3(0.0, -_gravity_velocity, 0.0)
	move_and_slide()
	# A pose override (e.g. "holding-both" while piloting the Kino) takes the
	# place of plain idle. Driven every frame so the locomotion logic can't
	# stomp it back to "idle".
	if _mint != null:
		_drive_mint_locomotion(0.0)
	elif _mixamo != null:
		_drive_mixamo_locomotion(0.0, false)
	else:
		_play_anim(_pose_override if _pose_override != "" else "idle", 0.15)

func _handle_movement(delta: float) -> void:
	# Camera-relative input.
	var input_vec: Vector3 = Vector3.ZERO
	input_vec.x = Input.get_axis("move_left", "move_right")
	input_vec.z = Input.get_axis("move_forward", "move_back")
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	if view != null:
		input_vec = input_vec.rotated(Vector3.UP, view.rotation.y)

	_poll_mixamo_combat_input()

	var target_speed: float = walk_speed
	if _mixamo != null:
		# Showcase-scale loco; walk_speed export stays for Mint/modular.
		target_speed = 3.2
	if Input.is_action_pressed("sprint") and not _mixamo_aiming:
		target_speed *= (1.8 if _mixamo != null else sprint_multiplier)
	elif _mixamo_aiming:
		# Showcase: slightly slower while aiming on the move.
		target_speed = 3.2 * (1.15 if Input.is_action_pressed("sprint") else 0.9)

	var target_velocity: Vector3 = input_vec * target_speed
	_move_velocity = _move_velocity.lerp(target_velocity, accel_smoothing * delta)

	_apply_gravity(delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		_gravity_velocity = -jump_strength
		_mint_jump_requested = true
		Audio.play("res://sounds/jump.ogg")

	velocity = Vector3(_move_velocity.x, -_gravity_velocity, _move_velocity.z)
	move_and_slide()

	# Face direction of motion (or camera yaw when standing still / aiming).
	# Negated atan2 args put body yaw in Godot's -Z-forward convention so the
	# body yaw at idle (= view yaw) matches the body yaw during forward motion.
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if _mixamo_aiming and view != null:
		_facing_yaw = view.rotation.y
	elif horiz_speed > 0.2:
		_facing_yaw = atan2(-velocity.x, -velocity.z)
	elif view != null:
		_facing_yaw = view.rotation.y
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 12.0)

	_drive_locomotion_anim()
	_update_footsteps(delta)
	if _mixamo != null and _mixamo_aiming and _mixamo_want_fire:
		_mixamo.call("try_fire", _interact_camera())
	_refresh_target_lock(delta)
	_update_aim_crosshair()
	_update_combat_camera_aim()
	_update_lock_ui()


func _refresh_target_lock(_delta: float) -> void:
	if _lock_target == null:
		return
	if not is_instance_valid(_lock_target) or not _lock_target_alive(_lock_target):
		clear_target_lock()
		return
	# Keep body facing the lock while aiming.
	if _mixamo_aiming and view != null:
		var aim: Vector3 = get_lock_aim_point()
		var flat: Vector3 = aim - global_position
		flat.y = 0.0
		if flat.length_squared() > 0.01:
			_facing_yaw = atan2(-flat.x, -flat.z)

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_gravity_velocity = max(_gravity_velocity, 0.0)
	else:
		_gravity_velocity += gravity_strength * delta

func _drive_locomotion_anim() -> void:
	_particles_trail.emitting = false
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if _mixamo != null:
		_drive_mixamo_locomotion(horiz_speed, Input.is_action_pressed("sprint"))
		return
	if _mint != null:
		_drive_mint_locomotion(horiz_speed)
		return
	if is_on_floor():
		if horiz_speed > 0.25:
			var is_sprinting: bool = horiz_speed > walk_speed * 1.15
			_play_anim("sprint" if is_sprinting else "walk", 0.1)
			# Sprint clip is already fast; only scale walk by speed ratio.
			var pitch_ratio: float = clampf(horiz_speed / walk_speed, 0.4, sprint_multiplier)
			if _animation != null:
				_animation.speed_scale = 1.0 if is_sprinting else pitch_ratio
			if pitch_ratio > 1.2:
				_particles_trail.emitting = true
		else:
			_play_anim("idle", 0.1)
			if _animation != null:
				_animation.speed_scale = 1.0
	else:
		# Rising → jump clip; descending → fall clip (graceful fallback to jump
		# if the model only has one airborne anim).
		var airborne_anim: String = "jump" if _gravity_velocity < 0.0 else "fall"
		_play_anim(airborne_anim, 0.1)
		if _animation != null:
			_animation.speed_scale = 1.0


func _poll_mixamo_combat_input() -> void:
	var was_aiming: bool = _mixamo_aiming
	if _mixamo == null or _input_locked:
		_mixamo_aiming = false
		_mixamo_want_fire = false
		if was_aiming:
			_refresh_combat_music()
		return
	if _mixamo_tool_use_active():
		_mixamo_aiming = false
		_mixamo_want_fire = false
		if was_aiming:
			_refresh_combat_music()
		return
	if _demo_combat_override:
		_mixamo_aiming = _demo_aim
		_mixamo_want_fire = _demo_fire and _demo_aim
		if _mixamo_aiming != was_aiming:
			_refresh_combat_music()
		return
	# Aim/fire only while the sidearm (or other weapon) is the active hotbar item.
	var inv: Node = get_node_or_null("/root/Inventory")
	var wield_id: String = String(inv.call("active_wield_id")) if inv != null else ""
	var weapon_ready: bool = inv != null and bool(inv.call("is_weapon", wield_id))
	if not weapon_ready:
		_mixamo_aiming = false
		_mixamo_want_fire = false
		if was_aiming:
			_refresh_combat_music()
		return
	_mixamo_aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_mixamo_want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _mixamo_aiming
	if _mixamo_aiming != was_aiming:
		_refresh_combat_music()


## Capture / Movie Maker: force RMB-aim / LMB-fire without OS mouse state.
func set_demo_combat(aiming: bool, firing: bool = false) -> void:
	_demo_combat_override = true
	_demo_aim = aiming
	_demo_fire = firing and aiming
	_mixamo_aiming = aiming
	_mixamo_want_fire = firing and aiming
	_refresh_combat_music()


func clear_demo_combat() -> void:
	_demo_combat_override = false
	_demo_aim = false
	_demo_fire = false
	_mixamo_aiming = false
	_mixamo_want_fire = false
	_refresh_combat_music()


func _mixamo_tool_use_active() -> bool:
	return (
		_mixamo != null
		and _mixamo.has_method("is_tool_use_active")
		and bool(_mixamo.call("is_tool_use_active"))
	)


## Holster + play Digging/Working clip when present; otherwise idle + HUD stub.
## Optional duration auto-calls end_tool_use() (used by salvage/repair interact).
func begin_tool_use(kind: String = "repair", duration: float = 0.0) -> void:
	if _mixamo == null:
		return
	_tool_use_token += 1
	var token: int = _tool_use_token
	_mixamo_aiming = false
	_mixamo_want_fire = false
	if _mixamo.has_method("begin_tool_use"):
		_mixamo.call("begin_tool_use", kind)
	_update_tool_use_hud()
	_update_aim_crosshair()
	_update_combat_camera_aim()
	if duration > 0.0 and get_tree() != null:
		get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if token == _tool_use_token:
					end_tool_use(),
			CONNECT_ONE_SHOT
		)


func end_tool_use() -> void:
	if _mixamo == null:
		return
	_tool_use_token += 1
	if _mixamo.has_method("end_tool_use"):
		_mixamo.call("end_tool_use")
	_update_tool_use_hud()
	_update_aim_crosshair()
	_update_combat_camera_aim()


func is_tool_use_active() -> bool:
	return _mixamo_tool_use_active()


func _drive_mixamo_locomotion(horiz_speed: float, sprinting: bool) -> void:
	if _mixamo == null:
		return
	var move_input := Vector2.ZERO
	move_input.x = Input.get_axis("move_left", "move_right")
	move_input.y = Input.get_axis("move_forward", "move_back")
	if move_input.length() > 1.0:
		move_input = move_input.normalized()
	# Map Godot move_forward (negative Z wish) to showcase-style Vector2 where
	# -Y is forward for clip selection / strafe side.
	var cam_yaw: float = view.rotation.y if view != null else rotation.y
	var delta: float = get_physics_process_delta_time()
	var tool_active: bool = _mixamo_tool_use_active()
	_mixamo.call(
		"tick",
		delta,
		_mixamo_aiming and _pose_override == "" and not tool_active,
		_mixamo_want_fire and _pose_override == "" and not tool_active,
		move_input,
		sprinting and not _mixamo_aiming and not tool_active,
		cam_yaw
	)
	if horiz_speed > walk_speed * 1.15 and not _mixamo_aiming and not tool_active:
		_particles_trail.emitting = true
	_update_tool_use_hud()


func _ensure_aim_crosshair() -> void:
	if _aim_cross != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "MixamoAimUI"
	layer.layer = 20
	add_child(layer)
	_aim_cross = Control.new()
	_aim_cross.name = "AimCross"
	_aim_cross.visible = false
	_aim_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aim_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_aim_cross)
	var h := ColorRect.new()
	h.color = Color(1.0, 0.85, 0.35, 0.9)
	h.size = Vector2(18, 2)
	h.position = Vector2(-9, -1)
	h.set_anchors_preset(Control.PRESET_CENTER)
	_aim_cross.add_child(h)
	var v := ColorRect.new()
	v.color = Color(1.0, 0.85, 0.35, 0.9)
	v.size = Vector2(2, 18)
	v.position = Vector2(-1, -9)
	v.set_anchors_preset(Control.PRESET_CENTER)
	_aim_cross.add_child(v)
	_ensure_tool_use_hud()
	_ensure_lock_ui()


func _ensure_lock_ui() -> void:
	if _aim_cross == null:
		return
	var layer: CanvasLayer = _aim_cross.get_parent() as CanvasLayer
	if layer == null:
		return
	if _lock_label == null:
		_lock_label = Label.new()
		_lock_label.name = "TargetLockLabel"
		_lock_label.text = "TARGET LOCK"
		_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lock_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_lock_label.offset_top = 48.0
		_lock_label.add_theme_font_size_override("font_size", 16)
		_lock_label.modulate = Color(1.0, 0.85, 0.35, 0.95)
		_lock_label.visible = false
		_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_lock_label)
	if _lock_ring == null:
		_lock_ring = Control.new()
		_lock_ring.name = "TargetLockRing"
		_lock_ring.size = Vector2(36, 36)
		_lock_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lock_ring.visible = false
		layer.add_child(_lock_ring)
		var h := ColorRect.new()
		h.color = Color(1.0, 0.85, 0.25, 0.95)
		h.size = Vector2(36, 2)
		h.position = Vector2(0, 17)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lock_ring.add_child(h)
		var vv := ColorRect.new()
		vv.color = Color(1.0, 0.85, 0.25, 0.95)
		vv.size = Vector2(2, 36)
		vv.position = Vector2(17, 0)
		vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lock_ring.add_child(vv)


func _ensure_tool_use_hud() -> void:
	if _tool_use_label != null:
		return
	var layer: CanvasLayer = _aim_cross.get_parent() as CanvasLayer if _aim_cross != null else null
	if layer == null:
		return
	_tool_use_label = Label.new()
	_tool_use_label.name = "ToolUsePrompt"
	_tool_use_label.text = "Working…"
	_tool_use_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tool_use_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tool_use_label.offset_top = 72.0
	_tool_use_label.add_theme_font_size_override("font_size", 18)
	_tool_use_label.modulate = Color(0.75, 0.92, 1.0, 0.95)
	_tool_use_label.visible = false
	_tool_use_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_tool_use_label)


func _update_tool_use_hud() -> void:
	if _tool_use_label == null:
		_ensure_tool_use_hud()
	if _tool_use_label == null or _mixamo == null:
		return
	var show_stub: bool = (
		_mixamo.has_method("is_tool_use_fallback")
		and bool(_mixamo.call("is_tool_use_fallback"))
	)
	_tool_use_label.visible = show_stub and not _input_locked


func _update_aim_crosshair() -> void:
	if _aim_cross == null:
		return
	_aim_cross.visible = _mixamo != null and _mixamo_aiming and not _input_locked


func _update_combat_camera_aim() -> void:
	if view == null or _mixamo == null:
		return
	var aiming: bool = _mixamo_aiming and not _input_locked
	var crouching: bool = (
		aiming
		and _mixamo.has_method("is_crouch_aiming")
		and bool(_mixamo.call("is_crouch_aiming"))
	)
	if view.has_method("set_combat_aiming"):
		view.call("set_combat_aiming", aiming, crouching)
	else:
		if "combat_aiming" in view:
			view.set("combat_aiming", aiming)
		if "combat_crouching" in view:
			view.set("combat_crouching", crouching)


func _drive_mint_locomotion(horiz_speed: float) -> void:
	if _pose_override != "":
		# Kino remote: hold a light aim pose instead of Modular "talk".
		_mint.call("set_move_blend", 0.0, 0.0)
		if _mint.has_method("exit_aim_stance"):
			_mint.call("exit_aim_stance")
		_mint.call("set_aim_blend", 0.35)
		return
	var drawn: bool = _mint.has_method("is_weapon_drawn") and bool(_mint.call("is_weapon_drawn"))
	if is_on_floor():
		if horiz_speed > 0.25:
			var is_sprinting: bool = horiz_speed > walk_speed * 1.15
			var moving: float = clampf(horiz_speed / walk_speed, 0.0, 1.0)
			var gait: float = 1.0 if is_sprinting else clampf((horiz_speed / walk_speed) * 0.55, 0.0, 0.55)
			# Moving aim: loco + arm aim overlay (not frozen stance).
			if _mint.has_method("exit_aim_stance"):
				_mint.call("exit_aim_stance")
			_mint.call("set_move_blend", moving, gait)
			_mint.call("set_aim_blend", 0.85 if drawn else 0.0)
			if is_sprinting:
				_particles_trail.emitting = true
		else:
			_mint.call("set_move_blend", 0.0, 0.0)
			# Stationary + drawn → lock a dedicated aim pose (no Idle fidget).
			if drawn and _mint.has_method("enter_aim_stance"):
				_mint.call("enter_aim_stance")
			elif not drawn:
				if _mint.has_method("exit_aim_stance"):
					_mint.call("exit_aim_stance")
				_mint.call("set_aim_blend", 0.0)
	else:
		if _mint.has_method("exit_aim_stance"):
			_mint.call("exit_aim_stance")
		_mint.call("set_move_blend", 0.0, 0.0)
		_mint.call("set_aim_blend", 0.85 if drawn else 0.0)
	if _mint_jump_requested:
		_mint_jump_requested = false
		if _mint.has_method("request_jump"):
			_mint.call("request_jump")


# Capture the authored footstep volume and default to the ship surface (metal).
# Ship scenes never override, so they always sound metal; the planet scene calls
# set_footstep_surface() with its biome surface once its spec is resolved.
func _init_footsteps() -> void:
	if _sound_footsteps != null:
		_footstep_base_volume_db = _sound_footsteps.volume_db
	set_footstep_surface(_FOOTSTEP_LIBRARY.DEFAULT_SURFACE)


# Switch the active footstep surface (sample set + per-surface volume). Public so
# the planet scene can push the biome's surface; falls back to metal for an
# unknown id. Volume = authored base + the surface's gain (soft ground = quieter).
func set_footstep_surface(surface_id: String) -> void:
	_footstep_surface = surface_id if _FOOTSTEP_LIBRARY.has_surface(surface_id) else _FOOTSTEP_LIBRARY.DEFAULT_SURFACE
	_footstep_streams = _FOOTSTEP_LIBRARY.load_streams(_footstep_surface)
	if _sound_footsteps != null:
		_sound_footsteps.volume_db = _footstep_base_volume_db + _FOOTSTEP_LIBRARY.gain_db_for(_footstep_surface)


# Distance-based footstep cadence: accumulate horizontal travel and emit a
# random footstep sample every FOOTSTEP_STRIDE metres on the floor. Resets
# when airborne or stopped so the next stride starts fresh.
func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		_footstep_distance = 0.0
		return
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed < 0.5:
		_footstep_distance = 0.0
		return
	_footstep_distance += horiz_speed * delta
	if _footstep_distance >= FOOTSTEP_STRIDE:
		_footstep_distance -= FOOTSTEP_STRIDE
		_emit_footstep()


func _emit_footstep() -> void:
	if _footstep_streams.is_empty() or _sound_footsteps == null:
		return
	_sound_footsteps.stream = _footstep_streams[randi() % _footstep_streams.size()]
	_sound_footsteps.stream_paused = false
	_sound_footsteps.pitch_scale = randf_range(0.9, 1.1)
	_sound_footsteps.play()

func _play_anim(name: String, blend: float) -> void:
	if _mint != null or _mixamo != null:
		return
	if _animation == null:
		return
	if _mc != null:
		var clip: String = String(MODULAR_CLIP.get(name, name))
		if _animation.current_animation == "body/" + clip:
			return
		_mc.call("play_clip", clip, blend)
		return
	if not _animation.has_animation(name):
		return
	if _animation.current_animation == name:
		return
	_animation.play(name, blend)

func _handle_interact() -> void:
	var target: Node = _find_interact_target()
	if target != _current_interactable:
		_current_interactable = target
		interact_target_changed.emit(target)
	if target != null and Input.is_action_just_pressed("interact"):
		if target.has_method("interact"):
			target.interact(self)

func _find_interact_target() -> Node:
	var camera: Camera3D = _interact_camera()
	if camera == null:
		return null
	var origin: Vector3 = global_position + Vector3.UP * interact_origin_height
	# A clicked target wins while it's still valid + within the extended range.
	if _target_in_range(_clicked_target, origin, interact_reach_targeted):
		return _clicked_target
	_clicked_target = null
	# Otherwise pick the best in-range interactable in FRONT of the player.
	# Score = facing alignment minus a small distance penalty, with a big bonus
	# for the current quest target so the "diamond" NPC wins when two are close.
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return null
	forward = forward.normalized()
	var quest_anchor: String = _quest_anchor_name()
	var best: Node = null
	var best_score: float = -INF
	for node in get_tree().get_nodes_in_group("interactable"):
		var n3: Node3D = node as Node3D
		if n3 == null or not _interactable_enabled(n3):
			continue
		var to: Vector3 = n3.global_position - origin
		to.y = 0.0
		var dist: float = to.length()
		if dist > interact_reach or dist < 0.05:
			continue
		var aim: float = forward.dot(to / dist)
		if aim < interact_min_aim:
			continue
		var score: float = aim - dist * 0.05
		if quest_anchor != "" and n3.name == quest_anchor:
			score += 100.0
		if score > best_score:
			best_score = score
			best = n3
	return best


func _interact_camera() -> Camera3D:
	if view == null:
		return null
	var cam: Camera3D = view.get_node_or_null("SpringArm/Camera")
	if cam == null:
		cam = view.get_node_or_null("Camera")
	return cam


func _interactable_enabled(n: Node) -> bool:
	# Skip nodes disabled (e.g. Kino pickup after acquisition) so the HUD prompt
	# doesn't stick on a stale target.
	return not ("enabled" in n and not n.get("enabled"))


func _target_in_range(node: Node, origin: Vector3, reach: float) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_in_group("interactable"):
		return false
	if not _interactable_enabled(node):
		return false
	var n3: Node3D = node as Node3D
	if n3 == null:
		return false
	var flat: Vector3 = n3.global_position - origin
	flat.y = 0.0
	return flat.length() <= reach


# Node name of the current quest target's anchor (the "diamond" NPC/object), so
# the look-based pick can prefer it. Empty for sentinel anchors (e.g. nearest-
# console) which aren't real node names — those fall back to facing/nearest.
func _quest_anchor_name() -> String:
	if GameState == null or not GameState.has_method("quest_target"):
		return ""
	var t: Variant = GameState.call("quest_target")
	if t is Dictionary:
		return String((t as Dictionary).get("anchor", ""))
	return ""


# Click an interactable to select it (extends reach + makes the target obvious
# via the HUD prompt). Clicking empty space clears the selection.
func _try_click_target(screen_pos: Vector2) -> void:
	var camera: Camera3D = _interact_camera()
	if camera == null:
		return
	# Mouselook captures the cursor at screen centre — pick from there instead.
	var pos: Vector2 = screen_pos
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pos = get_viewport().get_visible_rect().size * 0.5
	var from: Vector3 = camera.project_ray_origin(pos)
	var dir: Vector3 = camera.project_ray_normal(pos)
	var to: Vector3 = from + dir * (interact_reach_targeted + 6.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self.get_rid()]
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = 4
	var hit: Dictionary = space.intersect_ray(params)
	var picked: Node = null
	if not hit.is_empty():
		var n: Node = hit.get("collider") as Node
		while n != null:
			if n.is_in_group("interactable"):
				picked = n
				break
			n = n.get_parent()
	var origin: Vector3 = global_position + Vector3.UP * interact_origin_height
	if picked != null and _target_in_range(picked, origin, interact_reach_targeted):
		_clicked_target = picked
	else:
		_clicked_target = null

func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	if locked:
		_move_velocity = Vector3.ZERO

# Override the locked-idle pose with a specific clip (""/empty restores idle).
func set_pose_override(anim: String) -> void:
	_pose_override = anim

# Drive the player toward a world-space target on a straight line. Locks input
# for the duration. Used by door transitions to sell "walked through the door"
# rather than fade-cutting between scenes. Emits `auto_walk_finished` when the
# player arrives within `_auto_walk_arrive_dist` of the target.
func auto_walk_to(target_world_pos: Vector3, speed: float = 5.0) -> void:
	_auto_walk_target = Vector3(target_world_pos.x, global_position.y, target_world_pos.z)
	_auto_walk_speed = max(speed, 0.1)
	_auto_walking = true
	_input_locked = true

# Cinematic dash — collision-FREE sprint to a world point. For cutscenes only:
# the actor cannot snag on terrain/props (clipping off) and won't trip scene
# triggers (collision_layer cleared). Emits auto_walk_finished on arrival.
func cinematic_dash_to(target_world_pos: Vector3, speed: float = 12.0) -> void:
	_dash_target = target_world_pos
	_dash_speed = maxf(speed, 0.1)
	_cinematic_dash = true
	_auto_walking = false
	_input_locked = true
	collision_layer = 0          # don't trip Area triggers (e.g. the return gate)
	collision_mask = 0           # we move by position, not move_and_slide

func _drive_cinematic_dash(delta: float) -> void:
	var to_target: Vector3 = _dash_target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < _auto_walk_arrive_dist:
		_cinematic_dash = false
		_play_anim("idle", 0.1)
		auto_walk_finished.emit()
		return
	var dir: Vector3 = to_target.normalized()
	var np: Vector3 = global_position + dir * _dash_speed * delta
	np.y = _ground_y(np, global_position.y)
	global_position = np
	_facing_yaw = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 16.0)
	_play_anim("sprint", 0.1)
	if _animation != null:
		_animation.speed_scale = 1.0

# Ground height under `at` via a downward ray against the terrain (layer 1), so
# the dash follows hills instead of clipping through or floating over them.
func _ground_y(at: Vector3, fallback: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return fallback
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(at.x, at.y + 30.0, at.z), Vector3(at.x, at.y - 80.0, at.z), 1)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.has("position"):
		return (hit["position"] as Vector3).y
	return fallback

func _drive_auto_walk(delta: float) -> void:
	var to_target: Vector3 = _auto_walk_target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < _auto_walk_arrive_dist:
		_auto_walking = false
		_input_locked = false
		_move_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		_apply_gravity(delta)
		move_and_slide()
		_play_anim("idle", 0.1)
		auto_walk_finished.emit()
		return
	var dir: Vector3 = to_target.normalized()
	_move_velocity = dir * _auto_walk_speed
	_facing_yaw = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, _facing_yaw, delta * 16.0)
	_apply_gravity(delta)
	velocity = Vector3(_move_velocity.x, -_gravity_velocity, _move_velocity.z)
	move_and_slide()
	_play_anim("walk", 0.1)
	if _animation != null:
		_animation.speed_scale = 1.0
	_update_footsteps(delta)
