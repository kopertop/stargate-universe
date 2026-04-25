# Voice Line Manifest — Stargate Universe Game

> **Status**: Draft (building from GDD analysis + script reference)
> **Last Updated**: 2026-04-11
> **TTS Voice Cast**: ElevenLabs Multilingual v2

## Voice Cast

| Character | ElevenLabs Voice | Voice ID | Description |
|-----------|-----------------|----------|-------------|
| Eli Wallace | Will | bIHbv24MWmeRgasZH58o | Young, american, chill — Eli's nerdy but casual energy |
| Ship AI (Destiny) | Alice | Xb7hH8MSUJpSbSDYk0k2 | Clear, british, professional — robotic ship computer |
| Colonel Young | Brian | nPczCjzI2devNBz1zQrb | Deep, resonant, american — authoritative military |
| Dr. Rush | George | JBFqnCBsd6RMkjVDRZzb | Warm, british, mature — intense scientist |
| Lt. Scott | Liam | TX3LPaxmHKxFdv7VOQHJ | Energetic, american, young — reliable field leader |
| Chloe Armstrong | Jessica | cgSgspJ2msm6clMCkdW9 | Playful, bright, warm — empathetic young woman |
| TJ Johansen | Lily | pFZP5JQG7iQjIQuC4Bku | Confident, british — composed medic |
| Sgt. Greer | Harry | SOYHLrjzK2X1ezoPC6cr | Fierce, american, rough — loyal soldier |
| Camile Wray | Matilda | XrExE9yKIg1WjnnlVkGX | Professional, american, upbeat — diplomatic civilian |
| Adam Brody | Chris | iP95p4xoKVk53GoZ742B | Charming, down-to-earth, casual — sarcastic engineer |
| Dale Volker | Roger | CwhRBWXzGAHq8TQ4Fs17 | Laid-back, casual, resonant — nervous astrophysicist |
| Lisa Park | Laura | FGY2WhTYpPnrIDTdsKH5 | Quirky, american, young — enthusiastic scientist |
| Vanessa James | Sarah | EXAVITQu4vr4xnSDxMaL | Mature, confident, professional — disciplined military |
| MSgt. Greer | Harry | SOYHLrjzK2X1ezoPC6cr | (same as above) |

---

## Line Categories

Each line has: **ID**, **Character**, **Text**, **Trigger Context**, **Priority** (P1=MVP, P2=Vertical Slice, P3=Full Game)

---

## 1. ELI WALLACE — Player Character (Primary Voice)

Eli is the player character. He speaks the most — reacting to everything the player encounters. His voice evolves from overwhelmed newcomer (S1) to confident operator (S3).

### 1.1 Exploration / Discovery

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-discovery-01 | "Whoa, okay, that's... that's definitely something." | First visit to new section | P1 | DONE |
| eli-discovery-02 | "I think I found something! Like, something actually useful for once." | Finding supply cache | P1 | DONE |
| eli-discovery-03 | "This is incredible. The Ancient tech in this section is completely intact." | Powered section discovery | P1 | DONE |
| eli-sealed-section | "I think this section has been sealed for centuries. Maybe longer." | Entering sealed area | P1 | DONE |
| eli-translate | "Ancient text on the console here. Give me a second to translate." | Interacting with data node | P1 | DONE |
| eli-puzzle-01 | "Wait, wait, wait. Let me figure this out." | Starting a puzzle/repair | P1 | DONE |
| eli-puzzle-solved | "Got it! The control sequence is... yeah, I can do this." | Completing puzzle | P1 | DONE |
| eli-explore-dark-01 | "It's pitch black in here. Where's my phone..." | Entering unpowered section | P2 | TODO |
| eli-explore-dark-02 | "Okay, this is officially creepy. Even for this ship." | Deep in unpowered section | P2 | TODO |
| eli-explore-new-room | "Another room. What were the Ancients even doing in here?" | Generic new room | P2 | TODO |
| eli-explore-bridge | "Is this... this could be another control center." | Finding important room | P2 | TODO |
| eli-explore-observation | "Wow. You can see the whole galaxy from here." | Observation deck | P2 | TODO |
| eli-explore-lab | "Some kind of lab. Rush is going to lose his mind when he sees this." | Finding lab/research area | P2 | TODO |
| eli-explore-damage | "This section took some serious damage. Be careful where you step." | Damaged section | P2 | TODO |
| eli-explore-ancient-01 | "The Ancients built this thing to last. A million years and it still works." | Admiring Ancient engineering | P3 | TODO |
| eli-explore-ancient-02 | "I keep forgetting — nobody ever lived here. The ship just... flew itself." | Reflecting on ship history | P3 | TODO |
| eli-knowledge-01 | "I'm starting to understand these symbols. It says... power conduit." | Knowledge tier increase | P2 | TODO |
| eli-knowledge-02 | "I can actually read this now. It's a maintenance log from... wow, old." | Reading previously unreadable data | P2 | TODO |
| eli-map-update | "The Kino map just updated. New section unlocked." | Map discovery | P2 | TODO |

### 1.2 Player Hints (Tutorial / Guidance)

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-hint-interact | "I should take a closer look at that console." | Near unactivated interactable | P1 | TODO |
| eli-hint-repair | "This conduit looks damaged. Might be able to fix it with the wrench." | Near repairable object | P1 | TODO |
| eli-hint-kino | "I should send a Kino ahead to scout before I go in there." | Before dangerous area | P1 | TODO |
| eli-hint-gate | "The gate's in this direction. Better not wander too far." | Player going wrong way on planet | P1 | TODO |
| eli-hint-timer | "Running out of time. Need to head back to the gate." | Timer at 25% remaining | P1 | TODO |
| eli-hint-resource | "Water supply is critical. I need to find some on the next planet run." | Resource critically low | P1 | TODO |
| eli-hint-door-power | "This door won't open without power to the section." | Trying unpowered door | P1 | TODO |
| eli-hint-door-sealed | "It's sealed from the other side. Need to find another way around." | Trying sealed door | P1 | TODO |
| eli-hint-talk | "I should talk to Rush about this. He might know what it means." | After finding Ancient data | P2 | TODO |
| eli-hint-talk-young | "Colonel Young probably wants a report on what I found." | After major discovery | P2 | TODO |
| eli-hint-health | "I should find TJ. This doesn't feel great." | Low health | P2 | TODO |
| eli-hint-oxygen | "Air's getting thin. I need to get to a pressurized section." | Low oxygen area | P1 | TODO |
| eli-hint-kino-remote | "Let me check the Kino Remote. Should be able to get a reading." | Reminder to use Kino | P2 | TODO |
| eli-hint-save-supplies | "I should grab whatever I can carry. We need everything." | Near uncollected resources | P2 | TODO |
| eli-hint-gate-return | "Destiny's going to jump soon. I need to get back to the gate." | FTL timer warning | P1 | TODO |

