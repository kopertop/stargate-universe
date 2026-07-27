"""Decompress Draco/WebP glTF assets so Godot 4.6 can import them.

Godot's built-in glTF importer cannot decode KHR_draco_mesh_compression (it
produces empty surfaces -> runtime load() failures). Blender imports Draco +
WebP natively, so we round-trip each .glb through Blender and re-export it
uncompressed (Draco off by default; WebP textures convert to PNG via AUTO).

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/decompress_glb.py -- models/sci-fi/stargate-props

Overwrites the .glb files in place. Re-run `godot --headless --import` after.
"""
import bpy
import sys
import glob
import os

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
target_dir = argv[0] if argv else "models/sci-fi/stargate-props"

files = sorted(glob.glob(os.path.join(target_dir, "*.glb")))
print("DECOMPRESS_TARGETS", len(files))
for f in files:
	# Empty scene so successive imports don't accumulate geometry.
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=f)
	# Minimal export (Blender 5.1): no removed keywords, Draco off by default.
	bpy.ops.export_scene.gltf(
		filepath=f,
		export_format='GLB',
		export_normals=True,
		export_texcoords=True,
	)
	size = os.path.getsize(f)
	print("DECOMPRESSED", os.path.basename(f), size)
print("DECOMPRESS_DONE")
