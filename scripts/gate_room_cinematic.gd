extends Node

# Cinematic / cold-open / crew-arrival module for the gate room. Extracted from
# gate_room.gd to decompose the god object. Added as a child Node "Cinematic"
# by the main script and called via the host reference.
#
# Owns: the prologue cold-open coroutine, arrival runner, skip support,
# crew-throw/projectile/ragdoll choreography, camera cuts, FTL jump,
# crate waves + impacts, crowd flood, crew recovery, and all associated
# audio/VO/SFX helpers.

# Shared crew-appearance source of truth (base models, outfits per context, gear).
const CharacterFactoryRef: Script = preload("res://scripts/character_factory.gd")

# ── Consts moved from gate_room.gd ────────────────────────────────────────────

# The real "Air" cold-open recording, played once as the master soundtrack and
# anchor for every beat below. The old per-line open-*.wav TTS clips are retired in
# favour of this single track (left on disk only as a fallback reference).
const COLD_OPEN_MASTER: String = "res://sounds/dialog/prologue/cold_open_master.mp3"
# The cold open now plays the Demucs-isolated AMBIENCE bed (music/kawoosh/crowd, the
# original voices stripped) and layers OUR designed per-character VO clips on top via
# cap(...) — so the dialog is our voices, not the recording's. The bed is still the
# master clock (same 255.3 s timeline as cold_open_master.mp3).
const COLD_OPEN_BED: String = "res://sounds/dialog/prologue/cold_open_bed.mp3"
const PROLOGUE_VO_DIR: String = "res://sounds/dialog/prologue/"

# Hold-to-skip: during the cold open, holding Jump (Space / gamepad A) for
# SKIP_HOLD_SEC aborts the cinematic straight to the playable hand-off.
const SKIP_HOLD_SEC: float = 0.9

# Sound bed layers for the cold open (all stopped/freed in finalize_cold_open so a
# skip can't orphan them). Each is a looping AudioStreamPlayer started at its beat and
# stopped when the narrative calls for it. All no-op if the asset is missing.
const CROWD_PANIC_BED: String = "res://sounds/dialog/prologue/crowd_panic_bed.ogg"
const ICARUS_RUMBLE: String = "res://sounds/dialog/prologue/icarus_rumble.ogg"
const SHIP_SHUDDER: String = "res://sounds/dialog/prologue/ship_shudder.ogg"
const RADIO_CLICK_SFX: String = "res://sounds/radio_click.ogg"

# Seconds after Scott's ragdoll settles before he stands.
const SCOTT_GETUP_DELAY: float = 1.5

# Gate-throw projectile tuning.
# Crew (and crates) are FIRED out of the wormhole on a ballistic arc — NOT
# ragdolled. The PhysicalBone joint solver bleeds the launch so badly the body
# never travels (it flops at the gate), so we drive a kinematic projectile that
# always reaches its spot.
const THROW_FLIGHT_TIME: float = 1.603    # seconds gate→landing (higher = floatier, taller arc)
const THROW_TUMBLE_BASE: float = 5.246     # head-over-heels tumble rate (rad/s) — limbs swing
const THROW_TUMBLE_DIST: float = 0.403    # extra tumble per metre of downrange throw
const THROW_CRATE_FLIGHT: float = 1.15   # crates fly flatter/faster than bodies
const THROW_CRATE_SPIN: float = 6.0      # crate tumble rate (rad/s)

# Candidate grunt clips (generated via the sound-effects pipeline; any present are
# used round-robin, and the whole thing no-ops cleanly until they exist on disk).
const GRUNT_PATHS: Array[String] = [
	"res://sounds/grunt_01.wav", "res://sounds/grunt_02.wav", "res://sounds/grunt_03.wav",
]

# Footlocker crate size: longer than wide/tall.
const CRATE_SIZE: Vector3 = Vector3(1.4, 0.55, 0.85)

# Per-character arrival roll clips (imported Mixamo). Scott dives; mil/civ get a
# varied roll; "hard" crashes (Young, crate victims).
const ARRIVAL_ROLLS: Array[String] = ["sprint_roll", "roll_to_run", "run_roll", "falling_roll"]

# Playhead windows where the camera is cut TIGHT on a staged two-shot (the medic
# tending the marine) — the gate isn't on screen, so we pause spawning so no new
# arrival walks ACROSS the focus en route to the wall.
const FLOOD_QUIET_WINDOWS: Array = [[22.5, 33.5]]   # medic two-shot

# Flight time for the impact crate to reach the victim.
const IMPACT_CRATE_TIME: float = 0.55

# Two-person crate carry tuning.
const CRATE_CARRY_HEIGHT: float = 1.0     # crate ride height when two crew lift it
const CRATE_FLANK: float = 0.85           # half-gap between the two carriers

# Standoff camera script for cut-to-speaker framing during the cold open.
const StandoffCameraScript: Script = preload("res://scripts/standoff_camera.gd")

# The FTL jump sound for the cold open.
const FTL_JUMP_SOUND_COLDOPEN: String = "res://sounds/ftl_jump_destiny.ogg"


# ── State vars moved from gate_room.gd (public, no underscore) ────────────────

# Wall-clock anchor (ms) for the cold open, used only when the master stream fails
# to load so the beats still pace out. Real play reads the audio playhead instead.
var cold_open_start_ms: int = 0
# True for the whole cold-open cinematic. While set, newly-built crew nametags
# spawn hidden — a cutscene carries NO floating UI labels (captions name the
# speaker instead). Flipped false at the hand-off, then crew tags are revealed.
var cold_open_active: bool = false
# Skip support. Hold the Jump action for SKIP_HOLD_SEC during the cold open to abort:
# co_skip makes every wait primitive (await_audio / cap / cwait) and the cut helpers
# no-op, so the cinematic coroutine unwinds in a single frame — spawning the remaining
# crew straight into their settled spots — and lands on finalize_cold_open() (guarded
# by co_finalized so the normal end and a skip can't both run the hand-off).
var co_skip: bool = false
var co_finalized: bool = false
var co_audio: AudioStreamPlayer = null
var skip_hold_t: float = 0.0
var skip_hint: Label = null   # cached "Hold to skip" HUD label (built lazily)
# Dev/QA only: seconds into the cold open to auto-fire the skip (set via the
# `coldopen_autoskip=<secs>` cmdline arg). 0 = disabled (normal play).
var autoskip_after: float = 0.0
# Sound bed layers for the cold open (all stopped/freed in finalize_cold_open so a
# skip can't orphan them).
var co_crowd_bed: AudioStreamPlayer = null
var co_rumble: AudioStreamPlayer = null
var co_klaxon: AudioStreamPlayer = null
# Active StandoffCamera during the verbatim cold open.
var cut_cam: Node = null
# True while the arrival cinematic is running.
var arrival_running: bool = false
# Round-robin pool of body-impact players for the panic arrival (built lazily).
var thud_players: Array[AudioStreamPlayer] = []
var thud_streams: Array[AudioStream] = []
var thud_i: int = 0
# Metallic deck-ring overlay played under each thud (the floor is steel grating).
var thud_metal: AudioStreamPlayer = null
# Round-robin pool for the wormhole "puddle" splash — every body/crate that breaks
# the gate surface gets a short watery punch-through (built lazily).
var splash_players: Array[AudioStreamPlayer] = []
var splash_streams: Array[AudioStream] = []
var splash_i: int = 0
# Vocal effort grunts as bodies slam onto the deck (built lazily; no-op if assets
# are absent).
var grunt_players: Array[AudioStreamPlayer] = []
var grunt_streams: Array[AudioStream] = []
var grunt_i: int = 0
# Crates hurled through the gate this cold-open, so crew can shove them to the
# walls afterward (out of the way so nobody trips over them).
var arrival_crates: Array[Node3D] = []


# ── Setup ────────────────────────────────────────────────────────────────────

# Host reference (the gate_room.gd Node3D). Set by the host before any calls.
var host: Node3D = null

func setup(room: Node3D) -> void:
	host = room


# ── Arrival ──────────────────────────────────────────────────────────────────

func run_arrival() -> void:
	arrival_running = true
	GameState.set_objective("Talk to Lt Scott.")
	GameState.add_log("Eli: Okay… where am I?")
	GameState.add_log("Lt Scott: Hey — over here. We need to figure out where we are.")
	if host._player != null and host._player.has_method("set_input_locked"):
		host._player.set_input_locked(true)

	# Headless / scripted runs (e1_playthrough) skip the cinematic spectacle and
	# settle straight to the gameplay state — the cinematic uses tweens/timers and
	# a temp camera that those tests neither tick nor want.
	var sr: Node = host.get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		if host._stargate != null and "active" in host._stargate:
			host._stargate.active = false
		host.interactables.gate_forced_open = false
		host.interactables.start_ambient()
		if host._player != null and host._player.has_method("set_input_locked"):
			host._player.set_input_locked(false)
		arrival_running = false
		return

	await play_prologue_cinematic()

	# A skip funnels this same cleanup through finalize_cold_open() already, so only
	# run it here for a cinematic that played out to the end.
	if not co_finalized:
		host.interactables.start_ambient()
		if host._player != null and host._player.has_method("set_input_locked"):
			host._player.set_input_locked(false)
		arrival_running = false