### 1.3 Danger / Warning

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-danger-01 | "Okay, we should probably not be here right now." | Entering hazard zone | P1 | DONE |
| eli-danger-02 | "That... does not sound good. That sounds really bad actually." | Ship system failure | P1 | DONE |
| eli-danger-03 | "We need to go. Like, right now. Seriously." | Imminent danger | P1 | DONE |
| eli-danger-04 | "The power just dropped. We're on backup systems." | Power failure event | P1 | DONE |
| eli-creature-01 | "Something's moving out there. I definitely saw something." | Hostile wildlife detected | P1 | DONE |
| eli-flee-01 | "Run! Go go go!" | Combat/chase trigger | P1 | DONE |
| eli-safe-01 | "Okay, I think we lost it. For now." | Leaving danger zone | P1 | DONE |
| eli-ship-shake | "Whoa! Did you feel that? The whole ship just shook." | Ship impact/turbulence | P1 | DONE |
| eli-danger-hull | "Hull breach! Get out of this section!" | Hull breach event | P2 | TODO |
| eli-danger-atmosphere | "The air is venting. Seal the door, seal the door!" | Decompression event | P2 | TODO |
| eli-danger-toxic | "Don't breathe this in. The atmosphere here is toxic." | Toxic planet area | P2 | TODO |
| eli-danger-radiation | "Radiation levels are spiking. We can't stay here long." | Radiation hazard | P3 | TODO |
| eli-danger-creature-02 | "What IS that thing? It doesn't look friendly." | First alien wildlife encounter | P2 | TODO |
| eli-danger-creature-flee | "It's coming this way. Back to the gate, now!" | Hostile pursuit | P2 | TODO |

### 1.4 Stargate / Planetary Runs

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-gate-01 | "The gate's dialing! Everyone get ready." | Gate activation | P1 | DONE |
| eli-gate-02 | "We've got a lock! Wormhole established." | Wormhole established | P1 | DONE |
| eli-gate-03 | "Kino's through. Atmosphere is breathable. We're good to go." | Kino scout report | P1 | DONE |
| eli-planet-01 | "Okay, this planet is... actually kind of beautiful." | Arriving on temperate/nice planet | P1 | DONE |
| eli-planet-02 | "I'm picking up some interesting readings over there." | Detecting POI on planet | P1 | DONE |
| eli-ftl-drop | "Destiny just dropped out of FTL. Where are we this time?" | FTL drop event | P1 | DONE |
| eli-timer-01 | "Clock's ticking. We need to get back to the gate." | Timer at 50% | P1 | DONE |
| eli-timer-02 | "Destiny's about to jump to FTL. Move it!" | Timer at 10% | P1 | DONE |
| eli-retreat | "That's our cue to leave. Back to the gate!" | Timer urgent | P1 | DONE |
| eli-planet-hostile | "This place is not welcoming. Let's get what we need fast." | Hostile environment planet | P2 | TODO |
| eli-planet-desert | "It's like a furnace out here. We need to stay hydrated." | Desert planet arrival | P2 | TODO |
| eli-planet-ice | "Freezing. Absolutely freezing. Why is it always extremes?" | Ice planet arrival | P2 | TODO |
| eli-planet-jungle | "Dense vegetation everywhere. Can't see more than ten feet." | Jungle planet arrival | P2 | TODO |
| eli-planet-volcanic | "Active geothermal. Ground's not stable — watch your step." | Volcanic planet arrival | P2 | TODO |
| eli-planet-ruins | "Ancient ruins! These structures predate anything we've seen." | Ruins planet arrival | P2 | TODO |
| eli-gate-closing | "Gate's losing power. We need to go through NOW." | Gate shutdown imminent | P1 | TODO |
| eli-gate-noreturn | "We're cut off. The gate shut down." | Stranded on planet | P2 | TODO |
| eli-planet-scan | "Kino's picking up mineral deposits to the northeast." | Resource scan result | P2 | TODO |
| eli-planet-alien-tech | "That's not natural. Someone built this." | Discovering alien structure | P2 | TODO |
| eli-return-relief | "Made it. Back on Destiny. That was too close." | Safe return from planet | P2 | TODO |

### 1.5 Ship State / Systems

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-ship-flicker | "Lights are flickering. That's... never a good sign." | Power fluctuation | P1 | DONE |
| eli-ship-sound | "Can you hear that? The ship sounds different in this section." | Ambient audio anomaly | P1 | DONE |
| eli-ship-air | "Air quality's dropping in here. We should seal this section." | Atmosphere warning | P1 | DONE |
| eli-repair-01 | "Let me take a look at this. Should be able to fix it." | Starting repair | P1 | DONE |
| eli-repair-02 | "Almost got it. Just need to reroute the power conduit." | Mid-repair | P1 | DONE |
| eli-repair-03 | "Done! Power should be coming back online now." | Repair complete | P1 | DONE |
| eli-ship-hum-change | "The engine pitch just changed. Destiny's recalculating something." | FTL course change | P3 | TODO |
| eli-ship-power-low | "Power reserves are way down. We need to conserve." | Low power state | P2 | TODO |
| eli-ship-power-restored | "Lights coming back. That's more like it." | Power restored | P2 | TODO |
| eli-ship-systems-online | "Life support is back. We can breathe easy. Literally." | Life support restored | P2 | TODO |

