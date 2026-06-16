# SGU Opening Scene — Atmosphere & Dialog Reference

> **Source:** transcribed from the reference recording `SGU Openning.m4a` (the *Stargate
> Universe* "Air, Part 1" cold open — the Icarus Base evacuation through the gate onto
> Destiny). Used as the authoring target for the E1 prologue cinematic.
> **Status:** reference doc — feeds GitHub issue "E1 cold-open: replicate the SGU opening
> atmosphere + dialog → *Find Rush*".
> **Last updated:** 2026-06-16

## How this was captured

Transcribed with `mlx_whisper` (large-v3-turbo) in two passes:

1. Default pass — accurate on the sparse intelligible dialog, but fell into a
   repetition-loop (`"Get him over!"` ×80) across the long non-verbal stretches.
2. `--condition-on-previous-text False` pass — broke the loop and surfaced the
   late lines that set up the **Find Rush** beat.

The long repeated runs in the raw transcript (`"No!"`, `"Where is it?"`, `"Are you
serious?"`) are **transcription artifacts** over non-speech audio. The real soundbed in
those spans is **chaos, not dialog**: bodies slamming the deck, pained grunts, the gate
kawoosh, metal clatter, and overlapping panicked shouting. That distinction drives the
sound-design spec below.

---

## The essence (atmosphere)

A **disaster evacuation**, not an arrival. Icarus is coming apart; people are being
shoved through an unstable gate **at speed** and crashing onto a cold, derelict deck in
the dark. The tone is **panic under discipline** — soldiers barking marshalling orders to
hold a terrified, injured crowd together while bodies keep flying through behind them.

Defining qualities to reproduce:

- **Overlapping, layered voices** — not clean one-at-a-time lines. Marshalling barks
  ("Move! Off to the side!") cut across civilian confusion ("Where are we? What's going
  on?") and pain.
- **Velocity & impact** — people come through *hard*, head-first, and hit the deck. The
  rhythm is a steady percussion of thuds + grunts, ≤2 in the air at once.
- **Darkness & cold** — the room is unpowered/derelict; the only light is the wormhole and
  flashlights.
- **No answers** — every "Where are we?" is met with "There's no time" / "I don't know,
  sir." Nobody is in control of the *situation*, only the *crowd*.
- **The turn to wonder** — it resolves on a single stunned beat: the shudder of the ship,
  a hush, and "**What the hell was that?**" / "**What is this place?**" — the moment the
  evac becomes *discovery*. This is the hand-off into gameplay.

---

## Faithful dialog (de-hallucinated)

Timestamps approximate. Speaker attributions are best-effort for design purposes (the
recording is a chaotic mix); they map onto roles we already cast in
`design/voice-line-manifest.md`. Confidence: **H** = in both passes / clearly intelligible,
**M** = single pass, reconciled to scene.

| ~Time | Speaker (role) | Line | Conf |
|------|----------------|------|------|
| 0:16 | Soldier (marshal) | "Get out of the way!" | H |
| 0:30 | Scott / gate officer | "Slow down the evac — we're coming in too high!" | H |
| 0:34 | Soldier | "Come in! Come on!" | M |
| 0:35 | Civilian | "Where are we?" | H |
| 0:49 | Civilian | "Why didn't we come through together?" *(garbled)* | M |
| 0:50 | Scott / Greer (marshal) | "There's no time to explain — off to the side!" | H |
| 0:53 | Civilian | "What's going on?" | H |
| 1:05 | TJ (medic) | "Can you move your fingers?" | M |
| 1:12 | Wounded crew | "I think it's broken." | M |
| 1:14 | TJ (medic) | "Okay — hold your arm there, we'll get it in a sling." | M |
| 2:00 | Soldier | "Leave it — there'll be more coming through." | M |
| 2:25 | TJ / Chloe | "Are you okay?" | H |
| 2:38 | Soldier | "Clear!" | H |
| 2:40 | Crew | "Right behind you." | M |
| 2:55 | Young / Greer (marshal) | "Move, move, move!" | H |
| 2:57 | Young / Greer | "Stay calm! Keep it down!" | M |
| 3:12 | Young | "Where are we?" | H |
| 3:13 | Junior officer | "I don't know, sir." | H |
| 3:14 | Young | "Are you serious?" | M |
| 3:53 | Eli / civilian | "What is this place?" | H |
| 3:55 | Scott | "I haven't seen Rush — I don't know if he went through ahead of me." | M |
| 3:58 | Young / Scott | "Rush! … Rush!" | H |
| 4:02 | Young → Scott | "You all right? **Help me find him.**" | H |
| 4:11 | Crew | "What the hell *was* that?" | H |
| ~end | Scott → Eli | "**Eli! NOW!**" *(shouted, urgent — Scott rounds on Eli)* | H |
| ~end | Eli | "Okay! I'm coming!" *(scramble — hands control to the player)* | H |

> **`Help me find him.`** (4:02) is the diegetic line that launches the first quest —
> step `find_rush` in `data/quests.json`. The cold open lands on **Scott yelling "Eli!
> NOW!"** and **Eli's "Okay! I'm coming!"** — the button that snaps the camera back to the
> player and starts gameplay (heading off to find Rush).

---

## Beat sheet (cuts to the existing prologue choreography)

Maps the recording onto what `scripts/gate_room.gd::_play_prologue_cinematic()` already
stages (see waves 1–8 + Eli). Bold = new authoring this issue adds.

1. **Black / dial.** Ring spins, chevrons light, kawoosh — `dial_and_open(true)`.
   Soundbed: rising gate energize → kawoosh. **Add:** distant Icarus rumble / alarms
   bleeding through the open wormhole.
2. **First through — Scott (Wave 1).** Crashes in, kneels, rises. **Add:** his marshalling
   barks layered over the existing `scott_clear.wav` radio line ("Slow down the evac…",
   "Off to the side!").
3. **The flood (Waves 2–8).** Young (thrown hardest, injured, face-down), James (medic
   kneeling), Park/Volker to consoles, soldiers + civilians in pairs, crates raining in.
   Soundbed: **percussion of thuds + grunts**, overlapping crowd panic, "Where are we?",
   "What's going on?", "Move, move, move!".
4. **Medic pocket.** Near James/TJ over a wounded crew member — **add** the arm/sling
   exchange ("Can you move your fingers?" / "I think it's broken." / "…in a sling.").
5. **Eli last through.** Slams in closest to the gate, groggily stands. Gate collapses
   behind him — `_collapse_gate()`.
6. **The hush → wonder.** Lights/consoles wake (`_wake_consoles()`); the ship shudders.
   **Add** the turn: "What is this place?" → "**What the hell was that?**".
7. **Hand-off to Rush.** Scott released to greet (`_set_scott_autogreet(true)`). **Add**
   Young/Scott's "I haven't seen Rush… **Help me find him.**" → then **Scott rounds on Eli
   and yells "Eli! NOW!"**, Eli answers "Okay! I'm coming!" — this is the button that
   `_restore_player_camera()` snaps back on, activates quest `find_rush`, and points the
   waypoint at the Control Interface Room.

---

## Sound-design spec

The atmosphere lives or dies on the soundbed. What exists vs. what's missing:

**Already present** (`sounds/`): `land.ogg`, `fall.ogg`, `break.ogg` (impact pool, varied
pitch via `gate_room.gd::_thud()`), `gate_kawoosh.wav`, `gate_active_hum.wav`,
`ftl-dropout.ogg` / `ftl-jump.ogg`, `dialog/prologue/scott_clear.wav`.

**Missing — to author/source** (see `/sound-fetch`, `/team-audio`):

| Need | Why | Notes |
|------|-----|-------|
| Crowd-panic ambient bed | The "many terrified people" layer | Loop under waves 2–8; duck under voiced lines |
| Crew effort grunts (pool of 4–6) | Visceral impact on each landing | Trigger alongside `_thud()` per wave |
| Gate **energize ramp** | Tension before kawoosh | Cross-fade `gate_active_hum` → `gate_kawoosh` |
| Distant Icarus rumble / klaxon | "The base behind them is dying" | Bleeds through open wormhole, cuts on `_collapse_gate()` |
| Radio static/crackle | Comms authenticity on Scott's line | Light EQ/distortion over `scott_clear.wav` |
| Ship-shudder / groan one-shot | The wonder beat (step 6) | Pairs with `Cinematic.flash()` + camera hold |

---

## New voice lines to author

These extend `design/voice-line-manifest.md` (cast + ElevenLabs voice IDs already defined
there). Several arrival lines are already `DONE` (e.g. `eli-ship-shake`, `eli-gate-*`,
`crew-acknowledge-*`) and can be reused. Net-new for the cold open:

- **Marshalling barks** (Scott / Greer): "Off to the side!", "There's no time — move!",
  "Slow down the evac!", "Clear!"
- **Crowd confusion** (generic crew, layered): "Where are we?", "What's going on?", "What
  is this place?"
- **Medic pocket** (TJ): "Can you move your fingers?", "Hold your arm — we'll get it in a
  sling.", "Are you okay?"
- **Command** (Young): "Move, move, move!", "Stay calm — keep it down!", "Where are we?"
  / (officer) "I don't know, sir."
- **The Rush hand-off** (Young/Scott): "I haven't seen Rush — I don't know if he made it
  through.", "Rush! … **Help me find him.**"
- **The wonder** (crew/Eli): "What the hell *was* that?"
- **The button** (Scott, shouted → Eli): "**Eli! NOW!**" → Eli "Okay! I'm coming!" — snaps
  control back to the player and starts the *Find Rush* objective

---

## Existing systems to build on (do not duplicate)

| System | File | Role in the cold open |
|--------|------|-----------------------|
| Prologue sequencer | `scripts/gate_room.gd::_play_prologue_cinematic()` (L544+) | Master arrival flow; waves 1–8 + Eli |
| Crew ballistics / settle | `_throw_persistent_crew()`, `_settle_persistent_crew()`, `_thud()` | Bodies fly in, land, pose; impact SFX pool |
| Scott radio beat | `_scott_radio_line()` (L842) | Letterbox + caption + baked VO — template for new voiced beats |
| Letterbox / captions / flash | `scripts/cinematic.gd` (`letterbox_in/out`, `set_caption`, `flash`) | Cinematic framing for the dialog beats |
| Cinematic camera | `scripts/standoff_camera.gd` (`frame`, `follow`, orbit) | Wide arrival framing + medic-pocket push-ins |
| Caption cutscene player | `scripts/standoff_cinematic.gd` | Space/E-advanced multi-line beats (the Rush hand-off) |
| SFX playback | `scripts/audio.gd` (`Audio.play`) | Pooled one-shots for ambient/grunts |
| Runtime VO | `scripts/tts_client.gd` (`say`) | Fallback synthesis for un-baked lines |
| Quest runtime | `scripts/quest_log.gd` + `data/quests.json` step `find_rush` | "Help me find him." → activates the first quest |
| Objective marker | `scripts/quest_waypoint.gd` | Points to Control Interface Room after hand-off |

Prior related issues: **#136** (cold-open standoff cutscene), **#137** (E1 away-team split).
