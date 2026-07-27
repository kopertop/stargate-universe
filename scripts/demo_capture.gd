extends Object

# Shared capture-mode helpers for Movie Maker / scripted demos.
# Avoids locking the host OS mouse while --write-movie or demo_capture is active.


static func is_demo_capture(tree: SceneTree = null) -> bool:
	if tree != null and tree.has_meta("demo_capture"):
		return true
	for arg in OS.get_cmdline_args():
		var s: String = str(arg)
		if s == "--write-movie" or s.begins_with("--write-movie="):
			return true
	for arg2 in OS.get_cmdline_user_args():
		var s2: String = str(arg2)
		if s2 == "--write-movie" or s2.begins_with("--write-movie="):
			return true
	return false