### 1.6 Kino Remote / Tech

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-kino-01 | "Let me pull up the Kino. Should be able to scout ahead." | Deploying Kino | P1 | DONE |
| eli-kino-02 | "The Kino's showing something weird in the next corridor." | Kino finds anomaly | P1 | DONE |
| eli-kino-low | "The Kino's battery is low. Bringing it back." | Kino low battery | P2 | DONE |
| eli-kino-lost | "Lost the Kino signal. Something's interfering." | Kino destroyed/lost | P2 | TODO |
| eli-kino-deploy | "Sending a Kino through first. I'm not stupid." | Pre-gate Kino deploy | P2 | TODO |

### 1.7 Resource Collection

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-resource-water | "Score! Fresh water source. Filling containers now." | Water found | P1 | DONE |
| eli-resource-minerals | "Found some minerals that might be useful. Grabbing samples." | Minerals found | P1 | DONE |
| eli-resource-food | "There's some kind of edible plant life here. Beats what we have on the ship." | Food found | P1 | DONE |
| eli-resource-parts | "Ship parts. This is exactly what Brody needs for repairs." | Ship parts found | P2 | TODO |
| eli-resource-ancient-data | "An Ancient database fragment. Rush will want to see this." | Ancient data found | P2 | TODO |
| eli-resource-medicine | "Medical supplies! TJ's been asking for these." | Medicine found | P2 | TODO |
| eli-resource-lime | "Lime deposits. We can use this to scrub CO2 from the air." | Lime found | P1 | TODO |
| eli-resource-full | "Can't carry any more. Inventory's full." | Inventory full | P1 | TODO |

### 1.8 Idle / Ambient

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-idle-01 | "You know, for a billion-year-old ship, this place isn't that bad." | Random idle | P1 | DONE |
| eli-idle-02 | "I wonder if the Ancients had a cafeteria or something." | Random idle | P1 | DONE |
| eli-idle-03 | "Still can't believe I'm actually on an Ancient spaceship. In another galaxy." | Random idle | P1 | DONE |
| eli-idle-miss-home | "I wonder what my mom is doing right now." | Random idle (emotional) | P3 | TODO |
| eli-idle-games | "I'd kill for a game console right now. Just saying." | Random idle (humor) | P3 | TODO |
| eli-idle-math | "If my calculations are right, we're about... really far from Earth." | Random idle (nerdy) | P3 | TODO |
| eli-idle-food | "What I wouldn't give for a real pizza. Not alien plant mush." | Random idle (food) | P3 | TODO |
| eli-idle-destiny | "The ship's been out here for millions of years. Alone. Kind of sad, really." | Random idle (reflective) | P3 | TODO |
| eli-idle-ancients | "The Ancients were geniuses. Flawed, but geniuses." | Random idle (lore) | P3 | TODO |
| eli-idle-video-log | "I should record another Kino diary. For posterity. Or something." | Random idle (meta) | P3 | TODO |

### 1.9 Conversational Starters / NPC Seeking

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| eli-find-rush | "I need to find Rush. He'll know what to do with this." | After finding tech/data | P1 | TODO |
| eli-find-young | "Where's Colonel Young? He needs to hear about this." | After important discovery | P1 | TODO |
| eli-find-tj | "I should find TJ. Someone's going to need medical attention." | After injury/hazard | P2 | TODO |
| eli-find-brody | "Brody could probably fix this. Where is he?" | Complex repair needed | P2 | TODO |
| eli-find-chloe | "I wonder where Chloe is. Should check on her." | Player-initiated (relationship) | P3 | TODO |
| eli-where-am-i | "Where am I? This section doesn't match the schematics." | Player lost/off-map | P2 | TODO |
| eli-where-gate | "Which way to the gate room? I always get turned around in here." | Player navigating ship | P2 | TODO |
| eli-need-help | "I can't do this alone. I need to get some backup." | Before difficult task | P2 | TODO |
| eli-check-in | "How is everyone doing? Feels like we haven't talked in a while." | Social prompt idle | P3 | TODO |

---

## 2. SHIP AI (DESTINY) — Automated Announcements

The ship's AI speaks in formal, clipped English. No personality — pure information. These are PA-system style announcements heard ship-wide (non-positional).

### 2.1 Emergency / Warning

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| ship-warning-hull-breach | "Warning. Hull breach detected in section seven. Sealing bulkheads." | Hull breach event | P1 | DONE |
| ship-warning-power-critical | "Power reserves critical. Non-essential systems shutting down." | Power < 10% | P1 | DONE |
| ship-warning-life-support | "Life support systems offline in sections three through five." | Life support failure | P1 | DONE |
| ship-emergency-recall | "Emergency. All personnel return to the ship immediately." | Emergency recall | P1 | DONE |
| ship-lockdown | "Section locked down. Access restricted." | Section lockdown | P1 | DONE |
| ship-shield-damage | "Shield integrity compromised. Recommend immediate repair." | Shield damage | P1 | DONE |
| ship-warning-radiation | "Elevated radiation levels in forward sections. Avoid prolonged exposure." | Radiation hazard | P2 | TODO |
| ship-warning-fire | "Fire suppression activated in section twelve." | Fire event | P2 | TODO |
| ship-warning-intruder | "Unauthorized access detected. Security alert." | Intruder event | P3 | TODO |

### 2.2 FTL / Navigation

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| ship-ftl-countdown | "FTL jump sequence initiated. Countdown in progress." | FTL countdown start | P1 | DONE |
| ship-ftl-exit | "Dropping out of FTL. Stellar coordinates acquired." | FTL drop | P1 | DONE |
| ship-nav-update | "Navigation update. New destination plotted." | Course change | P2 | DONE |
| ship-ftl-imminent | "FTL jump in thirty seconds. Secure all sections." | 30s to FTL | P1 | TODO |
| ship-ftl-five-min | "FTL jump in five minutes. Gate window closing." | 5 min to FTL | P1 | TODO |
| ship-ftl-one-min | "FTL jump in one minute. Return to ship immediately." | 1 min to FTL | P1 | TODO |

