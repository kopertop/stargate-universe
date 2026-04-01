# Crew Dialogue & Choice System

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-04-01
> **Implements Pillar**: Pillar 4 (Your Choices, Your Destiny)

## Overview

The Crew Dialogue & Choice System manages all conversations between Eli and
Destiny's crew — from casual passing remarks to story-critical confrontations that
shape the narrative. Dialogue is presented as full branching conversation trees
(Bioware-style): when Eli talks to a crew member, the camera shifts to a dialogue
view, the crew member speaks, and the player chooses from 2-4 response options that
represent Eli's actual words. Eli has a voice — the player shapes his personality
through the lines they choose, whether that's supportive, sarcastic, cautious, or
bold.

The system tracks **crew relationships** (how each crew member feels about Eli),
**faction standing** (military vs. civilian tension), and **choice history** (which
decisions the player has made). These values influence available dialogue options,
crew behavior, and story branching. Dialogue is data-driven: conversations are
authored as JSON dialogue trees with conditions, effects, and branching paths.
The system publishes events via the Event Bus (`crew:dialogue:started`,
`crew:choice:made`, `crew:morale:changed`) so other systems can react — the
Episode Narrative system uses choice history to branch the story, the Crew AI
system uses relationships to adjust NPC behavior, and the Resource system provides
context for crew complaints or gratitude.

## Player Fantasy

The Crew Dialogue & Choice System serves the fantasy of **being the person
everyone turns to** — and feeling the weight of that responsibility.

Eli isn't the captain. He isn't the scientist. He's the kid who's too smart to
ignore and too human to dismiss. When Colonel Young and Dr. Rush are at each
other's throats, they both talk to Eli. When Chloe is scared, she finds Eli.
When the crew is divided, Eli is the bridge. The dialogue system puts the player
in that position — not as a commander giving orders, but as a person navigating
relationships, earning trust, and sometimes making impossible choices.

**The power fantasy isn't control — it's connection.** You feel it when Rush
confides something to you he's told no one else, because you've earned his
respect through 20 hours of gameplay. You feel it when your sarcastic response
to Young actually makes him laugh and shifts his trust. You feel it when a choice
you made three episodes ago comes back in a way you didn't expect — because the
crew remembers.

This serves **Pillar 4 (Your Choices, Your Destiny)**: key story decisions
belong to the player. Alliances, sacrifices, resource priorities, and moral
dilemmas shape the narrative. The story follows SGU's spirit faithfully, but
your decisions create YOUR version of events — with real consequences.

## Detailed Design

### Core Rules

1. **Dialogue tree data model**: Each conversation is a `DialogueTree`:
   - `id`: string (e.g., `"rush-s1e03-power-crisis"`)
   - `speaker`: string (crew member ID)
   - `trigger`: enum — `PlayerInitiated`, `ProximityAmbient`, `EventTriggered`, `EpisodeScripted`
   - `priority`: int (higher priority conversations override lower ones)
   - `conditions`: array of predicates that must be true to make this tree available
     (e.g., `{ type: "relationship", target: "rush", min: 20 }`, `{ type: "episode", after: "s1e02" }`,
     `{ type: "resource", resource: "water", below: 0.3 }`)
   - `nodes`: array of `DialogueNode` (the conversation content)
   - `oneShot`: boolean (can only be triggered once, or repeatable)

2. **Dialogue node structure**: Each node in a tree is a `DialogueNode`:
   - `id`: string
   - `speaker`: `"npc"` | `"eli"`
   - `text`: string (the spoken line)
   - `animation`: string (optional — facial/body animation cue)
   - `responses`: array of `ResponseOption` (if player must choose)
   - `next`: string (ID of next node, if linear — no choice)
   - `effects`: array of effects applied when this node plays (relationship
     changes, event publishing, flag setting)
   - `conditions`: array of predicates (node is skipped if conditions fail,
     allowing dynamic dialogue within a tree)

3. **Response options**: When the player must choose, 2-4 `ResponseOption` are shown:
   - `id`: string
   - `text`: string (what Eli says — shown to player before selecting)
   - `tone`: enum — `Supportive`, `Sarcastic`, `Direct`, `Cautious`, `Bold`
   - `effects`: array of effects (relationship shifts, flags set, events published)
   - `next`: string (ID of next dialogue node after this response)
   - `conditions`: array (option only appears if conditions met — e.g., high
     relationship with Rush unlocks a unique response)

