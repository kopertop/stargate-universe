"""SGU composable-music stem palette — the single registry of generatable loops.

Each stem is an ISOLATED, seamlessly-looping texture (or a short one-shot accent) the
runtime MusicDirector (scripts/music_director.gd) layers and crossfades into moods. The
sonic identity is Stargate Universe (Joel Goldsmith): intimate, melancholic, electronic-
acoustic — solo cello/violin, sparse piano, vast lonely synth drones. Crisis/combat get
intensity from pulsing synth + low swells + light percussion, NOT bombastic orchestra.

ONE dict, no per-stem forks (honors the project's collection-fork policy). bake.py reads
this; jobs/*.json just SELECT stem ids to bake. Re-tune a prompt once here and re-bake.

kind drives which ElevenLabs API bake.py calls:
  loop     -> text_to_sound_effects.convert(loop=True)  — sustained seamless texture (a stem)
  oneshot  -> text_to_sound_effects.convert(loop=False) — short non-looping accent / sting
  bed      -> music.compose()                            — a fully-mixed standalone piece
                                                           (reserved; full library uses loops)

Fields: layer (taxonomy group), kind, duration_s (0.5..30 for SFX), prompt, prompt_influence
(0..1 adherence), mood_tags (which moods reference it — documentation only; the authoritative
mood->stem mapping lives in data/music_moods.json).
"""
from __future__ import annotations