### 2.3 Stargate / Planet

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| ship-gate-incoming | "Stargate activation detected. Incoming wormhole." | Incoming wormhole | P1 | DONE |
| ship-gate-ready | "Gate address locked. Ready for activation." | Gate address locked | P1 | DONE |
| ship-gate-timer | "Gate connection will terminate in five minutes." | Gate timer warning | P1 | DONE |
| ship-gate-unstable | "Wormhole connection unstable. Gate will shut down in sixty seconds." | Gate losing power | P1 | DONE |
| ship-planet-safe | "Atmosphere breathable. Gravity within acceptable parameters." | Safe planet scan | P1 | DONE |
| ship-planet-hostile | "Caution. Atmospheric conditions are hostile. Environmental suit recommended." | Hostile planet scan | P1 | DONE |
| ship-life-signs | "Unknown life signs detected on the planet surface." | Life detected | P1 | DONE |
| ship-hostile-env | "Sensors detect hostile environment. Proceed with caution." | Dangerous planet | P1 | DONE |
| ship-gate-two-min | "Gate connection will terminate in two minutes." | 2 min gate timer | P1 | TODO |
| ship-gate-one-min | "Gate connection will terminate in one minute." | 1 min gate timer | P1 | TODO |
| ship-gate-thirty-sec | "Gate connection will terminate in thirty seconds." | 30s gate timer | P1 | TODO |
| ship-gate-closed | "Wormhole disengaged. Gate offline." | Gate shutdown | P1 | TODO |
| ship-planet-resources | "Preliminary scan indicates mineral deposits in the survey area." | Resource scan | P2 | TODO |

### 2.4 System Status

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| ship-power-restored | "Power restored to section. Systems coming online." | Power restored | P1 | DONE |
| ship-repair-complete | "Repair complete. Section restored to operational status." | Repair done | P1 | DONE |
| ship-resource-low | "Resource supply critically low. Recommend immediate resupply." | Resource critical | P1 | DONE |
| ship-scan-clear | "Scanning complete. No threats detected." | Scan complete | P2 | DONE |
| ship-air-ok | "Oxygen levels optimal. Air filtration operational." | Air restored | P2 | DONE |
| ship-systems-nominal | "All systems nominal." | Ship healthy | P2 | TODO |
| ship-alert-incoming | "Alert. Incoming." | Generic alert | P2 | TODO |
| ship-welcome | "Welcome aboard." | Game start/load | P2 | TODO |
| ship-water-low | "Water reserves at fifteen percent. Resupply required." | Water low | P1 | TODO |
| ship-food-low | "Food stores depleted. Recommend planetary resupply." | Food low | P1 | TODO |
| ship-power-restored-section | "Power restored to section. Lighting and life support active." | Section power on | P2 | TODO |

---

## 3. COLONEL YOUNG — Military Commander

Authoritative, measured, controlled. Gives orders. Rarely shows emotion. When he does, it hits hard.

### 3.1 Orders / Command

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| young-mission-brief | "Listen up. We've got limited time on this planet. Stay focused, get what we need, and get back." | Pre-planet mission | P1 | DONE |
| young-order-retreat | "That's an order. Fall back to the gate now." | Retreat order | P1 | DONE |
| young-order-secure | "Greer, take your team and secure the perimeter." | Order to secure | P1 | DONE |
| young-gate-safety | "Nobody goes through that gate alone. Take someone with you." | Gate safety | P1 | DONE |
| young-priorities | "We need supplies. Water is the priority. Everything else is secondary." | Resource priority | P1 | DONE |
| young-order-hold | "Hold position. Nobody moves until I say so." | Hold order | P2 | TODO |
| young-order-recon | "Scott, take a team and check out the perimeter. Report back." | Recon order | P2 | TODO |
| young-order-evac | "All teams, pull back to the gate. We're leaving." | Evacuation | P1 | TODO |
| young-order-eli | "Eli, I need you on this. You're the only one who can figure it out." | Tasking Eli | P2 | TODO |

### 3.2 Status / Assessment

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| young-status-request | "Status report. What are we dealing with?" | Requesting update | P1 | DONE |
| young-time-check | "How much time do we have before the gate shuts down?" | Timer check | P1 | DONE |
| young-encourage | "Good work. Let's keep it moving." | Positive feedback | P1 | DONE |
| young-hurry | "We don't have time for this. Keep moving." | Urging speed | P1 | DONE |
| young-suspicious | "I don't like this. Something doesn't feel right." | Ambush setup | P1 | DONE |
| young-caution | "Everyone stay sharp. We don't know what's down there." | Entering unknown | P1 | DONE |
| young-assess-damage | "How bad is it? Can we fix it?" | Damage assessment | P2 | TODO |
| young-assess-supplies | "What did we bring back? Is it enough?" | Post-mission debrief | P2 | TODO |

### 3.3 Ambient / Bark

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| young-bark-tired | "Get some rest, people. Tomorrow's going to be a long day." | Low morale | P3 | TODO |
| young-bark-concern | "How are you holding up, Eli?" | Proximity bark | P2 | TODO |
| young-bark-decision | "I've made my decision. I don't need a committee." | Post-crew-conflict | P3 | TODO |
| young-bark-responsibility | "Everyone on this ship is my responsibility. All of them." | Reflective moment | P3 | TODO |
| young-bark-rush-frustration | "Rush is keeping something from us. I can feel it." | Rush distrust | P3 | TODO |

---

## 4. DR. RUSH — Brilliant Scientist

Intense, driven, often condescending. Speaks in complex sentences. Obsessed with the ship's mission. Manipulative but sometimes genuinely in awe.

### 4.1 Discovery / Science

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| rush-discovery-01 | "Fascinating. The power signature in this section is unlike anything I've seen before." | New tech found | P1 | DONE |
| rush-console-01 | "I need more time with this console. The data here could be invaluable." | At console | P1 | DONE |
| rush-database-01 | "Incredible. This system appears to be an Ancient database. Do not shut it down." | Database found | P1 | DONE |
| rush-power-readings | "The power readings in this section are off the charts." | High energy area | P1 | DONE |
| rush-passionate | "Don't you understand? This ship is the greatest discovery in human history!" | Passionate moment | P2 | DONE |
| rush-analyze | "Give me a moment. The data patterns here are... complex." | Analyzing data | P2 | TODO |
| rush-eureka | "Of course! The power matrix is a fibonacci sequence. Brilliant." | Breakthrough | P2 | TODO |
| rush-disappointed | "Another dead end. The Ancients encrypted everything." | Failed attempt | P2 | TODO |
| rush-ancient-respect | "Say what you will about the Ancients, they were meticulous engineers." | Admiring Ancient work | P3 | TODO |

