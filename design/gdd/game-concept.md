# Game Concept: Stargate Universe — The Destiny Mission

*Created: 2026-03-29*
*Status: Draft*

---

## Elevator Pitch

> It's a third-person exploration-survival game where you play as Eli Wallace
> aboard the Ancient ship Destiny, billions of light-years from Earth. Explore
> the ship's vast unmapped sections, make desperate supply runs to alien worlds
> during FTL stops, manage crew crises, and uncover the Destiny's true mission —
> telling the complete Stargate Universe story, including the ending the show
> never got to tell.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Third-person exploration-survival with narrative choice |
| **Platform** | PC (Web/Desktop via ggez + Three.js) |
| **Target Audience** | Exploration gamers + Stargate fans (see Player Profile) |
| **Player Count** | Single-player |
| **Session Length** | 30-90 minutes (one "episode" per session) |
| **Monetization** | None (personal project / fan game) |
| **Estimated Scope** | Large (9+ months) |
| **Comparable Titles** | Subnautica, Outer Wilds, Tacoma, Firewatch |

---

## Core Fantasy

You are Eli Wallace — a brilliant, self-taught genius who was playing video games
in his mother's basement when the Stargate program recruited him to solve an
Ancient equation. Now you're stranded aboard a million-year-old ship hurtling
through the universe with a crew of soldiers, scientists, and civilians who
didn't sign up for this.

The ship is vast, ancient, and full of secrets. The crew is fractured, scared,
and looking for someone to hold things together. You're not a soldier or a
trained scientist — you're the smartest person in the room who also happens to
be the most human. Every day is a new crisis: failing life support, hostile
aliens, power struggles between Colonel Young and Dr. Rush, and the ever-present
question of whether you'll ever see Earth again.

The core fantasy is: **you are the person who figures things out.** You explore
the ship, decode Ancient technology, jury-rig solutions, and — through your
choices — shape the destiny of everyone aboard.

---

## Unique Hook

Like Subnautica, AND ALSO the "base" you're exploring is a sentient Ancient
starship with its own mission, and every few hours it drops out of FTL near a
star system where you can gate to alien worlds for supplies before time runs out.

The ship isn't just a hub — it's the primary exploration space, and it's telling
its own story through the technology and logs the Ancients left behind. Your
survival depends on understanding a vessel that was ancient before humanity
existed.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** (sensory pleasure) | 3 | Dark atmospheric corridors, Ancient tech glow, ambient ship sounds, planetary vistas |
| **Fantasy** (make-believe, role-playing) | 2 | You ARE Eli Wallace. Your choices shape the crew's fate aboard an Ancient starship |
| **Narrative** (drama, story arc) | 1 | Beat-for-beat SGU retelling with player agency at key decision points, continuing past S2 |
| **Challenge** (obstacle course, mastery) | 5 | Survival pressure (resources, time limits), puzzle-solving with Ancient tech |
| **Fellowship** (social connection) | N/A | Single-player, but crew relationships create simulated social bonds |
| **Discovery** (exploration, secrets) | 1 | Unmapped ship sections, alien worlds, Ancient mysteries, the Destiny's true mission |
| **Expression** (self-expression) | 4 | Story choices create "your version" of the SGU narrative |
| **Submission** (relaxation) | N/A | Not a relaxation game — tension is constant |

### Key Dynamics (Emergent player behaviors)

- Players will obsessively explore every corridor and room on Destiny looking for
  lore, supplies, and Ancient tech — the ship rewards thoroughness
- Players will agonize over timed planetary missions: "Do I grab more lime for
  the CO2 scrubbers or explore that Ancient ruin?"
- Players will replay key story decisions to see alternate outcomes
- Players will piece together the Destiny's mission from scattered clues across
  dozens of hours before the game explicitly reveals it

### Core Mechanics (Systems we build)

1. **Third-person ship exploration** — Navigate Destiny's corridors, scan rooms,
   interact with Ancient consoles, unlock sealed sections
2. **Planetary supply runs** — Gate to alien worlds during FTL stops, gather
   resources under varying time pressure, face environmental hazards