4. **Crew relationships**: Each crew member has a single `affinity` value toward
   Eli, ranging from -100 to +100:
   - **-100 to -50**: Hostile — crew member actively opposes Eli, may refuse requests
   - **-49 to -1**: Distrustful — guarded, short conversations, withholds info
   - **0**: Neutral — default starting point for most crew
   - **1 to 49**: Friendly — open to conversation, shares some info
   - **50 to 100**: Trusted — confides in Eli, unlocks unique dialogue, supports
     Eli's decisions in crew votes
   - Starting affinities are per-character: Chloe starts at 30 (friends from the
     start), Rush starts at -10 (dismissive), Young starts at 10 (cautious respect)

   **Romance**: When affinity reaches 90+, a **romance track** may unlock for any
   crew member (gated by narrative availability — not every character has romance
   content in every season). Romance is a separate value (0-100) that tracks
   independently from affinity. Romance-specific dialogue trees become available,
   and romance level affects unique story branches, exclusive scenes, and crew
   behavior toward Eli. Romance can be pursued with any character — the system
   imposes no restrictions on gender or role. Multiple romances are technically
   possible but may have narrative consequences (jealousy, faction tension).

5. **Choice history**: Every `ResponseOption` selected is recorded in a
   `ChoiceHistory` log: `{ dialogueId, nodeId, responseId, timestamp }`. The
   Episode Narrative system reads this history to determine story branching.
   Choices are permanent — no take-backs within a conversation.

6. **Conversation triggers**:
   - **PlayerInitiated**: Eli approaches a crew member, radial menu "Talk". If
     dialogue trees are available (conditions met), the highest-priority tree starts.
   - **ProximityAmbient**: Crew members say one-liner remarks when Eli walks near
     them. These are NOT full dialogue trees — just contextual barks (short lines
     reacting to game state). No camera change, no player choice.
   - **EventTriggered**: An Event Bus event starts a conversation (e.g.,
     `ship:lifesupport:critical` triggers Rush demanding Eli help).
   - **EpisodeScripted**: The Episode system forces a specific dialogue at a
     specific moment in the story.

7. **Dialogue camera**: When a full dialogue tree starts, the camera transitions
   to a **dialogue mode** (defined in Camera System GDD): two-shot framing of Eli
   and the speaker, with over-the-shoulder cuts between speakers. Game time pauses
   during dialogue (timers halt). Player can still look around slightly but cannot
   move.

8. **Ambient barks**: Short contextual lines that don't interrupt gameplay:
   - Crew members have bark pools keyed to game state (resource levels, ship
     condition, recent events, relationship with Eli)
   - Barks play as floating text above the crew member's head + audio
   - Cooldown between barks from the same character (no spam)
   - Barks do NOT affect relationships or choice history

9. **Effects system**: Dialogue nodes and responses can trigger effects:
   - `{ type: "relationship", target: "rush", delta: +15 }` — shift affinity
   - `{ type: "romance", target: "chloe", delta: +10 }` — shift romance level
   - `{ type: "flag", key: "told_rush_about_stones", value: true }` — set a
     narrative flag
   - `{ type: "event", name: "crew:choice:made", payload: {...} }` — publish
     to Event Bus
   - `{ type: "resource", resource: "food", delta: -10 }` — dialogue can
     cost/grant resources ("Trade half our food for safe passage")
   - `{ type: "morale", delta: -5 }` — affect crew-wide morale

10. **Conversation interruption**: Since game time pauses during dialogue, new
    crises cannot *start* mid-conversation. However, if a crisis was already
    active when dialogue began (e.g., player talked to Rush during an ongoing
    hull breach), the conversation may be interrupted by an escalation event.
    This is rare and episode-scripted only. The speaker says a context-appropriate
    line ("We'll finish this later!"), dialogue ends, and the conversation state
    is saved so it can be resumed.

### States and Transitions

| State | Entry Condition | Exit Conditions | Behavior |
|-------|----------------|-----------------|----------|
| **Idle** | No conversation active | Player initiates "Talk", event triggers dialogue, episode scripts dialogue | Ambient barks can play. Crew members are interactable. |
| **Starting** | Dialogue tree selected, camera transitioning | Camera reaches dialogue framing → In Dialogue | Camera shifts to dialogue mode. Game time pauses. HUD fades. |
| **In Dialogue** | Camera ready, first node playing | Conversation reaches end node → Ending. Crisis interruption → Interrupted. | NPC lines play automatically. Player choices appear when a response node is reached. Player selects a response. Effects apply immediately on selection. |
| **Awaiting Choice** | Node with responses reached | Player selects a response → In Dialogue (next node). Timer expires (if timed) → default response selected. | Response options displayed. Player reads and selects. Some critical choices may be timed (rare). |
| **Interrupted** | Crisis event fires during dialogue | Interruption line finishes → Idle. | Speaker delivers interruption line. Conversation state saved (current node). Can be resumed later via PlayerInitiated trigger. |
| **Ending** | Final node reached (no next, no responses) | Exit animation completes → Idle | Closing line plays. Camera transitions back to gameplay. Game time resumes. Effects from the conversation are finalized. |