### 4.2 Conflict / Manipulation

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| rush-warning-01 | "Don't touch that! We have no idea what that system does." | Player touching unknown tech | P1 | DONE |
| rush-ship-trust | "The ship chose this course for a reason. We need to trust it." | Defending Destiny's actions | P1 | DONE |
| rush-ship-knows | "I told you, the ship knows what it's doing. It's been doing this for millions of years." | Ship AI trust | P1 | DONE |
| rush-busy | "Leave me alone. I'm close to decrypting this database." | Dismissing interruption | P2 | DONE |
| rush-power-01 | "We're losing power to this section. We need to reroute immediately." | Power crisis | P1 | DONE |
| rush-timer-01 | "If my calculations are correct, and they usually are, we have approximately thirty minutes." | Timer estimate | P1 | DONE |
| rush-condescend | "I wouldn't expect you to understand. It's quite technical." | Being dismissive | P3 | TODO |
| rush-urgent | "This is more important than any of you realize." | Urgent research | P2 | TODO |
| rush-secret | "There's something I need to show you. Just you." | Private conversation hook | P3 | TODO |
| rush-young-conflict | "Young doesn't understand. He never will." | Anti-Young bark | P3 | TODO |

### 4.3 Ambient / Bark

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| rush-bark-muttering | "The ratio should be... no, that can't be right..." | Working alone | P3 | TODO |
| rush-bark-eli | "Eli. Good. I could use a second opinion." | Eli proximity | P2 | TODO |
| rush-bark-sleep | "Sleep is a luxury I can't afford right now." | Low morale / tired | P3 | TODO |
| rush-bark-mission | "We haven't even scratched the surface of what this ship can tell us." | Ship exploration | P3 | TODO |

---

## 5. LT. SCOTT — Field Team Leader

Reliable, brave, earnest. Young officer who takes his duties seriously. Often leads off-world teams.

### 5.1 Field Operations

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| scott-move-out | "Alright, let's move out. Stay tight." | Team movement | P1 | TODO |
| scott-point | "I'll take point. Stay behind me." | Leading team | P1 | TODO |
| scott-scout | "Let me scout ahead. Give me two minutes." | Pre-exploration | P2 | TODO |
| scott-clear | "Clear. Move up." | Area cleared | P1 | TODO |
| scott-contact | "Contact! Two o'clock!" | Enemy spotted | P1 | TODO |
| scott-cover | "Get to cover! Now!" | Under attack | P1 | TODO |
| scott-gate-time | "We've got about ten minutes. Make them count." | Planet timer start | P2 | TODO |
| scott-regroup | "Everyone regroup on me." | Regrouping | P2 | TODO |
| scott-fallen | "Man down! We need TJ over here!" | Ally injured | P2 | TODO |
| scott-retreat | "Fall back to the gate! Go!" | Retreat | P1 | TODO |

### 5.2 Ambient / Bark

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| scott-bark-duty | "I volunteered for this mission. Whatever happens, I'm responsible." | Reflective | P3 | TODO |
| scott-bark-eli | "Hey Eli. Hanging in there?" | Eli proximity | P2 | TODO |
| scott-bark-planet-nice | "Some of these planets... makes you forget where we are." | Nice planet | P3 | TODO |
| scott-bark-ready | "I'm always ready. That's kind of the job." | Idle bark | P3 | TODO |

---

## 6. CHLOE ARMSTRONG — Senator's Daughter

Intelligent, empathetic, grows from sheltered civilian to capable crew member. Close to Eli early on.

### 6.1 Support / Concern

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| chloe-caution-01 | "Be careful in there. We don't know what's on the other side." | Before exploration | P1 | DONE |
| chloe-concern-01 | "Is everyone okay? Anyone hurt?" | Post-crisis | P1 | DONE |
| chloe-uneasy-01 | "We should keep moving. I have a bad feeling about this place." | Uneasy environment | P1 | DONE |
| chloe-water-clean | "The water here tests clean. We should fill up." | Water found | P1 | DONE |
| chloe-air-concern | "Something's not right. The air feels different here." | Atmosphere issue | P1 | DONE |
| chloe-kino-request | "Eli, can you get a reading on this with the Kino?" | Requesting Kino help | P1 | DONE |
| chloe-encourage-eli | "You can do this, Eli. You always figure it out." | Encouraging Eli | P2 | TODO |
| chloe-scared | "I'm trying not to be scared. Not really working." | Honest fear | P3 | TODO |
| chloe-thanks | "Thank you. For keeping us safe." | Post-rescue | P3 | TODO |

### 6.2 Growth (Season 2-3)

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| chloe-capable | "I can handle this. Just tell me what to do." | Volunteering | P2 | TODO |
| chloe-translate | "I think I can translate some of this. The patterns are familiar." | Ancient text (S2+) | P2 | TODO |
| chloe-fight-back | "We're not running. Not this time." | Standing ground | P3 | TODO |
| chloe-strategy | "There might be another way around. Through the lower decks." | Tactical suggestion | P2 | TODO |

---

## 7. TJ JOHANSEN — Medic

Composed under pressure. Professional but caring. The crew's medical lifeline.

### 7.1 Medical

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| tj-medical-01 | "Hold still. Let me take a look at that." | Treating injury | P1 | DONE |
| tj-medical-02 | "You'll be fine. Just take it easy for a bit." | Post-treatment | P1 | DONE |
| tj-medical-03 | "We're running low on medical supplies. Be careful out there." | Low supplies warning | P1 | DONE |
| tj-concussion | "Don't move. I need to check for a concussion." | Head injury | P1 | DONE |
| tj-status-ok | "Everyone's accounted for. Minor injuries only." | Post-crisis status | P1 | DONE |
| tj-triage | "Who's hurt worst? Bring them to me first." | Mass casualty | P2 | TODO |
| tj-medicine-planet | "If we find any plant life, I should analyze it. Could be medicinal." | Planet mission | P2 | TODO |
| tj-stabilize | "I've stabilized them, but they need proper rest." | Serious injury | P2 | TODO |
| tj-cant-help | "I've done everything I can. The rest is up to them." | Beyond help | P3 | TODO |

