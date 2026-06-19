# Opening Scene Script — E1 Cold Open ("Air, Part 1" gate evacuation)

> **What this is.** The script for the E1 *cold open* — the pre-flashback opening where the
> Icarus crew is shoved through the Stargate onto the derelict *Destiny* and Scott hands the
> player the **Find Rush** objective. §1 is the **canonical scene** (exact dialogue, story
> order); §3 maps it onto the shipped **verbatim ~2.5-minute cut** that
> `scripts/gate_room.gd::_play_prologue_cinematic()` actually renders.
>
> **Dialogue source.** Exact lines are from the *Stargate Universe* "Air, Part 1" episode
> transcript (GateWorld, transcribed by Callie Sullivan). Action/staging is paraphrased.
>
> **Audio.** The cold open is now the **full verbatim transcript** (~2.5 min). Voices were
> stripped from the reference recording with Demucs and the loud sections stitched into a
> **~165 s lull-free ambience bed** `cold_open_bed.mp3` (music, kawoosh, crowd — no dialog),
> played once as the master clock. Every line is our **designed per-character VO** (Qwen3-TTS
> Design→Clone) played on top via `_cap(..., vo_id)`; the camera cuts to the speaker
> (`standoff_camera`). `cold_open_master.mp3` (255.3 s) is kept only as the timing reference.
>
> **Status.** Reference / production doc. Supersedes beat 7 of `design/sgu-opening-reference.md`
> (the old "Scott walks over to brief you" hand-off — replaced; see §5).
> **Last updated:** 2026-06-18

---

## 0. TL;DR — the spine