**Relationship thresholds** (not states, but tracked values):

| Threshold | Affinity | Effect on Available Dialogue |
|-----------|----------|----------------------------|
| Hostile | -100 to -50 | Only confrontational dialogue. May refuse to speak. |
| Distrustful | -49 to -1 | Limited topics. Guarded responses. |
| Neutral | 0 | Standard dialogue available. |
| Friendly | 1 to 49 | Expanded topics. Personal stories shared. |
| Trusted | 50 to 89 | Confidential info, unique missions, support in crew votes. |
| Romance-eligible | 90 to 100 | Romance dialogue trees become available (if authored). |

**Romance levels** (0-100, separate track):

| Level | Range | Effect |
|-------|-------|--------|
| Interest | 0-30 | Flirtatious undertones in dialogue. Subtle cues. |
| Dating | 31-60 | Exclusive dialogue scenes. Crew notices and reacts. |
| Committed | 61-100 | Deep story integration. Unique crisis responses. Partner-specific scenes. |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Event Bus** | Bidirectional | Publishes: `crew:dialogue:started`, `crew:dialogue:ended`, `crew:choice:made`, `crew:morale:changed`, `crew:relationship:changed`, `crew:romance:changed`. Subscribes to: `ship:*` (crisis interruptions), `resource:*` (bark context), `episode:*` (scripted dialogues). |
| **Player Controller** | Inbound (trigger) | "Talk" radial menu action on crew members triggers `PlayerInitiated` dialogue. Interaction range: 3.5m (dialogue reach). Player movement locked during dialogue. |
| **Camera System** | Outbound (mode switch) | Requests dialogue camera mode (two-shot, OTS cuts). Returns to exploration mode on dialogue end. |
| **Timer & Pressure** | Bidirectional | Timers pause during dialogue (game time halts). Crisis timer events can interrupt conversations. |
| **Resource & Inventory** | Reads + writes | Reads resource levels for conditional dialogue and bark context. Dialogue effects can grant/consume resources. |
| **Ship State** | Reads | Reads ship conditions for contextual barks (power level complaints, life support warnings). |
| **Episode Narrative** *(undesigned)* | Bidirectional | Episodes trigger `EpisodeScripted` dialogues. Choice history feeds episode branching. Romance levels affect story arcs. |
| **Crew AI & Schedule** *(undesigned)* | Outbound (read) | Crew AI reads relationship values to adjust NPC behavior (proximity to Eli, helpfulness, faction alignment). |
| **Stargate & Planetary Runs** | Reads | Post-run context for dialogue (what was gathered, what was left behind). |
| **Kino Remote** *(undesigned)* | Outbound (read) | May display crew relationship summary screen. |
| **Save/Load** *(undesigned)* | Outbound (serialization) | Serializes: all relationship values, romance values, choice history, narrative flags, interrupted conversation state. |

**Provisional contracts:**
- Episode Narrative: scripted dialogue trigger protocol and story-branching query API TBD
- Crew AI: relationship-to-behavior mapping TBD

## Formulas

### Relationship Shift

```
new_affinity = clamp(affinity + delta * tone_modifier, -100, 100)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `affinity` | int | -100 to 100 | crew member state | Current affinity |
| `delta` | int | -30 to +30 | dialogue effect | Base shift from this choice |
| `tone_modifier` | float | 0.5-1.5 | character config | How much this character responds to specific tones (Rush responds more to Direct, Chloe to Supportive) |

### Romance Eligibility

```
romance_available = affinity >= ROMANCE_THRESHOLD
                 && romance_content_authored(character, current_episode)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `ROMANCE_THRESHOLD` | int | 90 | config | Minimum affinity to unlock romance |
| `romance_content_authored` | bool | — | content | Whether romance dialogue exists for this character at this story point |

### Bark Cooldown

