extends Node

# NPC / crew builder module for the gate room. Extracted from gate_room.gd
# to decompose the god object. Added as a child Node by the main script and
# called via the host reference.
#
# Builds: Lt Scott (standing NPC), medic tableau (Young + James), Phase E
# crew (Brody, Rush, Park), away-team assembly + walkthrough, returned
# away team, crew nametag visibility, and Scott auto-greet control.

# Preloads that belong exclusively to the NPC/crew functions.
const NPC_SCRIPT: Script = preload("res://scripts/npc.gd")
const GREER_SCRIPT: Script = preload("res://scripts/greer.gd")
const CompanionScript: Script = preload("res://scripts/companion.gd")
const CharacterFactoryRef: Script = preload("res://scripts/character_factory.gd")

# Shared consts also defined on the orchestrator (kept here for local use).
const GATE_CONSOLE_Z: float = -4.0

# Host reference (the gate_room.gd Node3D). Set by the host before build calls.
var host: Node3D = null

# State vars that moved from the orchestrator (public, no underscore).
var gate_team: Array[Node3D] = []
var gate_player_locked: bool = false
var team_walkthrough_running: bool = false


# Called by the host to wire this module to the room node.
func setup(room: Node3D) -> void:
	host = room


# ──────────────────────────────────────────────────────────────────────────
# Crew visibility helpers
# ──────────────────────────────────────────────────────────────────────────

func set_arrival_crew_visible(vis: bool) -> void:
	var names: Array = ["LtScott", "ColonelYoung", "LtJames", "GateBrody", "GateRush", "GatePark"]
	for node_name in names:
		if vis and node_name == "LtScott":
			continue   # Scott is already positioned by Wave 1 — skip
		var n: Node = host._world.get_node_or_null(node_name)
		if n is Node3D:
			(n as Node3D).visible = vis


# Show/hide every crew nametag in the room at once. Used to strip floating UI
# labels for the duration of the cold-open cinematic and restore them at the
# hand-off (so gameplay can still ID Scott/Greer across the room).
func set_crew_nametags_visible(vis: bool) -> void:
	if host._world == null:
		return
	for tag in host._world.find_children("Nametag", "Label3D", true, false):
		if tag is Label3D:
			(tag as Label3D).visible = vis


# ──────────────────────────────────────────────────────────────────────────
# Scott auto-greet control
# ──────────────────────────────────────────────────────────────────────────

func set_scott_autogreet(on: bool) -> void:
	var scott: Node = host._world.get_node_or_null("LtScott")
	if scott == null:
		return
	if on:
		if not GameState.met_scott:
			# CRITICAL: disabling auto_greet earlier made npc._process turn ITSELF off
			# (`not auto_greet` → set_process(false)). Just flipping the flag back on
			# won't restart the walk — reset the greet state AND re-enable _process, or
			# Scott stands frozen and never comes over to brief the player.
			scott.set("auto_greet", true)
			scott.set("_auto_greet_done", false)
			scott.set("_auto_greet_t", 0.0)
			scott.set_process(true)
	else:
		scott.set("auto_greet", false)


# ──────────────────────────────────────────────────────────────────────────
# Away-team assembly + walkthrough
# ──────────────────────────────────────────────────────────────────────────