Dark, drifting *Destiny* → unsupported Stargate dials and kawooshes → **Scott** crashes through
and rises to marshal the flood → crew, crates, and the wounded pour through in continuous panic
→ **Col. Young** comes through hardest of all and goes down → the gate shuts → Scott reaches
Young, who passes him command and blacks out (**blood on Scott's hand**) → Scott calls **TJ**,
then rounds on **Eli** to find **Rush** → an FTL shimmer rolls over everyone → Scott shouts
**"Eli! NOW!"** → **hand-off to gameplay: the player already holds quest step 1, _Find Rush_.**

No menu, no Scott briefing dialog — the cold open *is* the tutorial framing, and it ends with
the objective already in the log.

---

## 1. Canonical scene — exact dialogue (source of truth)

Beats in story order. **Action** is paraphrased; **dialogue is verbatim.** The shipped ~90 s cut
(§3) condenses and re-attributes some of this; reconcile toward this section.

> **In-game name note:** the medic is billed in the source as **1st Lt. Tamara Johansen
> ("T.J.")**. In our build she is **Lt. James, called TJ** — one character; see the cast note
> in §2.

### 1.1 Establishing — deep space / the gate room
A massive, arrow-shaped ship drifts silently through black space; its corridors are mostly
unlit. The engines seem to be throttling down and a little lighting flickers on. In a large
room stands a Stargate — **unsupported**, its lower arc sunk into the floor, its chevrons
spinning *with* the ring as it dials. The ring locks; an energy vortex bursts out and settles
to a flat horizon.

### 1.2 First through — Scott
A young marine, **Lt. Matthew Scott**, flies through the horizon and crashes to the floor.
Groaning, he drags himself up and sweeps the dark room with his rifle. A large box flies out of
the gate — he flinches aside. A woman follows, through too fast, landing hard; before he can
help her, another woman soars through with a yelp. More follow; Scott hauls the early arrivals
toward their feet.

> **SCOTT:** All right, get out of here. Get out of the way!

### 1.3 Pandemonium — the flood
More people — military and civilian — hurtle through and fall heavily; many carry boxes and
cases, and more cases fly through on their own. People scramble clear of incoming bodies and
objects. Scott keys his radio.

> **SCOTT:** This is Scott! Slow down the evac — we are comin' in too hot!

The arrivals don't slow. I.O.A. representative **Camile Wray** scrambles up and grabs at Scott.

> **WRAY:** Where are we? Why didn't we come through to Earth?
> **SCOTT:** *(gesturing)* There's no time to explain. Off to the side!

He goes back to dragging people and boxes clear; others pitch in. He tries the radio again — no
answer.

> **SCOTT:** This is Scott — come in!

### 1.4 "I need a medic" — TJ
A marine calls out; TJ answers that she's heard him, already working a patient.

> **MARINE:** I need a medic!
> **TJ:** Over here! *(to her patient)* Can you move your fingers?
> **MAN:** No. I think my arm is broken.
> **TJ:** *(folding his arm across his chest)* OK, just hold your arm there and we'll put it in a sling, OK?

### 1.5 Rush, Eli, and the staircase
**Dr. Nicholas Rush** pulls himself up and crosses to a nearby control console — unlit, and he
can make no sense of it. At the gate, civilian **Eli Wallace** hurtles through, gets to his
knees patting himself for injuries, and looks up just as a metal case flies through and knocks
him flat again. Rush watches helplessly as people keep crashing through; the relatively
uninjured move people and gear out of the arrival zone.

> **SCOTT:** Clear this area! There could still be more incoming!

Rush climbs a metal staircase to an upper level and looks down at the chaos, smiling ruefully.
**Senator Armstrong** and his aide and daughter **Chloe** hurtle through; she helps him up.

> **CHLOE:** Are you OK?
> **SENATOR:** Yeah. *(as they stumble clear)* Where the hell are we?

### 1.6 "Where's Colonel Young?"
Scott crosses to **Master Sergeant Ronald Greer**.

> **SCOTT:** Greer? Where's Colonel Young?
> **GREER:** He was right behind me.

### 1.7 Young arrives — the gate shuts
**Colonel Everett Young** comes through faster than anyone, soars across the room, and crashes
to the floor yards from the gate. Seconds later the Stargate shuts down and the room is plunged
into darkness — then plumes of flame and steam vent from either side of the gate. Civilians
scream; the flames die; anyone with a flashlight switches it on. Greer clears a path as he and
Scott push across to the colonel.

> **GREER:** Move, move, move. *(calling out)* Stay calm! Keep it down! *(to those in his way)* Move, move, move, move, move.

### 1.8 The command hand-off
Scott reaches Young, lying still, kneels, and cradles his head. Greer warns the crowd back.

> **SCOTT:** Colonel? Colonel?
> **GREER:** Don't move!
> **YOUNG:** *(weakly, vaguely)* Where are we? Where are we?
> **SCOTT:** I don't know, sir.
> **YOUNG:** *(weakly)* You're in charge, OK? You're …

His eyes close and his head rolls aside. Scott realizes the hand cradling Young's head is
covered in blood.

> **SCOTT:** *(softly)* Yes, sir.

He eases his hand free, stares at the blood, then turns and screams into the room.

> **SCOTT:** T.J.!
> **TJ:** I'm coming!

A marine clears the way; she kneels beside Young.

> **GREER:** Is he OK?
> **TJ:** Uh, I dunno.

She shines a medical light into Young's eye. Scott scrambles up and yells for the civilian.

> **SCOTT:** Wallace!

Eli hurries over.

> **SCOTT:** What is this place?
> **WALLACE:** *(nervously)* Look, I just did what Rush told me.
> **SCOTT:** Where is he?
> **WALLACE:** I don't know if he went ahead of me.
> **SCOTT:** *(yelling)* Rush!

Somewhere, unnoticed, engines begin to spin up — a rising hum.

> **SCOTT:** Rush! Eli, help me find him.
> **WALLACE:** Well, I …

### 1.9 The shimmer — and the button
The hum grows louder and shifts tone; a brief shimmer envelops everyone, then dissipates (the
ship jumps).

> **GREER:** What in the hell was that?!
> **SCOTT:** I don't know. *(turning to Greer)* Sergeant, I need you to get these people settled here. I need you to find out who and what we've got. Nobody leaves this room.
> **GREER:** Yes, sir.

Scott heads off as Greer watches TJ begin dressing Young's head wound; Eli is staring down at
them too. Scott yells at him.

> **SCOTT:** Eli! Now!

*(In our build this returns control to the player with the **Find Rush** objective already
active — see §3 / §4.)*

---

## 2. Timing model (read before §3)

The cold open is the **full verbatim transcript (~2.5 min)**. Every cue in §3 is **seconds
into `cold_open_bed.mp3`** — the ~165 s, lull-free ambience bed (Demucs no-vocals, voices
stripped); the gate stays active and crew + gear flow **continuously** with no dead air. The
cinematic paces itself to that bed's playhead:

- `_await_audio(audio, t)` — blocks the visual flow until the playhead reaches `t`.
- `_cap(speaker, line, at_t [, vo_id])` — fire-and-forget; waits for `at_t`, subtitles the line
  (auto-clears before the next cue), and plays the designed VO clip over the bed.
- Wall-clock (`_cold_open_start_ms`) is only a fallback if the stream fails to load.
- Headless smoke (`tests/smoke/cold_open_lines.gd`) skips the live path via `instant_mode` and
  guards the design by string-match, **not** timing — so keep caption strings stable.

Captions render as `SPEAKER — "line"`.

> **Cast note — the medic.** Official name **Lt. James**; everyone calls her **TJ**. They are
> ONE character: `data/characters.json` resolves `Lt James` / `Dr James` / `TJ` / `TJ Johansen`
> to the same portrait (`tj-johansen.png`) and short name **TJ**. Cold-open captions use **TJ**
> (what Scott yells); her infirmary dialogue keys off `Lt James` and still renders as TJ. The
> in-world body remains the `lt_james` build in `character_factory.gd`.

---

## 3. Shot list — the shipped verbatim cut (~2.5 min)

The shipped cut now plays **§1 verbatim** — every line, correct speaker, in order — over the
~165 s bed, with the camera **cutting to the speaker**. Playhead seconds below are approximate;
the authoritative timings live in `scripts/gate_room.gd::_play_prologue_cinematic()`.

Arrivals: each body flies a ballistic arc, plays a **Mixamo roll** (`dive_roll` Scott, varied for
mil/civ, `crash` for hard hits), `get_up`, then `walk_to` a perimeter spot (`_co_arrival` /
`_co_roll_settle`). Nameless `civ_#`/`mil_#` pour in continuously (`_co_crowd_flood`, ~1–2/s,
frozen once settled). Crates rain via `_launch_crate_wave`; **hero impact crates** are real
RigidBody3D that physically hit the broken-arm marine and Young (`_launch_impact_crate` →
`_wound_crew`). Camera via `standoff_camera` (`_begin_cuts`/`_cut_to`/`_cut_follow`/`_cut_wide`).

| ~t | Beat | Caption (speaker — verbatim line) |
|---:|---|---|
| 0.5 | Dial & open (per-chevron lock SFX) | — |
| 4 | Scott dives through, rolls up | `LT. SCOTT — "All right, get out of here. Get out of the way!"` (6) |
| 7+ | Continuous flood begins (people, then crates @16) | — |
| 10 | Scott on the radio | `LT. SCOTT — "This is Scott! Slow down the evac — we are comin' in too hot!"` |
| 13.5 | Wray grabs Scott | `CAMILE WRAY — "Where are we? Why didn't we come through to Earth?"` |
| 15.5 | Scott | `LT. SCOTT — "There's no time to explain. Off to the side!"` |
| 18.5 | Scott (no reply) | `LT. SCOTT — "This is Scott — come in!"` |
| 20 | A marine | `MARINE — "I need a medic!"` |
| 24 | **cut to TJ + wounded man** | `TJ — "Over here! Can you move your fingers?"` |
| 27 | **crate clips the marine's arm** (RigidBody) | `MARINE — "No. I think my arm is broken."` (29) |
| 32 | TJ slings the arm | `TJ — "Okay, just hold your arm there and we'll put it in a sling, okay?"` |
| 38 | Scott | `LT. SCOTT — "Clear this area! There could still be more incoming!"` |
| 44 | Chloe helps the Senator up | `CHLOE — "Are you okay?"` / `SENATOR — "Yeah."` (47) / `SENATOR — "Where the hell are we?"` (49) |
| 55 | Scott → Greer | `LT. SCOTT — "Greer? Where's Colonel Young?"` / `SGT. GREER — "He was right behind me."` (58) |
| 53 | Eli (player) thrown in, lands prone closest to the gate | — |
| 61 | **Young thrown hardest; crate clips his head** (head wound) | — |
| 64 | Gate collapses, flame/steam vent | `SGT. GREER — "Move, move, move. Stay calm! Keep it down! ..."` (66) |
| 68 | Eli stands | — |
| 70–88 | **Command hand-off** (Scott crosses to Young) | `LT. SCOTT — "Colonel? Colonel?"` (72) / `SGT. GREER — "Don't move!"` (74) |
| 76 | **close on Young** | `COL. YOUNG — "Where are we? Where are we?"` / `LT. SCOTT — "I don't know, sir."` (78) |
| 80 | Young passes command | `COL. YOUNG — "You're in charge, okay? You're..."` |
| 83.5 | blood on his hand | `LT. SCOTT — "Yes, sir."` |
| 86 | Scott screams for the medic | `LT. SCOTT — "TJ!"` / `TJ — "I'm coming!"` (88) / `SGT. GREER — "Is he okay?"` (91) / `TJ — "Uh, I dunno."` (93) |
| 96 | Scott rounds on Eli | `LT. SCOTT — "Wallace!"` / `LT. SCOTT — "What is this place?"` (99) / `ELI — "Look, I just did what Rush told me."` (101) |
| 104 | | `LT. SCOTT — "Where is he?"` / `ELI — "I don't know if he went ahead of me."` (106) |
| 109 | Scott yells for Rush | `LT. SCOTT — "Rush!"` / `LT. SCOTT — "Rush! Eli, help me find him."` (112) / `ELI — "Well, I..."` (114) |
| 118 | **FTL JUMP — left-right shake + blur** (`_ftl_jump`) | `SGT. GREER — "What in the hell was that?!"` (120) |
| 123 | Scott takes command | `LT. SCOTT — "I don't know. Sergeant, I need you to get these people settled here. ... Nobody leaves this room."` / `SGT. GREER — "Yes, sir."` (133) |
| 139 | **THE BUTTON** (cut to player) | `LT. SCOTT — "Eli! Now!"` |
| 142 | End — letterbox out, release cuts, hand-off → quest | — |

> **Hand-off:** at the end the player ALREADY holds quest step 1 (Find Rush) — see §4. Captions
> are guarded by `tests/smoke/cold_open_lines.gd`.

---

## 4. The hand-off (video → quest system)

The exact frame the cinematic returns control, all at once, after the bars lift:

```gdscript
_restore_player_camera(cam)     # snap from the cinematic cam back to the player SpringArm
_wake_consoles()                # Destiny powers up — consoles come online
GameState.met_scott = true      # Scott counts as "met" (no separate briefing dialog)
GameState.advance_air_quest()   # e1_air: talk_scott → find_rush  ← QUEST STEP 1 IS NOW LIVE
_set_scott_autogreet(false)     # Scott stays put; he does NOT walk over to brief you
```

**The moment the player regains WASD control, the objective log already reads _Find Rush_**, with
a waypoint to the Control Interface Room (`scripts/quest_waypoint.gd`). The first thing the player
does is follow Scott's order through the door — no tutorial conversation. Locked by
`tests/smoke/cold_open_lines.gd::test_cold_open_advances_quest_without_scott_walkup`.

> **Line in the sand:** everything above happens *in the cinematic*; everything after
> `advance_air_quest()` is *gameplay* and lives in the quest/level docs, not here.

---

## 5. Game vs. source — intentional divergences

We follow the scene closely; these differences are deliberate (don't "fix" them back):

| Source "Air, Part 1" | Our cold open | Why |
|---|---|---|
| Young blacks out; TJ takes over his care while Scott works the room and **gives Greer orders** before leaving. | We keep Young down and let **Scott** carry the whole command thread (`~77–84 s`); Greer's "settle the room" orders are trimmed. | Single clear authority figure; tighter runtime. |
| Scott's exit line lands amid ongoing chaos. | Scott shouts **"Eli! NOW!"** straight at the player → instant control return with the quest already active. | A hard, diegetic "go" button instead of a menu/dialog. |
| The hand-off is implied; Scott briefs the crew over time. | The player **already holds _Find Rush_** when control returns; Scott does **not** walk over to brief them. | "First stop is the quest, not a Scott chat." |

The command hand-off beat — Young's collapse, Scott crossing to check him, **"You're in
charge,"** the blood reaction, and the **"TJ!" / "Coming!"** medic call — is staged in the
**~66–72 s** window by `_co_command_handoff()` (see §3, rows 66–72.5 s). Young/Scott/TJ here use
our own designed VO over the no-vocals bed (no double-talk, since the bed's voices are stripped).

---

## 6. Audio assets backing this scene

- **Ambience bed (played once, master clock):** `sounds/dialog/prologue/cold_open_bed.mp3`
  (~165 s) — two loud sections of the Demucs no-vocals stem (music/kawoosh/crowd, voices
  stripped) crossfaded into a lull-free cut. Captions/VO are timed to its playhead.
- **Per-line VO (our designed voices):** `sounds/dialog/prologue/open-*.wav` (38-line verbatim
  set), played on top of the bed by `_cap(..., vo_id)`. Built via the **Qwen3-TTS Design→Clone**
  pipeline (`tools/tts-bakeoff/`): VoiceDesign per-mode refs (`refs_qwen/<char>_<mode>.wav`,
  picks in `make_qwen_refs.py`) → Base clone (`qwen_clone.py` + `jobs_qwen/cold_open_full.json`).
  Principals: Scott/Greer/Eli/TJ/Young/Rush; named extras: Wray/Chloe/Senator; generic
  marine/civ. (Earlier IndexTTS-2 + 90 s-cut takes are superseded.)
- **Reference master:** `cold_open_master.mp3` (255.3 s) — the full TV recording, kept for
  timing/reference only.
- **SFX:** gate `dial`/`kawoosh`/`hum`, per-chevron lock, impact pool (`land`/`fall`/`break` via
  `_thud()`), ship shudder one-shot. Inventory + gaps: `design/sgu-opening-reference.md`
  §"Sound-design".

---

## 7. ASR timing anchors (from the 255 s master, approximate)

Raw `mlx_whisper` anchors from the original recording — **approximate**, the basis for where
beats fell before the ~90 s re-time. Exact wording lives in §1; the long non-verbal stretches
are chaos (thuds, grunts, kawoosh, overlapping shouts), not dialog.

```
~0:17  first marshalling bark              (Scott)
~0:30  "...slow down the evac... too hot"  (Scott, radio)
~0:35  "where are we..."                   (Wray)
~0:50  "...off to the side"                (Scott)
~1:05  fingers / broken / sling            (TJ medic pocket)
~3:53  "what is this place?"               (Scott → Eli)
~3:55  "...help me find him"               (Scott)
~3:58  "Rush!"
~4:11  "...what... was that?"              (Greer — the shimmer)
~end   "Eli! Now!"                         (the button)
```

---

## 8. Where to look in code

| System | File | Role |
|---|---|---|
| Cold-open sequencer | `scripts/gate_room.gd::_play_prologue_cinematic()` (L548+) | The whole pass in §3 |
| Playhead sync / captions | same file: `_await_audio()`, `_cap()` | Master-clock blocking + caption/VO cues |
| Command hand-off | `_co_command_handoff()` | Scott→Young→TJ staging in the lull |
| Crew ballistics | `_launch_ragdoll()`, `_co_wave1_scott()`, `_co_wave2()`, `_extra_pair()`, `_thud()` | Bodies/crates fly in and land |
| Gate dial/collapse | `dial_and_open()`, `_collapse_gate()` | Open + snuff the wormhole |
| Cinematic framing | `scripts/cinematic.gd` (`letterbox_in/out`, `set_caption`, `flash`) | Bars / subtitles / shimmer flash |
| Hand-off | `GameState.met_scott`, `GameState.advance_air_quest()`, `_restore_player_camera()` | Video → quest step 1 |
| Drift guard | `tests/smoke/cold_open_lines.gd` | Locks captions + hand-off end-state |
| Cast registry | `data/characters.json` | Lt James / TJ aliasing |
| Atmosphere / sound spec | `design/sgu-opening-reference.md` | Companion doc (tone, SFX gaps) |
