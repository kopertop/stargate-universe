class_name PlanetTerrainSystem
extends RefCounted

# Camera-frustum-aware terrain generation within the Kino camera view range
# (issue #150). A pure helper layering OVER the existing PlanetChunkManager
# streaming + PlanetGenerator.height_at() global height field. It does NOT own
# the chunk meshes or collision — it computes which chunks SHOULD be loaded
# given a camera frustum + far plane, and the edge cases at the view limit.
#
# The existing PlanetChunkManager already streams a square window of chunks
# around the tracked body (view_radius Chebyshev distance). This system adds the
# CONSUMER-FACING queries a Kino recon / camera-driven surface needs:
#   * visible_chunk_coords()    — chunk coords inside the camera frustum AND
#                                  within the Kino far plane (no wasted mesh beyond
#                                  what the camera sees).
#   * frustum_aware_window()    — the full wanted set given a camera + body,
#                                  merging the tracked-body window with the
#                                  frustum window so the body always has ground.
#   * view_limit_edge_cases()   — handles the edge cases at the view limit:
#                                  far-plane clipping, behind-camera chunks,
#                                  degenerate frustums, and the "tracked body at
#                                  the edge of view" case where the body's own
#                                  window keeps ground under it even when the
#                                  camera looks away.
#
# Headless-safe: pure functions that take a frustum (Plane[6]) + transforms and
# return coord sets. No Godot node access required (no autoload lookups), so it
# works under a bare `-s` SceneTree script.

# The chunk side length (metres). Mirrors PlanetChunkManager.chunk_size so the
# coord math agrees. Kept as a const here so the helper is self-contained for
# tests; the live manager is the source of truth at runtime.
const CHUNK_SIZE: float = 64.0


# --- Frustum-aware chunk selection -------------------------------------------

# Return the set of chunk coords (Vector2i) that are BOTH inside the camera
# frustum AND within the Kino far plane from `camera_origin`. A chunk is
# "visible" when any of its four ground corners is inside all six frustum
# planes AND the nearest corner is within `far_plane`. This avoids building
# meshes the camera can't see (the wasteful ring behind the camera / off to the
# sides that a plain distance window would load).
#
# `frustum` is the 6 Plane array from Camera3D.get_frustum(). `far_plane` is the
# camera's far clip distance (the Kino recon cam far). `max_radius` caps the
# scan radius around the camera (chunks) so a degenerate/wide frustum can't
# iterate to infinity. Returns a Dictionary { "ix,iz": true } of wanted coords.
static func visible_chunk_coords(frustum: Array, camera_origin: Vector3,
		far_plane: float, max_radius: int = 16) -> Dictionary:
	var wanted: Dictionary = {}
	if frustum.size() < 6:
		return wanted
	var center: Vector2i = _chunk_coord(camera_origin)
	# Pre-compute the near plane distance so we reject chunks clearly behind the
	# camera without sampling all four corners.
	for dx in range(-max_radius, max_radius + 1):
		for dz in range(-max_radius, max_radius + 1):
			var coord: Vector2i = center + Vector2i(dx, dz)
			if _chunk_visible(coord, frustum, camera_origin, far_plane):
				wanted[_key(coord)] = true
	return wanted


# True when a chunk's ground footprint intersects the frustum AND is within the
# far plane. Samples the four ground corners at the global height field height
# (flat approx — height is gentle, so the corner is representative).
static func _chunk_visible(coord: Vector2i, frustum: Array,
		camera_origin: Vector3, far_plane: float) -> bool:
	var origin_x: float = float(coord.x) * CHUNK_SIZE
	var origin_z: float = float(coord.y) * CHUNK_SIZE
	var corners: Array = [
		Vector3(origin_x, 0.0, origin_z),
		Vector3(origin_x + CHUNK_SIZE, 0.0, origin_z),
		Vector3(origin_x + CHUNK_SIZE, 0.0, origin_z + CHUNK_SIZE),
		Vector3(origin_x, 0.0, origin_z + CHUNK_SIZE),
	]
	var nearest_dist: float = INF
	var any_inside: bool = false
	for c in corners:
		# Distance from camera to this corner (planar — height is noise-scale).
		var dist: float = _planar_dist(camera_origin, c)
		nearest_dist = min(nearest_dist, dist)
		if _point_in_frustum(c, frustum):
			any_inside = true
	# At least one corner inside the frustum AND the nearest corner within far.
	# The "nearest within far" guard rejects chunks entirely beyond the view
	# limit (the far plane clips them even if a corner passed the side planes).
	return any_inside and nearest_dist <= far_plane


