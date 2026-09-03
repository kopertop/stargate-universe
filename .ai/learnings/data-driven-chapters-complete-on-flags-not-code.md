# Chapter steps complete on flags; room-entry steps complete by anchor convention

**Design.** `web/gate-room/data/chapters.json` uses the repo's `data/quests.json` step schema
(`id, label, objective, target{room,anchor}, complete_when`) plus `xp`, `on_enter`/`on_exit` triggers
(`subtitle`, `radio`, `toast`, `ftl_drop`, `dial`) and a per-chapter `planet` (biome + atmosphere +
resource). Episode 2 "Water" is data only — same step types, an icy biome and `ice` as the resource.

**Gotcha.** A flag set early (e.g. `ftl_dropped` from merely entering the gate room at the start) would
auto-complete a later step the moment it became current. Room-entry flags are therefore only set when
the *current* step targets that room with anchor `RoomCenter`; all other flags come from interactions
that are themselves gated on step id (`stepIs('gear_up')`).

**Waypoint.** `NearestResource` is a virtual anchor resolved at runtime to the closest undone node, so
the beacon and minimap need no per-node data.