# The cold open — now driven by the REAL "Air" recording (sounds/dialog/prologue/
# cold_open_master.mp3) played as ONE master track. Every visual beat is timed
# against that clip's playhead (await_audio) and the captions subtitle its own
# dialogue, so the scene stays locked to the audio across its full ~4:15 runtime.
# Beats:
#   • The gate DIALS (spin → chevrons lock → portal flushes open → stabilises).
#   • WAVE 1: Lt Scott flung through first, kneels, rises, waves the rest through.
#   • WAVES 2–8: the flood — Young thrown hardest (injured, face-down), James the
#     medic, Park/Volker to consoles, soldiers + civilians in pairs, crates raining.
#   • Eli (the player) last through, closest to the gate; he groggily stands.
#   • The hush → wonder → Scott can't find Rush → "Eli! NOW!". The recording carries
#     the voices; we subtitle them and stage Scott's looks.
# The old per-line baked TTS clips (open-*.wav) are retired by this single track.
func play_prologue_cinematic() -> void:
	# Score the cold open: tense, urgent bed for the evac chaos. Shifts to wonder at the
	# ship-shudder beat below, then start_ambient() resolves to ship_calm afterward.
	Audio.set_mood("tension")
	host.npcs.set_arrival_crew_visible(false)
	# Hold Scott's auto-greet for the WHOLE cold open — and, per the synced-audio
	# design, we DON'T turn it back on at the end: by the time the recording finishes
	# the player already holds the Find-Rush objective (set below), so Scott never
	# walks over to brief them (the "first stop is the quest, not a Scott chat" beat).
	host.npcs.set_scott_autogreet(false)
	# The player body stays hidden until his wave delivers him.
	show_player_model(false)
	# Consoles are dead/offline on the derelict during the cold open.
	host.interactables.set_consoles_offline()

	# A cinematic carries NO floating UI labels — the captions name the speaker.
	# Hide any nametag already in the room (pre-built Scott/James/Young) and arm
	# the flag so every crew body built mid-flood spawns its tag hidden too.
	cold_open_active = true
	co_skip = false
	co_finalized = false
	skip_hold_t = 0.0
	host.npcs.set_crew_nametags_visible(false)
	show_skip_hint(true)

	# Camera cuts (cut-to-speaker) own the framing for the whole verbatim cold open.
	# OPEN on the SGU establishing shot: low, down the dark amber-lit walkway to the
	# gate at the far end — held through the dial so we arrive on the reference still.
	begin_cuts()
	cut_establishing(0.5)

	# THE soundtrack: the ~165s ambience BED, played ONCE. cold_open_start_ms anchors
	# the wall-clock fallback if the stream fails (real play has it; headless skips this
	# whole path via instant_mode). Our designed per-character VO plays on top via cap.
	cold_open_start_ms = Time.get_ticks_msec()
	var audio: AudioStreamPlayer = AudioStreamPlayer.new()
	audio.name = "ColdOpenMaster"
	host.add_child(audio)
	var bed: AudioStream = load(COLD_OPEN_BED) as AudioStream
	if bed != null:
		if "loop" in bed:
			bed.set("loop", false)
		audio.stream = bed
		audio.play()
	co_audio = audio   # so a skip can stop the bed immediately

	# Crush the lights to near-black so the establishing shot + the gate dial play in
	# the SGU gloom — only the gate and the amber floor strips glow (matches the
	# reference still). flicker_lights_up() restores them as the crew flood in.
	host.lighting.open_dark()

	await Cinematic.letterbox_in()

	# DIAL (≈0.5–3.5s): ring spins → chevrons lock one-by-one (sound per chevron) →
	# kawoosh. Held on the LOW establishing shot down the dark amber walkway → we land
	# on the reference image (dark room, active gate at the far end).
	await cwait(0.5)
	await host.interactables.dial_and_open(true)

	# §1.1b ICARUS RUMBLE + KLAXON — the base behind them is dying. Distant rumble and
	# alarm bleed through the open wormhole while the gate is active. Both are stopped
	# in collapse_gate() (the gate shuts = the connection to Icarus is severed) and in
	# finalize_cold_open() (skip safety). Low volume so they sit under the VO + crowd.
	co_rumble = co_start_loop(ICARUS_RUMBLE, -15.0)
	co_klaxon = co_start_loop("res://sounds/klaxon.ogg", -18.0)

	# Hold a beat on the dark establishing shot with the gate now ACTIVE — this is the
	# exact SGU "Air" opening still (black room, amber walkway, bright gate far off).
	await cwait(1.6)

	# §1.2 FIRST THROUGH — Scott ALONE. He's flung out of the active wormhole, hits the
	# deck and GRUNTS (no line yet). Hold WIDE so we see him thrown into the dark room.
	# This beat is paced by real timers off the dial + throw-flight (NOT the bed
	# playhead — the dial runs on timers, so absolute playhead cues desync here).
	cut_wide(0.6)
	# §1.1: "a little lighting flickers on" — the derelict's lights stutter up to full
	# now, as the first crew come barrelling through (not before — the dial is dark).
	host.lighting.flicker_lights_up()
	var scott: StaticBody3D = co_arrival("Lt Scott", "", Vector3(1.6, 0.05, host.GATE_Z - 4.5),
			Vector3(2.2, 0.05, host.GATE_Z - 5.5), "scott", host._world.get_node_or_null("LtScott") as StaticBody3D)
	GameState.add_log("Lt Scott comes barrelling through the gate!")
	GameState.narrate("Lt Scott comes barrelling through the gate!")
	await cwait(THROW_FLIGHT_TIME + 0.15)
	grunt(scott)                                # impact grunt as he hits the deck
	# Frame Scott in the foreground with the GATE behind him (camera on the room side,
	# looking back toward the wormhole) so the two who follow are SEEN coming through.
	cut_follow(scott, Vector3(2.4, 1.7, -4.5))

	# §1.3 …a BEAT (~1.1s) later, the first TWO follow him through and scramble aside.
	# Scott only barks "get out of the way" once there are actually people to clear.
	await cwait(1.1)
	co_arrival("mil_0", "greer", Vector3(-1.2, 0.05, host.GATE_Z - 4.0),
			Vector3(-12.5, 0.05, host.GATE_Z - 6.0), "mil", null, true)
	co_arrival("civ_1", "", Vector3(1.0, 0.05, host.GATE_Z - 4.6),
			Vector3(12.5, 0.05, host.GATE_Z - 7.0), "civ", null, true)
	grunt(scott)                                # the two crash in (grunts on the punch-through)
	await cwait(THROW_FLIGHT_TIME)            # let the two land first
	cut_to(scott, 3.2, 1.5, 1.6, 0.5)
	# Radio crackle before Scott's first comms line — sells that he's on radio, not just shouting.
	co_one_shot(RADIO_CLICK_SFX, -6.0)
	cap_now("LT. SCOTT", "All right, get out of here. Get out of the way!", "open-scott-clearway")

	# §1.3b PANDEMONIUM — NOW the continuous flood ramps as Scott marshals it. Tapers by
	# ~38s (the named principals keep the gate flowing after) so it's a believable evac
	# that clears to the walls, not an endless clone-wall.
	await cwait(2.0)
	cut_wide(0.8)                               # WIDE: the flood + gate + room as one shot
	# Crowd-panic ambient bed: the "many terrified people" layer that loops under the
	# flood and ducks under the voiced lines. Stopped in collapse_gate() (evac is over)
	# and finalize_cold_open() (skip safety). Sits below the VO in the mix.
	co_crowd_bed = co_start_loop(CROWD_PANIC_BED, -12.0)
	var flood_from: float = audio.get_playback_position() if (audio != null and is_instance_valid(audio)) else 9.0
	co_crowd_flood(audio, flood_from, 38.0, 0.9)
	# Crowd confusion VO — overlapping, layered over the captioned lines (fire-and-forget,
	# no caption). Alternates between the two clips at semi-regular intervals during the
	# flood window for the chaotic "overlapping voices" read.
	cap_crowd("open-crowd-where")
	cap_crowd("open-crowd-what")
	# Marshalling barks (layered, no caption) — Greer's "Clear!" and Marine "Clear!" fire
	# alongside the existing Scott captions for depth.
	cap_crowd("open-greer-clear")
	cap_crowd("open-marine-clear")
	# Radio crackle before Scott's second comms line.
	co_one_shot(RADIO_CLICK_SFX, -6.0)
	cap_now("LT. SCOTT", "This is Scott! Slow down the evac — we are comin' in too hot!", "open-scott-evac")
	# §1.3c WRAY grabs at Scott. She comes through, scrambles UP to him, and the two
	# KNEEL together amid the chaos as he turns to her and she asks where they are —
	# staged as a walk-up (not a cut to her landing spot). Timer-paced; we re-lock to
	# the bed playhead afterward (downstream cap calls self-heal if it has advanced).
	await cwait(0.5)
	var wray_at_scott: Vector3 = scott.global_position + Vector3(-1.4, 0.0, 0.25)
	var wray: StaticBody3D = co_arrival("Camile Wray", "", Vector3(0.2, 0.05, host.GATE_Z - 4.2),
			wray_at_scott, "civ")
	grunt(wray)
	cut_follow(scott, Vector3(2.2, 1.6, -3.6))   # hold on Scott (gate behind) as she crosses to him
	await cwait(THROW_FLIGHT_TIME + 3.0)      # land, roll up, scramble to his side
	if is_instance_valid(wray):
		rise_npc(wray, "crouch_idle")            # she drops to a knee beside him
		face_node(wray, scott)
	rise_npc(scott, "crouch_idle")               # Scott crouched amid the wounded, turns to her
	face_node(scott, wray)
	cut_to_spot(scott.global_position, 2.6, 1.2, 1.5, 0.5)   # low two-shot of the kneeling pair
	cap_now("CAMILE WRAY", "Where are we? Why didn't we come through to Earth?", "open-wray-whereare")
	await cwait(2.9)
	face_node(scott, wray)
	cap_now("LT. SCOTT", "There's no time to explain. Off to the side!", "open-scott-side")
	await cwait(2.0)
	# Scott rises and waves her off to the side; re-lock to the bed playhead.
	rise_npc(scott, "idle")
	if is_instance_valid(wray) and wray.has_method("walk_to"):
		wray.call("walk_to", Vector3(-11.5, 0.05, host.GATE_Z - 7.0), 2.8, 0.0)
	await await_audio(audio, 17.5)
	launch_crate_wave()                       # gear now raining in (after the first people)
	cap("LT. SCOTT", "This is Scott — come in!", 18.5, "open-scott-comein")

	# §1.4 "I NEED A MEDIC" — TJ working the broken-arm man; a crate hits him.
	# Reveal TJ at the medic pocket and place the wounded man beside her.
	var tj: StaticBody3D = host._world.get_node_or_null("LtJames") as StaticBody3D
	var medic_spot: Vector3 = Vector3(3.4, 0.05, host.GATE_Z - 8.0)
	if tj != null:
		tj.visible = true
		if "enabled" in tj: tj.set("enabled", true)
		tj.global_position = medic_spot
		rise_npc(tj, "crouch_idle")
	var man_spot: Vector3 = medic_spot + Vector3(0.85, 0.0, 0.2)   # close beside TJ
	var man: StaticBody3D = co_arrival("Wounded Marine", "", man_spot, man_spot, "hard")
	cap("MARINE", "I need a medic!", 20.0, "open-marine-medic")
	await await_audio(audio, 23.0)
	# TIGHT LOW two-shot centred on the pair so TJ + the wounded marine fill the frame
	# (was a wide shot that blended them into the crouched crowd).
	var medic_mid: Vector3 = medic_spot.lerp(man_spot, 0.5)
	cut_to_spot(medic_mid, 2.1, 0.95, -1.5, 0.6)
	cap("TJ", "Over here! Can you move your fingers?", 24.0, "open-tj-fingers")
	await await_audio(audio, 27.0)
	launch_impact_crate(man, "arm")           # a crate skids in and clips his arm
	cap("MARINE", "No. I think my arm is broken.", 29.0, "open-man-broken")
	cap("TJ", "Okay, just hold your arm there and we'll put it in a sling, okay?", 32.0, "open-tj-sling")

	# §1.5 RUSH/ELI + the staircase; Scott marshals; Senator + Chloe arrive.
	await await_audio(audio, 36.0)
	cut_wide(0.8)
	cap("LT. SCOTT", "Clear this area! There could still be more incoming!", 38.0, "open-scott-cleararea")
	# The Senator comes through, lands HARD and stays down (injured); Chloe scrambles to
	# him and drops to a KNEE to tend him — a kneeling pair, framed low, not lost among
	# standing extras. Captions fire via cap_now once she's posed at his side.
	await await_audio(audio, 39.5)
	# Land the pair in the VACATED central landing zone (crew cleared to the walls),
	# not the -X transit lane — so no standing extra blocks the downed Senator.
	var senator_spot: Vector3 = Vector3(-2.5, 0.05, host.GATE_Z - 5.0)
	var senator: StaticBody3D = co_arrival("Senator Armstrong", "", senator_spot, senator_spot, "hard")
	var chloe_spot: Vector3 = senator_spot + Vector3(-1.2, 0.0, 0.45)
	var chloe: StaticBody3D = co_arrival("Chloe Armstrong", "", Vector3(-3.6, 0.05, host.GATE_Z - 5.6),
			chloe_spot, "civ")
	# Tight LOW two-shot on the pair's midpoint — a low angle crops the standing
	# background crew above the frame so the downed Senator + kneeling Chloe read.
	var sen_mid: Vector3 = senator_spot.lerp(chloe_spot, 0.5)
	cut_to_spot(sen_mid, 1.9, 0.78, 1.5, 0.6)
	await await_audio(audio, 44.0)
	# Guarantee the staged pair is posed by their lines (snap past any walk-in). The
	# Senator is hurt and DOWN at Chloe's level — the "hard" role leaves the body
	# upright in a crash clip, so force a low crouch — and Chloe kneels facing him.
	# Both low → the low two-shot crops the standing background crew above frame.
	if is_instance_valid(senator):
		senator.global_position = senator_spot
		rise_npc(senator, "crouch_idle")
		face_node(senator, chloe)
	if is_instance_valid(chloe):
		chloe.global_position = chloe_spot
		rise_npc(chloe, "crouch_idle")
		face_node(chloe, senator)
	cap_now("CHLOE", "Are you okay?", "open-chloe-areyouok")
	await await_audio(audio, 47.0)
	cap_now("SENATOR", "Yeah.", "open-senator-yeah")
	await await_audio(audio, 49.0)
	if is_instance_valid(chloe):
		face_node(chloe, senator)
	cap_now("SENATOR", "Where the hell are we?", "open-senator-whereare")

	# §1.6 "Where's Colonel Young?" — Scott to Greer.
	await await_audio(audio, 51.0)
	var greer: StaticBody3D = co_arrival("Sgt Greer", "greer", Vector3(4.4, 0.05, host.GATE_Z - 5.0),
			Vector3(5.6, 0.05, host.GATE_Z - 6.5), "mil")
	# Eli (the player) is delivered last-ish, closest to the gate.
	await await_audio(audio, 53.0)
	var eli_spot: Vector3 = Vector3(-0.6, 0.05, host.GATE_Z - 6.2)
	var r_eli: Node3D = launch_ragdoll("Eli", eli_spot)
	GameState.add_log("Eli is hurled through and slams into the deck!")
	cut_to(scott, 3.2, 1.5, 1.6, 0.5)
	cap("LT. SCOTT", "Greer? Where's Colonel Young?", 55.0, "open-scott-greerwhere")
	await await_audio(audio, 54.5)
	if host._player != null and not co_skip:
		host._player.global_position = eli_spot   # don't yank the player back here after a skip
		lay_player_prone(true)
		show_player_model(true)
	if is_instance_valid(r_eli): r_eli.queue_free()
	if not co_skip:
		thud()
	cut_to(greer, 3.0, 1.5, 1.5, 0.5)
	cap("SGT. GREER", "He was right behind me.", 58.0, "open-greer-behindme")

	# §1.7 YOUNG arrives HARDEST → a crate clips his head → the gate shuts.
	await await_audio(audio, 60.5)
	# Young soars across the room but lands in the CLEARED central landing zone (not
	# deep aft where the evac crowd settles) so the command hand-off frames him + Scott,
	# not a wall of standing extras behind them.
	var young_spot: Vector3 = Vector3(-2.0, 0.05, host.GATE_Z - 7.5)
	var young: StaticBody3D = co_arrival("Colonel Young", "", young_spot, young_spot, "hard",
			host._world.get_node_or_null("ColonelYoung") as StaticBody3D)
	cut_to_spot(young_spot, 3.0, 1.0, 1.6, 0.6)   # low on his landing, not the gate mouth mid-flight
	await await_audio(audio, 63.0)
	launch_impact_crate(young, "head")        # head wound
	await await_audio(audio, 64.0)
	cut_wide(0.5)                                     # SEE the gate shut + vent
	host.lighting.collapse_gate()
	host.lighting.vent_gate_sides()                                 # flame/steam plumes from the gate sides
	host.lighting.collapse_blackout()                               # room plunged into darkness; flames glow through
	host.lighting.flashlights_during_dark()                         # crew flick on flashlights in the gloom
	if cut_cam != null and is_instance_valid(cut_cam) and cut_cam.has_method("shake"):
		cut_cam.call("shake", 0.22, 0.55)             # the room shudders as the gate snuffs out
	await await_audio(audio, 66.0)
	cut_follow(greer, Vector3(2.0, 1.6, 3.0))
	cap("SGT. GREER", "Move, move, move. Stay calm! Keep it down! Move, move, move, move, move.", 66.0, "open-greer-move")

	# Eli groggily climbs to his feet.
	await await_audio(audio, 68.0)
	lay_player_prone(false)

	# §1.8 COMMAND HAND-OFF — Scott crosses to Young; Young passes command; blood; TJ called.
	co_command_handoff(scott, young)
	cut_follow(scott, Vector3(1.8, 1.5, 3.0))
	cap("LT. SCOTT", "Colonel? Colonel?", 72.0, "open-scott-colonel")
	cap("SGT. GREER", "Don't move!", 74.0, "open-greer-dontmove")
	await await_audio(audio, 76.0)
	cut_to(young, 2.2, 0.65, 1.2, 0.6)        # LOW close on Young (floor drama; standing crew sit above frame)
	cap("COL. YOUNG", "Where are we? Where are we?", 76.0, "open-young-whereare")
	cap("LT. SCOTT", "I don't know, sir.", 78.0, "open-scott-idontknow")
	cap("COL. YOUNG", "You're in charge, okay? You're...", 80.0, "open-young-incharge")
	cut_to(scott, 2.6, 1.4, 1.4, 0.6)
	cap("LT. SCOTT", "Yes, sir.", 83.5, "open-scott-yessir")   # blood-on-the-hand beat
	cap("LT. SCOTT", "TJ!", 86.0, "open-scott-tj")
	cut_follow(tj, Vector3(1.8, 1.5, 2.8))
	cap("TJ", "I'm coming!", 88.0, "open-tj-coming")
	cap("SGT. GREER", "Is he okay?", 91.0, "open-greer-isheok")
	cap("TJ", "Uh, I dunno.", 93.0, "open-tj-dunno")

	# §1.8b Scott rounds on Eli (Wallace) to find Rush.
	await await_audio(audio, 96.0)
	cut_to(scott, 3.0, 1.5, 1.5, 0.5)
	cap("LT. SCOTT", "Wallace!", 96.0, "open-scott-wallace")
	cut_to(host._player, 3.0, 1.5, 1.5, 0.5)
	cap("LT. SCOTT", "What is this place?", 99.0, "open-scott-whatisplace")
	cap("ELI", "Look, I just did what Rush told me.", 101.0, "open-eli-didwhat")
	cut_to(scott, 3.0, 1.5, 1.5, 0.5)
	cap("LT. SCOTT", "Where is he?", 104.0, "open-scott-whereishe")
	cut_to(host._player, 3.0, 1.5, 1.5, 0.5)
	cap("ELI", "I don't know if he went ahead of me.", 106.0, "open-eli-wentahead")
	await await_audio(audio, 108.5)
	face_gate(scott)
	cut_to(scott, 3.4, 1.6, 1.6, 0.5)
	cap("LT. SCOTT", "Rush!", 109.0, "open-scott-rush")
	cap("LT. SCOTT", "Rush! Eli, help me find him.", 112.0, "open-scott-findhim")
	cap("ELI", "Well, I...", 114.5, "open-eli-welli")

	# §1.9 THE SHIMMER — the ship jumps to FTL (left-right shake + blur), then the button.
	await await_audio(audio, 118.0)
	ftl_jump()
	Audio.play_sting("impact_jump")           # musical hit on the FTL lurch
	Audio.set_mood("mystery")                 # evac panic gives way to awe
	Cinematic.flash(Color(0.6, 0.8, 1.0, 0.5), 0.6)   # a brief blue shimmer envelops everyone
	cut_wide(0.8)
	cap("SGT. GREER", "What in the hell was that?!", 120.0, "open-greer-whatwasthat")
	cut_to(scott, 3.2, 1.5, 1.6, 0.5)
	cap("LT. SCOTT", "I don't know. Sergeant, I need you to get these people settled here. I need you to find out who and what we've got. Nobody leaves this room.", 123.0, "open-scott-settle")
	cut_to(greer, 3.0, 1.5, 1.5, 0.5)
	cap("SGT. GREER", "Yes, sir.", 133.0, "open-greer-yessir")
	await await_audio(audio, 137.0)
	face_player(scott)
	cut_to(host._player, 2.8, 1.5, 1.4, 0.5)
	cap("LT. SCOTT", "Eli! Now!", 139.0, "open-scott-elinow")

	# §1.10 THE TAKEOVER — Scott RUNS OFF toward the exit to find Rush, and control
	# returns to the player AS Eli, to follow him (the SGU hand-off into gameplay).
	await await_audio(audio, 142.0)
	if not co_skip:
		# Theatrical hand-off: follow Scott breaking for the door before the bars lift.
		Cinematic.set_caption("")
		var exit_spot: Vector3 = Vector3(0.0, 0.05, -host.room_size.y * 0.5 + 3.5)
		if is_instance_valid(scott) and scott.has_method("walk_to"):
			scott.call("walk_to", exit_spot, 5.5, 0.0)   # run speed toward the exit
		cut_follow(scott, Vector3(2.2, 1.8, 4.5))
		await cwait(0.8)
	await finalize_cold_open()