# stem id -> definition
STEMS: dict[str, dict] = {
	# --- Beds: location foundation, always-on drone under everything --------------
	"bed_ship_warm": {
		"layer": "bed", "kind": "loop", "duration_s": 28.0, "prompt_influence": 0.4,
		"prompt": "deep warm electronic drone, vast lonely spaceship interior, low sustained "
		          "synth hum, gentle slow movement, ambient cinematic sci-fi, no rhythm, no melody",
		"mood_tags": ["ship_calm", "mystery", "tension", "somber"],
	},
	"bed_derelict_cold": {
		"layer": "bed", "kind": "loop", "duration_s": 28.0, "prompt_influence": 0.4,
		"prompt": "cold hollow metallic drone, abandoned derelict spaceship, distant creaks and "
		          "groans, eerie empty ambient, low frequency, unsettling, no rhythm, no melody",
		"mood_tags": ["mystery", "tension"],
	},
	"bed_planet_open": {
		"layer": "bed", "kind": "loop", "duration_s": 28.0, "prompt_influence": 0.4,
		"prompt": "wide open alien wilderness ambient, soft desolate wind, distant atmospheric "
		          "pad, lonely barren planet, low sustained strings underneath, no rhythm",
		"mood_tags": ["planet"],
	},
	"bed_space_vast": {
		"layer": "bed", "kind": "loop", "duration_s": 28.0, "prompt_influence": 0.4,
		"prompt": "vast deep space ambient drone, immense emptiness, slow swelling low pad, awe "
		          "and isolation, sub bass, no rhythm, no melody, cinematic",
		"mood_tags": ["ship_calm", "somber"],
	},

	# --- Pads: harmonic mood color stacked over a bed -----------------------------
	"pad_strings_warm": {
		"layer": "pad", "kind": "loop", "duration_s": 24.0, "prompt_influence": 0.45,
		"prompt": "warm sustained string section pad, cellos and violas, soft and consonant, "
		          "slow swell, intimate, melancholic but hopeful, no percussion, no rhythm",
		"mood_tags": ["ship_calm", "planet"],
	},
	"pad_strings_tense": {
		"layer": "pad", "kind": "loop", "duration_s": 24.0, "prompt_influence": 0.45,
		"prompt": "tense dissonant high string cluster, sustained and slowly rising, anxious, "
		          "unease and dread, cinematic suspense, no percussion, no clear melody",
		"mood_tags": ["tension", "crisis", "combat"],
	},
	"pad_shimmer": {
		"layer": "pad", "kind": "loop", "duration_s": 24.0, "prompt_influence": 0.45,
		"prompt": "shimmering high ethereal synth pad, mysterious, glassy bell-like overtones, "
		          "wonder and discovery, slow evolving texture, weightless, no rhythm",
		"mood_tags": ["mystery"],
	},

	# --- Melodic: emotional spotlight, sparse phrases with rests ------------------
	"mel_cello_lonely": {
		"layer": "melodic", "kind": "loop", "duration_s": 20.0, "prompt_influence": 0.5,
		"prompt": "solo cello, mournful slow melody, sparse and intimate, long pauses of silence "
		          "between phrases, melancholic, reverberant, no accompaniment",
		"mood_tags": ["somber"],
	},
	"mel_violin_hope": {
		"layer": "melodic", "kind": "loop", "duration_s": 20.0, "prompt_influence": 0.5,
		"prompt": "solo violin, gentle hopeful melody, tender and warm, sparse phrases with rests, "
		          "emotional, minimal soft piano underneath, reverberant",
		"mood_tags": ["planet"],
	},
	"mel_piano_sparse": {
		"layer": "melodic", "kind": "loop", "duration_s": 20.0, "prompt_influence": 0.5,
		"prompt": "sparse solo piano, single reflective notes with lots of space and silence "
		          "between them, contemplative, intimate, soft, reverberant, no rhythm",
		"mood_tags": ["ship_calm"],
	},

	# --- Pulse / rhythm: pace + intensity -----------------------------------------
	"pulse_slow": {
		"layer": "pulse", "kind": "loop", "duration_s": 12.0, "prompt_influence": 0.4,
		"prompt": "slow low synth pulse, steady heartbeat-like throb, subtle building unease, "
		          "minimal sparse dark electronic, no melody",
		"mood_tags": ["tension"],
	},
	"pulse_drive": {
		"layer": "pulse", "kind": "loop", "duration_s": 12.0, "prompt_influence": 0.4,
		"prompt": "driving urgent electronic pulse, fast insistent rhythmic synth, rising tension, "
		          "crisis and danger, propulsive, dark, no melody",
		"mood_tags": ["crisis", "combat"],
	},
	"perc_action": {
		"layer": "pulse", "kind": "loop", "duration_s": 12.0, "prompt_influence": 0.4,
		"prompt": "tense action percussion, taut drums and low hits, military urgency, driving but "
		          "restrained, cinematic combat, dark electronic",
		"mood_tags": ["combat"],
	},

	# --- Accents: one-shot stings (non-looping) -----------------------------------
	"sting_discovery": {
		"layer": "accent", "kind": "oneshot", "duration_s": 3.0, "prompt_influence": 0.5,
		"prompt": "short bright magical discovery sting, shimmering reveal chime, wonder, ancient "
		          "alien technology awakening, cinematic",
		"mood_tags": ["mystery"],
	},
	"sting_alarm": {
		"layer": "accent", "kind": "oneshot", "duration_s": 2.5, "prompt_influence": 0.5,
		"prompt": "short urgent alarm sting, tense synth stab, danger alert, sci-fi warning, "
		          "sharp attack",
		"mood_tags": ["crisis"],
	},
	"riser_jump": {
		"layer": "accent", "kind": "oneshot", "duration_s": 4.0, "prompt_influence": 0.45,
		"prompt": "rising tension riser, accelerating whoosh building to a peak, faster-than-light "
		          "jump charge-up, sweeping sci-fi",
		"mood_tags": ["ftl_jump"],
	},
	"impact_jump": {
		"layer": "accent", "kind": "oneshot", "duration_s": 3.0, "prompt_influence": 0.5,
		"prompt": "deep cinematic impact hit, faster-than-light jump arrival boom, sub bass drop "
		          "with metallic resonance, powerful sci-fi",
		"mood_tags": ["ftl_jump"],
	},
	"braam_danger": {
		"layer": "accent", "kind": "oneshot", "duration_s": 3.5, "prompt_influence": 0.5,
		"prompt": "low ominous cinematic braam, dark brassy synth swell, looming threat, dread, "
		          "sci-fi tension",
		"mood_tags": ["crisis", "combat"],
	},
}


def resolve(stem_id: str, overrides: dict | None = None) -> dict:
	"""Return a stem definition (id merged in), applying per-job overrides. Raises on typo."""
	if stem_id not in STEMS:
		raise KeyError(f"unknown stem '{stem_id}' (have: {sorted(STEMS)})")
	d = dict(STEMS[stem_id])
	if overrides:
		d.update(overrides)
	d["id"] = stem_id
	return d
