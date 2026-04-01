# Ship Atmosphere & Lighting

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-04-01
> **Implements Pillar**: Pillar 1 (The Ship IS the World)

## Overview

The Ship Atmosphere & Lighting system translates Destiny's physical state into
visual atmosphere — making the data in the Ship State system *visible* and
*feelable*. When power is low in a corridor, the lights dim. When life support
is failing, emergency red strips activate. When a section is fully powered and
repaired, Ancient tech glows with warm cyan light and the air feels clear. The
player never needs to check the Kino Remote to know a section's condition —
they can see it and feel it.

The system uses **dynamic lighting** driven by Ship State data (per-section power
level, atmosphere, system conditions) combined with **baked atmospheric presets**
(fog density, particle effects, ambient color) that blend between authored states.
Each section has an `AtmosphereConfig` that defines how ship state maps to visual
parameters. Light color, intensity, and fog all respond to real-time state changes,
while heavier effects (volumetric particles, detailed ambient occlusion) use
pre-authored presets that blend smoothly as conditions change.

## Player Fantasy

The Ship Atmosphere & Lighting system serves the fantasy of **living inside a
dying ship that you're slowly bringing back to life.**

When you first arrive on Destiny, the corridors are dark, oppressive, and barely
lit by emergency strips. The air feels thin — you can almost see dust particles
floating in the dim light. Repairing a power conduit doesn't just change a number
on the Kino Remote — the lights physically brighten, the Ancient patterns on the
walls begin to glow, the fog thins, and the corridor transforms from hostile to
habitable. You *see* your progress in the world around you.

The flip side is equally powerful. When power fails, you watch the lights die
section by section, the Ancient glow fading as emergency red takes over. When
atmosphere drains from a compromised section, the fog thickens, frost creeps
across surfaces, and the silence of vacuum replaces the hum of machinery. The
ship's state is never abstract — it's the air you breathe and the light you
see by.

This serves **Pillar 1 (The Ship IS the World)**: Destiny feels alive because
every system change is reflected in the environment around you. The atmosphere
IS the ship's vital signs.

## Detailed Design

### Core Rules

