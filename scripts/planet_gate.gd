class_name PlanetGate
extends Area3D

# Stargate portal trigger. The visible ring is built separately; this Area3D
# owns the cross-scene travel rule for either ship->planet or planet->ship.

@export_enum("to_planet", "to_ship") var mode: String = "to_ship"
@export var target_scene: String = "res://scenes/gate_room.tscn"
@export var target_spawn: String = "FromGate"

var _transitioning: bool = false

# Arm-latch (mirrors the Kino path in kino_drone.gd::_try_gate_crossing): a player
# who SPAWNS already overlapping the gate's Area3D — e.g. landing on/near the
# destination gate after a crossing — must LEAVE the volume once before a crossing
# can fire. Without this, an open two-way gate would instantly bounce the player
# straight back through on arrival. The gate starts DISARMED and arms only once we
# confirm (after a physics frame) the player is NOT already inside it; a player
# standing in the volume at spawn keeps it disarmed until they walk out (body_exited)
# and back in. A first body_entered while disarmed only arms — it never crosses.
var _armed: bool = false

func _ready() -> void:
	add_to_group("planet_gate")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Arm once we confirm a clear spawn (player not overlapping). Deferred to the
	# next physics frame because the player rig is placed by SceneRouter in the same
	# frame the scene builds — get_overlapping_bodies() is empty before physics ticks.
	_arm_if_spawn_clear.call_deferred()

func _arm_if_spawn_clear() -> void:
	# Let the spawned player's transform sync into the physics server and Area3D
	# overlap detection report it (a single frame can resume before this frame's
	# collision pass populates overlaps — so settle a few frames first). Then arm
	# ONLY if the player is not standing in the volume; a player who spawned inside
	# stays disarmed until they walk out (body_exited re-arms). A genuine fresh
	# walk-in spawns clear, so this arms before they ever reach the gate.
	for _i in 4:
		if not is_inside_tree():
			return
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	if not _player_overlapping():
		_armed = true

func _player_overlapping() -> bool:
	for b in get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			return true
	return false

func activate(body: Node) -> void:
	# Explicit activation (e.g. a manual interact) bypasses the spawn-bounce latch.
	_armed = true
	await _travel(body)

func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if not _armed:
		# Contact while disarmed — this is the spawn-overlap body_entered (a player
		# placed inside the volume): do NOT cross and do NOT arm. Arming is owned by
		# leaving the volume (body_exited) or by _arm_if_spawn_clear confirming a
		# clear spawn; otherwise an open two-way gate would bounce the player home.
		return
	await _travel(body)

func _on_body_exited(body: Node) -> void:
	# Leaving the volume always arms the gate for the next genuine entry — this is
	# how a player who spawned inside (or just crossed and landed on the far gate)
	# becomes eligible to travel again.
	if body != null and body.is_in_group("player"):
		_armed = true

func _travel(body: Node) -> void:
	if _transitioning:
		return
	if body == null or not body.is_in_group("player"):
		return
	if mode == "to_planet":
		if not GameState.can_travel_to_lime_planet():
			GameState.add_log("The Stargate is not locked to the lime planet yet.")
			return
		_transitioning = true
		GameState.add_log("You step through the active Stargate to the lime planet.")
		await SceneRouter.change_to(target_scene, target_spawn)
		return
	if mode == "to_ship":
		if GameState.quest_step == GameState.QUEST_MINE_LIME and not GameState.has_resource(
				GameState.AIR_LIME_RESOURCE,
				GameState.AIR_LIME_REQUIRED
			):
			GameState.add_log("The planet gate is active, but leaving without enough lime will not fix the scrubber.")
			return
		_transitioning = true
		# The away team comes home WITH the player exactly ONCE — the first crossing
		# back. `return_from_lime_planet()` is the one-shot story latch (quest advance
		# + team-home); flag the return spawn only while that latch is still unset so
		# repeated solo crossings on an open gate don't re-muster / double-spawn crew.
		if not GameState.returned_from_lime_planet:
			# gate_room consumes this flag and lands the team past the platform
			# alongside the player.
			GameState.pending_planet_return = true
		GameState.return_from_lime_planet()
		await SceneRouter.change_to(target_scene, target_spawn)