# The cold-open hand-off, run EXACTLY ONCE whether the cinematic played out or was
# skipped (guarded by co_finalized). Stops the bed, lifts the bars, restores the
# player camera, and arms the Find-Rush objective — Scott is left running off toward
# the exit so the reveal is "Eli gives chase". Both the normal tail and the
# hold-to-skip path funnel through here.
# Player held Jump long enough: silence the cinematic and funnel to the hand-off. The
# still-running coroutine sees co_skip and unwinds in a frame (gated waits no-op, crew
# snap to settled spots), then hits the guarded finalize_cold_open() — which we also
# call here so the skip resolves immediately even if the coroutine is mid-await.
func trigger_cold_open_skip() -> void:
	if co_skip:
		return
	co_skip = true
	if is_instance_valid(co_audio):
		co_audio.stop()
	finalize_cold_open()


# Show/hide the "Hold to skip" prompt on the HUD layer (built lazily). Reflects hold
# progress while the button is down so the player knows it's working. The label is
# cached (skip_hint) so the per-frame progress update during a hold doesn't re-scan
# the HUDLayer node path each frame.
func show_skip_hint(show: bool) -> void:
	if not show:
		if skip_hint != null and is_instance_valid(skip_hint):
			skip_hint.queue_free()
		skip_hint = null
		return
	if skip_hint == null or not is_instance_valid(skip_hint):
		var layer: CanvasLayer = host.get_node_or_null("HUDLayer") as CanvasLayer
		if layer == null:
			return
		skip_hint = Label.new()
		skip_hint.name = "SkipHint"
		skip_hint.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.75))
		skip_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		skip_hint.add_theme_constant_override("outline_size", 6)
		skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		skip_hint.position = Vector2(-260.0, -56.0)
		layer.add_child(skip_hint)
	if skip_hold_t > 0.05:
		skip_hint.text = "Skipping… %d%%" % int(clampf(skip_hold_t / SKIP_HOLD_SEC, 0.0, 1.0) * 100.0)
	else:
		skip_hint.text = "Hold [Space] to skip"


func finalize_cold_open() -> void:
	if co_finalized:
		return
	co_finalized = true
	show_skip_hint(false)
	Cinematic.set_caption("")
	# Make sure Scott is running off to find Rush (the skip path never issued this).
	var scott_node: Node = host._world.get_node_or_null("LtScott")
	var exit_spot: Vector3 = Vector3(0.0, 0.05, -host.room_size.y * 0.5 + 3.5)
	if scott_node != null and is_instance_valid(scott_node) and scott_node.has_method("walk_to"):
		scott_node.call("walk_to", exit_spot, 5.5, 0.0)
	if is_instance_valid(co_audio):
		co_audio.queue_free()
	co_audio = null
	# Lights/ambient back to full in case a skip landed during the dark establishing beat.
	host.lighting.flicker_lights_up()
	# DETERMINISTIC END STATE. A skip can fire at any beat, so don't trust the racing
	# coroutine to have flipped these — force the fully-completed gameplay state here:
	#   • the gate is shut/dormant (no lingering open wormhole),
	#   • the player model is visible and standing (not hidden / face-down),
	#   • on a skip, the player stands at a clean spawn facing the exit (the cinematic
	#     left him prone at the gate). Transition-only effects are guarded off (see
	#     collapse_gate / lay_player_prone / the Eli-delivery block / FX funcs).
	# Gate: drop the cinematic's force-open request and let the ONE authority
	# (refresh_gate_state) drive the portal visual — gate_active controls the horizon,
	# so clearing the request + refreshing snuffs the puddle. (arrival_running is
	# cleared below so the refresh isn't short-circuited.)
	host.interactables.gate_forced_open = false
	host.interactables.light_chevrons(0)
	arrival_running = false
	host.interactables.refresh_gate_state()
	show_player_model(true)
	lay_player_prone(false, true)
	if co_skip and host._player != null:
		host._player.global_position = Vector3(0.0, 0.05, 3.5)   # central, clear of the gate
		host._player.rotation.y = 0.0                             # face -Z toward the exit
		var model: Node3D = host._player.get_node_or_null("Character") as Node3D
		if model != null:
			model.rotation.x = 0.0
			model.position.y = 0.0
	await Cinematic.letterbox_out()
	end_cuts()
	# Hand control to the player AS Eli — Scott is already running off; Eli follows.
	restore_player_camera(null)
	if co_skip and host._view != null and host._view.has_method("snap_to_target"):
		host._view.snap_to_target()   # heading is downstream of view yaw — resync after repositioning
	host.interactables.wake_consoles()
	host.npcs.set_arrival_crew_visible(true)
	# Cinematic over: restore crew nametags so the player can ID who's who in the
	# room (anonymous flood extras carry no tag, so only named crew light up).
	cold_open_active = false
	host.npcs.set_crew_nametags_visible(true)
	# Finish run_arrival's post-cinematic cleanup here (a skip funnels through finalize
	# before the awaited coroutine returns): unlock movement and start the ambient bed.
	# (arrival_running was already cleared above so refresh_gate_state snuffed the gate.)
	if host._player != null and host._player.has_method("set_input_locked"):
		host._player.set_input_locked(false)
	host.interactables.start_ambient()
	GameState.met_scott = true
	GameState.advance_air_quest()
	host.npcs.set_scott_autogreet(false)
	# The player regains control here, mid-chase. Wipe the cinematic chatter so the
	# only standing message is Scott calling Eli after him.
	GameState.clear_chat()
	GameState.say("Lt Scott", "Eli — with me! We have to find Rush.")


# Throw a pair of crew (and optionally a crate) head-first through the gate, ≤2 in
# the air. Each crew member is a REAL persistent interactable NPC whose own body is
# the ragdoll that flies through — the SAME body lands, settles, and stays as the
# character (no throwaway-then-spawn swap). Names are real SGU cast.
func extra_pair(a_name: String, a_kind: String, a_spot: Vector3,
		b_name: String, b_kind: String, b_spot: Vector3,
		crate_spot: Vector3 = Vector3.ZERO) -> void:
	var na: StaticBody3D = throw_persistent_crew(a_name, a_kind, a_spot)
	await get_tree().create_timer(0.35).timeout
	var nb: StaticBody3D = throw_persistent_crew(b_name, b_kind, b_spot)
	if crate_spot != Vector3.ZERO:
		launch_crate(crate_spot)
	await get_tree().create_timer(2.3).timeout   # full flight + settle
	# Stop the ragdoll on each body and leave THE SAME body, where it landed, in a
	# beaten-up kneel/sit (nobody pops straight up after a hit like that).
	settle_persistent_crew(na)
	settle_persistent_crew(nb)
	await get_tree().create_timer(0.6).timeout


# Build a REAL interactable crew NPC, dive it HEAD-FIRST through the gate as a
# ragdoll (its own skeleton is the physics body), and return it. After it lands,
# call settle_persistent_crew() to stop the sim and leave the same body in place.
func throw_persistent_crew(display_name: String, kind: String, spot: Vector3,
		existing: StaticBody3D = null) -> StaticBody3D:
	# The gate is a PORTAL: crew RUN through it and emerge at FLOOR level from the
	# BOTTOM of the ring (the puddle meets the deck) — not flung from the centre. Spawn
	# low, just in front of the gate plane, with a slight random side so they don't all
	# come through dead-centre. fly_projectile then carries them low + tumbling.
	var lateral: float = (float((display_name.hash()) % 7) - 3.0) * 0.35
	var origin: Vector3 = Vector3(lateral, 0.55, host.GATE_Z - 1.2)
	var npc: StaticBody3D = existing
	if npc == null:
		# Generic returned-crew body (extras who have no authored scene node).
		npc = host.npcs.build_returned_crew_npc(
			display_name, kind, "res://models/characters/scott.glb", Color.WHITE)
		var tree: Variant = npc.get("dialogue_tree")
		if tree == null or (tree is Array and (tree as Array).is_empty()):
			var generic: Array = [{"speaker": display_name,
				"text": "Still shaking that off. Give me a second.",
				"choices": [{"text": "(nod)", "next": "exit"}]}]
			npc.set("dialogue_tree", generic)
			npc.set("repeat_dialogue_tree", generic)
		npc.position = origin
		npc.set_meta("arrival_spot", spot)
		host._world.add_child(npc)
	else:
		# Re-use a PRE-BUILT scene NPC (Scott, Young) so the SAME body that flies is
		# the one that stays — keeping its authored dialogue / auto_greet / met-flag
		# identity. No throwaway-then-reveal swap (the old "different body appears
		# somewhere else" artifact). It was hidden at cold-open start; reveal it now.
		npc.visible = true
		if "enabled" in npc:
			npc.set("enabled", true)
		npc.global_position = origin
		npc.set_meta("arrival_spot", spot)
	# Fire head-first across the room as a PROJECTILE (clean ballistic arc), NOT a
	# ragdoll. The PhysicalBone joint solver bleeds the launch so hard the body never
	# travels — it flops at the gate, and the old code hid that by TELEPORTING it to
	# the spot at settle (the "lands here / spawns over there" jump). A projectile
	# flies far like it was hurled out of the wormhole and lands EXACTLY on the spot.
	fly_projectile(npc, spot, THROW_FLIGHT_TIME)
	return npc


