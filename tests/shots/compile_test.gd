extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Try to compile gate_room_hero.gd
	var script_path = "res://scripts/gate_room_hero.gd"
	print("Compiling: ", script_path)

	var err = ResourceLoader.load(script_path)
	if err is GDScript:
		print("SUCCESS: gate_room_hero.gd compiles without parse errors")
		quit(0)
	else:
		print("ERROR: Failed to load script - ", err)
		quit(1)