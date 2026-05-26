class_name KinoMapView
extends Control

# Tiny Control subclass whose only job is to own the _draw() override for
# the Kino Remote's map page. Drawing must happen inside this node's _draw()
# (Godot 4 restricts draw_* calls to the canvas item's own draw context;
# external signal handlers can't call them reliably). This script simply
# forwards _draw() back to KinoRemote so the rendering logic stays
# co-located with the rest of the Kino UI.

signal needs_geometry(canvas: KinoMapView)

func _draw() -> void:
	# KinoRemote subscribes to needs_geometry and does all the actual
	# rendering with `canvas` as the draw target. Splitting the dispatcher
	# this way keeps the canvas-item context valid through every draw_*
	# call.
	needs_geometry.emit(self)
