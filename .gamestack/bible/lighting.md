# Per-Region Lighting Bible

Destiny is an ancient, failing ship. Lighting tells the story of each region's function, power state, and mood before the player reads a single sign.

## Design Principles

1. **Ancient tech glows; everything else is dark metal.** The ship's walls are dark gray-blue; the accent color is what gives each region its identity. Lighting is diegetic — it comes FROM the sconces, bands, and console screens, not from invisible fill lights.
2. **Cool = functional, warm = habitable, green = life support.** Corridors and control spaces are cool blue/amber (functional, powered). Quarters are warm amber (habitable). Hydroponics is green (life). Elevator is electric cyan (transport tech).
3. **Less light = more atmosphere.** Every room has one FillLight (ceiling OmniLight, no shadow) + accent sconces. The gate room is the artisan exception with 18+ lights. Volumetric fog adds depth without extra lights.
4. **Emergency states override everything.** Red alert tints all lights + emissives + ambient. Blackout (gate close) crushes to near-dark with flashlight spots. Caution (post-crisis) is a dim amber wash.

## Per-Region Lighting Specs

### Gate Room (gate-room-template)
- **Ambient:** Color(0.46, 0.54, 0.7), energy 1.35 — cool blue-gray
- **Key Light:** DirectionalLight3D, cool blue (0.78, 0.85, 1.0), energy 1.4, shadows on
- **Ceiling Fill:** 6 OmniLights in 2x3 grid, cool blue, energy 1.5, range 15m
- **Floor Uplights:** 6 OmniLights at perimeter, cool blue (0.42, 0.58, 0.95), energy 1.6
- **Gate Uplighting:** 3 SpotLights (front + 2 sides) aimed at gate ring, cool blue
- **Door Arch:** 1 warm Spotlight (1.0, 0.78, 0.45), energy 5.5 — reads as "lit doorway"
- **Volumetric Fog:** FogVolume at gate ring — atmospheric haze where the event horizon glows
- **Ceiling Strips:** Emissive blue material (unshaded), energy 2.6 — flickers with power-up
- **Dark-open:** All lights crushed to 4%, ambient to 10%, ceiling strips to 4%; flickers back up over 0.8s

### Corridors (corridor-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2 — neutral gray
- **Accent:** Amber (1.0, 0.55, 0.18) — warm functional lighting
- **Sconces:** Emissive amber at 1.65m height + OmniLight per sconce (range 5.5m, energy 1.6)
- **Ceiling/Floor Strips:** Emissive amber at ceiling -0.45m and floor 0.20m
- **Fill Light:** Single ceiling OmniLight, warm-tinted, energy 1.1, no shadow
- **Volumetric Fog:** Global low-density (0.015) + FogVolume in long corridors for depth haze
- **Ancient Glow:** Sconce emissive pulses subtly (0.5 amplitude, 2s period) — ship "breathing"

### Control Room (control-room-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2
- **Accent:** Amber (1.0, 0.55, 0.18) — same as corridors, unified "command" palette
- **Wall Band:** Continuous emissive amber at 1.4m height around all walls
- **Central Pillar:** Floor-to-ceiling Ancient power column with emissive ring bands
- **Console Screens:** Dim blue when idle, bright tech-blue when activated (gate_console.gd)
- **Fill Light:** Ceiling OmniLight, energy 1.1
- **Ancient Glow:** Pillar ring bands pulse in sync (slow, 3s period) — power flowing

### Kino Room (kino-room-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2
- **Accent:** Warm bronze (0.85, 0.70, 0.45) — archival/museum feel
- **Pedestal Light:** OmniLight at pedestal, warm-tinted, energy 0.8
- **Fill Light:** Ceiling OmniLight, energy 1.1

### Quarters (quarters-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2
- **Accent:** Warm dim amber (0.75, 0.62, 0.50) — dim, intimate
- **Fill Light:** Ceiling OmniLight, energy 1.1