3. **Ancient tech puzzle-solving** — Decode and repair ship systems through
   logic puzzles and environmental clue-reading (not inventory crafting)
4. **Crew relationship and crisis management** — Dialogue choices, crew morale,
   faction tensions (military vs. civilian), key story decisions
5. **Episode-based narrative progression** — Story advances in episode-sized
   chunks, each with its own crisis, resolution, and character development

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | Story decisions shape narrative outcomes. Exploration order is player-driven. Planetary mission triage is your call. | Core |
| **Competence** (mastery, skill growth) | Growing understanding of Ancient technology. Ship sections that were impossible early become navigable. Puzzle-solving skill improves. | Core |
| **Relatedness** (connection, belonging) | Deep crew relationships. Eli's bonds with Chloe, Rush, Young, and others. Feeling responsible for everyone aboard. | Supporting |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Explorers** (discovery, understanding systems, finding secrets) — The
  entire game is built around exploring Destiny and alien worlds, piecing
  together Ancient mysteries
- [x] **Socializers** (relationships, cooperation, community) — Crew
  relationships and story choices create deep simulated social bonds
- [ ] **Achievers** (goal completion, collection, progression) — Secondary.
  Ship repair progress and episode completion provide achievement hooks
- [ ] **Killers/Competitors** (domination, PvP, leaderboards) — Not served.
  Combat is situational, not competitive

### Flow State Design

- **Onboarding curve**: The game opens with the Icarus Base evacuation — chaos,
  confusion, arriving on Destiny with no idea what's happening. The player
  learns by doing, just as Eli did. Early episodes teach one system at a time
  (life support crisis teaches resource management, first planet stop teaches
  gate mechanics, etc.)
- **Difficulty scaling**: Early episodes have tight timers and limited ship
  access. As you repair systems and understand Ancient tech, you gain more
  control, more time, more options. The challenges shift from "survive the
  next hour" to "make impossible choices about the mission."
- **Feedback clarity**: Ship status displays (power, life support, shields)
  provide constant feedback. Crew reactions to your decisions show social
  consequences. Newly accessible ship sections are visible proof of progress.
- **Recovery from failure**: Failure is narrative, not punitive. A failed
  supply run means the crew goes hungry — triggering a crisis episode, not a
  game over screen. Death rewinds to the last checkpoint within the episode.

---

## Core Loop

### Moment-to-Moment (30 seconds)
Walking Destiny's corridors in first person. Scanning rooms with your kino
(floating camera drone). Reading Ancient consoles. Finding crew logs, supply
caches, and sealed doors. Interacting with crew members in passing. The ship
hums and groans around you — it feels alive, ancient, and vast.

### Short-Term (5-15 minutes)
Complete a task within the current episode: repair a conduit to restore power
to a new section, explore a sealed deck, gather specific supplies on a planet
before the timer runs out, mediate a crew dispute, or solve an Ancient tech
puzzle to unlock a new capability. Each task feeds the episode's narrative arc.

### Session-Level (30-90 minutes)
Play through one "episode" — a self-contained story beat mirroring the show's
structure. Each episode has:
- A central crisis or objective (water shortage, alien attack, power failure)
- Character development moments (crew conversations, relationship shifts)
- A key decision point where the player's choice matters
- A resolution that advances the overarching narrative
- A natural stopping point (cliffhanger or quiet moment)

### Long-Term Progression
- **Ship state**: Sections repaired, systems online, capabilities unlocked.
  Destiny transforms from a death trap into a home over dozens of hours.
- **Story arc**: From "get us home" (Season 1) to "understand the mission"
  (Season 2) to "complete what the Ancients started" (Season 3+).
- **Relationships**: Crew bonds deepen, factions shift, alliances form and
  break based on your decisions.
- **Knowledge**: Your understanding of Ancient language and technology grows,
  opening previously incomprehensible systems.

### Retention Hooks
- **Curiosity**: What's behind the next sealed door? What is the Destiny's
  mission? What happened to the Ancients? Each episode ends with unanswered
  questions.
- **Investment**: The crew feels like family. Destiny feels like home. Your
  repair progress is visible everywhere you look.