# Drive `npc` along a ballistic arc from its current position to `spot` over
# `flight` seconds — fired out of the gate STRAIGHT to its landing spot, NO flip.
# The body holds one fixed face-down dive orientation the whole flight (so it can't
# rotate through the floor) and lands FACE DOWN exactly on the spot. Kinematic (we
# integrate the position ourselves), so it always arrives on `spot` (no teleport/
# jump) and the floor-clamp guarantees it never sinks through the deck mid-air.
# Fire-and-forget coroutine; settle_persistent_crew then poses the landed body.
func fly_projectile(npc: StaticBody3D, spot: Vector3, flight: float) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	splash()   # punch-through the wormhole surface as the body leaves the gate
	var origin: Vector3 = npc.global_position
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var disp: Vector3 = spot - origin
	# RUN-THROUGH-A-PORTAL trajectory: the crew emerge LOW (from the bottom of the gate)
	# with forward momentum and TUMBLE across the deck — NOT flung from the centre on a
	# high arc. Horizontal carries them to the landing spot; the vertical pop is CAPPED
	# low so the arc stays flat (a stumble-and-fall, not a launch). A kinematic arc, not
	# a thrown ragdoll (the solver bleeds those into a floor-flop). Snapped to spot at end.
	var vy0: float = clampf((disp.y + 0.5 * g * flight * flight) / flight, 0.0, 3.0)
	var vel: Vector3 = Vector3(disp.x / flight, vy0, disp.z / flight)
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	var yaw: float = atan2(disp.x, disp.z)
	# Per-body tumble STYLE so arrivals don't all do the same rigid dive:
	#   0 = forward somersault, 1 = barrel roll (around travel axis), 2 = mixed flail.
	var style: int = absi(npc.name.hash()) % 3
	var fwd_spin: float = TAU * (2.0 if style != 1 else 0.6)    # head-over-heels turns (pitch)
	var roll_spin: float = TAU * (1.6 if style != 0 else 0.0)   # barrel-roll turns (around forward)
	if model != null and is_instance_valid(model):
		model.rotation = Vector3(PI * 0.35, yaw, 0.0)
		model.position.y = 0.55
	var t: float = 0.0
	while t < flight and is_instance_valid(npc):
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		vel.y -= g * dt
		npc.global_position += vel * dt
		# Collision floor: never let the body sink through the deck while airborne.
		if npc.global_position.y < 0.05:
			npc.global_position.y = 0.05
		# Tumble in the air: forward somersault (pitch) + barrel roll (roll), easing
		# toward a flat sprawl for touchdown so co_roll_settle's roll clip blends in.
		if model != null and is_instance_valid(model):
			var f: float = clampf(t / flight, 0.0, 1.0)
			var land_blend: float = clampf((f - 0.8) / 0.2, 0.0, 1.0)
			var pitch: float = PI * 0.35 + fwd_spin * f
			var roll: float = roll_spin * f * (1.0 - land_blend)
			model.rotation = Vector3(pitch, yaw, roll)
			model.position.y = lerpf(0.55, 0.1, land_blend)
		t += dt
		await get_tree().process_frame
	# Arrive exactly on the aimed spot, FACE DOWN. settle_persistent_crew then either
	# leaves them sprawled face-down or rises them to a kneel/crouch.
	if is_instance_valid(npc):
		npc.global_position = Vector3(spot.x, 0.05, spot.z)
		var mc0: Node3D = first_mc(npc)
		if mc0 != null and mc0.has_method("play_clip"):
			mc0.call("play_clip", "idle")
		thud()


# Stop a thrown crew member's ragdoll and leave THE SAME body where it landed, in
# a beaten-up kneel/crouch/recoil. No swap, no free — this is the persistent
# character. `pose`: "auto" picks a varied injured clip per character; pass an
# explicit clip (e.g. "repair") to force one.
func settle_persistent_crew(npc: StaticBody3D, pose: String = "auto") -> void:
	if npc == null or not is_instance_valid(npc):
		return
	# The projectile already flew the body to its aimed spot (no teleport jump), so
	# this just confirms the position and drops it into the injured pose. (sim is
	# null on the projectile path; the guard keeps it safe if a ragdoll body is ever
	# passed in.)
	var rest: Vector3 = npc.get_meta("arrival_spot", npc.global_position)
	npc.global_position = rest
	var sim: PhysicalBoneSimulator3D = ragdoll_sim(npc)
	if sim != null:
		sim.physical_bones_stop_simulation()
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	var mc: Node3D = first_mc(npc)
	# Pose pool: kneel (repair), low crouch (crouch_idle), or stay sprawled FACE-DOWN
	# (facedown). All land face-down off the throw; the kneel/crouch ones have pushed
	# themselves up to a knee. Deterministic per character so the crowd isn't uniform.
	var clip: String = pose
	if pose == "auto":
		var pool: Array[String] = ["repair", "crouch_idle", "facedown"]
		clip = pool[absi(npc.name.hash()) % pool.size()]
	if clip == "facedown":
		# Knocked flat on their front (NOT on their back) — rotation.x = +PI/2 is the
		# same face-down lay the player prone uses.
		if model != null:
			model.rotation = Vector3(PI * 0.5, PI, 0.0)
			model.position.y = 0.1
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "idle")
	else:
		# Recovered to a knee/crouch — upright again.
		if model != null:
			model.rotation = Vector3(0.0, PI, 0.0)
			model.position.y = 0.0
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", clip)
	thud()   # body hits the deck


# The ModularCharacter under a crew NPC's "Model" holder (or null).
func first_mc(npc: Node) -> Node3D:
	if npc == null:
		return null
	var model: Node = npc.get_node_or_null("Model")
	if model == null:
		return null
	for c: Node in model.get_children():
		return c as Node3D
	return null


# Gated wait used by the cold-open coroutine in place of bare create_timer awaits, so a
# skip collapses every pause to nothing instead of ticking out in real time.
func cwait(t: float) -> void:
	if co_skip:
		return
	await get_tree().create_timer(t).timeout


# Block until the master cold-open track's PLAYHEAD reaches `t` seconds — this is how
# every visual wave + caption stays locked to the recording instead of free-running
# on tuned timers. Falls back to a wall-clock measured from cold_open_start_ms when
# the stream is missing (so it never hangs and never over-waits cumulatively).
func await_audio(player: AudioStreamPlayer, t: float) -> void:
	if co_skip:
		return
	if player != null and is_instance_valid(player) and player.stream != null:
		while is_instance_valid(player) and player.playing and player.get_playback_position() < t:
			await get_tree().process_frame
		return
	var target_ms: int = int(t * 1000.0)
	while (Time.get_ticks_msec() - cold_open_start_ms) < target_ms:
		await get_tree().process_frame


# Fire-and-forget caption cue: await the playhead to `at_t`, then subtitle the
# recording's own line (empty `line` clears the caption). Scheduling these without
# `await` lets the main flow keep pacing the visual waves while captions land on time.
func cap(speaker: String, line: String, at_t: float, vo_id: String = "") -> void:
	if co_skip:
		return
	var player: AudioStreamPlayer = host.get_node_or_null("ColdOpenMaster") as AudioStreamPlayer
	await await_audio(player, at_t)
	if co_skip:
		return
	if line == "":
		Cinematic.set_caption("")
		return
	GameState.add_log("%s: %s" % [speaker, line])
	Cinematic.set_caption("%s — \"%s\"" % [speaker, line])
	# Voiced line (our designed VO) on top of the ambience bed. Fire-and-forget; frees
	# itself when finished. Lines with no baked clip stay caption-only.
	if vo_id == "":
		return
	var path: String = PROLOGUE_VO_DIR + vo_id + ".wav"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var vo: AudioStreamPlayer = AudioStreamPlayer.new()
	vo.name = "ColdOpenVO"
	host.add_child(vo)
	vo.stream = stream
	vo.finished.connect(vo.queue_free)
	vo.play()


# Show a caption + VO RIGHT NOW (no playhead wait). The opening beat is sequenced by
# real timers relative to the dial completion + throw-flight (the dial runs on timers,
# not the bed playhead, so absolute cap times desync there); this fires each line at
# the exact staged moment instead.
func cap_now(speaker: String, line: String, vo_id: String = "") -> void:
	if co_skip:
		return
	if line == "":
		Cinematic.set_caption("")
		return
	GameState.add_log("%s: %s" % [speaker, line])
	Cinematic.set_caption("%s — \"%s\"" % [speaker, line])
	if vo_id == "":
		return
	var path: String = PROLOGUE_VO_DIR + vo_id + ".wav"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var vo: AudioStreamPlayer = AudioStreamPlayer.new()
	vo.name = "ColdOpenVO"
	host.add_child(vo)
	vo.stream = stream
	vo.finished.connect(vo.queue_free)
	vo.play()


# Fire-and-forget crowd/ambient VO: plays the clip WITHOUT a caption (or a brief,
# non-blocking one) and does NOT wait on the playhead or for caption advance. This is
# the key new abstraction for the chaotic evac — overlapping crowd confusion and
# marshalling barks that layer OVER the existing captioned lines, not replacing them.
# Deterministic (the caller picks the timing), and guarded by co_skip.
func cap_crowd(vo_id: String, caption: String = "") -> void:
	if co_skip:
		return
	if vo_id == "":
		return
	if caption != "":
		# Brief non-blocking caption (does not drive the cinematic flow; the primary
		# captioned lines still own the playhead-locked beats).
		Cinematic.set_caption(caption)
	var path: String = PROLOGUE_VO_DIR + vo_id + ".wav"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var vo: AudioStreamPlayer = AudioStreamPlayer.new()
	vo.name = "ColdOpenCrowdVO"
	vo.volume_db = -3.0   # sit just under the primary VO so it reads as background
	host.add_child(vo)
	vo.stream = stream
	vo.finished.connect(vo.queue_free)
	vo.play()


# Play a one-shot SFX clip (e.g. ship shudder, radio click) and auto-free it. No-ops
# cleanly if the asset is missing. Guarded by co_skip.
func co_one_shot(path: String, vol_db: float = 0.0) -> void:
	if co_skip:
		return
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = "ColdOpenSFX"
	p.volume_db = vol_db
	host.add_child(p)
	p.stream = stream
	p.finished.connect(p.queue_free)
	p.play()


# Start a looping ambient bed player. Returns the player (null if the asset is
# missing). Guarded by co_skip.
func co_start_loop(path: String, vol_db: float = -12.0) -> AudioStreamPlayer:
	if co_skip:
		return null
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return null
	if "loop" in stream:
		stream.set("loop", true)
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.volume_db = vol_db
	host.add_child(p)
	p.stream = stream
	p.play()
	return p


# Stop + free a looping bed player (skip-safety). Idempotent.
func co_stop_loop(p: AudioStreamPlayer) -> void:
	if p != null and is_instance_valid(p):
		p.stop()
		p.queue_free()


# Turn Scott to face the (dead) gate — he's calling back through the wormhole / for Rush.
func face_gate(scott: Node3D) -> void:
	if scott == null or not is_instance_valid(scott) or not scott.has_method("look_at"):
		return
	var pt: Vector3 = Vector3(scott.global_position.x, scott.global_position.y, host.GATE_Z)
	if scott.global_position.distance_to(pt) > 0.1:
		scott.look_at(pt, Vector3.UP)


# Turn Scott to face the player (Eli) — for the "Eli! NOW!" button.
func face_player(scott: Node3D) -> void:
	if scott == null or not is_instance_valid(scott) or not scott.has_method("look_at") or host._player == null:
		return
	var pt: Vector3 = Vector3(host._player.global_position.x, scott.global_position.y, host._player.global_position.z)
	if scott.global_position.distance_to(pt) > 0.1:
		scott.look_at(pt, Vector3.UP)


# Turn `node` to face `target` on the horizontal plane (generic version of the two above).
func face_node(node: Node3D, target: Node3D) -> void:
	if node == null or not is_instance_valid(node) or target == null \
			or not is_instance_valid(target) or not node.has_method("look_at"):
		return
	var pt: Vector3 = Vector3(target.global_position.x, node.global_position.y, target.global_position.z)
	if node.global_position.distance_to(pt) > 0.1:
		node.look_at(pt, Vector3.UP)


# WAVE 1 (fire-and-forget): the pre-built LtScott body flies through, lands kneeling,
# rises, and turns back to the gate to wave the rest through.
func co_wave1_scott(scott: StaticBody3D) -> void:
	scott = throw_persistent_crew("Lt Scott", "", Vector3(2.0, 0.05, 2.0), scott)
	await get_tree().create_timer(1.6).timeout
	settle_persistent_crew(scott, "repair")
	await get_tree().create_timer(1.1).timeout
	rise_npc(scott, "idle")
	await get_tree().create_timer(0.5).timeout
	face_gate(scott)
	# Scott moves toward the crew crashing onto the deck in front of the gate — the
	# "Get out of the way!" beat (the line plays at ~6 s in play_prologue_cinematic).
	if is_instance_valid(scott) and scott.has_method("walk_to"):
		scott.call("walk_to", Vector3(1.0, 0.05, host.GATE_Z - 4.5), 2.6, 0.0)
		await get_tree().create_timer(2.2).timeout
		if is_instance_valid(scott) and scott.has_method("stop_walk"):
			scott.call("stop_walk")
		face_gate(scott)


# WAVE 2 (fire-and-forget): Young thrown hardest (off-screen, stays face-down injured)
# + Lt James landing in view as the kneeling medic.
func co_wave2(young: StaticBody3D) -> void:
	young = throw_persistent_crew("Colonel Young", "", Vector3(-3.0, 0.05, -15.0), young)
	await get_tree().create_timer(0.35).timeout
	var james: StaticBody3D = throw_persistent_crew("Lt James", "", Vector3(1.5, 0.05, -2.0))
	await get_tree().create_timer(2.0).timeout
	settle_persistent_crew(young, "facedown")
	settle_persistent_crew(james, "repair")