### Hydroponics (hydroponics-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2
- **Accent:** Bioluminescent green (0.30, 1.0, 0.45) — living, growing
- **Grow Lights:** Emissive green at high energy (4.0) — plant growth lamps
- **Fill Light:** Ceiling OmniLight, energy 1.1

### Elevator (elevator-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2
- **Accent:** Electric cyan (0.20, 0.85, 1.0) — transport technology
- **Fill Light:** Ceiling OmniLight, energy 1.1

### Storage (storage-template)
- **Ambient:** Color(0.52, 0.52, 0.54), energy 1.2
- **Accent:** Amber (0.90, 0.60, 0.20) — utilitarian
- **Fill Light:** Ceiling OmniLight, energy 1.1

## Emergency Lighting States

### Normal (default)
- All lights at full energy
- Ambient at template default (1.2 for corridors, 1.35 for gate room)
- No fog tint change

### Caution (post-crisis, scrubber damaged)
- Lights dimmed to 70%
- Ambient energy reduced to 0.8
- Subtle amber fog tint (warm, low-density)
- Ancient glow pulses faster (1.5s period) — ship "stressed"

### Red Alert (air crisis active, breach unsealed)
- All Light3D.light_color lerped 92% toward Color(1.0, 0.20, 0.15)
- All emissive materials tinted toward red
- Ambient color → Color(0.62, 0.18, 0.14)
- Alert pulse: lights flicker between 80%-100% at 0.5s intervals
- Implemented in: scripts/ship_alert.gd

### Blackout (gate collapse / power failure)
- All Light3D energies crushed to 12%
- Ambient crushed to 10%
- Ceiling emissive strips crushed to 4%
- Flashlight SpotLights spawn from perimeter positions
- Recovery: lights tween back up over 1.3s
- Implemented in: scripts/gate_room.gd (_collapse_blackout, _open_dark, _flicker_lights_up)

## Volumetric Fog Configuration

### Global (destiny-interior-environment.tres)
- volumetric_fog_enabled = true
- volumetric_fog_density = 0.015 (very subtle — base atmospheric haze)
- volumetric_fog_albedo = Color(0.8, 0.82, 0.85) (cool gray-blue)
- volumetric_fog_emission = Color(0, 0, 0)
- volumetric_fog_length = 64.0
- volumetric_fog_temporal_reprojection_enabled = true

### Gate Room (gate-room-environment.tres)
- volumetric_fog_enabled = true
- volumetric_fog_density = 0.02 (slightly thicker — monumental space)
- volumetric_fog_albedo = Color(0.6, 0.68, 0.85) (blue-tinted, matches ambient)
- FogVolume at gate ring: FogMaterial density 0.15, emission Color(0.2, 0.4, 0.8) (event horizon glow)

### Corridor FogVolumes
- Long corridors (>20m) get a FogVolume: FogMaterial density 0.08, albedo matches accent color
- Placed at ceiling level, 2m height, corridor width
- Gives corridors visible "depth haze" when looking down long axis

## Ancient Glow System

### scripts/ancient_glow.gd
Reusable component for pulsing emissive surfaces. Attach to any MeshInstance3D with an emissive StandardMaterial3D.

**Parameters:**
- pulse_amplitude: float (0.0-1.0, default 0.15) — how much the glow varies
- pulse_period: float (seconds, default 3.0) — full pulse cycle duration
- pulse_color: Color (default Color(0.3, 0.65, 1.0)) — Ancient tech blue-cyan
- flicker: bool (default false) — random flicker instead of smooth pulse
- flicker_probability: float (default 0.02) — chance per frame of flicker

**Usage in room_builder.gd:**
- Corridor sconces: amplitude 0.10, period 2.5, color = palette accent
- Control room pillar rings: amplitude 0.15, period 3.0, synchronized
- Console screens (idle): amplitude 0.05, period 4.0 — barely perceptible
- Activated consoles: amplitude 0.0 (steady bright glow, no pulse)

**Alert integration:**
- When ShipAlert is active, ancient_glow.gd speeds up pulse (period * 0.5) and shifts color toward red
- When blackout fires, glow dims to 5% and stops pulsing