func assemble_away_team_at_gate() -> void:
	if not gate_team.is_empty():
		return
	var sr: Node = host.get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	# Line them up on the deck just in front of the floor-pinned gate.
	var gate_z: float = host.room_size.y * 0.5 - 3.8
	var line_z: float = gate_z - 2.4         # a couple metres south of the event horizon
	var line_y: float = 0.05                 # main floor (no dais now)
	# Roster order matches the planet-side spawn (Greer left, Park centre,
	# Scott right) and the cutscene's group "away_team" muster. Appearance
	# (models, fatigues, Greer's skin tone) comes from CharacterFactory.
	var roster: Array = [
		{"name": "Greer", "glb": "res://models/characters/greer.glb", "x": -1.6},
		{"name": "Park", "glb": "res://models/characters/park.glb", "x": 0.0},
		{"name": "Lt Scott", "glb": "res://models/characters/scott.glb", "x": 1.6},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var c: Node3D = CompanionScript.new()
		c.name = "GateTeam_" + String(entry["name"]).replace(" ", "")
		c.set("stationary", true)
		host._world.add_child(c)
		c.position = Vector3(float(entry["x"]), line_y, line_z)
		c.rotation.y = 0.0    # model holder is internally flipped 180° → visible front faces +Z (the gate)
		c.call("setup", String(entry["name"]), String(entry["glb"]), i)
		gate_team.append(c)
	# Lock the player out of the gate until the team has walked through.
	gate_player_locked = true
	host.interactables.refresh_gate_state()
	# Every character who joined the away team has a standing gate-room NPC
	# (Scott at the briefing spot, Park at the gate console) — hide them so the
	# same person isn't on screen twice. Rush/Brody are NOT on the team, so they
	# stay. (Greer has no standing NPC.) Keyed by the known node names from
	# build_npcs / build_gate_phase_e_crew.
	for npc_node_name in ["LtScott", "GatePark"]:
		var dup: Node = host._world.get_node_or_null(npc_node_name)
		if dup is Node3D:
			(dup as Node3D).visible = false
			if "enabled" in dup:
				dup.set("enabled", false)
	# Drop a trigger volume a few metres south of the team. Walking up behind
	# them fires the choreographed walkthrough exactly once.
	var trigger: Area3D = Area3D.new()
	trigger.name = "TeamWalkthroughTrigger"
	trigger.position = Vector3(0.0, line_y, line_z - 2.4)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(6.0, 2.4, 1.5)
	cs.shape = box
	trigger.add_child(cs)
	# The player capsule sits on layer 1; only react to it (not crew bodies).
	trigger.collision_mask = 1
	trigger.body_entered.connect(on_team_walkthrough_trigger)
	host._world.add_child(trigger)
	GameState.add_log("Lt Scott: We'll head through first — keep tight, Eli.")


func on_team_walkthrough_trigger(body: Node) -> void:
	if team_walkthrough_running:
		return
	if not (body is Node3D) or not body.is_in_group("player"):
		return
	team_walkthrough_running = true
	run_team_walkthrough()


func run_team_walkthrough() -> void:
	var gate_z: float = host.room_size.y * 0.5 - 3.8
	# Walk each companion forward to the event horizon, staggered so they file
	# through one at a time. rush_to() flips the companion into its cinematic
	# sprint mode and ARRIVE handles the visible=false.
	for i in gate_team.size():
		var c: Node3D = gate_team[i]
		if not is_instance_valid(c):
			continue
		var target: Vector3 = Vector3(c.global_position.x, c.global_position.y, gate_z + 0.6)
		c.call("rush_to", target)
		await host.get_tree().create_timer(0.45).timeout
		# Wait until this one's through, then flash + hide before launching the next.
		while is_instance_valid(c) and c.get("_rushing") == true:
			await host.get_tree().process_frame
		if is_instance_valid(c):
			c.visible = false
	# Whole team through — open the gate for the player and free the trigger.
	gate_player_locked = false
	host.refresh_gate_state()
	var trigger: Node = host._world.get_node_or_null("TeamWalkthroughTrigger")
	if trigger != null:
		trigger.queue_free()
	GameState.add_log("Away team's through. Your turn.")


# Play an in-person WoW dialog in the gate room. Skipped in instant_mode (tests
# drive state directly); short beat so the HUD settles before it opens.
func play_gate_dialog(tree: Array) -> void:
	var sr: Node = host.get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	await host.get_tree().create_timer(0.8).timeout
	if not host.is_inside_tree():
		return
	var player: Node = host.get_tree().get_first_node_in_group("player")
	GameState.dialog_started.emit(player, tree)


# ──────────────────────────────────────────────────────────────────────────
# Returned away team
# ──────────────────────────────────────────────────────────────────────────

# The away team that mined with the player on the planet steps back through the
# gate too. They land on the dais just south of the event horizon, then walk
# (staggered) down to their home posts on the main floor and idle there — fully
# talkable NPCs, not the static Companion props they used to be (issue #43).
# Lt Scott reuses his quest-aware repeat line; Greer uses the Greer hint script;
# Park gets a short authored wrap-up. Skipped in instant_mode (headless tests
# drive state directly), so the e1_playthrough path is unaffected.
func spawn_returned_away_team() -> void:
	var sr: Node = host.get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	if host._world == null:
		return
	# Idempotent: the returned away team comes home exactly once. Bail if any
	# member is already present so a double pending_planet_return (or a re-entry)
	# can't put two of each crewmember on screen. Members are named ReturnTeam_*.
	for child in host._world.get_children():
		if String(child.name).begins_with("ReturnTeam_"):
			return
	# Spawn line: on the deck a couple metres in front of the gate. Home line: down
	# on the main floor, gate-side of the FromPlanet landing. Appearance from CF.
	var gate_z: float = host.room_size.y * 0.5 - 3.8
	var spawn_z: float = gate_z - 2.4               # just in front of the ring
	var home_z: float = host.room_size.y * 0.5 - 10.5    # main floor (y≈0.05)
	var roster: Array = [
		{"name": "Greer", "glb": "res://models/characters/greer.glb", "tint": Color.WHITE, "x": -2.4, "kind": "greer"},
		{"name": "Park", "glb": "res://models/characters/park.glb", "tint": Color.WHITE, "x": 0.0, "kind": "park"},
		{"name": "Lt Scott", "glb": "res://models/characters/scott.glb", "tint": Color.WHITE, "x": 2.4, "kind": "scott"},
	]
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var npc: StaticBody3D = build_returned_crew_npc(
			String(entry["name"]), String(entry["kind"]),
			String(entry["glb"]), entry["tint"])
		# Stand in front of the gate facing the room (-Z forward), then stroll to the
		# home post. rotation.y=0 → -Z forward (toward the player landing south).
		npc.position = Vector3(float(entry["x"]), 0.05, spawn_z)
		npc.rotation.y = 0.0
		host._world.add_child(npc)
		# Fan out: each member targets its home post with a small stagger so they
		# don't march in lockstep. ~2.5 m/s reads as an unhurried "we made it".
		npc.call("walk_to", Vector3(float(entry["x"]), 0.05, home_z), 2.5, float(i) * 0.4)
	# Scott is part of the returned team — hide the briefing-spot LtScott NPC so
	# there aren't two Scotts on screen (same fix as assemble_away_team_at_gate).
	var briefing_scott: Node = host._world.get_node_or_null("LtScott")
	if briefing_scott is Node3D:
		(briefing_scott as Node3D).visible = false
		if "enabled" in briefing_scott:
			briefing_scott.set("enabled", false)
	GameState.add_log("The away team steps back through the gate onto Destiny.")


# Build one returned-crew NPC body: StaticBody3D + the right dialogue script,
# CapsuleShape3D, GLB model holder (scaled 2.6×, internally flipped 180° to face
# the body's -Z), colormap/tint, idle anim, and a billboard nametag. Mirrors the
# build_npcs Lt-Scott pattern so the returned trio share that one code path.
# `kind` picks the dialogue wiring: "scott" (quest-aware repeat line), "greer"
# (Greer hint script), or "park" (short authored wrap-up).
# Nameless crowd built by _co_crowd_flood: internal ids, not characters to label.
func is_anonymous_extra(display_name: String) -> bool:
	return display_name.begins_with("mil_") or display_name.begins_with("civ_")


# A muted per-civilian clothing tint so the evac crowd's civvies aren't identical
# cream clones. Deterministic by name hash; deliberately desaturated (a derelict-ship
# evac, not a parade). Multiplies the cream "Peasant" texture, so values stay <1.
func civ_tint(display_name: String) -> Color:
	var pool: Array[Color] = [
		Color(0.46, 0.52, 0.60), Color(0.62, 0.46, 0.44),   # dusty blue, faded brick
		Color(0.50, 0.54, 0.48), Color(0.42, 0.48, 0.52),   # sage, steel
		Color(0.66, 0.60, 0.48), Color(0.55, 0.50, 0.58),   # khaki, mauve-grey
	]
	return pool[absi(display_name.hash()) % pool.size()]


func build_returned_crew_npc(display_name: String, kind: String, glb_path: String,
		tint: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "ReturnTeam_" + display_name.replace(" ", "")
	match kind:
		"greer":
			body.set_script(GREER_SCRIPT)
		_:
			body.set_script(NPC_SCRIPT)
	body.set("character_name", display_name)
	body.set("prompt", "Talk to %s" % display_name)
	if kind == "scott":
		# Reuse Scott's quest-aware repeat line so the returned Scott reflects the
		# post-mission step ("Get that lime to the scrubber…").
		body.set("dialogue_tree", returned_scott_dialog())
		body.set("repeat_dialogue_tree", returned_scott_dialog())
	elif kind == "park":
		body.set("dialogue_tree", returned_park_dialog())
		body.set("repeat_dialogue_tree", returned_park_dialog())
	# Greer rebuilds its tree from quest_step on every interact (greer.gd), so it
	# needs no authored tree here.

	# Collision capsule — blocks the player and acts as the interactable hitbox.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(cs)

	# Visual body — flipped 180° (models export +Z forward).
	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.rotation.y = PI
	body.add_child(model_holder)
	# VRM-first: use the full VRoid body when a .vrm file exists for this character.
	var _vrm_path: String = String(CharacterFactoryRef.profile_for(display_name).get("vrm", ""))
	if _vrm_path != "" and ResourceLoader.exists(_vrm_path):
		var VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")
		var vrm: Node3D = VrmCharacterScript.create(_vrm_path, display_name)
		if vrm != null:
			model_holder.add_child(vrm)
			var MgrScript: Script = preload("res://scripts/vrm_character_manager.gd")
			var expr_profile: Dictionary = MgrScript.EXPRESSION_PROFILES.get(display_name, {})
			if not expr_profile.is_empty():
				var personality: String = String(expr_profile.get("personality", "neutral"))
				if personality != "neutral":
					vrm.call("set_emotion", personality, 0.6)
			if CharacterFactoryRef.is_military(display_name):
				vrm.call("attach_gear", "sidearm", false)
	elif CharacterFactoryRef.profile_for(display_name).has("mod"):
		var mc: Node3D = CharacterFactoryRef.build_modular(display_name)
		model_holder.add_child(mc)
		# Back aboard: ship dress code (duty tint + sidearm for military).
		CharacterFactoryRef.dress_modular(mc, display_name, CharacterFactoryRef.CTX_SHIP)
		# Break the identical-civvies look: give each anonymous CIVILIAN extra a muted
		# per-body clothing tint so the evac crowd reads as varied clothes, not clones.
		# Military keep their uniform (a uniform SHOULD be uniform). Deterministic by name.
		if is_anonymous_extra(display_name) and display_name.begins_with("civ_") \
				and mc.has_method("tint_clothing"):
			mc.call("tint_clothing", civ_tint(display_name))
	else:
		model_holder.scale = Vector3(2.6, 2.6, 2.6)
		var glb: PackedScene = load(CharacterFactoryRef.model_for(display_name, glb_path))
		if glb != null:
			var inst: Node = glb.instantiate()
			model_holder.add_child(inst)
			Npc.play_idle_animation(inst)
		CharacterFactoryRef.dress(body, model_holder, display_name, CharacterFactoryRef.CTX_SHIP)
		if tint != Color.WHITE:
			# Legacy per-instance tint for unregistered characters.
			tint_kenney_model(model_holder, tint)

	# Anonymous flood extras (mil_#/civ_#) are nameless crowd — never stamp their
	# internal id over their head (the "mil_22 floating over an extra" cinematic
	# tell). Named crew get a tag, but it spawns hidden during the cold open.
	if not is_anonymous_extra(display_name):
		var tag: Label3D = Label3D.new()
		tag.name = "Nametag"
		tag.text = display_name
		tag.pixel_size = 0.0042
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 6
		tag.shaded = false
		tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
		tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		tag.position = Vector3(0.0, 2.05, 0.0)
		tag.visible = not host.cinematic.cold_open_active
		body.add_child(tag)
	return body


# Re-tint the just-applied colormap material per-instance so Greer can share
# Scott's body GLB and still read as a different character (same trick as
# Companion._apply_tint — duplicate the shared material before mutating albedo).
func tint_kenney_model(root: Node, tint: Color) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.albedo_color = tint
				mi.material_override = mat
		for c in n.get_children():
			stack.append(c)


# Returned Lt Scott — quest-aware wrap-up. The repeat line method already maps
# the post-mission steps (REPAIR_SCRUBBER → "Get that lime to the scrubber…").
func returned_scott_dialog() -> Array:
	return [
		{
			"speaker": "Lt Scott",
			"text": scott_repeat_line(),
			"choices": [{"text": "On it.", "next": "exit"}],
		},
	]

# Returned Dr Park — short authored wrap-up beat (she had no dialogue before).
func returned_park_dialog() -> Array:
	return [
		{
			"speaker": "Dr Park",
			"text": "We actually pulled it off. Get that lime to the scrubber and we might just keep breathing.",
			"choices": [
				{"text": "How are you holding up?", "next": 1},
				{"text": "On my way.", "next": "exit"},
			],
		},
		{
			"speaker": "Dr Park",
			"text": "Rattled, but in one piece. First alien world I've ever set foot on — I'll process that later. Go on, the scrubber won't wait.",
			"choices": [{"text": "Hang in there.", "next": "exit"}],
		},
	]


# ──────────────────────────────────────────────────────────────────────────
# Crew body attachment (shared by build_npcs and build_tableau_npc)
# ──────────────────────────────────────────────────────────────────────────

func attach_crew_body(model_holder: Node3D, character: String, fallback_glb: String,
		context: String = "") -> Node:
	var ctx: String = context if context != "" else CharacterFactoryRef.CTX_SHIP
	# VRM-first: use the full VRoid body when a .vrm file exists for this character.
	var vrm_path: String = String(CharacterFactoryRef.profile_for(character).get("vrm", ""))
	if vrm_path != "" and ResourceLoader.exists(vrm_path):
		var VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")
		var vrm: Node3D = VrmCharacterScript.create(vrm_path, character)
		if vrm != null:
			model_holder.add_child(vrm)
			# Apply personality-driven expression profile
			var MgrScript: Script = preload("res://scripts/vrm_character_manager.gd")
			var expr_profile: Dictionary = MgrScript.EXPRESSION_PROFILES.get(character, {})
			if not expr_profile.is_empty():
				var personality: String = String(expr_profile.get("personality", "neutral"))
				if personality != "neutral":
					vrm.call("set_emotion", personality, 0.6)
			if CharacterFactoryRef.is_military(character):
				vrm.call("attach_gear", "sidearm", ctx == CharacterFactoryRef.CTX_SHIP)
			return vrm
	if CharacterFactoryRef.profile_for(character).has("mod"):
		var mc: Node3D = CharacterFactoryRef.build_modular(character)
		if mc != null:
			model_holder.add_child(mc)
			CharacterFactoryRef.dress_modular(mc, character, ctx)
			return mc
	# Legacy fallback: Kenney mini at 2.6× with the shared colormap + dressing.
	model_holder.scale = Vector3(2.6, 2.6, 2.6)
	var glb: PackedScene = load(CharacterFactoryRef.model_for(character, fallback_glb))
	if glb == null:
		return null
	var inst: Node = glb.instantiate()
	model_holder.add_child(inst)
	var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
	if colormap != null:
		Npc.apply_kenney_colormap(inst, colormap)
	Npc.play_idle_animation(inst)
	if model_holder.get_parent() is Node3D:
		CharacterFactoryRef.dress(model_holder.get_parent(), model_holder, character, ctx)
	return inst


# ──────────────────────────────────────────────────────────────────────────
# Standing NPCs (Lt Scott, medic tableau, Phase E crew)
# ──────────────────────────────────────────────────────────────────────────

# Lt Scott waits down the dais ramp from the arrival platform and walks up to
# the player to brief them. His body is the Quaternius ModularCharacter (ship
# duty dress) so he reads as a distinct crew member. Collision capsule + Label3D
# nametag are still procedural — the model is purely visual.
func build_npcs() -> void:
	var half_z: float = host.room_size.y * 0.5
	var spawn: Vector3 = Vector3(1.5, 0.0, half_z - 9.0)
	var scott: StaticBody3D = StaticBody3D.new()
	scott.set_script(NPC_SCRIPT)
	scott.name = "LtScott"
	scott.position = spawn
	# Face -Z (toward the dais) so the player arriving on the dais sees his face.
	scott.rotation.y = 0.0
	scott.set("character_name", "Lt Scott")
	scott.set("prompt", "Talk to Lt Scott")
	# Choice-tree dialog (renders via objects/dialog_screen.tscn — full screen
	# Fable-style portrait + branching choices). Indexes refer to positions in
	# this same array; "exit" closes the conversation.
	# New quest opening (sprint-005, 2026-05-23): Scott has no answers — he kicks
	# the player toward Rush, who's the one who'll actually know what's going on.
	# All other E1 objectives (quarters, map, hull breach) are gated in
	# GameState._recompute_objective behind met_rush so Scott's opening doesn't
	# promise tasks the player hasn't been told about yet.
	scott.set("dialogue_tree", [
		{
			"speaker": "Lt Scott",
			"text": "Eli! Hey — you alright? What the hell just happened?",
			"choices": [
				{"text": "Where are we?", "next": 1},
				{"text": "What happened?", "next": 2},
			],
		},
		{
			"speaker": "Lt Scott",
			"text": "Hell if I know. We just came through the gate, and... this isn't earth. This isn't anywhere I've ever heard of.",
			"choices": [
				{"text": "Where's Rush?", "next": 3},
			],
		},
		{
			"speaker": "Lt Scott",
			"text": "Gate dialed an unknown address. Rush yelled GO, and we went — next thing we know, we're here. Wherever 'here' is.",
			"choices": [
				{"text": "Where's Rush?", "next": 3},
			],
		},
		{
			"speaker": "Lt Scott",
			"text": "I think he went through that door. Catch up to him — he'll know what's happening. He always does, even when he won't say.",
			"choices": [
				{"text": "On it.", "next": "exit"},
			],
		},
	])
	scott.set("repeat_dialogue_tree", [
		{
			"speaker": "Lt Scott",
			"text": scott_repeat_line(),
			"choices": [
				{"text": "On it.", "next": "exit"},
			],
		},
	])
	scott.set("met_flag", "met_scott")
	scott.set("first_meet_recompute_objective", true)
	# Walk up to the player and trigger the briefing automatically — no E-press.
	# He heads over the MOMENT control returns (short delay, brisk pace) so the
	# first thing the player does is talk to Scott, which kicks off the main quest
	# (met_scott → objective recompute → "find Rush").
	scott.set("auto_greet", not GameState.met_scott)
	scott.set("auto_greet_distance", 2.6)
	scott.set("auto_greet_delay", 0.3)
	scott.set("auto_greet_speed", 2.8)

	# Collision capsule — blocks the player and acts as interactable hitbox.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	scott.add_child(cs)

	# Visual body — Kenney "Mini Characters 1" GLB. Wrapped in a Node3D so we
	# can tune scale/yaw without touching the imported scene's transform.
	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	model_holder.position = Vector3(0.0, 0.0, 0.0)
	# Models export with +Z forward; rotate 180° to Godot's -Z forward —
	# otherwise Scott walks/auto-greets facing the wrong way.
	model_holder.rotation.y = PI
	scott.add_child(model_holder)
	# PRIMARY: Quaternius ModularCharacter, uniquely dressed for ship duty (duty
	# blacks + sidearm for military). Mirrors build_returned_crew_npc so the
	# whole gate-room crew shares one styling code path. Falls back to the legacy
	# mini GLB only if the profile has no modular spec or the base fails to load.
	attach_crew_body(model_holder, "Lt Scott", "res://models/characters/scott.glb")

	# Floating nametag billboard so the player can ID him from across the room.
	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = "Lt Scott"
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	tag.position = Vector3(0.0, 2.05, 0.0)
	tag.visible = not host.cinematic.cold_open_active
	scott.add_child(tag)

	host._world.add_child(scott)

	# Medic tableau: Colonel Young laid out unconscious with Lt James kneeling
	# beside him. Only present BEFORE the air crisis — once it starts, James has
	# moved Young to the Infirmary (off the south corridor) to recover, so the
	# gate-room floor is clear.
	if not GameState.air_crisis_started:
		build_medic_tableau()

	# Phase E: Brody (at the gate console) plus Rush + Park, who "followed" Eli
	# in to look at the dialed gate. Present from arrival through the lime run.
	build_gate_phase_e_crew()


# Lt Scott's repeat line is quest-aware: a nudge toward Rush early on, but once
# the Kino scout confirms the lime world he's supportive about the away mission
# (he leads it). Default preserves the early "find Rush" nudge.
func scott_repeat_line() -> String:
	match GameState.quest_step:
		GameState.QUEST_MINE_LIME:
			return "Breathable air and lime on the far side — good work, Eli. I guess we'd better go mine some."
		GameState.QUEST_RETURN_DESTINY:
			return "Grab what lime you can and get back to the gate."
		GameState.QUEST_REPAIR_SCRUBBER:
			return "Get that lime to the scrubber — we're counting on you."
		_:
			return "Hurry up Eli, find Rush!"


# Spawn Brody + Rush + Park clustered by the gate-control console during the
# Phase E gate window (arrival → Kino scout). Unique node names so NPCState
# doesn't cross-restore them to the control-room / infirmary versions.
func build_gate_phase_e_crew() -> void:
	# Present from the gate report through the lime run: Brody/Rush/Park stay to
	# brief the away party once the Kino scout confirms the planet (MINE_LIME).
	var q: String = GameState.quest_step
	var in_window: bool = (q == GameState.QUEST_GO_TO_GATE
		or q == GameState.QUEST_FETCH_KINO
		or q == GameState.QUEST_SCOUT_KINO
		or q == GameState.QUEST_DIAL_LIME_PLANET
		or q == GameState.QUEST_MINE_LIME)
	if not in_window:
		return
	var z_console: float = GATE_CONSOLE_Z
	# Brody at the gate-control console (x -3.5), facing the player's arrival.
	build_tableau_npc(
		"GateBrody", "Dr Brody",
		Vector3(-5.2, 0.0, z_console - 1.0), 0.0,
		"res://models/characters/scott.glb",
		[{"speaker": "Dr Brody", "text": "Still no telemetry from the other side. We're flying blind here.", "choices": [{"text": "Working on it.", "next": "exit"}]}],
		"", "stand", true,
	)
	build_tableau_npc(
		"GateRush", "Dr Rush",
		Vector3(-1.4, 0.0, z_console - 1.6), 0.0,
		"res://models/characters/rush.glb",
		[{"speaker": "Dr Rush", "text": "Whenever you're ready, Mr Wallace. The gate won't stay open forever.", "choices": [{"text": "Right.", "next": "exit"}]}],
		"", "stand", true,
	)
	build_tableau_npc(
		"GatePark", "Dr Park",
		Vector3(0.8, 0.0, z_console - 1.6), 0.0,
		"res://models/characters/park.glb",
		[{"speaker": "Dr Park", "text": "A camera drone through a wormhole. Honestly? Worth a shot.", "choices": [{"text": "Let's find out.", "next": "exit"}]}],
		"", "stand", true,
	)


# Medic vignette down-range from the gate where Colonel Young was thrown:
#   • Young lying face-up on the floor, unconscious and not interactable.
#   • Lt James kneeling on the gate-side of him, facing Young.
# James is the only talkable NPC in this cluster. The spot is also where the
# prologue's "Young thrown farthest" ragdoll lands, so the reveal is seamless.
func build_medic_tableau() -> void:
	var tableau_center: Vector3 = Vector3(-1.5, 0.0, -6.5)   # = Young's arrival landing spot

	# --- Colonel Young — laid out on his back ----
	build_tableau_npc(
		"ColonelYoung",
		"Colonel Young",
		tableau_center + Vector3(0.0, 0.0, 0.0),
		0.0,
		"res://models/characters/scott.glb",
		[],
		"met_young",
		"down",
		false,
		"X_X",
	)

	# --- Lt James — kneeling BESIDE Young by his head (gate-side of him),
	# facing him so she reads as a medic mid-triage. Offset on +X to clear
	# his body; her yaw turns her -90° so she looks toward -X (at Young).
	build_tableau_npc(
		"LtJames",
		"Lt James",
		tableau_center + Vector3(0.85, 0.0, 0.4),
		PI * 0.5,
		"res://models/characters/james.glb",
		james_tableau_dialog(),
		"",
		"kneel",
	)


# Tableau NPC builder — supports two poses beyond standing:
#   • "down"  — rotated 90° around X so the model lies face-up on the floor.
#   • "kneel" — Y-axis squashed so the model reads as crouched / kneeling.
# The collision capsule + nametag are repositioned to suit each pose.
func build_tableau_npc(
		npc_name: String,
		character: String,
		pos: Vector3,
		yaw: float,
		glb_path: String,
		dialog_tree: Array,
		met_flag: String,
		pose: String,
		talkable: bool = true,
		face_override: String = "",
	) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	if talkable:
		body.set_script(NPC_SCRIPT)
	body.name = npc_name
	body.position = pos
	body.rotation.y = yaw
	if talkable:
		body.set("character_name", character)
		body.set("prompt", "Talk to %s" % character)
		body.set("dialogue_tree", dialog_tree)
		body.set("met_flag", met_flag)
		body.set("first_meet_recompute_objective", true)
	else:
		body.collision_layer = 1
		body.collision_mask = 0

	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	if pose == "down":
		# Wide flat hitbox at floor height — capsule oriented horizontally.
		cap.radius = 0.4
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0.0, 0.25, 0.0)
		# Capsule's long axis is Y; rotate so it lies along the body's local Z.
		cs.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	elif pose == "kneel":
		cap.radius = 0.36
		cap.height = 1.2
		cs.shape = cap
		cs.position = Vector3(0.0, 0.6, 0.0)
	else:
		cap.radius = 0.32
		cap.height = 1.75
		cs.shape = cap
		cs.position = Vector3(0.0, 0.88, 0.0)
	body.add_child(cs)

	var model_holder: Node3D = Node3D.new()
	model_holder.name = "Model"
	# PRIMARY for EVERY pose now: the Quaternius ModularCharacter, uniquely dressed
	# by CharacterFactory (goal: all crew are Quaternius, incl. the prone Young and
	# kneeling James). The "Invalid array format for surface" push_error is benign
	# garment-surface stripping noise that the standing modular crew already emit.
	var modular: bool = CharacterFactoryRef.profile_for(character).has("mod")
	if pose == "down":
		# Lay character on their back: tip the holder forward 90° so what was up
		# (head along +Y) now extends along +Z away from the feet anchor.
		# Lift slightly so the back doesn't z-fight with the floor.
		model_holder.rotation = Vector3(PI * 0.5, PI, 0.0)   # face-DOWN (injured, prone)
		model_holder.position = Vector3(0.0, 0.15, 0.0) if modular else Vector3(0.0, 0.18, 0.7)
		if not modular:
			model_holder.scale = Vector3(2.6, 2.6, 2.6)
	elif pose == "kneel":
		if modular:
			# Real rig: the kneeling-repair clip replaces the legacy Y-squash.
			model_holder.rotation = Vector3(0.0, PI, 0.0)
		else:
			# Compress the standing model vertically — reads as crouched/kneeling
			# without needing a separate rig. Slight forward tilt sells the lean.
			model_holder.rotation = Vector3(deg_to_rad(-20.0), PI, 0.0)
			model_holder.scale = Vector3(2.6, 1.5, 2.6)
	else:
		model_holder.rotation.y = PI
		if not modular:
			model_holder.scale = Vector3(2.6, 2.6, 2.6)

	body.add_child(model_holder)
	if modular:
		var mc: Node3D = CharacterFactoryRef.build_modular(character)
		model_holder.add_child(mc)
		CharacterFactoryRef.dress_modular(mc, character, CharacterFactoryRef.CTX_SHIP)
		if pose == "kneel":
			mc.call("play_clip", "repair")   # kneeling, hands working — medic triage
		elif pose == "down":
			# Freeze the idle pose: an unconscious body shouldn't breathe-sway.
			mc.call("freeze_pose")
	else:
		var glb: PackedScene = load(glb_path)
		if glb != null:
			var inst: Node = glb.instantiate()
			model_holder.add_child(inst)
			var colormap: Texture2D = load("res://models/characters/Textures/colormap.png")
			if colormap != null:
				Npc.apply_kenney_colormap(inst, colormap)
			# Down characters DON'T idle-loop — the breathe-anim makes "unconscious"
			# read as "stretching." Kneelers do, so they feel busy with their hands.
			if pose != "down":
				Npc.play_idle_animation(inst)
	# The face-override plane is positioned for the mini head; modular bodies
	# have a real face, so the X-eyed sticker would float mid-air — skip it.
	if face_override != "" and not modular:
		add_face_override(body, face_override, pose)

	var tag: Label3D = Label3D.new()
	tag.name = "Nametag"
	tag.text = character
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 6
	tag.shaded = false
	tag.modulate = Color(0.95, 0.92, 0.78, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# Pull the nametag closer to the floor for the prone character so it floats
	# above his chest rather than way up where his head used to be.
	if pose == "down":
		tag.position = Vector3(0.0, 0.9, 0.3)
	elif pose == "kneel":
		tag.position = Vector3(0.0, 1.5, 0.0)
	else:
		tag.position = Vector3(0.0, 2.05, 0.0)
	tag.visible = not host.cinematic.cold_open_active
	body.add_child(tag)

	host._world.add_child(body)


func add_face_override(body: Node3D, text: String, pose: String) -> void:
	var face: Label3D = Label3D.new()
	face.name = "FaceOverride"
	face.text = text
	face.pixel_size = 0.0068
	face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face.outline_size = 2
	face.shaded = false
	face.modulate = Color(0.03, 0.035, 0.04, 1.0)
	face.outline_modulate = Color(0.85, 0.62, 0.46, 0.85)
	face.position = Vector3(0.0, 0.78, 1.35) if pose == "down" else Vector3(0.0, 1.7, 0.0)
	body.add_child(face)


func james_tableau_dialog() -> Array:
	return [
		{
			"speaker": "Lt James",
			"text": "Hold on — give me space, please. Colonel Young took a hard fall when we landed. He's unconscious, but his pulse is steady.",
			"choices": [
				{"text": "Will he be okay?", "next": 1},
				{"text": "Can I help?", "next": 2},
				{"text": "I'll keep moving.", "next": "exit"},
			],
		},
		{
			"speaker": "Lt James",
			"text": "I need him still until I can finish checking him. He's breathing, and that's the part that matters right now.",
			"choices": [
				{"text": "Can I help?", "next": 2},
				{"text": "Glad to hear it.", "next": "exit"},
			],
		},
		{
			"speaker": "Lt James",
			"text": "Yes — find Dr Rush. He's the one who needs to know what state the Colonel is in, and he's the only one of us who might be able to read these consoles. He went through to the control room.",
			"choices": [
				{"text": "Heading there now.", "next": "exit"},
			],
		},
	]