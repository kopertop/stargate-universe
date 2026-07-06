class_name Checkpoint
extends Area3D

# Checkpoint node (issue #83 — Save Profiles + Permanent Checkpoints).
#
# Drop one in any scene where the player should reach a save bookmark. When
# the on-foot player enters the checkpoint's trigger volume the node emits
# checkpoint_reached(slot_id) and asks SaveManager to write a permanent
# checkpoint into the configured slot (default slot_01). The checkpoint is
# idempotent for one trigger-area stay: re-entering after leaving re-arms it
# so a player who walks back through still produces a fresh save.
#
# The slot_id @export lets a designer bind a specific slot per checkpoint
# (e.g. the gate-room arrival → slot_01, the lime-planet gate → slot_02).
# SaveManager.autosave_checkpoint() is the no-op-when-empty guard — a
# checkpoint reached before the player exists / before a scene is staged
# simply doesn't write, matching the autosave rules in SaveManager.
#
# Headless / -s test harness: trigger() is a pure, signal-only entry point so
# a smoke test can fire a checkpoint without an Area3D body_entered pass
# (collision wiring only runs inside the active scene tree — same caveat as
# HazardZone / SensorZone). The trigger volume + collision is set up in
# _ready() and only matters for live play.

signal checkpoint_reached(slot_id: String)

# Which profile slot this checkpoint writes to. Defaults to slot_01 (the
# quick-save slot). Validate against SaveManager.PROFILE_SLOTS.
@export var slot_id: String = "slot_01"
# Optional human label stamped onto the checkpoint meta (e.g. "Gate Room
# Arrival"). Empty falls back to SaveManager's default per-slot label.
@export var label: String = ""
# When true the checkpoint fires ONCE per scene load and never re-arms (the
# classic one-shot checkpoint). Default false so a back-tracking player
# re-saves at the last checkpoint they crossed.
@export var one_shot: bool = false

# Per-stay latch so body_entered doesn't re-fire while the player is still
# standing inside the volume. Re-arms on body_exited unless one_shot.
var _triggered: bool = false
var _one_shot_fired: bool = false


func _ready() -> void:
	add_to_group("checkpoint")
	# Detect the player body (layer 1) only; never the camera/interact layers.
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	trigger()


func _on_body_exited(_body: Node) -> void:
	# Re-arm for the next stay unless this is a one-shot checkpoint.
	if not one_shot:
		_triggered = false


# Pure, signal-only trigger entry point. Fires checkpoint_reached and asks
# SaveManager to write the slot. Returns true the FIRST time it actually
# writes in this stay (so tests + live play share one code path). Returns
# false when: already triggered this stay, a one-shot already fired, the
# slot id is invalid, or SaveManager declines to write (no player / no scene).
func trigger() -> bool:
	if one_shot and _one_shot_fired:
		return false
	if _triggered:
		return false
	var sm: Node = _save_manager()
	if sm == null:
		return false
	if not sm.is_valid_profile_slot(slot_id):
		push_warning("Checkpoint: invalid slot_id '%s' on %s" % [slot_id, name])
		return false
	var ok: bool = sm.autosave_checkpoint(slot_id)
	if not ok:
		return false
	_triggered = true
	if one_shot:
		_one_shot_fired = true
	checkpoint_reached.emit(slot_id)
	return true


# Reach the SaveManager autoload via the SceneTree root (NOT a bare
# identifier — that fails to compile under -s; NOT /root get_node — that
# raises outside the active scene tree). Same pattern as SensorZone /
# GameState._autoload_node.
func _save_manager() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("SaveManager")