# COMMAND HAND-OFF (fire-and-forget): during the post-collapse hush Scott breaks for
# the downed Young, kneels to check him over, takes his "you're in charge", finds
# blood on his hand, and calls the medic — who crosses from the medic pocket. Young
# stays face-down (out cold). Subtitled against the master bed in
# play_prologue_cinematic; this only stages the bodies. Every wait is on the audio
# playhead so it stays locked to the recording (and no-ops via the wall-clock fallback
# in headless, where the cinematic is skipped entirely).
func co_command_handoff(scott: StaticBody3D, young: StaticBody3D) -> void:
	if co_skip:
		return
	if not is_instance_valid(scott) or not is_instance_valid(young):
		return
	var audio: AudioStreamPlayer = host.get_node_or_null("ColdOpenMaster") as AudioStreamPlayer
	# Scott crosses to Young (room-left/gate-side of him) the moment the gate snuffs out.
	var beside: Vector3 = Vector3(young.global_position.x + 1.6, 0.05, young.global_position.z)
	await await_audio(audio, 70.0)
	if is_instance_valid(scott) and scott.has_method("walk_to"):
		scott.call("walk_to", beside, 3.2, 0.0)
	# Arrive, stop, kneel beside him and check him over.
	await await_audio(audio, 73.5)
	if is_instance_valid(scott):
		if scott.has_method("stop_walk"):
			scott.call("stop_walk")
		face_node(scott, young)
		rise_npc(scott, "crouch_idle")
	# Scott rocks back — blood on his hand — and stands to take charge.
	await await_audio(audio, 84.0)
	if is_instance_valid(scott):
		rise_npc(scott, "idle")
	# The medic breaks from the pocket to Young.
	await await_audio(audio, 87.5)
	var james: StaticBody3D = host._world.get_node_or_null("LtJames") as StaticBody3D
	if is_instance_valid(james):
		rise_npc(james, "idle")
		if james.has_method("walk_to"):
			james.call("walk_to",
					Vector3(young.global_position.x - 1.4, 0.05, young.global_position.z), 3.4, 0.0)
		await get_tree().create_timer(2.2).timeout
		if is_instance_valid(james):
			if james.has_method("stop_walk"):
				james.call("stop_walk")
			face_node(james, young)
			rise_npc(james, "crouch_idle")


# A console scientist (fire-and-forget): flies through, settles low, then steps onto
# the station and faces the console at x=`console_x`, z=GATE_CONSOLE_Z.
func co_console_crew(disp_name: String, kind: String, spot: Vector3, console_x: float) -> void:
	var n: StaticBody3D = throw_persistent_crew(disp_name, kind, spot)
	await get_tree().create_timer(2.2).timeout
	settle_persistent_crew(n, "crouch_idle")
	man_console_after(n, Vector3(console_x, 0.05, host.GATE_CONSOLE_Z - 1.1), 1.0)


# Play a standing/working clip so a downed crew member rises to their feet. Resets
# the model upright first, so a body that was lying FACE-DOWN stands properly
# instead of playing the clip while still pitched into the deck.
func rise_npc(npc: Node3D, clip: String = "idle") -> void:
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation = Vector3(0.0, PI, 0.0)
		model.position.y = 0.0
	var mc: Node3D = first_mc(npc)
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)


# A body hits the metal deck — play one of the impact one-shots (round-robin,
# varied pitch) to build the panic arrival soundscape. Pool is built on first use.
func thud() -> void:
	if thud_streams.is_empty():
		for p: String in ["res://sounds/land.ogg", "res://sounds/fall.ogg", "res://sounds/break.ogg"]:
			var s: AudioStream = load(p) as AudioStream
			if s != null:
				thud_streams.append(s)
		for i in 4:
			var pl: AudioStreamPlayer = AudioStreamPlayer.new()
			pl.volume_db = -7.0
			host.add_child(pl)
			thud_players.append(pl)
	if thud_streams.is_empty() or thud_players.is_empty():
		return
	var pl2: AudioStreamPlayer = thud_players[thud_i % thud_players.size()]
	pl2.stream = thud_streams[thud_i % thud_streams.size()]
	pl2.pitch_scale = 0.85 + 0.12 * float(thud_i % 3)   # vary so it's not a metronome
	pl2.play()
	# Metallic deck ring layered under the thump — the floor is steel grating, so a
	# body/crate hitting it clangs, not just thumps. bong_001 is the metal resonance.
	if thud_metal == null:
		var ms: AudioStream = load("res://sounds/bong_001.ogg") as AudioStream
		if ms != null:
			thud_metal = AudioStreamPlayer.new()
			thud_metal.stream = ms
			thud_metal.volume_db = -11.0
			host.add_child(thud_metal)
	if thud_metal != null:
		thud_metal.pitch_scale = 0.78 + 0.18 * float(thud_i % 4)   # deep, varied clang
		thud_metal.play()
	# Crew effort grunt — the human panic layer the no-vocals ambience bed strips out.
	# Triggered alongside every thud so each body-impact on the deck has a vocal layer
	# (the grunt pool no-ops cleanly until the grunt assets exist on disk).
	grunt()
	thud_i += 1


# A body or crate breaks the wormhole surface — the "puddle" splash as it punches
# through the gate. Short watery transient (footstep_water pool, pitched down for
# mass), so every single arrival is audible over the ambience bed.
func splash() -> void:
	if splash_streams.is_empty():
		for p: String in ["res://sounds/footstep_water_00.ogg", "res://sounds/footstep_water_01.ogg",
				"res://sounds/footstep_water_02.ogg", "res://sounds/footstep_water_03.ogg"]:
			var s: AudioStream = load(p) as AudioStream
			if s != null:
				splash_streams.append(s)
		for i in 4:
			var pl: AudioStreamPlayer = AudioStreamPlayer.new()
			pl.volume_db = -4.0
			host.add_child(pl)
			splash_players.append(pl)
	if splash_streams.is_empty() or splash_players.is_empty():
		return
	var pl2: AudioStreamPlayer = splash_players[splash_i % splash_players.size()]
	pl2.stream = splash_streams[splash_i % splash_streams.size()]
	pl2.pitch_scale = 0.62 + 0.1 * float(splash_i % 3)   # pitched down = bigger splash
	pl2.play()
	splash_i += 1


# A vocal effort grunt as a body slams onto the deck — the human panic layer the
# no-vocals ambience bed strips out. `_who` is accepted for call-site readability
# (AudioStreamPlayer is non-positional, so it's unused).
func grunt(_who: Node3D = null) -> void:
	if grunt_streams.is_empty():
		for p: String in GRUNT_PATHS:
			var s: AudioStream = load(p) as AudioStream
			if s != null:
				grunt_streams.append(s)
		for i in 3:
			var pl: AudioStreamPlayer = AudioStreamPlayer.new()
			pl.volume_db = -5.0
			host.add_child(pl)
			grunt_players.append(pl)
	if grunt_streams.is_empty() or grunt_players.is_empty():
		return   # no grunt assets yet — silent, never errors
	var pl2: AudioStreamPlayer = grunt_players[grunt_i % grunt_players.size()]
	pl2.stream = grunt_streams[grunt_i % grunt_streams.size()]
	pl2.pitch_scale = 0.9 + 0.13 * float(grunt_i % 3)
	pl2.play()
	grunt_i += 1