---

## 8. SGT. GREER — Soldier

Fiercely loyal, intense, always ready for a fight. Terse and direct.

### 8.1 Combat / Security

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| greer-combat-01 | "Contact! We've got hostiles!" | Enemies detected | P1 | DONE |
| greer-protect-01 | "Stay behind me. I'll take point." | Protecting team | P1 | DONE |
| greer-clear-01 | "Area clear. Moving up." | Area secured | P1 | DONE |
| greer-weapons-hot | "Weapons hot! Stay behind cover!" | Combat start | P1 | DONE |
| greer-cover | "I've got your six. Move up." | Covering fire | P1 | DONE |
| greer-surprise | "What the hell was that?" | Unexpected event | P1 | DONE |
| greer-perimeter-clear | "Perimeter secure. No contacts." | Perimeter check | P1 | DONE |
| greer-threat | "I see movement. Stay low." | Potential threat | P2 | TODO |
| greer-defend | "Nobody gets past this door. Period." | Defending position | P2 | TODO |
| greer-ready | "Say the word, Colonel. I'm ready." | Awaiting orders | P2 | TODO |
| greer-hunt | "Whatever that thing is, I'll find it." | Tracking hostile | P3 | TODO |

### 8.2 Ambient / Bark

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| greer-bark-trust | "I don't trust Rush. Never have, never will." | Rush proximity bark | P3 | TODO |
| greer-bark-loyalty | "Colonel Young gave the order. That's good enough for me." | Young loyalty | P3 | TODO |
| greer-bark-eli | "You're alright, Eli. Just... stay behind me." | Eli proximity | P2 | TODO |
| greer-bark-planet | "I've seen worse terrain. But not by much." | Planet observation | P3 | TODO |

---

## 9. CAMILE WRAY — IOA Civilian Representative

Political, diplomatic, fights for civilian rights. Measured speech, always strategic.

### 9.1 Political / Civilian

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| wray-civilian-concern | "The civilians are scared. They need to know what's happening." | Low morale event | P2 | TODO |
| wray-rights | "Military authority doesn't extend to personal decisions." | Civilian conflict | P3 | TODO |
| wray-negotiate | "Perhaps we can find a solution that works for everyone." | Mediation | P2 | TODO |
| wray-resource-fair | "Resources need to be distributed fairly. Not just to the military." | Resource dispute | P2 | TODO |
| wray-support-eli | "Eli, you have the support of the civilian contingent." | Supporting Eli | P3 | TODO |
| wray-report | "I'm filing a report on this. Earth needs to know what's happening." | Accountability | P3 | TODO |
| wray-compromise | "We all want to get home. That means working together." | Unity call | P2 | TODO |
| wray-angry | "This is exactly what I was afraid of. Unchecked military control." | Anti-military bark | P3 | TODO |

---

## 10. ADAM BRODY — Ship Engineer

Sarcastic, competent, pragmatic. The ship repair guy. Deadpan humor under pressure.

### 10.1 Engineering / Repair

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| brody-repair-assess | "Let me see what we're working with here." | Assessing damage | P2 | TODO |
| brody-repair-bad | "Yeah, this is pretty bad. Gonna need parts we don't have." | Major damage | P2 | TODO |
| brody-repair-doable | "I can fix this. Might take a few hours, but it's doable." | Moderate repair | P2 | TODO |
| brody-repair-done | "That should hold. For now." | Repair complete | P2 | TODO |
| brody-sarcasm-01 | "Oh great. Another system failure. What a surprise." | System failure | P2 | TODO |
| brody-sarcasm-02 | "The Ancients built it to last a million years. They just didn't plan for us." | Sarcastic observation | P3 | TODO |
| brody-parts-request | "If you find any Ancient circuit boards down there, grab them. Please." | Pre-planet request | P2 | TODO |
| brody-warning | "Don't touch that panel. The wiring behind it is completely shot." | Safety warning | P2 | TODO |
| brody-volker-banter | "Volker, I swear, if you break another conduit..." | Banter | P3 | TODO |

---

## 11. DALE VOLKER — Astrophysicist

Nervous, hypochondriac, but genuinely brilliant at his job. Comic relief but with depth.

### 11.1 Science / Navigation

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| volker-star-analysis | "Interesting. This star is more active than the sensors indicated." | Star analysis | P2 | TODO |
| volker-planet-data | "I'm getting readings on two viable planets. Maybe three." | Planet scan | P2 | TODO |
| volker-nervous | "Is it just me, or is this section way too quiet?" | Nervous observation | P2 | TODO |
| volker-complain | "My back is killing me. These Ancient chairs were not designed for humans." | Complaint | P3 | TODO |
| volker-scared | "I'm going back to the lab. It's safer there." | Retreating | P3 | TODO |
| volker-eureka | "Wait, that reading can't be right. Unless... oh. That changes everything." | Discovery | P2 | TODO |
| volker-brody-banter | "Brody, tell me that alarm isn't what I think it is." | Banter | P3 | TODO |

---

## 12. LISA PARK — Scientist

Enthusiastic, smart, optimistic. Brings energy to the science team.

### 12.1 Research / Analysis

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| park-analysis | "I'm running analysis on the samples now. Give me five minutes." | Analyzing | P2 | TODO |
| park-discovery | "This is remarkable! The molecular structure is completely novel." | Science discovery | P2 | TODO |
| park-planet-flora | "The plant life here is extraordinary. I need samples." | Planet biology | P2 | TODO |
| park-enthusiastic | "Do you realize what this means? This could change everything!" | Excited discovery | P2 | TODO |
| park-caution | "We should run more tests before anyone eats that." | Safety concern | P2 | TODO |
| park-data | "The data Rush pulled from the console — it's an Ancient star map." | Data analysis | P2 | TODO |
| park-optimist | "It's not as bad as it looks. We can work with this." | Optimistic assessment | P3 | TODO |

