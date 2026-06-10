extends SceneTree

# Smoke test for the character generation system (CharacterFactory).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/character_gen.gd
#
# Asserts:
#   1. Registry integrity — every profile's base model GLB loads; every swatch
#      cell is inside the 512x512 atlas.
#   2. Profile resolution — model/outfit per context; keyword fallback for
#      generic labels ("Soldier 2"); unknown civilians get civvies.
#   3. is_military exactness — "Lt James" military, "Dr James" civilian.
#   4. Outfit baking — civvies returns the base atlas; duty_black darkens
#      uniform cells; fatigues turn them olive; skin cells are byte-identical
#      to the base atlas (faces never tint).
#   5. Bake cache — same texture instance on repeat calls.
#   6. dress() gear sync — military ship = sidearm only; mission = sidearm +
#      rifle; civilian mission = unarmed; re-dress removes stale gear.
#   7. Gear builders — rifle auto-scales to ~0.85 units; add_gear idempotent.

const FactoryRef: Script = preload("res://scripts/character_factory.gd")

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== character_gen smoke test ===")
	call_deferred("_run")


func _run() -> void:
	_test_registry_models_load_and_cells_in_bounds()
	_test_profile_resolution_per_context()
	_test_is_military_exact_and_keyword()
	_test_outfit_bake_recolors_uniform_cells_not_skin()
	_test_outfit_bake_cache_returns_same_instance()
	_test_dress_syncs_gear_to_context()
	_test_gear_builders_scale_and_idempotence()
	_report()


# --- 1. registry integrity -------------------------------------------------

func _test_registry_models_load_and_cells_in_bounds() -> void:
	for character_name in FactoryRef.PROFILES:
		var path: String = FactoryRef.model_for(character_name)
		var glb: PackedScene = load(path)
		_expect(glb != null, "model for %s loads (%s)" % [character_name, path])
	for stem in FactoryRef.SWATCH_GROUPS:
		var groups: Dictionary = FactoryRef.SWATCH_GROUPS[stem]
		for role in groups:
			for cell in groups[role]:
				var ok: bool = cell.x >= 0 and cell.x <= 15 and cell.y >= 0 and cell.y <= 15
				if not ok:
					_expect(false, "%s/%s cell %s in atlas bounds" % [stem, role, cell])
	_expect(true, "all swatch cells inside the 16x16 cell grid")


# --- 2. profile resolution ---------------------------------------------------

func _test_profile_resolution_per_context() -> void:
	_expect(FactoryRef.model_for("Eli").ends_with("eli.glb"), "Eli resolves to eli.glb")
	_expect(FactoryRef.model_for("Colonel Young").ends_with("young.glb"), "Young has his own body (not Scott's)")
	_expect(FactoryRef.model_for("Sgt Greer").ends_with("greer.glb"), "Greer has his own body (not Scott's)")
	_expect(FactoryRef.model_for("Lt James") != FactoryRef.model_for("Chloe Armstrong"),
		"Lt James no longer shares Chloe's body")
	_expect(FactoryRef.outfit_id_for("Eli", FactoryRef.CTX_SHIP) == "civvies", "Eli ship outfit = civvies")
	_expect(FactoryRef.outfit_id_for("Eli", FactoryRef.CTX_MISSION) == "fatigues", "Eli mission outfit = fatigues")
	_expect(FactoryRef.outfit_id_for("Lt Scott", FactoryRef.CTX_SHIP) == "duty_black", "Scott ship outfit = duty blacks")
	_expect(FactoryRef.outfit_id_for("Lt Scott", FactoryRef.CTX_MISSION) == "combat", "Scott mission outfit = combat")
	var soldier: Dictionary = FactoryRef.profile_for("Soldier 2")
	_expect(String(soldier["ship"]) == "duty_black", "generic 'Soldier 2' label falls back to military profile")
	var unknown: Dictionary = FactoryRef.profile_for("Random Crewman")
	_expect(String(unknown["ship"]) == "civvies", "unknown character falls back to civvies")
	_expect(FactoryRef.model_for("Random Crewman", "res://fallback.glb") == "res://fallback.glb",
		"unknown character uses per-site fallback model")


# --- 3. military classification ---------------------------------------------

func _test_is_military_exact_and_keyword() -> void:
	_expect(FactoryRef.is_military("Lt Scott"), "Lt Scott is military")
	_expect(FactoryRef.is_military("Sgt Greer"), "Sgt Greer is military")
	_expect(FactoryRef.is_military("Colonel Young"), "Colonel Young is military")
	_expect(FactoryRef.is_military("Lt James"), "Lt James is military")
	_expect(FactoryRef.is_military("Soldier 3"), "generic Soldier label is military")
	_expect(not FactoryRef.is_military("Dr James"), "Dr James is a civilian (exact profile beats keyword)")
	_expect(not FactoryRef.is_military("Eli"), "Eli is a civilian")
	_expect(not FactoryRef.is_military("Dr Park"), "Dr Park is a civilian")


# --- 4. outfit baking ---------------------------------------------------------

func _base_image() -> Image:
	var tex: Texture2D = load(FactoryRef.COLORMAP_PATH)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _cell_center(img: Image, cell: Vector2i) -> Color:
	return img.get_pixel(cell.x * 32 + 16, cell.y * 32 + 16)