# Stand a spawned NPC up after `delay` seconds (fire-and-forget coroutine).
func stand_after(npc: Node3D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	stand_npc(npc)


# Rise a settled crew member to their feet after `delay` (plays a standing clip).
func rise_after(npc: Node3D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	rise_npc(npc)


# Rise a settled operator, walk them onto their console `stand_pos`, then turn them
# to FACE the console (+Z, at z=GATE_CONSOLE_Z) so Park/Volker end up working their
# stations rather than standing idle. Fire-and-forget coroutine.
func man_console_after(npc: Node3D, stand_pos: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(npc):
		return
	rise_npc(npc, "idle")
	await get_tree().create_timer(0.4).timeout
	if not is_instance_valid(npc):
		return
	if npc.has_method("walk_to"):
		npc.call("walk_to", stand_pos, 2.0, 0.0)
	# Let the short walk finish, then stop it and face the console.
	await get_tree().create_timer(2.4).timeout
	if not is_instance_valid(npc):
		return
	if npc.has_method("stop_walk"):
		npc.call("stop_walk")
	var face: Vector3 = Vector3(stand_pos.x, npc.global_position.y, host.GATE_CONSOLE_Z)
	if npc.global_position.distance_to(face) > 0.05:
		npc.look_at(face, Vector3.UP)
	# Drop into the two-handed "working the console" pose (the frozen typing pose
	# authored for Rush) rather than standing idle — Park/Volker man their stations.
	var mc: Node3D = first_mc(npc)
	if mc != null and mc.has_method("pose_console_work"):
		mc.call("pose_console_work")
	else:
		rise_npc(npc, "idle")


# Reveal a PRE-BUILT crew NPC at `pos` (where its thrown body came to rest), play
# an injured `clip`, and thud. Used for Scott, whose walk-up/talk auto-greet is
# wired on the pre-built LtScott node — so we reveal that body rather than keep
# the thrown ragdoll.
func reveal_crew_at(node_name: String, pos: Vector3, clip: String) -> void:
	var npc: Node3D = host._world.get_node_or_null(node_name) as Node3D
	if npc == null:
		return
	npc.global_position = pos
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation = Vector3(0.0, PI, 0.0)
	npc.visible = true
	if "enabled" in npc:
		npc.set("enabled", true)
	var mc: Node3D = first_mc(npc)
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)
	thud()


# ── Crate waves ──────────────────────────────────────────────────────────────

# Ten supply crates hurled through the gate, in pairs with a short stagger, to
# open spots scattered across the room (clear of the consoles, the gate mouth, and
# the player's landing). One skids in next to Sgt Riley. Fire-and-forget.
func launch_crate_wave() -> void:
	if co_skip:
		return
	var spots: Array[Vector3] = [
		Vector3(2.2, 0.05, 2.4), Vector3(-2.6, 0.05, 2.0),
		Vector3(3.6, 0.05, -1.2), Vector3(-3.8, 0.05, -1.0),
		Vector3(4.0, 0.05, -6.3), Vector3(-4.4, 0.05, -5.6),   # first one lands by Sgt Riley
		Vector3(1.6, 0.05, -3.4), Vector3(-1.8, 0.05, -3.0),
		Vector3(5.2, 0.05, -3.6), Vector3(-5.4, 0.05, -3.9),
	]
	for i in range(spots.size()):
		launch_crate(spots[i])
		await get_tree().create_timer(0.45).timeout

# Fire a supply crate out of the gate as a PROJECTILE (same reliable kinematic arc
# the crew use — a RigidBody's launch velocity gets bled/reset the same way, so we
# drive it ourselves). It tumbles through the air and lands FLAT on the deck at
# `target` (which may be on or beside a downed crewman). Returns the crate body.
func launch_crate(target: Vector3) -> Node3D:
	splash()   # a crate breaks the wormhole surface punching through
	var crate: StaticBody3D = StaticBody3D.new()
	crate.name = "ArrivalCrate"
	crate.collision_layer = 1           # solid once landed (player/crew can't walk through)
	crate.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = CRATE_SIZE
	cs.shape = box
	crate.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = CRATE_SIZE
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.30, 0.26, 1.0)   # placeholder crate grey-brown
	mat.metallic = 0.2
	mat.roughness = 0.7
	mi.material_override = mat
	crate.add_child(mi)
	host._world.add_child(crate)
	crate.global_position = Vector3(0.0, host.interactables.gate_center_y(), host.GATE_Z - 0.4)
	arrival_crates.append(crate)
	fly_crate(crate, target, THROW_CRATE_FLIGHT)
	return crate


# Kinematic ballistic arc for a crate: hurls it out of the gate, tumbling in 3D,
# and lands it FLAT (rotation zeroed, resting on its base) exactly at `target`.
func fly_crate(crate: Node3D, target: Vector3, flight: float) -> void:
	if crate == null or not is_instance_valid(crate):
		return
	var origin: Vector3 = crate.global_position
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var rest_y: float = CRATE_SIZE.y * 0.5
	var land: Vector3 = Vector3(target.x, rest_y, target.z)
	var disp: Vector3 = land - origin
	var vel: Vector3 = Vector3(disp.x / flight, (disp.y + 0.5 * g * flight * flight) / flight, disp.z / flight)
	var spin: Vector3 = Vector3(THROW_CRATE_SPIN, THROW_CRATE_SPIN * 0.35, THROW_CRATE_SPIN * 0.6)
	var rot: Vector3 = Vector3.ZERO
	var t: float = 0.0
	while t < flight and is_instance_valid(crate):
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		vel.y -= g * dt
		crate.global_position += vel * dt
		rot += spin * dt
		crate.rotation = rot
		t += dt
		await get_tree().process_frame
	# Land flat on the deck at the target (settles on its base, not an edge).
	if is_instance_valid(crate):
		crate.global_position = land
		crate.rotation = Vector3.ZERO
		thud()


# ── Cold-open arrival: roll in → get up → scramble clear ──────────────────────

func arrival_roll_for(role: String, name_hash: int) -> String:
	match role:
		"scott": return "dive_roll"
		"hard":  return "crash"
		_:       return ARRIVAL_ROLLS[absi(name_hash) % ARRIVAL_ROLLS.size()]

# Build (or reuse `existing`) a crew body, fire it through the gate (kinematic arc),
# land it, play its assigned ROLL upright, push up with get_up, then scramble to
# `clear_spot` to dodge incoming crates. Returns the body. `role`: "scott" | "mil" |
# "civ" | "hard". A "hard" arrival stays down where it lands (crash → prone) — Young.
# `freeze` drops the body out of _process once settled (cheap nameless extras).
func co_arrival(disp_name: String, kind: String, land_spot: Vector3, clear_spot: Vector3,
		role: String = "mil", existing: StaticBody3D = null, freeze: bool = false) -> StaticBody3D:
	# throw_persistent_crew builds/reveals the NPC and fires the ballistic arc.
	var npc: StaticBody3D = throw_persistent_crew(disp_name, kind, land_spot, existing)
	# On skip: don't fly/roll — drop the body straight onto its settled perimeter spot
	# so the unwinding coroutine populates the room without a shower of late arrivals.
	if co_skip:
		if is_instance_valid(npc):
			npc.global_position = clear_spot
			rise_npc(npc, "idle")
		return npc
	co_roll_settle(npc, clear_spot, role, freeze)
	return npc


# Post-throw behaviour for an already-launched body: wait out the arc, play the ROLL
# upright, get up, and scramble to `clear_spot`. Split out so principals can grab the
# node ref from throw_persistent_crew synchronously, then fire this and keep going.
func co_roll_settle(npc: StaticBody3D, clear_spot: Vector3, role: String = "mil", freeze: bool = false) -> void:
	await get_tree().create_timer(THROW_FLIGHT_TIME).timeout   # let the arc land
	if npc == null or not is_instance_valid(npc):
		return
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	var mc: Node3D = first_mc(npc)
	var roll: String = arrival_roll_for(role, npc.name.hash())
	# Upright the model so the roll clip drives the pose (the arc left it face-down).
	if model != null:
		model.rotation = Vector3(0.0, model.rotation.y, 0.0)
		model.position.y = 0.0
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", roll)
	thud()
	if role == "hard":
		return   # crashed hard — stays down where it landed
	await get_tree().create_timer(0.95).timeout
	if not is_instance_valid(npc):
		return
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", "get_up")
	await get_tree().create_timer(1.0).timeout
	# Scramble to the side, out of the landing zone (dodging crates).
	if is_instance_valid(npc) and npc.has_method("walk_to"):
		npc.call("walk_to", clear_spot, 3.2, 0.0)
		await get_tree().create_timer(1.6).timeout
		if is_instance_valid(npc) and npc.has_method("stop_walk"):
			npc.call("stop_walk")
		if is_instance_valid(npc) and mc != null and mc.has_method("play_clip"):
			# A settled evac crowd is a shell-shocked MIX — most drop to a crouch/knee,
			# some stay standing — NOT a wall of idle clones at attention. Low poses also
			# keep heads down so camera cuts to the principals aren't blocked. Deterministic
			# per body so it's stable across frames. Named principals (not frozen) stay
			# standing so they read as active.
			var settle_clip: String = "idle"
			if freeze:
				var pool: Array[String] = ["crouch_idle", "repair", "crouch_idle", "crouch_idle", "idle"]
				settle_clip = pool[absi(npc.name.hash()) % pool.size()]
			mc.call("play_clip", settle_clip)
	if freeze and is_instance_valid(npc):
		npc.set_process(false)   # settled extra — cap cost


func flood_quiet(t: float) -> bool:
	for w in FLOOD_QUIET_WINDOWS:
		if t >= float(w[0]) and t < float(w[1]):
			return true
	return false

# Continuous nameless flood: spawn civ_#/mil_# every ~`gap`s from `from_t` to `to_t`
# (playhead), each rolling in to a scattered spot then scrambling to the perimeter.
# Keeps the gate "always flowing" with ~1-2 bodies/sec. Cheap (frozen once settled).
func co_crowd_flood(audio: AudioStreamPlayer, from_t: float, to_t: float, gap: float = 0.7) -> void:
	await await_audio(audio, from_t)
	var i: int = 0
	var t: float = from_t
	while t < to_t and is_instance_valid(audio) and not co_skip:
		if flood_quiet(t):
			t += gap
			await await_audio(audio, t)
			continue
		var mil: bool = (i % 2) == 0
		var nm: String = ("mil_%d" % i) if mil else ("civ_%d" % i)
		# Scatter landings across the front half of the room…
		var side: float = (-1.0 if (i % 2) else 1.0)
		var sx: float = side * (2.0 + float(i % 5) * 0.9)
		var lz: float = host.GATE_Z - (3.0 + float(i % 6) * 1.4)
		var land: Vector3 = Vector3(sx * 0.5, 0.05, lz)
		# …then everyone scrambles ALL the way to the side walls (room half-width 16)
		# and spreads aft, so the gate mouth + centre landing zone stay clear — nobody
		# loiters in the arrival path (only the scripted injured stay put). Deeper
		# arrivals tuck further back along the wall.
		var clear: Vector3 = Vector3(side * (11.5 + float(i % 4) * 1.2), 0.05,
				host.GATE_Z - (6.0 + float(i % 9) * 1.9))
		co_arrival(nm, ("greer" if mil else ""), land, clear, ("mil" if mil else "civ"), null, true)
		i += 1
		t += gap
		await await_audio(audio, t)


# ── Cold-open crate impact: REAL RigidBody3D that HITS a victim ───────────────

# Hurl a REAL RigidBody crate at `victim` so it physically collides (contact-monitored).
# On first contact with the victim it fires the scripted wound reaction (`wound`:
# "arm" = clutch/limp, "head" = down + blood). The crate then tumbles/settles via
# physics. Returns the crate. Deterministic enough for a headless physics test.
func launch_impact_crate(victim: StaticBody3D, wound: String) -> RigidBody3D:
	if co_skip:
		return null
	splash()   # the heavy impact crate punches through the wormhole
	var crate: RigidBody3D = RigidBody3D.new()
	crate.name = "ImpactCrate"
	crate.mass = 16.0
	crate.contact_monitor = true
	crate.max_contacts_reported = 6
	crate.collision_layer = 1
	crate.collision_mask = 1 | 2          # floor, walls, and crew static bodies (layer 1)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = CRATE_SIZE
	cs.shape = box
	crate.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = CRATE_SIZE
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.24, 1.0)
	mat.metallic = 0.2
	mat.roughness = 0.7
	mi.material_override = mat
	crate.add_child(mi)
	host._world.add_child(crate)
	crate.global_position = Vector3(0.0, host.interactables.gate_center_y(), host.GATE_Z - 0.4)
	arrival_crates.append(crate)
	if victim != null and is_instance_valid(victim):
		var aim: Vector3 = victim.global_position + Vector3(0.0, 0.95, 0.0)
		var disp: Vector3 = aim - crate.global_position
		crate.linear_velocity = disp / IMPACT_CRATE_TIME + Vector3.UP * 2.0
		crate.angular_velocity = Vector3(7.0, 2.0, 4.0)
		crate.body_entered.connect(on_impact_crate_hit.bind(crate, victim, wound))
	return crate


func on_impact_crate_hit(body: Node, crate: RigidBody3D, victim: StaticBody3D, wound: String) -> void:
	if body != victim or not is_instance_valid(victim):
		return
	if crate.get_meta("hit", false):
		return
	crate.set_meta("hit", true)
	wound_crew(victim, wound)
	thud()


# Scripted wound reaction (the crew bodies are static — physics doesn't shove them).
# "arm": clutch and go to a knee (the broken-arm marine). "head": crash flat and stay
# down with a head-wound mark (Col. Young).
func wound_crew(victim: StaticBody3D, wound: String) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	victim.set_meta("wounded", true)
	var model: Node3D = victim.get_node_or_null("Model") as Node3D
	var mc: Node3D = first_mc(victim)
	if wound == "head":
		if model != null:
			model.rotation = Vector3(PI * 0.5, PI, 0.0)   # face-down
			model.position.y = 0.1
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "idle")
		add_head_blood(victim)
	else:   # "arm"
		if model != null:
			model.rotation = Vector3(0.0, model.rotation.y, 0.0)
			model.position.y = 0.0
		if mc != null and mc.has_method("play_clip"):
			mc.call("play_clip", "crouch_idle")   # hunched, favouring the arm


# Small dark-red marker at head height to read as a head wound (placeholder VFX).
func add_head_blood(victim: Node3D) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if victim.get_node_or_null("HeadWound") != null:
		return
	var blood: MeshInstance3D = MeshInstance3D.new()
	blood.name = "HeadWound"
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	blood.mesh = sm
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.albedo_color = Color(0.35, 0.02, 0.02, 1.0)
	bmat.roughness = 0.3
	blood.material_override = bmat
	blood.position = Vector3(0.15, 0.25, 0.0)   # near the head when face-down
	victim.add_child(blood)


# ── Two-person crate carry ────────────────────────────────────────────────────

# After the crew are up, TWO-PERSON teams lift the loose crates and carry them to
# the side walls (out of the way). Crates are split round-robin across the teams;
# each team works through its share one crate at a time. Fire-and-forget.
func carry_crates_to_edges(teams: Array) -> void:
	if teams.is_empty():
		return
	# Round-robin the crates into a per-team queue.
	var queues: Array = []
	for _t in teams:
		queues.append([])
	var i: int = 0
	for crate in arrival_crates:
		if is_instance_valid(crate):
			queues[i % teams.size()].append(crate)
			i += 1
	for ti in range(teams.size()):
		team_carry_loop(teams[ti], queues[ti], float(ti) * 0.8)

# One two-person team carries its whole list of crates to the walls, one at a time.
func team_carry_loop(team: Array, crates: Array, start_delay: float) -> void:
	if team.size() < 2:
		return
	await get_tree().create_timer(start_delay).timeout
	var a: Node3D = team[0]
	var b: Node3D = team[1]
	var half_x: float = host.room_size.x * 0.5 - 1.6
	var idx: int = 0
	for crate in crates:
		if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
			continue
		# Stack along the wall on the crate's own side, spaced by z so they don't pile up.
		var cp: Vector3 = (crate as Node3D).global_position
		var dest: Vector3 = Vector3(signf(cp.x) * half_x, CRATE_SIZE.y * 0.5,
			clampf(cp.z + float(idx) * 0.2, -host.room_size.y * 0.5 + 2.0, host.room_size.y * 0.5 - 2.0))
		await two_person_carry(crate as Node3D, a, b, dest)
		idx += 1

# Two crew flank `crate` (one on each side), LIFT it to carry height, walk it to
# `dest` with the crate riding the midpoint BETWEEN them the whole way, then set it
# down. Awaitable so a team carries its crates sequentially.
func two_person_carry(crate: Node3D, a: Node3D, b: Node3D, dest: Vector3) -> void:
	if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
		return
	var cp: Vector3 = crate.global_position
	# Phase 1 — get up and walk to opposite sides of the crate (obstacle-aware walk).
	rise_npc(a, "idle")
	rise_npc(b, "idle")
	if a.has_method("walk_to"):
		a.call("walk_to", Vector3(cp.x - CRATE_FLANK, 0.05, cp.z), 2.3, 0.0)
	if b.has_method("walk_to"):
		b.call("walk_to", Vector3(cp.x + CRATE_FLANK, 0.05, cp.z), 2.3, 0.0)
	await get_tree().create_timer(2.0).timeout
	if not (is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b)):
		return
	# Phase 2 — both stop walking and hold a carry pose; lift the crate between them.
	if a.has_method("stop_walk"): a.call("stop_walk")
	if b.has_method("stop_walk"): b.call("stop_walk")
	face(a, crate.global_position); face(b, crate.global_position)
	play_clip_on(a, "walk_carry"); play_clip_on(b, "walk_carry")
	var lift: Tween = host.create_tween()
	lift.tween_property(crate, "global_position:y", CRATE_CARRY_HEIGHT, 0.5).set_trans(Tween.TRANS_SINE)
	await lift.finished
	# Phase 3 — manually walk both carriers to the dest flanks (manual move keeps the
	# walk_carry pose, which the NPC walker would otherwise overwrite with "walk"),
	# crate tracking their midpoint at carry height.
	var da: Vector3 = Vector3(dest.x - CRATE_FLANK, 0.05, dest.z)
	var db: Vector3 = Vector3(dest.x + CRATE_FLANK, 0.05, dest.z)
	var speed: float = 1.5
	var t: float = 0.0
	while t < 6.0 and is_instance_valid(crate) and is_instance_valid(a) and is_instance_valid(b):
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		var travel: Vector3 = (da - a.global_position); travel.y = 0.0
		a.global_position = a.global_position.move_toward(Vector3(da.x, 0.05, da.z), speed * dt)
		b.global_position = b.global_position.move_toward(Vector3(db.x, 0.05, db.z), speed * dt)
		if travel.length() > 0.05:
			face(a, da); face(b, db)
		var mid: Vector3 = (a.global_position + b.global_position) * 0.5
		crate.global_position = Vector3(mid.x, CRATE_CARRY_HEIGHT, mid.z)
		t += dt
		if a.global_position.distance_to(Vector3(da.x, 0.05, da.z)) < 0.25 \
				and b.global_position.distance_to(Vector3(db.x, 0.05, db.z)) < 0.25:
			break
		await get_tree().process_frame
	# Phase 4 — set the crate down at the wall; carriers stand off.
	if is_instance_valid(crate):
		var down: Tween = host.create_tween()
		down.tween_property(crate, "global_position", Vector3(dest.x, CRATE_SIZE.y * 0.5, dest.z), 0.5).set_trans(Tween.TRANS_SINE)
		await down.finished
	if is_instance_valid(a): play_clip_on(a, "idle")
	if is_instance_valid(b): play_clip_on(b, "idle")


# Face a crew body toward a world point (model holder convention handled by look_at).
func face(npc: Node3D, target: Vector3) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var flat: Vector3 = Vector3(target.x, npc.global_position.y, target.z)
	if npc.global_position.distance_to(flat) > 0.05:
		npc.look_at(flat, Vector3.UP)


# Play a body clip on an NPC's ModularCharacter (no orientation reset, unlike rise_npc).
func play_clip_on(npc: Node3D, clip: String) -> void:
	var mc: Node3D = first_mc(npc)
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)