- **Mastery**: Ancient puzzles get more complex but your growing knowledge
  makes you feel smarter, not more frustrated.

---

## Game Pillars

### Pillar 1: The Ship IS the World
Destiny is a character, not a backdrop. Exploring, repairing, and understanding
the ship is the core experience. It should feel vast, ancient, and real — a
million-year-old vessel with its own history, damage, and secrets.

*Design test*: "Should we add another planet type or another ship section?"
-> Another ship section. The ship always comes first.

### Pillar 2: Survival with Purpose
Resources are scarce because the story demands it, not for grind. Every supply
run has narrative stakes — the crew needs water, the CO2 scrubbers need lime,
the shields need power. Scarcity creates drama, not busywork.

*Design test*: "Should we add a crafting tree?" -> No. Resources feed
story-critical repairs and crew needs, not progression systems.

### Pillar 3: Earned Discovery
Nothing is handed to you. Understanding Ancient tech, ship systems, and the
mission comes through exploration and puzzle-solving. Environmental clues guide
the player, not quest markers or tutorials.

*Design test*: "Should we add a waypoint to the next objective?" -> No.
The player figures it out, just like Eli would.

### Pillar 4: Your Choices, Your Destiny
Key story decisions belong to the player. Alliances, sacrifices, resource
priorities, and moral dilemmas shape the narrative. The story follows SGU's
spirit faithfully, but your decisions create YOUR version of events — with
real consequences.

*Design test*: "Should Rush's betrayal be a cutscene or a player-driven
moment?" -> Player-driven. The player decides how to respond.

### Anti-Pillars (What This Game Is NOT)

- **NOT combat-focused**: Combat exists (Lucian Alliance boardings, drone
  attacks, hostile aliens) but it's situational and tense. This is not a
  shooter with Stargate skin. If a fight breaks out, something has gone wrong.
- **NOT aimless**: The story drives forward through episodes, but between
  episodes, Destiny and nearby worlds are a full sandbox to explore freely.
  Exploration is encouraged and rewarded — but the narrative never stalls
  waiting for the player to find a trigger. You choose when to advance.
- **NOT passive**: The player doesn't watch the story — they live it. Decisions
  have consequences that ripple through future episodes.

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| Subnautica | Exploration-survival in an alien environment, base as progression | The "base" is a pre-existing Ancient ship you repair, not build from scratch | Validates exploration-survival + story works commercially |
| Outer Wilds | Knowledge-as-progression, environmental storytelling, mystery structure | Linear episode structure instead of open time loop; survival mechanics add stakes | Proves discovery-driven gameplay is deeply compelling |
| Tacoma / Gone Home | Third-person narrative exploration, environmental storytelling, found logs | Active survival mechanics and crew interaction add gameplay beyond walking | Validates atmospheric exploration on a ship/station |
| Firewatch | Character relationships through dialogue, player choice in narrative | Larger cast, longer arc, more mechanical depth | Proves intimate character stories work in third-person |
| Stargate Universe (show) | The entire setting, cast, story, tone, and themes | Interactive — the player IS Eli and makes the choices | The source material and the reason this game exists |

