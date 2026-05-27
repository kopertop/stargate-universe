class_name InfirmaryJames
extends Npc

# Lt James in the Infirmary: paces back and forth between Colonel Young's bed
# and her desk, facing her direction of travel. Pausing briefly at each end.
# Pacing halts while a conversation is open (the tree is paused, so _process
# doesn't run) and while she's turned to face the player mid-talk.

@export var pace_a: Vector3 = Vector3.ZERO
@export var pace_b: Vector3 = Vector3.ZERO
@export var pace_speed: float = 1.2
@export var pace_hold: float = 1.2

var _toward_b: bool = true
var _hold_t: float = 0.0

func _ready() -> void:
	super()
	set_process(true)

func _process(delta: float) -> void:
	if _facing_player:
		return
	# Pace points are assigned by room.gd right after spawn; until then (or if
	# never configured) there's nowhere to pace.
	if pace_a == Vector3.ZERO and pace_b == Vector3.ZERO:
		return
	var target: Vector3 = pace_b if _toward_b else pace_a
	var to: Vector3 = Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dist: float = to.length()
	if dist < 0.15:
		_hold_t += delta
		if _hold_t >= pace_hold:
			_toward_b = not _toward_b
			_hold_t = 0.0
		return
	global_position += to.normalized() * min(pace_speed * delta, dist)
	look_at(Vector3(target.x, global_position.y, target.z), Vector3.UP)
