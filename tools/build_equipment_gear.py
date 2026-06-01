"""Build first-pass equipment gear GLBs for the Kenney mini-character rig (#73).

The Kenney All-in-1 kit ships no modular character gear sized for the mini-char
rig, so these are SIMPLE PROCEDURAL PLACEHOLDERS authored in bone-local space to
fit the rig (model ~0.37 units tall; head bone y=0.343, torso bone y=0.176, root
y=0). Flagged for a later art pass. Each piece carries a single flat UV so the
mount's colormap override (models/characters/Textures/colormap.png) samples a
sensible palette swatch instead of a stray texel.

Run headless:
  blender --background --python tools/build_equipment_gear.py

Blender 5.1: do NOT pass the removed `export_colors` kwarg (see skill
blender5-gltf-export-api-changes).
"""

import bpy
import bmesh
import os
import math

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models", "equipment")

# UV swatch centers picked off models/characters/Textures/colormap.png (v=0 top).
UV = {
	"olive": (0.17, 0.62),    # military green column
	"tan": (0.80, 0.86),      # khaki / brown column (bottom-right)
	"charcoal": (0.05, 0.87), # dark grey (bottom-left)
	"black": (0.10, 0.90),    # near-black grey
}


def clear_scene():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
		for item in list(block):
			block.remove(item)


def flat_uv_material():
	mat = bpy.data.materials.new("gear_placeholder")
	mat.use_nodes = False
	mat.diffuse_color = (0.4, 0.4, 0.42, 1.0)
	return mat


def set_flat_uv(obj, uv):
	mesh = obj.data
	if not mesh.uv_layers:
		mesh.uv_layers.new(name="UVMap")
	uv_layer = mesh.uv_layers.active.data
	for loop in mesh.loops:
		uv_layer[loop.index].uv = uv


def finalize(obj, uv_key):
	# Recompute normals, assign material + flat UV, smooth-ish look.
	mesh = obj.data
	mesh.materials.clear()
	mesh.materials.append(flat_uv_material())
	set_flat_uv(obj, UV[uv_key])
	mesh.update()


def add_box(name, center, size):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = (size[0], size[1], size[2])
	bpy.ops.object.transform_apply(scale=True)
	return obj


def add_sphere(name, center, radius, cut_below=None):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=center)
	obj = bpy.context.active_object
	obj.name = name
	if cut_below is not None:
		# Flatten the bottom of the dome by clamping verts below cut_below.
		for v in obj.data.vertices:
			if v.co.z + center[2] < cut_below:
				v.co.z = cut_below - center[2]
	return obj


def join(objs, name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	obj = bpy.context.active_object
	obj.name = name
	return obj


def export(name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in bpy.data.objects:
		o.select_set(True)
	path = os.path.join(OUT_DIR, name + ".glb")
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format="GLB",
		use_selection=True,
		export_normals=True,
		export_texcoords=True,
		export_yup=True,
	)
	size = os.path.getsize(path)
	print("EXPORTED %s (%d bytes)" % (path, size))


# --- Gear pieces. Authored in bone-local space (Blender Z-up; export_yup maps
# Z->Y). The gear origin = the bone joint; geometry is built around it. ---------

def build_marine_helmet():
	clear_scene()
	# Head bone is at character head-center; cover from origin up + around.
	dome = add_sphere("dome", (0.0, 0.0, 0.04), 0.085, cut_below=-0.02)
	# Front brim / visor lip.
	brim = add_box("brim", (0.0, 0.06, 0.01), (0.16, 0.05, 0.03))
	obj = join([dome, brim], "marine_helmet")
	finalize(obj, "olive")
	export("marine_helmet")


def build_recon_cap():
	clear_scene()
	# Lower, softer than the helmet; a cap crown + a forward bill.
	crown = add_sphere("crown", (0.0, 0.0, 0.025), 0.07, cut_below=-0.005)
	bill = add_box("bill", (0.0, 0.075, -0.01), (0.13, 0.06, 0.018))
	obj = join([crown, bill], "recon_cap")
	finalize(obj, "tan")
	export("recon_cap")


def build_tac_vest():
	clear_scene()
	# Torso bone ~ spine base; vest shell wraps the chest above the bone.
	front = add_box("front", (0.0, 0.07, 0.075), (0.19, 0.06, 0.16))
	back = add_box("back", (0.0, -0.07, 0.075), (0.19, 0.05, 0.16))
	shoulderL = add_box("shL", (0.075, 0.0, 0.15), (0.05, 0.14, 0.04))
	shoulderR = add_box("shR", (-0.075, 0.0, 0.15), (0.05, 0.14, 0.04))
	# A magazine pouch to read as tactical.
	pouch = add_box("pouch", (0.0, 0.085, 0.03), (0.1, 0.04, 0.05))
	obj = join([front, back, shoulderL, shoulderR, pouch], "tac_vest")
	finalize(obj, "charcoal")
	export("tac_vest")


def build_field_backpack():
	clear_scene()
	# Mounted on the torso bone; geometry sits BEHIND the spine (-Y) so the
	# data-model attach_offset can stay ~zero at this scale.
	body = add_box("body", (0.0, -0.11, 0.07), (0.16, 0.09, 0.19))
	lid = add_box("lid", (0.0, -0.11, 0.18), (0.16, 0.085, 0.04))
	pocket = add_box("pocket", (0.0, -0.16, 0.04), (0.11, 0.04, 0.09))
	obj = join([body, lid, pocket], "field_backpack")
	finalize(obj, "tan")
	export("field_backpack")


def build_combat_boots():
	clear_scene()
	# Mounted on the root bone (floor). Two boots at the leg x-offsets (+-0.083).
	objs = []
	for i, x in enumerate((0.083, -0.083)):
		shaft = add_box("shaft%d" % i, (x, -0.005, 0.05), (0.06, 0.06, 0.1))
		foot = add_box("foot%d" % i, (x, 0.03, 0.015), (0.06, 0.12, 0.03))
		objs += [shaft, foot]
	obj = join(objs, "combat_boots")
	finalize(obj, "black")
	export("combat_boots")


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	build_marine_helmet()
	build_recon_cap()
	build_tac_vest()
	build_field_backpack()
	build_combat_boots()
	print("ALL GEAR BUILT")


main()