```
can_bark = (now - last_bark_time) > BARK_COOLDOWN_SECONDS
        && (now - last_bark_from_anyone) > BARK_GLOBAL_COOLDOWN
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `BARK_COOLDOWN_SECONDS` | float | 30-120s | config | Per-character cooldown |
| `BARK_GLOBAL_COOLDOWN` | float | 8-15s | config | Minimum gap between any barks |

### Crew Morale (aggregate)

```
crew_morale = average(all_crew_affinities) + resource_modifier + ship_modifier
resource_modifier = -20 if any resource depleted, -10 if critical, 0 otherwise
ship_modifier = (avg_ship_system_condition - 0.5) * 20
```

Crew morale is an aggregate value that affects ambient bark tone and episode triggers,
not a per-character value.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Affinity at -100, player tries to talk** | Crew member refuses: "I have nothing to say to you." One-line dismissal, no tree. | Hostile characters don't engage. Player must rebuild through actions, not words. |
| **Two dialogue triggers fire simultaneously** | Higher priority wins. Lower priority queues (if `EventTriggered` or `EpisodeScripted`) or drops (if `ProximityAmbient`). | Scripted events should never be lost. Ambient barks are expendable. |
| **Pre-existing crisis escalates during conversation** | Rare, episode-scripted only (since new crises can't start — timers are paused). Conversation saves at current node. When resumed, the choice re-presents. | Game time is paused during dialogue, so this only happens with already-active crises. |
| **Player walks away during dialogue** | Not possible — movement is locked during full dialogue. Player must finish or wait for interruption. | Dialogue is a commitment. Prevents accidentally breaking conversations. |
| **Romance pursued with multiple characters** | System allows it. Individual characters may react with jealousy dialogue (if authored). Faction effects possible. No system-level block. | Player freedom — consequences are narrative, not mechanical gates. |
| **Dialogue references a resource that was gathered after the tree was authored** | Conditions use live game state. If a condition references "water below 30%" but water is now at 50%, that dialogue branch simply doesn't appear. | Conditions are evaluated at trigger time, not authoring time. |
| **All response options fail conditions** | Fallback: show a single generic response ("..."). Log a warning for content authors. | Prevent soft lock — there must always be at least one option. |
| **Save/Load during dialogue** | Save captures: current dialogue tree, current node, pending choice (if awaiting), all relationship values. On load, dialogue resumes at saved node. | Mid-conversation save must work. |
| **Dialogue tree references a character who died in story** | Tree conditions include `{ type: "flag", key: "character_alive", value: true }`. Dead characters' trees are never triggered. | Content safety — don't summon dead characters. |
| **Bark fires during a loading screen or scene transition** | Bark is suppressed. Barks only play when the player is in active gameplay. | No disembodied voices during transitions. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Event Bus | Hard | Publishes all `crew:*` events. Subscribes to crisis events for interruption. |
| Save/Load (interface) | Hard (contract) | Serialization of relationships, romance, choice history, flags, interrupted state. |
| Player Controller | Soft | "Talk" radial menu trigger. Movement lock during dialogue. |
| Camera System | Soft | Dialogue camera mode. Works without (fixed camera fallback). |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Episode Narrative | Hard | Choice history for story branching. Relationship/romance values for arc gating. |
| Crew AI & Schedule | Hard | Relationship values for NPC behavior toward Eli. |
| Kino Remote | Soft | Relationship summary for optional crew status screen. |
| Audio & Ambience | Soft | Dialogue audio playback, bark audio. |
| Stargate & Planetary Runs | Soft | Post-run context for crew reactions. |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `ROMANCE_THRESHOLD` | 90 | 70-100 | Romance harder to unlock. More investment required. | Romance easier. Less earned. |
| `BARK_COOLDOWN_SECONDS` | 60s | 30-120s | Fewer barks. Quieter crew. | More barks. Livelier but potentially annoying. |
| `BARK_GLOBAL_COOLDOWN` | 10s | 5-20s | Longer gaps between any barks. | Overlapping crew comments. |
| `MAX_RELATIONSHIP_DELTA_PER_CONVERSATION` | 30 | 10-50 | Single conversations can shift relationships dramatically. | Slower relationship changes. More conversations needed. |
| `TIMED_CHOICE_DURATION` | 10s | 5-30s | More time for rare timed choices. | More pressure on timed choices. |
| `STARTING_AFFINITY_*` | varies | -50 to 50 | Per-character starting disposition. Higher = friendlier from the start. | Lower = more work to build relationship. |
| `TONE_MODIFIER_*` | varies | 0.5-2.0 | Per-character tone sensitivity. How much each tone affects them. | Less responsive to specific tones. |
| `DIALOGUE_CAMERA_TRANSITION_SECONDS` | 0.8s | 0.3-1.5s | Slower camera transition into dialogue. More cinematic. | Snappier. Less interruption to gameplay flow. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Dialogue start | Camera shifts to dialogue mode, HUD fades, subtle vignette | Ambient dips, conversation tone audio bed | High |
| NPC speaking | Lip sync (or approximation), body language animation | Character voice lines (or text with audio tone) | High |
| Player choice appears | Response options slide in, highlight on hover | Subtle UI sound on reveal | High |
| Choice selected | Selected option highlights, others fade | Selection click | Medium |
| Relationship shifted | No direct visual — felt through future dialogue | Subtle chime (positive) or low tone (negative) | Low |
| Romance option available | Heart/spark icon on response option | Warm musical accent | Medium |
| Ambient bark | Text floats above NPC head, fades after 3-4 seconds | Character voice bark (short audio clip) | Medium |
| Conversation end | Camera transitions back to gameplay, HUD returns | Ambient audio fades back up | High |
| Interruption | Speaker gestures urgently, camera shakes slightly | Urgent line, alarm audio bleeds in | Medium |

## UI Requirements

| Information | Display Location | Update Trigger | Condition |
|-------------|-----------------|----------------|-----------|
| NPC dialogue text | Bottom-center dialogue box (cinematic letterbox style) | Each dialogue node | During full dialogue |
| Response options | Left side of screen, stacked vertically | When response node reached | During player choice |
| Speaker name | Above dialogue text | On speaker change | During full dialogue |
| Tone indicator | Small icon/color on each response option | With response display | Optional — helps player understand tone |
| Ambient bark text | Floating above NPC head | On bark trigger | During gameplay (not during dialogue) |
| Relationship summary | Kino Remote — Crew screen (optional) | On relationship change | When player checks Kino Remote |

Dialogue UI uses a cinematic letterbox style (black bars top/bottom) to
distinguish dialogue from gameplay. Response options are positioned on the left
so the right side shows the NPC's face.

## Acceptance Criteria

- [ ] **Dialogue tree loading**: JSON dialogue trees load and parse correctly. All node references resolve.
- [ ] **Player-initiated dialogue**: "Talk" radial menu on crew member starts highest-priority available tree.
- [ ] **Response selection**: 2-4 options display. Player selects one. Eli's line plays. Correct next node follows.
- [ ] **Conditional responses**: Response options with failed conditions are hidden. At least one option always shows.
- [ ] **Relationship tracking**: Affinity values update correctly on dialogue effects. Clamped to -100/+100.
- [ ] **Romance unlock**: Romance dialogue trees become available when affinity reaches threshold. Romance value tracks independently.
- [ ] **Choice history**: Every response selection is logged. Episode system can query choice history.
- [ ] **Ambient barks**: Contextual one-liners play near crew members. Respect cooldowns. React to game state.
- [ ] **Dialogue camera**: Camera transitions to dialogue mode on start, returns on end. Game time pauses.
- [ ] **Conversation interruption**: Pre-existing crisis escalation can interrupt. State saved. Resumable.
- [ ] **Effects system**: Relationship shifts, flag setting, resource changes, event publishing all work from dialogue effects.
- [ ] **Conditional nodes**: Nodes with failed conditions are skipped. Dialogue flows correctly through conditional branches.
- [ ] **Serialization**: Relationships, romance, choice history, flags, interrupted state all serialize/deserialize correctly.
- [ ] **Performance**: Dialogue tree evaluation (condition checking, next-node resolution) completes in < 1ms.
- [ ] **All tuning values externalized**: Cooldowns, thresholds, starting affinities, tone modifiers from config.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Voice acting vs. text-only dialogue? If voice acted, how many lines per character? Massive content/cost decision. | Creative Director | Before production | — |
| How many crew members have full dialogue trees vs. just barks? Core cast (Young, Rush, Chloe, Greer, TJ, Camile) likely full; background crew just barks. | Narrative Director | Before S1 writing | — |
| Should timed choices exist? If so, how often? Timed choices add pressure but frustrate players who read slowly. | Game Designer | During prototype | — |
| How does the dialogue system handle crew members who aren't present in a scene? Can you "call" them via Kino Remote? | Game Designer | Before Kino Remote GDD | — |
| What's the total dialogue word count estimate for S1? Determines writing scope and potential voice acting budget. | Producer | Before S1 content planning | — |
| Should the player be able to review past conversation logs? Useful for complex narratives but adds UI. | UX Designer | Before Kino Remote GDD | — |