# True when `point` is inside all 6 frustum planes (Godot Plane: the half-space
# where the plane's normal points AWAY from the visible volume, so inside means
# `plane.is_point_over()` is false for every plane — a point on the inside).
static func _point_in_frustum(point: Vector3, frustum: Array) -> bool:
	for plane in frustum:
		if not (plane is Plane):
			continue
		# Camera3D.get_frustum() planes face INWARD: a point inside is on the
		# negative side of each plane (distance <= 0). Use is_point_over() which
		# returns true for the OUTWARD side; inside = NOT over.
		if (plane as Plane).is_point_over(point):
			return false
	return true


# --- Tracked-body + frustum merge -------------------------------------------

# The wanted chunk set for a camera-driven recon: merge the frustum-visible
# window with a small guaranteed window around the tracked body, so the body
# always has ground under it even when the camera looks away (the body's own
# window is body-centric, not camera-centric). Returns the merged coord set.
#
# `body_pos` is the tracked body's world position; `body_radius` is the Chebyshev
# chunk radius to keep around the body (mirrors PlanetChunkManager.view_radius).
# `far_plane` is the Kino camera far clip. `max_radius` caps the frustum scan.
static func frustum_aware_window(frustum: Array, camera_origin: Vector3,
		far_plane: float, body_pos: Vector3,
		body_radius: int = 2, max_radius: int = 16) -> Dictionary:
	var wanted: Dictionary = visible_chunk_coords(frustum, camera_origin,
		far_plane, max_radius)
	var body_center: Vector2i = _chunk_coord(body_pos)
	for dx in range(-body_radius, body_radius + 1):
		for dz in range(-body_radius, body_radius + 1):
			wanted[_key(body_center + Vector2i(dx, dz))] = true
	return wanted


# --- View-limit edge cases --------------------------------------------------

# Edge cases at the view limit:
#   * Far-plane clipping: chunks beyond `far_plane` are rejected even if a corner
#     passed a side plane (handled in _chunk_visible via nearest_dist).
#   * Behind-camera: chunks behind the camera are rejected by the near frustum
#     plane (handled in _point_in_frustum).
#   * Degenerate frustum (fewer than 6 planes, or all planes zero): returns an
#     empty set so the caller falls back to the plain distance window.
#   * Tracked body at the view limit (camera looking away): the body_radius
#     window in frustum_aware_window() keeps ground under the body.
#
# This helper surfaces the far-plane rejection as a standalone predicate so the
# chunk manager / tests can ask "is this chunk beyond the view limit?" without
# running the full frustum scan.
static func chunk_beyond_view_limit(coord: Vector2i, camera_origin: Vector3,
		far_plane: float) -> bool:
	var origin_x: float = float(coord.x) * CHUNK_SIZE
	var origin_z: float = float(coord.y) * CHUNK_SIZE
	var corners: Array = [
		Vector3(origin_x, 0.0, origin_z),
		Vector3(origin_x + CHUNK_SIZE, 0.0, origin_z),
		Vector3(origin_x + CHUNK_SIZE, 0.0, origin_z + CHUNK_SIZE),
		Vector3(origin_x, 0.0, origin_z + CHUNK_SIZE),
	]
	var nearest: float = INF
	for c in corners:
		nearest = min(nearest, _planar_dist(camera_origin, c))
	return nearest > far_plane


# True when a frustum is degenerate (wrong size or all-zero planes). A
# degenerate frustum makes the visible scan meaningless; callers should fall
# back to a plain distance window.
static func is_frustum_degenerate(frustum: Array) -> bool:
	if frustum.size() < 6:
		return true
	for plane in frustum:
		if not (plane is Plane):
			return true
		var p: Plane = plane
		# A zero normal means the plane is uninitialized.
		if p.normal.length_squared() < 0.0001:
			return true
	return false


# --- Coord helpers ----------------------------------------------------------

static func _chunk_coord(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / CHUNK_SIZE)),
		int(floor(world_pos.z / CHUNK_SIZE))
	)


static func _key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


# Planar (XZ) distance — terrain height is noise-scale and doesn't affect
# whether a chunk is "in view".
static func _planar_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()