---

## 13. VANESSA JAMES — Military (Lt.)

Professional, composed, competent soldier. Less intense than Greer but equally capable.

### 13.1 Military Operations

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| james-ready | "Ready on your order, Colonel." | Awaiting orders | P2 | TODO |
| james-position | "I'll hold this position. Go ahead." | Holding position | P2 | TODO |
| james-report | "All clear on the south corridor." | Status report | P2 | TODO |
| james-hostile | "Hostile terrain. Recommend we keep it to a short trip." | Planet assessment | P2 | TODO |
| james-covering | "I'm covering the door. Move when you're ready." | Covering | P2 | TODO |
| james-wounded | "Just a scratch. Keep moving." | Self-injury dismissal | P3 | TODO |

---

## 14. CREW GENERIC — Multiple Speakers

Short acknowledgments and reactions usable by any background crew member.

### 14.1 Acknowledgments

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| crew-acknowledge-01 | "Copy that." | Order acknowledged | P1 | DONE |
| crew-acknowledge-02 | "Understood. On my way." | Task accepted | P1 | DONE |
| crew-roger | "Roger that." | Radio acknowledgment | P2 | TODO |
| crew-yes-sir | "Yes, sir." | Military acknowledgment | P2 | TODO |
| crew-on-it | "On it." | Quick acknowledgment | P2 | TODO |
| crew-negative | "That's a negative." | Denial | P2 | TODO |
| crew-help | "We need help over here!" | Distress call | P2 | TODO |

---

## Summary Statistics

| Character | Done | P1 TODO | P2 TODO | P3 TODO | Total |
|-----------|------|---------|---------|---------|-------|
| Eli Wallace | 28 | 15 | 22 | 12 | 77 |
| Ship AI (Destiny) | 22 | 8 | 5 | 1 | 36 |
| Colonel Young | 11 | 2 | 5 | 5 | 23 |
| Dr. Rush | 11 | 0 | 5 | 6 | 22 |
| Lt. Scott | 0 | 6 | 4 | 4 | 14 |
| Chloe Armstrong | 6 | 0 | 4 | 3 | 13 |
| TJ Johansen | 5 | 0 | 3 | 1 | 9 |
| Sgt. Greer | 7 | 0 | 3 | 4 | 14 |
| Camile Wray | 0 | 0 | 4 | 4 | 8 |
| Adam Brody | 0 | 0 | 7 | 2 | 9 |
| Dale Volker | 0 | 0 | 4 | 3 | 7 |
| Lisa Park | 0 | 0 | 5 | 2 | 7 |
| Vanessa James | 0 | 0 | 5 | 1 | 6 |
| Crew Generic | 2 | 0 | 5 | 0 | 7 |
| **TOTALS** | **92** | **31** | **81** | **48** | **252** |

---

## 15. VARRO — Lucian Alliance Defector (S2-3)

Former Lucian Alliance, now loyal to Destiny's crew. Honor-driven, conflicted about his past. A potential ally or double agent depending on player choices.

### 15.1 Loyalty / Operations

| ID | Text | Trigger | Priority | Status |
|----|------|---------|----------|--------|
| varro-help | "You know I'll help however I can." | Offering assistance | P3 | TODO |
| varro-honor | "That act has no honor to it." | Opposing unethical action | P3 | TODO |
| varro-recon | "I know how they think. Let me take point." | LA encounter | P3 | TODO |
| varro-trust | "I've earned my place here. I won't betray it." | Trust conversation | P3 | TODO |

---

## 16. EFFORT / PHYSICAL SOUNDS (Non-Verbal)

Short non-verbal sounds for physical actions. Generated with TTS using emotional/effort descriptions.

### 16.1 Eli Physical Sounds

| ID | Text (TTS prompt) | Trigger | Priority | Status |
|----|-------------------|---------|----------|--------|
| eli-grunt-effort | "Ugh!" | Heavy lifting/climbing | P1 | TODO |
| eli-grunt-impact | "Oof!" | Wall collision / fall | P1 | TODO |
| eli-pain | "Ahh!" | Taking damage | P1 | TODO |
| eli-breathing-heavy | (heavy panting) | Sprint exertion | P1 | TODO |
| eli-gasp | (sharp intake of breath) | Surprise/fear | P1 | TODO |
| eli-sigh-relief | (relieved exhale) | Post-danger | P2 | TODO |
| eli-cough | (coughing) | Smoke/bad atmosphere | P2 | TODO |
| eli-shiver | "Brrr..." | Cold environment | P2 | TODO |
| eli-muttering | "Come on, come on..." | Repair under pressure | P1 | TODO |
| eli-thinking | "Hmm..." | Examining something | P2 | TODO |

---

## 17. SYSTEM-TRIGGERED VOICE LINES (From GDD Analysis)

Lines triggered automatically by game systems, not player-initiated.

### 17.1 Timer System Triggers

| ID | Character | Text | Trigger | Priority | Status |
|----|-----------|------|---------|----------|--------|
| timer-eli-2min | Eli | "Two minutes. We've got two minutes." | 2min gate remaining | P1 | TODO |
| timer-eli-1min | Eli | "One minute! Move it, people!" | 1min gate remaining | P1 | TODO |
| timer-eli-30sec | Eli | "Thirty seconds! Go go go!" | 30sec gate remaining | P1 | TODO |
| timer-rush-crisis | Rush | "Wallace! That was supposed to be fixed by now!" | Crisis timer expiring | P2 | TODO |
| timer-young-evac | Young | "Everyone through the gate! Now! That's an order!" | Evacuation timer | P1 | TODO |

### 17.2 Resource Depletion Triggers

| ID | Character | Text | Trigger | Priority | Status |
|----|-----------|------|---------|----------|--------|
| resource-crew-thirsty | Crew | "When was the last time we had water?" | Water < 20% | P2 | TODO |
| resource-crew-hungry | Crew | "Another half-ration. Wonderful." | Food < 20% | P2 | TODO |
| resource-brody-parts | Brody | "We're out of replacement parts. Next repair is going to be creative." | Ship parts depleted | P2 | TODO |
| resource-tj-medicine | TJ | "I'm rationing the last of our antibiotics." | Medicine < 10% | P2 | TODO |
| resource-eli-lime | Eli | "CO2 scrubbers are dying. We need lime or we stop breathing." | Lime critically low | P1 | TODO |

