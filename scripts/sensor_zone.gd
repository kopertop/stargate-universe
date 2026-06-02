class_name SensorZone
extends Area3D

# Alien-tech security sensor (issue #91 — Alien-tech biome traps/alarms to avoid).
#
# An Area3D trip-beam / pressure-plate / sensor-cone that the player must AVOID.
# Unlike the Jungle HazardZone (passive flora that hurts only while you stand in
# it), a SensorZone is a SECURITY TRIGGER: crossing it ONCE raises a persistent
# ALARM with an ESCALATING consequence — an alien defense locks down and the
# damage it deals ramps the longer the alarm stays up.
#
# Rules (project: NO DEATH, NO STRANDING):
#   * The player crossing the beam raises the alarm exactly once (trip()), even
#     if they back out — security has already noticed. Re-entry does NOT reset it.
#   * While the alarm is up, the active defense deals damage on a fixed TICK whose
#     strength ESCALATES each tick (base_damage_per_second * escalation^step,
#     clamped) so dawdling under an active alarm gets worse, not stable. The first
#     tick that would floor health routes GameState.knock_out(cause) — the no-death
#     knockout -> med-bay loop (issue #92). `cause` defaults to "alien_defense".
#   * Telegraphed FAIRLY: each sensor owns a VISIBLE emissive beam/cone mesh + a
#     warning strip so a careful player can read it and route around — avoidance is
#     skill, not luck. `telegraph` exposes the tell for tests.
#   * Reaching a goal WITHOUT crossing any sensor leaves alarm_raised false on
#     every zone — the stealth-reward path (a no-trip run yields a bonus elsewhere).
#
# Composition: PlanetGenerator builds the visual beam + this Area3D together and
# seats them flush on the terrain. Density/strength are data-driven from the
# biome's `hazard.sensors` block (tunable per spec).
#
# Headless: trip() and apply_tick() are pure, signal-free entry points so a test
# can raise the alarm and pump escalation without needing body_entered to fire
# (HazardZone._ready group/collision wiring only runs inside the active scene
# tree — feedback_godot_class_name_headless / feedback_godot_scenetree_script).

signal alarm_triggered(zone: SensorZone)

@export var base_damage_per_second: float = 10.0
@export var escalation: float = 1.5           # damage multiplier added per tick while armed
@export var max_damage_per_second: float = 60.0
@export var tick_interval: float = 0.5
@export var cause: String = "alien_defense"
@export var telegraph: String = "humming light-beam"

# Reuse an existing kit SFX as the alarm sting — no new asset (which would silently
# no-op without an .import sidecar). `coin.ogg` reads as an electronic alert chirp.
const ALARM_SFX: String = "res://sounds/coin.ogg"

# Whether this sensor's beam has been crossed and the alarm is up. Persistent for
# the run — security does not "un-notice" you. NOT acquisition vocabulary
# (no item/room set forks off it — it is a single per-zone latch).
var alarm_raised: bool = false
var _tick_t: float = 0.0
var _escalation_step: int = 0


func _ready() -> void:
	add_to_group("sensor_zone")
	# Detect the player body (layer 1) only; never the camera/interact layers.
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# Damage only accrues once the alarm is up — an untripped sensor is harmless,
	# so a careful player who routes around it takes nothing.
	if not alarm_raised:
		return
	_tick_t += delta
	while _tick_t >= tick_interval:
		_tick_t -= tick_interval
		apply_tick()


# Raise the alarm. Idempotent: re-crossing the beam does not re-arm or reset the
# escalation. Returns true the FIRST time it actually raises (so the generator /
# tests can react to the moment of tripping). Telegraphs the alert sting (live
# only — headless must stay silent + synchronous).
func trip() -> bool:
	if alarm_raised:
		return false
	alarm_raised = true
	_tick_t = 0.0
	_escalation_step = 0
	if not Engine.is_editor_hint():
		_play_alarm()
	alarm_triggered.emit(self)
	return true


# Current per-tick damage for the escalation step, ramped and clamped. Pure so a
# test can read the escalation curve without applying it.
func current_damage_per_second() -> float:
	var d: float = base_damage_per_second * pow(escalation, float(_escalation_step))
	return min(d, max_damage_per_second)


# Apply one escalating tick of alarm damage and, if it floors the player, route
# the no-death knockout. Pulled out of _physics_process so tests can drive it
# directly. Returns true if the tick fired a knockout (the run ends, alarm quiet).
# A no-op (returns false) when the alarm is not raised.
func apply_tick() -> bool:
	if not alarm_raised:
		return false
	var gs: Node = _game_state()
	if gs == null:
		return false
	var dmg: float = current_damage_per_second() * tick_interval
	_escalation_step += 1   # the NEXT tick hits harder — security is locking down
	gs.call("damage", dmg)
	if float(gs.get("health")) <= 0.0:
		gs.call("knock_out", cause)
		# The run is over — stop ticking until the player returns/respawns.
		alarm_raised = false
		_tick_t = 0.0
		_escalation_step = 0
		return true
	return false


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	trip()


func _play_alarm() -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	var audio: Node = loop.root.get_node_or_null("Audio")
	if audio != null and audio.has_method("play"):
		audio.call("play", ALARM_SFX)


func _game_state() -> Node:
	# Reach the GameState autoload via the SceneTree root (NOT a bare identifier —
	# that fails to compile under -s; NOT an absolute /root get_node — that raises
	# outside the active scene tree). The autoload lives on the main loop's root in
	# both live and headless contexts (feedback_godot_scenetree_script_gotchas).
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("GameState")