**Non-game inspirations**: SGU's cinematography (handheld, intimate, dark),
Battlestar Galactica's tension and crew dynamics, The Martian's "science the
shit out of it" problem-solving, 2001: A Space Odyssey's sense of cosmic scale.

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 20-40 |
| **Gaming experience** | Mid-core to hardcore (comfortable with third-person exploration, puzzle-solving) |
| **Time availability** | 30-90 minute sessions, several times per week |
| **Platform preference** | PC |
| **Current games they play** | Subnautica, Outer Wilds, Firewatch, No Man's Sky, narrative adventures |
| **What they're looking for** | A deep, atmospheric exploration game with real story stakes — especially if they're Stargate fans |
| **What would turn them away** | Twitch combat, grinding, lack of narrative payoff, disrespect of SGU source material |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Engine** | ggez (Three.js 0.181 framework) — already configured. WebGPU renderer with WebGL fallback |
| **Physics** | Crashcat (ggez built-in) — character movement, object interaction |
| **Key Technical Challenges** | Large ship interior rendering (occlusion culling critical), atmospheric lighting pipeline, episode/save state management, dialogue/choice system |
| **Art Style** | Atmospheric sci-fi — dark corridors, volumetric fog, glowing Ancient tech, moody lighting. AI-assisted asset creation (Meshy/Tripo for models, atmospheric rendering hides imperfections) |
| **Art Pipeline Complexity** | Medium — AI-generated base models + manual cleanup + heavy reliance on lighting/atmosphere |
| **Audio Needs** | High — ambient ship sounds, atmospheric music, voice or text dialogue. Sound design is critical for immersion in dark corridors |
| **Networking** | None (single-player) |
| **Content Volume** | ~40-60 episodes across 3+ "seasons", 15-20 explorable ship sections, 20-30 unique planet environments, 50+ hours of gameplay |
| **Procedural Systems** | Minimal — hand-crafted ship and story. Possible light procedural variation on planet surfaces |

---

## Risks and Open Questions

### Design Risks
- Episode pacing may feel too linear for players expecting sandbox freedom
- Balancing player agency with faithful SGU retelling — too much freedom breaks
  the story, too little feels like a walking simulator
- Crew AI and dialogue quality must be high enough to create genuine attachment

### Technical Risks
- Large ship interior performance — Destiny is enormous; rendering deep
  corridor networks in WebGPU needs careful LOD and occlusion culling
- Dialogue/choice system complexity for branching narrative
- AI-generated 3D assets may lack visual consistency — need a strong
  post-processing pipeline to unify the look

### Market Risks
- Fan game based on a cancelled show — audience is passionate but niche
- Stargate IP ownership (MGM/Amazon) means this likely can't be commercialized
- Long development timeline for a solo developer

### Scope Risks
- 40-60 episodes is an enormous amount of content for one person
- Each planet needs to feel distinct — content variety is the hardest challenge
- Branching narrative multiplies content requirements

### Open Questions
- How much voice acting (if any) vs. text dialogue? — Prototype both
- How complex should Ancient tech puzzles be? — Prototype a puzzle system
- How do we handle the SGU characters' likenesses? Stylized enough to avoid
  legal issues? — Research before committing to character models
- Should planetary exploration be fully 3D or could some planets use a
  simplified/top-down view to reduce content requirements? — Prototype

---

## MVP Definition

**Core hypothesis**: Players find exploring Destiny and making supply runs to
alien worlds engaging enough to want to play through the full SGU story.

**Required for MVP**:
1. Destiny bridge + 2-3 connected corridors (explorable third-person)
2. One functional Stargate (gate to a planet and back)
3. One planet with a timed supply run (gather resource, return to ship)
4. One ship repair task (use gathered resource to fix a system)
5. One crew interaction with a dialogue choice
6. Basic atmospheric rendering (fog, lighting, Ancient tech glow)

**Explicitly NOT in MVP** (defer to later):
- Full episode system / save states
- Multiple ship sections
- Branching narrative consequences
- Ancient tech puzzle system
- Crew relationship tracking
- Multiple planet types

### Scope Tiers (if budget/time shrinks)

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | Bridge + 3 corridors, 1 planet | Walk, gate, gather, repair, talk | 4-6 weeks |
| **Vertical Slice** | 5 ship sections, 3 planets, Episode 1-3 | Full episode loop, choices, ship status | 3-4 months |
| **Alpha** | 10 ship sections, 10 planets, Season 1 | All core systems, rough content | 6-9 months |
| **Full Vision** | Complete Destiny, 30+ planets, S1-S3+ | Full story, polished, branching narrative | 12-18+ months |

---

## Next Steps

- [ ] Validate concept with `/design-review design/gdd/game-concept.md`
- [ ] Decompose into systems with `/map-systems`
- [ ] Author per-system GDDs with `/design-system`
- [ ] Create first architecture decision record with `/architecture-decision`
- [ ] Prototype the core loop with `/prototype core-exploration`
- [ ] Plan first sprint with `/sprint-plan new`