### 17.3 Ship State Event Triggers

| ID | Character | Text | Trigger | Priority | Status |
|----|-----------|------|---------|----------|--------|
| state-rush-demand | Rush | "Eli! We're losing containment in section four!" | System failure event | P2 | TODO |
| state-young-damage | Young | "How bad is it? Can we fix it?" | Post-damage assessment | P2 | TODO |
| state-brody-assess | Brody | "The conduit's fried. We need to reroute through section six." | Engineering assessment | P2 | TODO |
| state-volker-readings | Volker | "These readings don't make sense. Unless..." | Anomalous scan | P2 | TODO |
| state-park-analysis | Park | "Running analysis now. Give me five minutes." | Science analysis | P2 | TODO |

### 17.4 Proximity Barks (Crew Near Eli)

| ID | Character | Text | Trigger Condition | Priority | Status |
|----|-----------|------|-------------------|----------|--------|
| bark-rush-respect | Rush | "Eli. Good. I could use a second opinion." | Rush nearby, high affinity | P2 | TODO |
| bark-rush-dismiss | Rush | "Not now. I'm very busy." | Rush nearby, low affinity | P2 | TODO |
| bark-young-checkin | Young | "How are you holding up, Eli?" | Young nearby, normal | P2 | TODO |
| bark-chloe-friendly | Chloe | "Hey Eli. Any luck figuring out those symbols?" | Chloe nearby, high affinity | P2 | TODO |
| bark-greer-respect | Greer | "You're alright, Eli. Just... stay behind me." | Greer nearby | P2 | TODO |
| bark-scott-casual | Scott | "Hey Eli. Hanging in there?" | Scott nearby | P2 | TODO |
| bark-tj-concern | TJ | "You look tired, Eli. Get some rest when you can." | TJ nearby, Eli injured | P2 | TODO |
| bark-brody-sarcasm | Brody | "Oh good, Eli's here. Everything's going to be fine now." | Brody nearby (sarcastic affection) | P3 | TODO |
| bark-volker-nervous | Volker | "Is it just me, or is this section way too quiet?" | Volker nearby, dark section | P3 | TODO |
| bark-park-excited | Park | "Eli! Come look at what I found in the lab!" | Park nearby, discovery | P3 | TODO |
| bark-wray-diplomatic | Wray | "Eli, a moment? The civilians have concerns." | Wray nearby, low morale | P2 | TODO |

### 17.5 S3-Specific Scenario Lines

| ID | Character | Text | Trigger | Priority | Status |
|----|-----------|------|---------|----------|--------|
| eli-center-universe | Eli | "We're at the center of the Universe. Do you understand what that means?" | Approaching galactic core | P3 | TODO |
| eli-first-contact | Eli | "I hate to sound all sci-fi, but they're hailing us." | Alien ship contact | P3 | TODO |
| eli-alien-peaceful | Eli | "I don't think they want to fight. They're trying to communicate." | First contact attempt | P3 | TODO |
| rush-ancient-language | Rush | "I recognize this. It's Ancient. The real thing." | Finding Ancient text | P3 | TODO |
| chloe-trance | Chloe | "The symbols... I know what they mean. I don't know how, but I know." | Chloe alien ability | P3 | TODO |
| park-computer | Park | "Computer, stop. Replay last fifteen seconds." | Park voice interface | P3 | TODO |
| eli-eloi-faith | Eli | "Something out there is watching over us. I believe that now." | Post-rescue reflection | P3 | TODO |

---

## Summary Statistics (Updated)

| Character | Done | P1 TODO | P2 TODO | P3 TODO | Total |
|-----------|------|---------|---------|---------|-------|
| Eli Wallace | 28 | 25 | 24 | 16 | 93 |
| Ship AI (Destiny) | 22 | 12 | 7 | 1 | 42 |
| Colonel Young | 11 | 3 | 7 | 5 | 26 |
| Dr. Rush | 11 | 0 | 8 | 8 | 27 |
| Lt. Scott | 0 | 6 | 5 | 4 | 15 |
| Chloe Armstrong | 6 | 0 | 5 | 4 | 15 |
| TJ Johansen | 5 | 0 | 5 | 1 | 11 |
| Sgt. Greer | 7 | 0 | 4 | 5 | 16 |
| Camile Wray | 0 | 0 | 5 | 4 | 9 |
| Adam Brody | 0 | 0 | 8 | 3 | 11 |
| Dale Volker | 0 | 0 | 5 | 3 | 8 |
| Lisa Park | 0 | 0 | 6 | 3 | 9 |
| Vanessa James | 0 | 0 | 5 | 1 | 6 |
| Varro | 0 | 0 | 0 | 4 | 4 |
| Crew Generic | 2 | 0 | 7 | 0 | 9 |
| Eli (non-verbal) | 0 | 5 | 5 | 0 | 10 |
| **TOTALS** | **92** | **51** | **111** | **62** | **316** |

### Generation Priority Plan

**P1 (MVP)**: 51 lines remaining — critical gameplay triggers, effort sounds, timer warnings
**P2 (Vertical Slice)**: 111 lines — new characters (Scott, Wray, Brody, Volker, Park, James), expanded barks, system triggers
**P3 (Full Game)**: 62 lines — S3 scenarios, personality depth, ambient flavor, alien encounters
**TOTAL REMAINING**: 224 lines to generate
**Estimated character cost**: ~12,000 characters (~31% of monthly TTS budget)

### Next Generation Session Priorities

1. **P1 Eli effort sounds** — grunts, breathing, gasps (critical for player character feel)
2. **P1 Timer voice lines** — countdown warnings across characters
3. **P1 Eli hints** — player guidance voice lines
4. **P2 Scott full voice** — 15 lines (field team leader, used in every planet run)
5. **P2 Proximity barks** — 11 character-specific ambient lines
6. **P2 Brody/Volker/Park** — science team voices
7. **P3 S3 scenarios** — alien contact, center of universe, Chloe abilities
