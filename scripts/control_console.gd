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
	# Diegetic boot sound — Ancient terminal waking up. Plays alongside the
	# menu_open chime when the Kino-Remote panel opens, layering the
	# "console powering on" feel underneath the UI chime.
	Audio.play("res://sounds/terminal_boot.ogg")
	# Advance any quest step that lives on a control console. Phase B+ will
	# layer in more (open-door buttons during red-alert beats, route-power
	# choices, etc.) — for now the access itself is the trigger.
	if GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
		GameState.diagnose_life_support()
	GameState.add_log("Console: Ancient interface comes online.")
	# Open the shipwide control menu. force=true so consoles work even
	# before the Kino Remote pickup (the menu surface is the console's,
	# we're just borrowing the rendering pipeline that already exists).
	if KinoRemote.has_method("open_remote"):
		KinoRemote.call("open_remote", true)
