class_name SharedMaterials
extends RefCounted

## Cached material factory for procedural geometry.
##
## Identical colour/metallic/roughness combos return the same
## StandardMaterial3D instance so the renderer can batch draw calls.
## Use the `_mutable` variants when the caller needs to tweak properties
## after creation (those return fresh copies and are NOT cached).


# --- flat (non-emissive) ------------------------------------------------------
static var _flat_cache: Dictionary = {}  # key -> StandardMaterial3D


static func get_flat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key: String = "flat_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f" % [
		col.r, col.g, col.b, col.a, metallic, roughness,
	]
	if _flat_cache.has(key):
		return _flat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = metallic
	mat.roughness = roughness
	mat.resource_local_to_scene = false
	_flat_cache[key] = mat
	return mat


# --- emissive (cached) --------------------------------------------------------
static var _emis_cache: Dictionary = {}  # key -> StandardMaterial3D


static func get_emis(
		col: Color,
		energy: float,
		metallic: float = 0.0,
		roughness: float = 0.0,
) -> StandardMaterial3D:
	var key: String = "emis_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f" % [
		col.r, col.g, col.b, col.a, energy, metallic, roughness,
	]
	if _emis_cache.has(key):
		return _emis_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.metallic = metallic
	mat.roughness = roughness
	mat.resource_local_to_scene = false
	_emis_cache[key] = mat
	return mat


# --- emissive (mutable, NOT cached) -------------------------------------------
static func get_emis_mutable(col: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.resource_local_to_scene = true
	return mat