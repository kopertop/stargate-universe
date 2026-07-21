"""Start BlenderMCP server after Blender GUI is ready."""
import bpy
import addon_utils

ADDON = "blender_mcp"

def _ensure_addon() -> None:
	enabled = {m.__name__ for m in addon_utils.modules() if addon_utils.check(m.__name__)[0]}
	# Prefer enabling via preferences API
	try:
		bpy.ops.preferences.addon_enable(module=ADDON)
		print("[blender_start_mcp] enabled", ADDON)
	except Exception as e:
		print("[blender_start_mcp] enable failed:", e)

def _start_server() -> None:
	try:
		# Prefer operator if registered
		if hasattr(bpy.ops, "blendermcp") and hasattr(bpy.ops.blendermcp, "start_server"):
			bpy.ops.blendermcp.start_server()
			print("[blender_start_mcp] start_server operator OK")
			return
	except Exception as e:
		print("[blender_start_mcp] operator failed:", e)
	# Fallback: construct server directly from imported module
	try:
		import blender_mcp as mod
		if not hasattr(bpy.types, "blendermcp_server") or not bpy.types.blendermcp_server:
			bpy.types.blendermcp_server = mod.BlenderMCPServer(port=9876)
		if not bpy.types.blendermcp_server.running:
			bpy.types.blendermcp_server.start()
		print("[blender_start_mcp] direct start, running=", bpy.types.blendermcp_server.running)
	except Exception as e:
		print("[blender_start_mcp] direct start failed:", e)

def _run() -> float | None:
	_ensure_addon()
	_start_server()
	return None  # unregister timer

# Delay until window/context exists
bpy.app.timers.register(_run, first_interval=1.0)
print("[blender_start_mcp] timer registered")