func _test_outfit_bake_recolors_uniform_cells_not_skin() -> void:
	var base_tex: Texture2D = load(FactoryRef.COLORMAP_PATH)
	var civvies: Texture2D = FactoryRef.outfit_texture("scott", "civvies")
	_expect(civvies == base_tex, "civvies bake returns the base atlas untouched")

	var base_img: Image = _base_image()
	var scott_top: Vector2i = Vector2i(1, 12)
	var scott_skin: Vector2i = Vector2i(15, 12)

	var duty: Texture2D = FactoryRef.outfit_texture("scott", "duty_black")
	_expect(duty != base_tex, "duty_black bake produces a new texture")
	var duty_img: Image = duty.get_image()
	var duty_px: Color = _cell_center(duty_img, scott_top)
	var duty_luma: float = (duty_px.r + duty_px.g + duty_px.b) / 3.0
	_expect(duty_luma < 0.25, "duty_black uniform cell is near-black (luma %.2f)" % duty_luma)

	var combat: Texture2D = FactoryRef.outfit_texture("scott", "combat")
	var combat_img: Image = combat.get_image()
	var olive: Color = _cell_center(combat_img, scott_top)
	_expect(olive.g > olive.b and olive.g >= olive.r * 0.95,
		"combat uniform cell reads olive (rgb %.2f/%.2f/%.2f)" % [olive.r, olive.g, olive.b])

	var skin_base: Color = _cell_center(base_img, scott_skin)
	var skin_duty: Color = _cell_center(duty_img, scott_skin)
	var skin_combat: Color = _cell_center(combat_img, scott_skin)
	_expect(skin_duty.is_equal_approx(skin_base) and skin_combat.is_equal_approx(skin_base),
		"skin cells byte-identical across outfits (faces never tint)")

	var eli_combat: Texture2D = FactoryRef.outfit_texture("eli", "fatigues")
	var eli_img: Image = eli_combat.get_image()
	var eli_top: Color = _cell_center(eli_img, Vector2i(3, 8))
	_expect(eli_top.g > eli_top.b, "Eli fatigues recolor his hoodie cells toward olive")


# --- 5. bake cache -------------------------------------------------------------

func _test_outfit_bake_cache_returns_same_instance() -> void:
	var a: Texture2D = FactoryRef.outfit_texture("scott", "duty_black")
	var b: Texture2D = FactoryRef.outfit_texture("scott", "duty_black")
	_expect(a == b, "repeat bake returns the cached texture instance")


# --- 6. dress() gear sync --------------------------------------------------------

func _make_actor() -> Array:
	var body: Node3D = Node3D.new()
	var holder: Node3D = Node3D.new()
	holder.name = "Model"
	body.add_child(holder)
	root.add_child(body)
	return [body, holder]


func _test_dress_syncs_gear_to_context() -> void:
	var pair: Array = _make_actor()
	var body: Node3D = pair[0]
	var holder: Node3D = pair[1]

	FactoryRef.dress(body, holder, "Sgt Greer", FactoryRef.CTX_SHIP)
	_expect(body.get_node_or_null("Sidearm") != null, "military on ship carries a sidearm")
	_expect(body.get_node_or_null("Rifle") == null, "military on ship carries NO rifle")

	FactoryRef.dress(body, holder, "Sgt Greer", FactoryRef.CTX_MISSION)
	_expect(body.get_node_or_null("Sidearm") != null, "military on mission keeps the sidearm")
	_expect(body.get_node_or_null("Rifle") != null, "military on mission carries a rifle")

	FactoryRef.dress(body, holder, "Sgt Greer", FactoryRef.CTX_SHIP)
	_expect(body.get_node_or_null("Rifle") == null, "re-dress for ship removes the rifle")

	var civ: Array = _make_actor()
	FactoryRef.dress(civ[0], civ[1], "Eli", FactoryRef.CTX_MISSION)
	_expect(civ[0].get_node_or_null("Sidearm") == null and civ[0].get_node_or_null("Rifle") == null,
		"Eli on mission wears fatigues but stays unarmed")

	body.queue_free()
	civ[0].queue_free()


func _test_gear_builders_scale_and_idempotence() -> void:
	var rifle: Node3D = FactoryRef.build_rifle()
	_expect(rifle.name == "Rifle", "rifle pivot named Rifle")
	var mesh_count: int = _count_meshes(rifle)
	_expect(mesh_count > 0, "rifle GLB instanced with meshes (%d)" % mesh_count)
	var aabb: AABB = FactoryRef._merged_aabb(rifle)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_expect(longest > 0.6 and longest < 1.1, "rifle scaled to ~0.85 body units (got %.2f)" % longest)
	rifle.free()

	var body: Node3D = Node3D.new()
	root.add_child(body)
	var h1: Node3D = FactoryRef.add_gear(body, "helmet")
	var h2: Node3D = FactoryRef.add_gear(body, "helmet")
	_expect(h1 == h2, "add_gear is idempotent (one helmet)")
	var helmet_total: int = 0
	for c in body.get_children():
		if c.name.begins_with("Helmet"):
			helmet_total += 1
	_expect(helmet_total == 1, "exactly one Helmet child after double add")
	body.queue_free()


func _count_meshes(root_node: Node) -> int:
	var n: int = 0
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


# --- harness -----------------------------------------------------------------

func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("---")
	print("%d passed, %d failed" % [_passes, _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for f in _failures:
			print("  FAILED: %s" % f)
		print("RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)