# Hand a flying-through ragdoll off to a PRE-BUILT, PRE-POSED tableau NPC (Young
# prone): reposition the NPC to its expected landing spot, reveal it, then free
# the ragdoll the SAME frame so the body appears to settle into the character (no
# vanish). Keeps the NPC's authored pose.
func handoff_tableau(rag: Node3D, node_name: String, pos: Vector3) -> void:
	var npc: Node3D = host._world.get_node_or_null(node_name) as Node3D
	if npc != null:
		npc.global_position = pos
		npc.visible = true
		if "enabled" in npc:
			npc.set("enabled", true)
	if is_instance_valid(rag):
		rag.queue_free()


# Spawn a recovered crew NPC face-down at `pos` (where their ragdoll landed),
# visible immediately. Returns the node so the caller can stand it up later.
func spawn_crew_prone(display_name: String, kind: String, pos: Vector3) -> StaticBody3D:
	var npc: StaticBody3D = host.npcs.build_returned_crew_npc(
		display_name, kind, "res://models/characters/scott.glb", Color.WHITE)
	var tree: Variant = npc.get("dialogue_tree")
	if tree == null or (tree is Array and (tree as Array).is_empty()):
		var generic: Array = [{"speaker": display_name,
			"text": "Still shaking that off. Give me a second.",
			"choices": [{"text": "(nod)", "next": "exit"}]}]
		npc.set("dialogue_tree", generic)
		npc.set("repeat_dialogue_tree", generic)
	npc.position = pos
	npc.rotation.y = 0.0
	host._world.add_child(npc)
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = PI * 0.5   # face-down
		model.position.y = 0.1
	return npc


# Stand a spawned NPC up (groggy, unsteady) — push up from face-down.
func stand_npc(npc: Node3D) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var t: Tween = host.create_tween().set_parallel(true)
	t.tween_property(model, "rotation:x", 0.0, 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 0.0, 1.8)


# Move the player rig to its WAVE-2 landing spot, lay it prone, and hide the body
# until the ragdoll toss "delivers" Eli there.
func place_player_for_toss(spot: Vector3) -> void:
	if host._player == null:
		return
	host._player.global_position = spot
	lay_player_prone(true)
	show_player_model(false)


func show_player_model(vis: bool) -> void:
	if host._player == null:
		return
	var model: Node = host._player.get_node_or_null("Character")
	if model is Node3D:
		(model as Node3D).visible = vis


func reveal_crew_member(node_name: String) -> void:
	var n: Node = host._world.get_node_or_null(node_name)
	if n is Node3D:
		(n as Node3D).visible = true


# Move a persistent NPC to `pos` and tip its Model node prone (rotation.x = -PI*0.5),
# then make it visible. Used by Wave 1 so Scott crumples at his ragdoll rest spot
# before standing up a moment later via stand_crew_member.
func place_crew_prone(node_name: String, pos: Vector3) -> void:
	var npc: Node3D = host._world.get_node_or_null(node_name) as Node3D
	if npc == null:
		return
	npc.global_position = pos
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = PI * 0.5   # face-DOWN (they get up by pushing off the deck)
		model.position.y = 0.1
	npc.visible = true


# Tween a persistent NPC's Model node from prone back to upright (same tween
# as lay_player_prone(false)). Used after place_crew_prone to animate standing.
func stand_crew_member(node_name: String) -> void:
	var npc: Node3D = host._world.get_node_or_null(node_name) as Node3D
	if npc == null:
		return
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model == null:
		return
	var t: Tween = host.create_tween().set_parallel(true)
	t.tween_property(model, "rotation:x", 0.0, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 0.0, 1.1)


# After the crew have landed and lain there, they recover: Dr Park and Dr Volker
# pick themselves up (staggered) and walk over to man the two operator consoles;
# Rush and Brody also get up (later) and file out the exit corridor.
# Young stays permanently prone (injured); James stays kneeling (no walker for them).
# `rest_positions` maps character name → ragdoll rest position on the floor.
func recover_crew(rest_positions: Dictionary) -> void:
	var half_z: float = host.room_size.y * 0.5
	# Stand the operators just in front of the ROOM's real consoles (GateControlConsole
	# at x=-3.5, FTLConsole at x=+3.5, both at z=GATE_CONSOLE_Z), on the arrival (-Z)
	# side where the controls face, looking back at the console.
	var console_l: Vector3 = Vector3(-3.5, 0.05, host.GATE_CONSOLE_Z - 1.1)   # GateControlConsole
	var console_r: Vector3 = Vector3(3.5, 0.05, host.GATE_CONSOLE_Z - 1.1)    # FTLConsole
	var exit_pos: Vector3 = Vector3(0.0, 0.05, -half_z + 3.2)    # toward the corridor door
	# All four walkers are called without await so they run as concurrent coroutines.
	# get_up_delay staggers when each one starts standing up — long, uneven gaps so
	# the crew read as dazed and disoriented, picking themselves up one at a time.
	recover_walker("Dr Park",  "park",  rest_positions.get("Dr Park",  console_l), console_l, false, 1.6)
	recover_walker("Dr Volker","volker",rest_positions.get("Dr Volker",console_r), console_r, false, 3.0)
	recover_walker("Dr Rush",  "rush",  rest_positions.get("Dr Rush",  exit_pos),  exit_pos,  true,  4.4)
	recover_walker("Dr Brody", "brody", rest_positions.get("Dr Brody", exit_pos),  exit_pos,  true,  5.6)