1. **Per-section atmosphere**: Each section on Destiny has an `AtmosphereConfig`:
   - `sectionId`: reference to Ship State section
   - `baseLightColor`: THREE.Color (the section's "signature" light tone when powered)
   - `baseFogColor`: THREE.Color
   - `baseFogDensity`: float (0-1)
   - `ambientParticles`: enum — `None`, `Dust`, `Steam`, `Sparks`, `Frost`
   - `ancientGlowElements`: array of mesh IDs that glow when powered
   - Section config is authored per-scene in the ggez World Editor

2. **State-driven lighting**: Each section's lights respond to Ship State in
   real-time:
   - **Light intensity** = `section.power_level * BASE_LIGHT_INTENSITY`
   - **Light color** blends from `emergencyColor` (red) at low power to
     `baseLightColor` at full power
   - **Ancient tech glow** activates above `ANCIENT_GLOW_THRESHOLD` power level
     (default 0.6) — emissive materials on designated meshes fade in
   - All transitions use smooth lerp over `LIGHT_TRANSITION_SPEED` seconds

3. **Atmosphere visual states**: Sections blend between these preset states based
   on Ship State conditions:

   | Condition | Fog | Light | Particles | Ancient Glow |
   |-----------|-----|-------|-----------|-------------|
   | **Fully powered** (power > 0.8) | Minimal, clear | Bright, base color | None or subtle dust | Full glow |
   | **Low power** (0.3-0.8) | Light haze | Dim, warmer tone | Dust motes | Partial glow |
   | **Emergency** (power < 0.3) | Moderate | Emergency red strips only | Sparks near damaged subsystems | Off |
   | **Unpowered** (power = 0) | Dense darkness | No lights (phone light only) | Heavy dust | Off |
   | **Compromised** (hull breach) | Frost/vacuum fog | Emergency red flashing | Frost particles, venting gas | Off |
   | **Life support failing** | Thickening haze (CO2) | Amber warning tint | Steam from vents | Dimming |

4. **Emergency lighting**: When a section's power drops below `EMERGENCY_POWER_THRESHOLD`,
   overhead lights cut out and emergency strips along the floor activate. These are
   always-on (battery-powered) and cast a dim red glow. This is the "Destiny is
   failing" look from SGU Season 1.

5. **Ancient tech glow**: Destiny's walls, consoles, and architectural elements
   have embedded Ancient patterns that glow cyan when powered. This glow is a
   key visual signature — when you repair a section, watching the Ancient
   patterns illuminate is one of the most satisfying visual moments in the game.
   Glow intensity scales with `section.power_level` above the threshold.

6. **Phone light integration**: In unpowered sections, the Player Controller's
   auto phone light activates. The Atmosphere system ensures the section is dark
   enough to trigger this (ambient light below `PHONE_LIGHT_TRIGGER_THRESHOLD`).

7. **Transition smoothing**: All visual changes lerp over time — no instant
   snapping. Power restoration brightens lights over 2-3 seconds. Emergency
   lighting activates with a brief flicker. Ancient glow fades in over 1 second.
   This makes the ship feel like a real electrical system, not a light switch.

8. **Performance budget**: Atmosphere effects must stay within 4ms of the 16.6ms
   frame budget. Dynamic lights are the most expensive — limit to
   `MAX_DYNAMIC_LIGHTS_PER_SECTION` active simultaneously. Use emissive materials
   over point lights for Ancient glow (learned from prototype).

### States and Transitions

Section atmosphere doesn't have discrete states — it's a continuous blend driven
by Ship State values. However, the key thresholds that trigger visual changes are:

| Threshold Crossed | Visual Change | Transition Speed |
|-------------------|---------------|-----------------|
| Power rises above 0.8 | Full lighting, Ancient glow activates | 2s fade-in |
| Power drops below 0.3 | Emergency strips activate, overhead dims | 1s (flicker) |
| Power reaches 0 | Total darkness, phone light triggers | 0.5s (sudden) |
| Atmosphere drops below 0.5 | Haze thickens, amber tint | 3s gradual |
| Section compromised (hull breach) | Frost, vacuum fog, red flash | 0.3s (immediate) |
| Section sealed (breach repaired) | Frost fades, atmosphere rebuilds | 5s (slow recovery) |
| Subsystem repaired | Local sparks stop, area brightens | 1s |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Ship State** | Inbound (read + subscribe) | Reads: section power_level, atmosphere, structural_integrity, subsystem conditions. Subscribes to `ship:power:changed`, `ship:section:*`, `ship:subsystem:*` for real-time updates. |
| **ggez Render Pipeline** | Outbound (configure) | Sets: light colors/intensities, fog parameters, emissive material values, particle system enable/disable. |
| **Event Bus** | Inbound (subscribe) | Subscribes to `ship:*` events for reactive visual changes. |
| **Player Controller** | Outbound (context) | Provides ambient light level for phone light trigger decision. |
| **Audio & Ambience** *(undesigned)* | Parallel | Audio system reads the same Ship State data. Visual and audio should be synchronized (lights dim = hum quiets). |
| **Camera System** | Soft | Camera auto-exposure may adjust based on section brightness. |
| **Timer & Pressure** | Inbound (subscribe) | Timer warning events may trigger visual alarm effects (screen border pulse). |

## Formulas

### Light Intensity

```
section_light_intensity = section.power_level * BASE_LIGHT_INTENSITY * condition_modifier
condition_modifier = avg(subsystem.condition for light-type subsystems in section)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `section.power_level` | float | 0-1.0 | Ship State | Power reaching this section |
| `BASE_LIGHT_INTENSITY` | float | 1.0-3.0 | config | Max light brightness |
| `condition_modifier` | float | 0-1.0 | calculated | Damaged lights are dimmer even with full power |

### Light Color Blend

```
light_color = lerp(EMERGENCY_COLOR, baseLightColor, power_blend)
power_blend = smoothstep(EMERGENCY_POWER_THRESHOLD, 0.8, section.power_level)
```

### Fog Density

```
fog_density = baseFogDensity * (1 + FOG_POWER_MODIFIER * (1 - section.power_level))
                             * (1 + FOG_ATMOSPHERE_MODIFIER * (1 - section.atmosphere))
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `baseFogDensity` | float | 0-0.5 | section config | Authored base fog |
| `FOG_POWER_MODIFIER` | float | 1.0-3.0 | config | How much low power thickens fog |
| `FOG_ATMOSPHERE_MODIFIER` | float | 1.0-5.0 | config | How much low atmosphere thickens fog |

### Ancient Glow Intensity

```
glow_intensity = max(0, (section.power_level - ANCIENT_GLOW_THRESHOLD)
                        / (1.0 - ANCIENT_GLOW_THRESHOLD))
                 * ANCIENT_GLOW_MAX_EMISSIVE
```

Glow is 0 below threshold, scales linearly to max above it.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Power fluctuates rapidly** | Lights flicker convincingly. Rate-limit visual updates to avoid strobing (minimum 0.1s between intensity changes). | Rapid power changes should look like flickering, not seizure-inducing strobe. |
| **Player walks between sections with different power levels** | Visual blend at section boundaries. No hard edge — interpolate over 2-3 meters. | Seamless transitions between areas. |
| **All sections unpowered simultaneously** | Entire ship is dark except emergency strips and phone light. Emergency battery provides strips for 30 minutes (per Ship State). | Total darkness is the ultimate crisis visual. |
| **Section atmosphere at 0 (vacuum)** | No fog particles (vacuum is clear), but frost on surfaces, ice crystal particles. Sound mutes (handled by Audio system). | Vacuum has its own distinctive look. |
| **Ancient glow on a destroyed subsystem** | Destroyed subsystems don't glow regardless of power. Glow elements tied to subsystem condition — at 0%, glow is off even if section is powered. | Visual consistency: broken things look broken. |
| **Scene transition (gate room → planet)** | Atmosphere system deactivates for ship, planet has its own environment lighting (owned by Stargate & Planetary Runs scene). | Ship atmosphere is ship-only. Planets have their own visual identity. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Ship State | Hard | section.power_level, section.atmosphere, section.structural_integrity, subsystem conditions |
| Event Bus | Hard | Subscribes to ship:* for real-time visual updates |
| ggez Render Pipeline | Hard | Light, fog, material, particle system APIs |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Player Controller | Soft | Ambient light level for phone light trigger |
| Camera System | Soft | Section brightness for auto-exposure |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `BASE_LIGHT_INTENSITY` | 2.0 | 0.5-4.0 | Brighter powered sections. | Dimmer overall. More atmospheric. |
| `EMERGENCY_POWER_THRESHOLD` | 0.3 | 0.1-0.5 | Emergency lighting kicks in earlier. | Later — more time in dim-but-not-emergency. |
| `ANCIENT_GLOW_THRESHOLD` | 0.6 | 0.4-0.8 | Glow needs more power. Rarer visual reward. | Glow appears at lower power. More frequent. |
| `ANCIENT_GLOW_MAX_EMISSIVE` | 0.8 | 0.3-1.5 | Brighter Ancient glow. More visible progression. | Subtler glow. |
| `LIGHT_TRANSITION_SPEED` | 2.0s | 0.5-5.0s | Slower transitions. More cinematic. | Faster. More responsive but less atmospheric. |
| `FOG_POWER_MODIFIER` | 2.0 | 0.5-4.0 | More fog in low-power sections. | Less fog variation between power levels. |
| `FOG_ATMOSPHERE_MODIFIER` | 3.0 | 1.0-6.0 | More fog when atmosphere is low. | Less atmospheric fog. |
| `MAX_DYNAMIC_LIGHTS_PER_SECTION` | 6 | 3-10 | More lights. Better visuals, higher cost. | Fewer lights. Better performance. |
| `PHONE_LIGHT_TRIGGER_THRESHOLD` | 0.1 | 0.05-0.3 | Phone light in dimmer sections. | Only in near-total darkness. |
| `EMERGENCY_COLOR` | #ff2200 | — | Red emergency strip color. | — |

## Visual/Audio Requirements

| Ship State Change | Visual Effect | Audio Effect (for Audio system reference) | Priority |
|-------------------|--------------|------------------------------------------|----------|
| Power restored to section | Lights brighten, Ancient glow fades in, fog thins | Ship hum rises, mechanical startup sounds | High |
| Power lost (emergency) | Overhead dies, emergency red strips activate, flicker | Power-down whine, emergency alarm | High |
| Total power loss | All dark except emergency strips | Ship hum dies, eerie silence, battery beep | High |
| Atmosphere draining | Haze thickens, amber tint, condensation on surfaces | Hissing air, breathing sounds change | High |
| Section compromised | Instant frost, vacuum fog, red flash, ice particles | Decompression whoosh, silence (vacuum) | High |
| Subsystem repaired | Local area brightens, sparks stop, glow returns | Mechanical startup, satisfying hum | Medium |
| Ancient patterns illuminate | Cyan/teal glow spreads along embedded wall patterns | Subtle harmonic tone | Medium |
| Section fully restored | Full bright, clear air, full Ancient glow | Rich ambient hum, sense of warmth | High |

## UI Requirements

None — this system has no UI elements. It IS the visual presentation layer.
Ship status information is communicated entirely through environmental visuals,
not UI overlays. The Kino Remote handles explicit data display; this system
handles implicit environmental communication.

## Acceptance Criteria

- [ ] **Power-driven lighting**: Section light intensity scales with power_level. 0 power = dark. Full power = bright.
- [ ] **Emergency lighting**: Below threshold, emergency red strips activate. Above, normal lights return.
- [ ] **Light color blending**: Lights smoothly blend from emergency red to base color as power increases.
- [ ] **Ancient glow**: Designated meshes emit cyan glow above threshold. Glow scales with power. Destroyed subsystems don't glow.
- [ ] **Fog response**: Fog density increases with low power and low atmosphere. Vacuum sections have frost instead of fog.
- [ ] **Smooth transitions**: All visual changes lerp over configured speed. No instant snapping. Power fluctuations produce convincing flicker.
- [ ] **Section boundaries**: Visual blend between adjacent sections with different power levels. No hard edges.
- [ ] **Phone light trigger**: Player Controller's phone light activates when ambient light drops below threshold.
- [ ] **Compromised section visuals**: Frost, vacuum fog, red flash, ice particles when section is breached.
- [ ] **Performance**: All atmosphere effects within 4ms budget. Dynamic lights capped per section. Emissive materials used for Ancient glow (not point lights).
- [ ] **Real-time updates**: Visual changes respond to Ship State events within the transition speed. No polling — event-driven.
- [ ] **All tuning values externalized**: Thresholds, intensities, colors, speeds from config.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Should volumetric fog be used (expensive but gorgeous) or screen-space fog (cheaper but less immersive)? Depends on WebGPU performance. | Technical Director | During prototype | — |
| How do section boundaries work architecturally? Are they defined by doors, or by invisible boundary volumes? | Level Designer | Before level production | — |
| Should damaged subsystems produce persistent visual effects (sparking conduit, steaming pipe) or only momentary? | Art Director | Before production | — |
| How does Ancient glow interact with the Kino drone's light? Does the Kino illuminate Ancient patterns? | Game Designer | Before Kino Drone GDD | — |
| What's the exact color palette for each atmosphere state? Needs concept art before implementation. | Art Director | Before production | — |
| How does atmosphere rendering work on the WebGPU pipeline? Need to validate Three.js fog + dynamic lights performance at scale. | Technical Director | During prototype | Partially validated in gate room prototype (6 lights @ 100 FPS) |
