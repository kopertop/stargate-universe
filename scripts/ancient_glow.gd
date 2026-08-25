class_name AncientGlow
extends Node

# Reusable pulsing emissive system for Ancient-tech surfaces. Attach as a
# child of any Node3D that owns emissive MeshInstance3D(s) — corridor sconces,
# control-room pillar rings, console screens, wall bands, door-arch runes.
#
# Drives emission_energy_multiplier on the target material(s) in _process.
# Does NOT create or own the materials — it grabs them from the parent's
# MeshInstance3D children at _ready, preserving the material setup convention
# in room_builder.gd (each accent creates its own _emissive_mat instance).
#
# Alert integration: when the ShipAlert autoload says alert is active, the
# pulse speeds up and the emission color shifts toward red. When blackout
# fires (parent sets meta "blackout_active"), glow dims to 5% and stops.
#
# Usage from room_builder.gd:
#   var glow := AncientGlow.new()
#   glow.pulse_amplitude = 0.10
#   glow.pulse_period = 2.5
#   glow.pulse_color = palette["accent"]
#   parent.add_child(glow)
#   glow.acquire_targets(parent)  # scans for emissive MeshInstance3D children

# --- Parameters (set before acquire_targets or at any time) --------------

## How much the glow varies from baseline (0 = steady, 1 = full off→on).
@export var pulse_amplitude: float = 0.15

## Full pulse cycle duration in seconds.
@export var pulse_period: float = 3.0

## Base emission color when not in alert state.
@export var pulse_color: Color = Color(0.3, 0.65, 1.0)

## Random flicker mode (damaged tech) instead of smooth sine pulse.
@export var flicker: bool = false

## Per-frame probability of a flicker spike (only when flicker=true).
@export var flicker_probability: float = 0.02

## If true, all MeshInstance3D children of the parent pulse in sync (same phase).
## If false, each target gets a random phase offset for organic variation.
@export var synchronized: bool = false

# --- Internal state --------------------------------------------------------

# Each entry: [material, base_energy, phase_offset]
var _targets: Array = []
var _time: float = 0.0
var _alert_active: bool = false
var _blackout: bool = false
# Cached originals so alert→normal transition can restore without re-reading.
var _orig_emissions: Dictionary = {}

# ShipAlert preload — same convention as room.gd / gate_room.gd: preload
# instead of class_name to survive headless `-s` runs where registration lags.
const ShipAlertScript: Script = preload("res://scripts/ship_alert.gd")


func _ready() -> void:
	set_process(true)
	# Check alert state on enter; updated in _process for live transitions.
	_check_alert()


func _process(delta: float) -> void:
	_time += delta
	_check_alert()
	_blackout = get_parent().has_meta("blackout_active") and get_parent().get_meta("blackout_active")

	if _targets.is_empty():
		return

	if _blackout:
		# Blackout: dim to 5%, no pulse
		for entry in _targets:
			var mat: StandardMaterial3D = entry[0]
			if is_instance_valid(mat):
				mat.emission_energy_multiplier = entry[1] * 0.05
		return

	var period: float = pulse_period
	var color: Color = pulse_color

	if _alert_active:
		period *= 0.5  # pulse twice as fast when alert is active
		color = Color(1.0, 0.20, 0.15)

	for entry in _targets:
		var mat: StandardMaterial3D = entry[0]
		var base_energy: float = entry[1]
		var phase: float = entry[2]
		if not is_instance_valid(mat):
			continue

		var energy: float
		if flicker:
			# Random flicker: base + occasional spikes
			energy = base_energy
			if randf() < flicker_probability:
				energy *= randf_range(0.3, 1.5)
		else:
			# Smooth sine pulse: base ± amplitude * base * sin
			var phase_time: float = (_time / period + phase) * TAU
			var pulse_val: float = sin(phase_time)
			energy = base_energy * (1.0 + pulse_amplitude * pulse_val)
			energy = maxf(0.0, energy)

		mat.emission_energy_multiplier = energy

		# Color shift during alert
		if _alert_active and not mat.has_meta("glow_orig_emission"):
			mat.set_meta("glow_orig_emission", mat.emission)
		if _alert_active:
			mat.emission = (mat.emission as Color).lerp(color, 0.05)  # gradual shift
		elif mat.has_meta("glow_orig_emission"):
			mat.emission = mat.get_meta("glow_orig_emission")
			mat.remove_meta("glow_orig_emission")


# Scan the given root node for MeshInstance3D children with emissive
# StandardMaterial3D and register them as pulse targets. Call after the
# parent's geometry is built (e.g. after _accent_corridor returns).
func acquire_targets(root: Node) -> void:
	_targets.clear()
	_orig_emissions.clear()
	_scan_emissive(root, 0)


func _scan_emissive(node: Node, depth: int) -> void:
	if depth > 4:  # don't recurse forever into deeply nested scenes
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mat: Variant = mi.material_override
		if mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat
			if smat.emission_enabled:
				var phase: float = 0.0 if synchronized else randf()
				_targets.append([smat, smat.emission_energy_multiplier, phase])
	for c in node.get_children():
		_scan_emissive(c, depth + 1)


# Manually add a single material as a pulse target (for cases where the
# material is created separately from the scene tree, like _glow_mat in
# gate_room.gd).
func add_target(mat: StandardMaterial3D, phase: float = 0.0) -> void:
	if mat == null or not mat.emission_enabled:
		return
	_targets.append([mat, mat.emission_energy_multiplier, phase])


func _check_alert() -> void:
	var new_alert: bool = false
	# ShipAlert.is_alert_active() reads GameState which may not be available
	# in all contexts (e.g. headless tests). Guard with try/catch pattern.
	if GameState != null:
		new_alert = ShipAlertScript.is_alert_active()
	if new_alert != _alert_active:
		_alert_active = new_alert