# Spawn one recovered crew member at where they landed, crumpled on the floor.
# After `get_up_delay` seconds they groggily stand, then walk to their post.
# `leave` = true means they're heading out (despawn once they reach the corridor);
# false means they stay (e.g. manning a console). Multiple callers fire this
# concurrently (no await in recover_crew), so each walker is its own coroutine.
func recover_walker(display_name: String, kind: String, from: Vector3, to: Vector3,
		leave: bool, get_up_delay: float = 0.0) -> void:
	var npc: StaticBody3D = host.npcs.build_returned_crew_npc(
		display_name, kind, "res://models/characters/scott.glb", Color.WHITE)
	# Anyone the returned-crew builder didn't author a line for gets a placeholder
	# so interacting can't error.
	var tree: Variant = npc.get("dialogue_tree")
	if tree == null or (tree is Array and (tree as Array).is_empty()):
		var generic: Array = [{"speaker": display_name,
			"text": "Still shaking that off. Give me a second.",
			"choices": [{"text": "(nod)", "next": "exit"}]}]
		npc.set("dialogue_tree", generic)
		npc.set("repeat_dialogue_tree", generic)
	npc.position = from
	npc.rotation.y = 0.0
	# Lay prone before adding to tree so the first visible frame is crumpled.
	host._world.add_child(npc)
	var model: Node3D = npc.get_node_or_null("Model") as Node3D
	if model != null:
		model.rotation.x = PI * 0.5   # face-DOWN (they get up by pushing off the deck)
		model.position.y = 0.1

	# Stagger: wait for this character's personal get-up timer.
	await get_tree().create_timer(get_up_delay).timeout
	if not is_instance_valid(npc):
		return

	# Stand up groggily — a slow, unsteady push to the feet (disoriented).
	model = npc.get_node_or_null("Model") as Node3D
	if model != null and is_instance_valid(model):
		var t: Tween = host.create_tween().set_parallel(true)
		t.tween_property(model, "rotation:x", 0.0, 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(model, "position:y", 0.0, 1.8)
	await get_tree().create_timer(1.8).timeout   # wait for stand tween to complete
	if not is_instance_valid(npc):
		return

	# Now walk to post.
	if npc.has_method("walk_to"):
		npc.call("walk_to", to, 2.4, 0.0)
	if leave:
		# Walked off down the corridor — remove once they've had time to reach it.
		await get_tree().create_timer(6.0).timeout
		if is_instance_valid(npc):
			npc.queue_free()


# Launch one throwaway ragdoll on a ballistic arc from the event horizon toward a
# landing spot (so Young can be thrown demonstrably farther than Eli). The body's
# PhysicalBone3D bones ARE the physics — they fall under their own gravity and
# carry the launch velocity, tumbling limb-by-limb. The root Node3D stays at the
# gate (the bones move in world space), so read the landed spot from the hips bone
# via ragdoll_rest_pos(). Returns the root so the caller can free it once settled.
func launch_ragdoll(character: String, target: Vector3) -> Node3D:
	splash()   # the body breaks the wormhole surface (e.g. Eli/Young hurled through)
	var root: Node3D = make_ragdoll(character)
	host._world.add_child(root)
	# Position the body at the event-horizon mouth BEFORE building the bones so they
	# start simulating from the correct world position.
	var origin: Vector3 = Vector3(0.0, host.interactables.gate_center_y(), host.GATE_Z - 0.4)
	root.global_position = origin
	# Ballistic solve: reach target.y at t=flight under gravity.
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var flight: float = 1.8
	var disp: Vector3 = target - origin
	var vy: float = (disp.y + 0.5 * g * flight * flight) / flight
	var launch_vel: Vector3 = Vector3(disp.x / flight, vy, disp.z / flight)
	# Hard tumble — magnitude scales with throw distance (deterministic, no RNG).
	var spin: float = 4.0 + absf(disp.z) * 0.6
	var launch_ang: Vector3 = Vector3(spin, spin * 0.5, spin * 0.7)
	# Build the physical skeleton and start it WITH the launch velocity in the same
	# frame, so every bone leaves the gate on one arc (no 1-frame free-fall gap).
	setup_ragdoll_physics(root, launch_vel, launch_ang)
	return root


# The RagdollSim simulator under a ragdoll root (or null).
func ragdoll_sim(root: Node3D) -> PhysicalBoneSimulator3D:
	var model: Node3D = root.get_node_or_null("Model")
	if model == null:
		return null
	var mc: Node3D = null
	for c: Node in model.get_children():
		mc = c as Node3D
		break
	if mc == null:
		return null
	var skel: Skeleton3D = find_skel_in_mc(mc)
	if skel == null:
		return null
	return skel.get_node_or_null("RagdollSim") as PhysicalBoneSimulator3D


# Where the ragdoll actually came to rest — the hips bone's world position (the
# root never moves; only the bones do). Falls back to the root position.
func ragdoll_rest_pos(root: Node3D) -> Vector3:
	var sim: PhysicalBoneSimulator3D = ragdoll_sim(root)
	if sim != null:
		var hips: Node = sim.get_node_or_null("PB_Hips")
		if hips is Node3D:
			var p: Vector3 = (hips as Node3D).global_position
			return Vector3(p.x, 0.05, p.z)
	return Vector3(root.global_position.x, 0.05, root.global_position.z)


# ── Cinematic camera ─────────────────────────────────────────────────────────

# Temp head-on Camera3D under the room, made current for the cold open. The
# player's SpringArm camera is restored by restore_player_camera(). The camera
# starts closer on the gate and DOLLIES BACK (pulls out) across the cinematic,
# revealing the whole cavernous room as the crew scatter across it — no shake.
func make_cinematic_camera() -> Camera3D:
	var cam: Camera3D = Camera3D.new()
	cam.name = "PrologueCam"
	cam.fov = 62.0
	host.add_child(cam)
	# Start closer on the gate; pull BACK (z more negative = away from the gate =
	# zoom OUT) over the cinematic, ending shy of the rear mezzanine (z≈-11.8) so the
	# camera stays in the open and doesn't clip the back balcony deck.
	var start_z: float = host.GATE_Z - 19.0
	var end_z: float = host.GATE_Z - 24.0
	cam.global_position = Vector3(0.0, 5.5, start_z)
	cam.look_at(Vector3(0.0, 1.4, host.GATE_Z - 9.0), Vector3.UP)
	cam.make_current()
	var t: Tween = host.create_tween()
	t.tween_property(cam, "global_position:z", end_z, 88.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return cam


func restore_player_camera(cam: Camera3D) -> void:
	var pcam: Camera3D = host.get_node_or_null("View/SpringArm/Camera")
	if pcam != null:
		pcam.make_current()
		if host._view != null and host._view.has_method("snap_to_target"):
			host._view.snap_to_target()
	if cam != null and is_instance_valid(cam):
		cam.queue_free()


# ── Cold-open camera cuts (cut-to-speaker) + FTL jump ─────────────────────────

# Spin up the cut camera (captures whatever camera is current for restore).
func begin_cuts() -> void:
	if cut_cam != null and is_instance_valid(cut_cam):
		return
	cut_cam = StandoffCameraScript.new()
	cut_cam.name = "ColdOpenCutCam"
	host.add_child(cut_cam)
	if cut_cam.has_method("configure"):
		cut_cam.call("configure", 50.0, 0.0)   # centred framing (no dialog window to dodge)
	if cut_cam.has_method("activate"):
		cut_cam.call("activate")

# Hard-cut/glide to frame `node` (the speaker). side/height/dist compose the shot.
func cut_to(node: Node3D, dist: float = 3.4, height: float = 1.5, side: float = 1.6, dur: float = 0.6) -> void:
	if cut_cam == null or not is_instance_valid(cut_cam) or node == null or not is_instance_valid(node):
		return
	var look: Vector3 = node.global_position + Vector3.UP * 1.4
	var pos: Vector3 = node.global_position + Vector3(side, height, dist)
	if cut_cam.has_method("frame"):
		cut_cam.call("frame", pos, look, dur, 0.05)

# Frame a fixed WORLD spot. Use this for a crew member we cut to in the same breath
# as co_arrival(): the body is still at the gate origin mid-flight at that instant,
# so cut_to(body) frames the wormhole mouth (fullscreen blue) — cut to where they're
# LANDING instead and the body rolls into a correctly-composed shot.
func cut_to_spot(spot: Vector3, dist: float = 3.4, height: float = 1.5, side: float = 1.6, dur: float = 0.6) -> void:
	if cut_cam == null or not is_instance_valid(cut_cam):
		return
	var look: Vector3 = spot + Vector3.UP * 1.2
	var pos: Vector3 = spot + Vector3(side, height, dist)
	if cut_cam.has_method("frame"):
		cut_cam.call("frame", pos, look, dur, 0.05)

# Track a moving subject (Scott crossing, TJ crossing in).
func cut_follow(node: Node3D, offset: Vector3 = Vector3(1.6, 1.5, 3.0), dur: float = 0.6) -> void:
	if cut_cam == null or not is_instance_valid(cut_cam) or node == null or not is_instance_valid(node):
		return
	if cut_cam.has_method("follow"):
		cut_cam.call("follow", node, offset, dur, 1.4)

# Wide establishing shot of the gate/landing zone.
func cut_wide(dur: float = 1.0) -> void:
	if cut_cam == null or not is_instance_valid(cut_cam):
		return
	var pos: Vector3 = Vector3(0.0, 5.5, host.GATE_Z - 20.0)
	var look: Vector3 = Vector3(0.0, 1.4, host.GATE_Z - 8.0)
	if cut_cam.has_method("frame"):
		cut_cam.call("frame", pos, look, dur, 0.02)

# The SGU "Air" opening establishing shot: a LOW angle from the back of the dark
# room looking straight down the amber-lit walkway to the active gate at the far
# end (matches the reference still). Near-floor camera so the receding floor strips
# + the bright gate dominate the frame.
func cut_establishing(dur: float = 1.0) -> void:
	if cut_cam == null or not is_instance_valid(cut_cam):
		return
	var half_z: float = host.room_size.y * 0.5
	var pos: Vector3 = Vector3(0.0, 1.0, -half_z + 1.5)
	var look: Vector3 = Vector3(0.0, 2.4, host.GATE_Z)
	if cut_cam.has_method("frame"):
		cut_cam.call("frame", pos, look, dur, 0.0)

func end_cuts() -> void:
	if cut_cam != null and is_instance_valid(cut_cam):
		if cut_cam.has_method("release"):
			cut_cam.call("release")
		cut_cam.queue_free()
	cut_cam = null

# The FTL jump: the ship lurches into faster-than-light. Repeated LEFT-RIGHT shake
# (shake_y_scale low) + box-blur over the whole world, with the jump whoosh. Spawns
# the FtlDrop overlay directly (NOT GameState.trigger_ftl_drop, which is gated on the
# later air-crisis state) so it's purely a cold-open visual.
func ftl_jump() -> void:
	if co_skip:
		return
	var fx: FtlDrop = FtlDrop.new()
	fx.sound_path = FTL_JUMP_SOUND_COLDOPEN   # enhanced Destiny FTL-jump whoosh
	fx.shake_y_scale = 0.2   # bias to a repeated left-right jolt
	get_tree().root.add_child(fx)


# Tip the player's visual body onto its back (prone) or stand it upright. Only
# the Character model is rotated — the physics capsule stays vertical so nothing
# downstream (camera target, idle facing) is disturbed.
func lay_player_prone(prone: bool, force: bool = false) -> void:
	# Skip in progress: the racing coroutine must not re-prone the player after the
	# finalize stood him up. `force` lets finalize itself still drive the un-prone.
	if co_skip and not force:
		return
	if host._player == null:
		return
	var model: Node3D = host._player.get_node_or_null("Character")
	if model == null:
		return
	if prone:
		# Snap flat instantly (Eli is already down when the scene opens).
		model.rotation.x = PI * 0.5   # face-DOWN (they get up by pushing off the deck)
		model.position.y = 0.1
	else:
		# Groggily push up to standing — slow and unsteady (disoriented).
		var t: Tween = host.create_tween().set_parallel(true)
		t.tween_property(model, "rotation:x", 0.0, 1.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(model, "position:y", 0.0, 1.9)


# ── Ragdoll physics ───────────────────────────────────────────────────────────

# One throwaway ragdoll: RigidBody3D root wrapper + Quaternius skeletal body.
# NOTE: the skeleton + PhysicalBone3D setup is deferred to setup_ragdoll_physics,
# which launch_ragdoll calls after _world.add_child(rb) so that mc._ready() has
# fired (ModularCharacter._ready builds _skel and the base gltf). If called before
# the node is in the scene tree, mc._ready() does not fire, _skel stays null,
# and find_skel_in_mc returns null — hence the two-phase design.
func make_ragdoll(character: String) -> Node3D:
	# Static root — the bones (PhysicalBone3D) own all motion in world space, so the
	# root just anchors the initial pose at the gate mouth and never moves itself.
	var root: Node3D = Node3D.new()
	root.name = "Ragdoll_" + character.replace(" ", "")
	root.set_meta("ragdoll_character", character)

	# Visual + skeleton holder. The crew were RUNNING when the gate flung them
	# through, so they enter DIVING HEAD-FIRST: pitch the body forward to near-
	# horizontal (head leading toward the room, -Z) — the limbs then flail behind
	# under the launch (torso gets the speed, limbs trail; see setup_ragdoll_physics).
	var holder: Node3D = Node3D.new()
	holder.name = "Model"
	holder.rotation = Vector3(-PI * 0.5, PI, 0.0)
	root.add_child(holder)

	# Build the Quaternius modular body and attach it. mc._ready() fires once root
	# is added to _world (in launch_ragdoll), populating its Skeleton3D.
	var mc: Node3D = CharacterFactoryRef.build_modular(character)
	if mc != null:
		holder.add_child(mc)
		CharacterFactoryRef.dress_modular(mc, character, CharacterFactoryRef.CTX_SHIP)
	return root


# Build the PhysicalBoneSimulator3D + 13 PhysicalBone3D limbs under the body's
# Skeleton3D, start the simulation, and impart the launch velocity to every bone
# in the SAME frame so the whole skeleton leaves the gate on one ballistic arc and
# tumbles limb-by-limb. Called after _world.add_child(root) so mc._ready() has fired.
func setup_ragdoll_physics(root: Node3D, vel: Vector3, ang: Vector3) -> void:
	var model: Node3D = root.get_node_or_null("Model")
	if model == null:
		return
	var mc: Node3D = null
	for c: Node in model.get_children():
		mc = c as Node3D
		break
	if mc == null:
		return

	# mc._ready() has fired (root is in the tree) → _skel is populated. Stop the
	# autoplay so bones start from the rest pose, not mid-walk.
	stop_anim(mc)

	var skel: Skeleton3D = find_skel_in_mc(mc)
	if skel == null:
		var char_name: String = String(root.get_meta("ragdoll_character", "?"))
		push_warning("setup_ragdoll_physics: Skeleton3D not found for '%s'" % char_name)
		return

	# Create the PhysicalBoneSimulator3D as a direct child of the Skeleton3D.
	# Godot resolves bone IDs via Skeleton3D → PhysicalBoneSimulator3D → PhysicalBone3D.
	var sim: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()
	sim.name = "RagdollSim"
	skel.add_child(sim)

	# --- Major bones with capsule sizes for Quaternius humanoid proportions ---
	# Base model is ~1.85 m at default scale; sizes are in world-space metres.
	# collision_layer=0 → bones are not hittable by raycasts.
	# collision_mask=1 → bones collide with floor/walls (layer 1), not player (layer 2).
	# Torso chain — TIGHT swing/twist so the spine can't fold backwards at the waist.
	make_physical_bone(sim, "Hips",       0.15, 0.30, PhysicalBone3D.JOINT_TYPE_CONE, 18.0, 12.0)
	make_physical_bone(sim, "Spine",      0.13, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 18.0, 12.0)
	make_physical_bone(sim, "Chest",      0.14, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 16.0, 12.0)
	make_physical_bone(sim, "UpperChest", 0.13, 0.22, PhysicalBone3D.JOINT_TYPE_CONE, 16.0, 12.0)
	make_physical_bone(sim, "Head",       0.12, 0.24, PhysicalBone3D.JOINT_TYPE_CONE, 30.0, 20.0)
	# Arms — shoulders swing wide, elbows are one-way hinges.
	make_physical_bone(sim, "LeftUpperArm",  0.07, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 70.0, 30.0)
	make_physical_bone(sim, "RightUpperArm", 0.07, 0.28, PhysicalBone3D.JOINT_TYPE_CONE, 70.0, 30.0)
	make_physical_bone(sim, "LeftLowerArm",  0.06, 0.26, PhysicalBone3D.JOINT_TYPE_HINGE)
	make_physical_bone(sim, "RightLowerArm", 0.06, 0.26, PhysicalBone3D.JOINT_TYPE_HINGE)
	# Legs — hips swing moderately, knees are one-way hinges.
	make_physical_bone(sim, "LeftUpperLeg",  0.10, 0.38, PhysicalBone3D.JOINT_TYPE_CONE, 50.0, 20.0)
	make_physical_bone(sim, "RightUpperLeg", 0.10, 0.38, PhysicalBone3D.JOINT_TYPE_CONE, 50.0, 20.0)
	make_physical_bone(sim, "LeftLowerLeg",  0.08, 0.36, PhysicalBone3D.JOINT_TYPE_HINGE)
	make_physical_bone(sim, "RightLowerLeg", 0.08, 0.36, PhysicalBone3D.JOINT_TYPE_HINGE)

	# Log any bones that failed to resolve — silent failure = no per-bone tumble.
	var char_name2: String = String(root.get_meta("ragdoll_character", "?"))
	for pb_child: Node in sim.get_children():
		if pb_child is PhysicalBone3D:
			var pb: PhysicalBone3D = pb_child as PhysicalBone3D
			if pb.get_bone_id() < 0:
				push_warning("setup_ragdoll_physics: bone '%s' unresolved for '%s'" % [pb.bone_name, char_name2])

	# Start the per-bone physics simulation, then impart the throw. EVERY bone gets
	# the full launch velocity so the body's centre of mass reaches the aimed spot
	# (no undershoot/clustering). The head-first DIVE orientation (set in
	# make_ragdoll) makes it enter head-first; the limbs get extra spin so the arms and
	# legs FLAIL behind during the flight (running-through-the-gate look).
	var lead_bones := {"Hips": true, "Spine": true, "Chest": true, "UpperChest": true, "Head": true}
	sim.physical_bones_start_simulation()
	for pb_child2: Node in sim.get_children():
		if pb_child2 is PhysicalBone3D:
			var pb2: PhysicalBone3D = pb_child2 as PhysicalBone3D
			pb2.linear_velocity = vel
			if lead_bones.has(pb2.bone_name):
				pb2.angular_velocity = ang
			else:
				pb2.angular_velocity = ang * 1.3   # limbs flail (modest — too much bleeds travel)


# Recursive depth-first search for the Skeleton3D inside a ModularCharacter node.
# ModularCharacter.skeleton() returns _skel if mc has already entered the tree
# (its _ready has fired). Falling back to a recursive walk handles edge cases where
# the method is unavailable or returns null.
func find_skel_in_mc(mc: Node3D) -> Skeleton3D:
	if mc.has_method("skeleton"):
		var s: Variant = mc.call("skeleton")
		if s is Skeleton3D:
			return s as Skeleton3D
	var stack: Array = [mc as Node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n as Skeleton3D
		for c: Node in n.get_children():
			stack.append(c)
	return null


# Create one PhysicalBone3D child of `sim`, assigned to `p_bone_name` on the
# parent Skeleton3D, with a CapsuleShape3D collider. collision_layer=0 so the
# bone is not a hittable target; collision_mask=1 so it reacts to floor/walls.
func make_physical_bone(
		sim: PhysicalBoneSimulator3D,
		p_bone_name: String,
		cap_radius: float,
		cap_height: float,
		j_type: int,
		swing_deg: float = 40.0,
		twist_deg: float = 25.0) -> PhysicalBone3D:
	var pb: PhysicalBone3D = PhysicalBone3D.new()
	pb.name = "PB_" + p_bone_name
	pb.bone_name = p_bone_name
	pb.joint_type = j_type
	pb.collision_layer = 0
	pb.collision_mask = 1
	pb.mass = 4.0
	# Heavier damping so the body settles into a believable heap instead of
	# flailing/jittering into broken-looking poses.
	pb.linear_damp = 1.2
	pb.angular_damp = 2.0
	# Joint limits keep the body in a HUMAN range of motion — no folding backwards
	# at the waist or hyperextending elbows/knees (joint_constraints spans are in
	# degrees on PhysicalBone3D).
	if j_type == PhysicalBone3D.JOINT_TYPE_CONE:
		pb.set("joint_constraints/swing_span", swing_deg)
		pb.set("joint_constraints/twist_span", twist_deg)
		pb.set("joint_constraints/relaxation", 1.0)
	elif j_type == PhysicalBone3D.JOINT_TYPE_HINGE:
		# Elbows/knees bend ONE way only (toward the body), never backwards.
		pb.set("joint_constraints/angular_limit_enabled", true)
		pb.set("joint_constraints/angular_limit_lower", -120.0)
		pb.set("joint_constraints/angular_limit_upper", 2.0)
	var bone_cs: CollisionShape3D = CollisionShape3D.new()
	var bone_cap: CapsuleShape3D = CapsuleShape3D.new()
	bone_cap.radius = cap_radius
	bone_cap.height = cap_height
	bone_cs.shape = bone_cap
	pb.add_child(bone_cs)
	sim.add_child(pb)
	return pb


# Halt the first AnimationPlayer under `root` so a tumbling ragdoll body stays
# limp (no walking/idle motion fighting the physics tumble).
func stop_anim(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			(n as AnimationPlayer).stop()
			return
		for c in n.get_children():
			stack.append(c)