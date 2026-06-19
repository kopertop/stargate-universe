# Opening Scene Script — E1 Cold Open ("Air, Part 1" gate evacuation)

> **What this is.** The script for the E1 *cold open* — the pre-flashback opening where the
> Icarus crew is shoved through the Stargate onto the derelict *Destiny* and Scott hands the
> player the **Find Rush** objective. §1 is the **canonical scene** (exact dialogue, story
> order); §3 maps it onto the shipped **~90 s cut** that
> `scripts/gate_room.gd::_play_prologue_cinematic()` actually renders.
>
> **Dialogue source.** Exact lines are from the *Stargate Universe* "Air, Part 1" episode
> transcript (GateWorld, transcribed by Callie Sullivan). Action/staging is paraphrased.
>
> **Audio.** Timing is anchored to the reference recording `~/Desktop/SGU Openning.m4a`
> (`cold_open_master.mp3`, 255.3 s). Its voices were stripped with Demucs and the result
> tightened into the **~90 s lull-free ambience bed** `cold_open_bed.mp3` (music, kawoosh,
> crowd — no dialog), played once as the master clock. Our **designed per-character VO**
> (Qwen3-TTS) plays on top via `_cap(..., vo_id)`.
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

The cold open is a **~90 s cut** (down from the 255 s recording). Every cue in §3 is **seconds
into `cold_open_bed.mp3`** — the ~90 s, lull-free ambience bed (Demucs no-vocals, voices
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

## 3. Shot list — the shipped ~90 s cut

Our cut **condenses** the canonical scene into a single playhead-timed pass with continuous
flow. Captions are the strings currently in `gate_room.gd`; where they diverge from §1 they're
marked **[adapt]** and should be reconciled toward §1 when the VO is (re)baked.

| Playhead | Beat | On-screen action / camera | Caption (speaker — line) | Code anchor |
|---:|---|---|---|---|
| 0.0 | **Letterbox in** | Cinematic bars slide in; wide cam dollies back across the whole ~90 s. Consoles dead, room dark, player model hidden. | — | `_make_cinematic_camera()`, `letterbox_in()` |
| ~0.5–3 | **Dial & open** | Ring spins → chevrons lock **one-by-one, a chevron-lock sound firing for each** → portal flushes (−Z plume) → kawoosh. | — | `dial_and_open(true)` → per-chevron `_play_chevron_lock()` |
| ~2–8 | **Wave 1 — Scott** | `LtScott` hurled through, lands **kneeling**, rises, then **walks toward the crew crashing onto the deck**. Crates already raining. | — | `_co_wave1_scott(scott)`, `_launch_crate_wave()` |
| 6.0 | Scott clears the LZ | Scott, moving to the downed crew. | `LT. SCOTT — "Get out of the way!"` **[adapt: canon "All right, get out of here. Get out of the way!"]** | `_cap(..., "open-scott-clearway")` |
| 8.0 | **Wave 2 — Young + medic** | **Col. Young** thrown *hardest* — face-down, off to the side, **stays down for the rest of the scene.** TJ/medic kneels near him. | — | `_co_wave2(young)` |
| 10.0 | Scott marshals | Comms-flavored shout. | `LT. SCOTT — "Slow down the evac — we're coming in too hot!"` **[adapt: canon "we are comin' in too hot!"]** | `_cap(..., "open-scott-evac")` |
| 13.0 | Crowd confusion | Disoriented crew picking themselves up. | `CREW — "Where are we?"` **[adapt: canon Wray "...Why didn't we come through to Earth?"]** | `_cap(..., "open-crowd-where")` |
| 16.0 | **Waves 3/4 — console crew** | **Dr Park** + **Dr Volker** pick their way to the dead consoles flanking the gate. | — | `_co_console_crew(...)` ×2 |
| 18.0 | Scott waves them clear | Waving civilians clear of the LZ. | `SGT. GREER — "There's no time to explain — off to the side!"` **[adapt: canon Scott]** | `_cap(..., "open-greer-side")` |
| 21.0 | Crowd confusion | — | `CREW — "What's going on?"` | `_cap(..., "open-crowd-what")` |
| 25.0 | **Medic pocket** | Push toward TJ working a wounded crewman's arm. | `TJ — "Can you move your fingers?"` | `_cap(..., "open-tj-fingers")` |
| 29.0 | … | Wounded crew grimacing. | `CREW — "I think it's broken."` **[adapt: canon "No. I think my arm is broken."]** | `_cap(..., "open-wounded-broken")` |
| 32.0 | … | TJ improvising a sling. | `TJ — "Okay — hold your arm there, we'll get it in a sling."` | `_cap(..., "open-tj-sling")` |
| 24 / 33 / 42 | **Waves 5–8 (+ crates)** | Greer+Spencer, Brody+Franklin, Riley+Wray, Dunning+Chloe pour through in pairs; more crates raining — **constant flow, no lull**. | — | `_extra_pair(...)` ×4, `_launch_crate_wave()` |
| 38.0 | Marshalling | Kicking debris aside, keeping the LZ clear. | `MARINE — "Leave it — there'll be more coming through."` | `_cap(..., "open-marine-leaveit")` |
| 43.0 | Medic check | TJ moving between casualties. | `TJ — "Are you okay?"` | `_cap(..., "open-tj-areyouokay")` |
| 47.0 | Status call | A landing reported clear. | `MARINE — "Clear!"` **[adapt: canon "Clear this area! There could still be more incoming!"]** | `_cap(..., "open-marine-clear")` |
| 50.0 | Marshalling | Driving the last stragglers off the pad. | `SGT. GREER — "Move, move, move!"` | `_cap(..., "open-greer-move")` |
| 56.0 | **Eli (the player) thrown** | Ragdoll proxy hurled through, landing **closest to the gate** (`Vector3(-0.6, 0.05, GATE_Z-6.2)`). | — | `_launch_ragdoll("Eli", eli_spot)` |
| 58.0 | Young, dazed | — | `COL. YOUNG — "Where are we?"` | `_cap(..., "open-young-whereare")` |
| 59.0 | **Player body swap** | Proxy freed; real `_player` snaps to the spot, **laid prone**, model shown. Thud. | — | `_lay_player_prone(true)`, `_show_player_model(true)` |
| 60.0 | Scott answers Young | — | `LT. SCOTT — "I don't know, sir."` **[adapt: canon, was OFFICER]** | `_cap(..., "open-officer-idontknow")` |
| 63.0 | **Gate collapses** | Event horizon snuffs out behind the last arrival; flame/steam plumes vent; no one else coming through. | — | `_collapse_gate()` |
| 66.0 | **Eli stands** | The player's body **groggily climbs to its feet**. | — | `_lay_player_prone(false)` |
| ~66–72 | **Command hand-off — Scott crosses to Young** | Scott walks to the downed Young, kneels to check him over, finds blood, stands to take charge. | — | `_co_command_handoff()` |
| 68.0 | Young passes command | Barely conscious, face-down. | `COL. YOUNG — "Scott … you're in charge."` **[adapt: canon "You're in charge, OK? You're …"]** | `_cap(..., "open-young-incharge")` |
| 71.0 | Scott calls the medic | Turns and screams for TJ. | `LT. SCOTT — "TJ!"` | `_cap(..., "open-scott-tj")` |
| 72.5 | Medic answers + crosses | TJ acknowledges and **breaks to Young**. | `TJ — "Coming!"` **[adapt: canon "I'm coming!"]** | `_cap(..., "open-tj-coming")` |
| 75.0 | **Turn to Eli / wonder** | Scott rounds on the civilian; crew look around the alien deck. | `ELI — "What is this place?"` **[adapt: canon Scott asks Eli this]** | `_cap(..., "open-eli-whatisthis")` |
| 77.0 | Scott faces the (dead) gate | He scans the arrivals, counting heads. | `LT. SCOTT — "I haven't seen Rush — I don't know if he went through ahead of me."` **[adapt: canon Eli "I don't know if he went ahead of me."]** | `_face_gate(scott)`, `_cap(..., "open-scott-norush")` |
| 81.5 | Scott calls out | Shouting into the dark room. | `LT. SCOTT — "Rush! … Rush!"` | `_cap(..., "open-scott-rush")` |
| 84.0 | **The quest line** | The diegetic launch of step 1. | `LT. SCOTT — "Help me find him."` **[adapt: canon "Rush! Eli, help me find him."]** | `_cap(..., "open-scott-findhim")` |
| 85.5 | **FTL shimmer** | Full-frame blue-white flash; the deck lurches (Destiny jumps). | `CREW — "What the hell was that?"` **[adapt: canon Greer "What in the hell was that?!"]** | `Cinematic.flash(...)`, `_cap(..., "open-crew-whatwasthat")` |
| 87.5 | **THE BUTTON** | Scott rounds on the player, hard and urgent. | `LT. SCOTT — "Eli! NOW!"` **[adapt: canon "Eli! Now!"]** | `_face_player(scott)`, `_cap(..., "open-scott-eli-now")` |
| 89.0 | Eli answers | Player-character scramble. | `ELI — "Okay! I'm coming!"` | `_cap(..., "open-eli-coming")` |
| 90.5 | **End** | Caption clears; **letterbox out**; bed freed. | *(blank)* | `letterbox_out()` |
| — | **HAND-OFF → GAMEPLAY** | See §4. | — | `_restore_player_camera()` … `advance_air_quest()` |

> **Sync note.** The **[adapt]** captions are our earlier condensed/re-attributed wording. When
> the Qwen3-TTS VO is (re)baked, reconcile each toward the exact §1 line and update
> `cold_open_lines.gd` to match.

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
  (~90 s) — the Demucs no-vocals stem of the TV recording (music/kawoosh/crowd, voices
  stripped), tightened to a lull-free cut. Captions/VO are timed to its playhead.
- **Per-line VO (our designed voices):** `sounds/dialog/prologue/open-*.wav`, played on top of
  the bed by `_cap(..., vo_id)`. Built via the **Qwen3-TTS Design→Clone** pipeline
  (`tools/tts-bakeoff/`): VoiceDesign per-mode refs (`refs_qwen/<char>_<mode>.wav`, picks in
  `make_qwen_refs.py`) → Base-model clone (`qwen_clone.py` + `jobs_qwen/`); generic crowd lines
  via `qwen_crowd.py`. Principals: Scott/Greer/Eli/TJ/Young; crowd: marine/civilian/officer.
  (Earlier IndexTTS-2 `rushed`-preset takes in `tools/tts-bake/` are superseded for the cold
  open.)
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
