class_name ControlConsole
extends Interactable

# Control Interface Room console. All four cardinal consoles are identical —
# they each open the shipwide control menu (Kino Remote panel: map, status,
# log, etc.). The consoles ARE the diegetic interface; the Kino Remote panel
# is the menu it brings up. Future content (open doors, route power, etc.)
# hangs off the same panel.
#
# Clipping convention matches gate_console.gd: collision_layer = 1 | 4 — layer
# 1 so the player capsule (mask = 1) can't walk through, layer 4 so the
# interact ray (mask = 4) still hits.

# RoomBuilder builds the console GLB at CONSOLE_SCALE = 2.2, giving a body
# AABB of roughly 1.76 m × 1.09 m × 1.17 m. The collider is set slightly
# inside that so the operator can stand right at the keyboard edge without
# being shoved. Centred so it spans y=0..1.1 — top of box sits at player
# chest height (interact ray origin) so E-prompts always register.
const COLLIDER_SIZE: Vector3 = Vector3(1.7, 1.1, 1.1)
const COLLIDER_Y: float = 0.55

func _ready() -> void:
	super()
	# Override Interactable's hard-set collision_layer = 4 so the player
	# capsule (mask = 1) also collides with the console body — without this
	# the player walks straight through.
	collision_layer = 1 | 4
	_ensure_collider()
	prompt = "Use control terminal"
	# Group membership lets room.gd's quest waypoint find the nearest console
	# to the player (all four are interchangeable objective targets).
	add_to_group("control_console")


# Build the collider in code if the scene didn't ship one. RoomBuilder spawns
# control consoles procedurally so they have no CollisionShape3D by default;
# guarding against duplicates lets a future scene-authored console keep its
# own shape without doubling up.
func _ensure_collider() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = COLLIDER_SIZE
	cs.shape = box
	cs.position = Vector3(0.0, COLLIDER_Y, 0.0)
	add_child(cs)


func _on_interact(_by: Node) -> void:
	GameState.add_log("Console: Ancient interface comes online.")

	# First post-crisis access runs the diagnostic (advances the quest to the
	# seal-breach objective) and downloads the affected section to the map.
	# The narrative — Scott flagging the door, the red-alert panic — is played
	# by the breach beat triggered below.
	var first_access: bool = (GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT)
	if first_access:
		GameState.diagnose_life_support()
		_reveal_route_to_quest_target()

	# Open the shipwide control menu in CONSOLE mode: force=true so it works
	# pre-Kino-pickup, console_mode=true so the map shows the full deck
	# schematic (not the handheld's fog-of-war). The menu surface is the
	# console's — we borrow the Kino Remote rendering pipeline.
	if KinoRemote.has_method("open_remote"):
		KinoRemote.call("open_remote", true, true)

	# First access during the crisis triggers the map-driven blocked-door
	# beat: Scott flags the LOCKED sealed section far to the north
	# (north_spur ↔ sealed_section_north); the player clicks it open on the
	# map (that section + its access corridor flood red), panics, clicks it
	# shut, then the jammed half-open door in the Damaged Section far to the
	# SOUTH (breached_section_south) is revealed pulsing red↔grey as the real
	# seal objective. Skipped under instant_mode (tests can't click) and once
	# the beat has already played.
	var sr: Node = get_node_or_null("/root/SceneRouter")
	var instant: bool = sr != null and sr.get("instant_mode")
	if first_access and not instant and not GameState.blocked_door_beat_done:
		if KinoRemote.has_method("begin_breach_beat"):
			KinoRemote.call("begin_breach_beat",
				"north_spur", "sealed_section_north", "breached_section_south",
				["sealed_section_north", "north_spur"])


# Discover every room between here and the active quest target so the map
# shows the full route (and the target room's amber highlight) — the
# console has the ship's own schematic, so it can reveal sections the
# player's handheld Kino hasn't physically scouted yet.
func _reveal_route_to_quest_target() -> void:
	var target: Dictionary = GameState.quest_target()
	var target_room: String = String(target.get("room", ""))
	if target_room == "":
		return
	var sl: Node = get_node_or_null("/root/ShipLayout")
	if sl == null:
		return
	var path: PackedStringArray = sl.call("path_through_rooms", GameState.current_room_id, target_room)
	for rid in path:
		GameState.discover_room(String(rid))
