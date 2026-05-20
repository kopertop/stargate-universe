extends Node3D

# Hull-breach compartment. Drains oxygen on a timer until the wall switch is
# engaged. Provides ambient leak SFX + a strobing red emergency light.

@export var breach_id: String = "breach_a"
@export var oxygen_drain_per_second: float = 6.0
@export var alarm_node_path: NodePath
@export var vent_particles_path: NodePath

var _sealed: bool = false
var _alarm: Light3D
var _vent: GPUParticles3D
var _t: float = 0.0

func _ready() -> void:
	GameState.discover_room("hull_breach", "Hull Breach — Compartment 14B")
	if not GameState.kino_acquired:
		GameState.set_objective("Acquire the Kino Remote before exploring further")
	else:
		GameState.set_objective("Engage the emergency seal to stop the leak")
	if GameState.breaches_sealed.has(breach_id):
		_sealed = true
	if not alarm_node_path.is_empty():
		_alarm = get_node_or_null(alarm_node_path) as Light3D
	if not vent_particles_path.is_empty():
		_vent = get_node_or_null(vent_particles_path) as GPUParticles3D
	if _vent != null:
		_vent.emitting = not _sealed
	GameState.episode_completed.connect(_on_episode_complete)

func _process(delta: float) -> void:
	if _sealed:
		if _alarm != null:
			_alarm.light_energy = lerpf(_alarm.light_energy, 0.0, delta * 3.0)
		return
	_t += delta
	GameState.consume_oxygen(oxygen_drain_per_second * delta)
	# Strobe alarm.
	if _alarm != null:
		_alarm.light_energy = 1.5 + sin(_t * 6.0) * 1.5
	# Recheck whether breach was sealed (the switch may have flipped state).
	if GameState.breaches_sealed.has(breach_id):
		_sealed = true
		if _vent != null:
			_vent.emitting = false
		GameState.add_log("Compartment 14B pressurized. Oxygen returning.")

func _on_episode_complete() -> void:
	# Stop strobing once the player has reached the wrap-up.
	if _alarm != null:
		_alarm.light_energy = 0.0
