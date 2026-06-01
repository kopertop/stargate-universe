class_name HazardZone
extends Area3D

# Biome hazard volume (issue #88 — Jungle traps / hazardous flora).
#
# An Area3D that applies steady damage to the player while they stand inside it.
# Used by the Jungle biome's trap plants / hidden snares, but biome-agnostic: any
# generated planet can scatter these from its biome `hazard.traps` block.
#
# Rules (project: NO DEATH, NO STRANDING):
#   * While a body in group "player" overlaps, drains GameState.health at
#     `damage_per_second`, applied on a fixed TICK so the rate is independent of
#     frame time and headless-testable.
#   * The FIRST tick of damage that would drop health to 0 routes through
#     GameState.knock_out(cause) — the no-death knockout → med-bay recovery loop
#     (issue #92) — never a death/game-over. `cause` defaults to "trap".
#   * Telegraphed FAIRLY: each zone carries a subtly-different "tell" — a tinted
#     flora cluster + (live only) a soft rustle SFX when the player enters — so a
#     careful player can read the danger. `telegraph` exposes the tell for tests.
#
# Composition: PlanetGenerator builds the visual flora + this Area3D together and
# seats them flush on the terrain. Density/strength are data-driven from the
# biome's `hazard.traps` block (tunable per spec — acceptance: hazard density
# tunable from data).
#
# Headless: the damage tick runs in _physics_process via get_overlapping_bodies()
# so a test can position a player body in the volume and pump physics frames (or
# call apply_tick() directly) without needing the body_entered signal to fire.

@export var damage_per_second: float = 12.0
@export var cause: String = "trap"
@export var tick_interval: float = 0.5
@export var telegraph: String = "rustling vines"

# Reuse an existing kit SFX for the snare/vine tell — no new asset (which would
# silently no-op without an .import sidecar). `break.ogg` reads as a snapping vine.
const RUSTLE_SFX: String = "res://sounds/break.ogg"

var _tick_t: float = 0.0
var _player_inside: bool = false

func _ready() -> void:
	add_to_group("hazard_zone")
	# Detect the player body (layer 1) only; never the camera/interact layers.
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if not _has_player_overlap():
		_player_inside = false
		_tick_t = 0.0
		return
	_player_inside = true
	_tick_t += delta
	while _tick_t >= tick_interval:
		_tick_t -= tick_interval
		apply_tick()


# Apply one tick's worth of damage and, if it floors the player, route the
# no-death knockout. Pulled out of _physics_process so tests can drive it
# directly without pumping physics frames. Returns true if the tick fired a
# knockout (the run ends, the volume goes quiet).
func apply_tick() -> bool:
	var gs: Node = _game_state()
	if gs == null:
		return false
	var dmg: float = damage_per_second * tick_interval
	gs.call("damage", dmg)
	if float(gs.get("health")) <= 0.0:
		gs.call("knock_out", cause)
		# The run is over — stop ticking until the player returns/respawns.
		_player_inside = false
		_tick_t = 0.0
		return true
	return false


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	# Telegraph the tell on entry (live only — headless must stay silent + sync).
	if not Engine.is_editor_hint():
		_play_rustle()


func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_inside = false
		_tick_t = 0.0


func _has_player_overlap() -> bool:
	for b in get_overlapping_bodies():
		if b != null and b.is_in_group("player"):
			return true
	return false


func _play_rustle() -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	var audio: Node = loop.root.get_node_or_null("Audio")
	if audio != null and audio.has_method("play"):
		audio.call("play", RUSTLE_SFX)


func _game_state() -> Node:
	# Reach the GameState autoload via the SceneTree root. Use Engine.get_main_loop()
	# rather than an absolute get_node() path: under a bare `-s` SceneTree test (no
	# current_scene) absolute /root paths raise "outside the active scene tree", but
	# the autoload still lives on the main loop's root in BOTH contexts.
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("GameState")
