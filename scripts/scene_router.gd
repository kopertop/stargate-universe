extends Node

# Cross-scene transition manager. Owns a fade-out CanvasLayer it parents to root
# at runtime, then deferred-loads the next scene. Places the player at a Marker3D
# named via metadata `spawn_point` if present.

signal scene_changed(scene_path: String)

const FADE_DURATION: float = 0.45

# When true, skip the fade animation and switch scenes synchronously. Used by
# headless tests (Tween.finished is unreliable across multiple back-to-back
# scene changes in headless mode) and available for any future fast-travel /
# instant-reload feature.
var instant_mode: bool = false

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _is_transitioning: bool = false
var _pending_spawn: String = ""

func _ready() -> void:
	_build_fade_layer()

func _build_fade_layer() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)

func change_to(scene_path: String, spawn_point: String = "") -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_pending_spawn = spawn_point
	await _fade_to(1.0)
	# Release mouse capture during transition so it doesn't carry over.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var err: int = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: failed to load %s (err %d)" % [scene_path, err])
		_is_transitioning = false
		await _fade_to(0.0)
		return
	# Wait one frame for the new scene to enter the tree.
	await get_tree().process_frame
	_place_player_at_spawn()
	scene_changed.emit(scene_path)
	await _fade_to(0.0)
	_is_transitioning = false

func _place_player_at_spawn() -> void:
	if _pending_spawn == "":
		return
	var tree: SceneTree = get_tree()
	var root: Node = tree.current_scene
	if root == null:
		return
	var marker: Node = _find_marker(root, _pending_spawn)
	if marker == null:
		return
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return
	(player as Node3D).global_transform = (marker as Node3D).global_transform

func _find_marker(node: Node, target_name: String) -> Node:
	if node.name == target_name and node is Marker3D:
		return node
	for c in node.get_children():
		var found: Node = _find_marker(c, target_name)
		if found != null:
			return found
	return null

func _fade_to(target_alpha: float) -> void:
	if instant_mode:
		_fade_rect.color.a = target_alpha
		return
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", target_alpha, FADE_DURATION)
	await tween.finished
