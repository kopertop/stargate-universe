class_name WeaponResource
extends Resource

## Custom Resource for weapon definitions. Each weapon is a data-driven
## Resource (.tres file) consumed by CombatSystem. Kept as a pure data
## container — no logic, no node deps — so it's safe to load in headless
## tests and trivially extensible by future weapon additions.
##
## Fields:
##   id              — unique weapon identifier (e.g. "beretta_m9")
##   display_name    — human-readable name for HUD / inventory
##   damage          — per-hit damage before armor / cover modifiers
##   fire_rate       — rounds per second (0 = semi-auto, one click = one shot)
##   magazine_size   — rounds per magazine
##   reload_time     — seconds to reload
##   range           — effective range in metres (hitscan ray length)
##   spread          — cone half-angle in degrees (0 = perfectly accurate)
##   recoil          — vertical kick per shot in degrees (camera pitch)
##   auto            — true = hold to fire; false = one click per shot
##   projectile_speed— m/s; 0 = hitscan (instant raycast), >0 = projectile
##   sound_fire      — AudioStream resource path (empty = no sound)
##   sound_reload    — AudioStream resource path (empty = no sound)

@export var id: String = ""
@export var display_name: String = ""
@export var damage: float = 10.0
@export var fire_rate: float = 2.0
@export var magazine_size: int = 15
@export var reload_time: float = 2.0
@export var range: float = 50.0
@export var spread: float = 2.0
@export var recoil: float = 1.5
@export var auto: bool = false
@export var projectile_speed: float = 0.0
@export var sound_fire: String = ""
@export var sound_reload: String = ""


## Returns true if this weapon uses hitscan (instant raycast) rather than
## spawning a projectile.
func is_hitscan() -> bool:
	return projectile_speed <= 0.0


## Returns the interval between shots in seconds (inverse of fire_rate).
## For semi-auto (fire_rate == 0) returns 0 — fire is click-gated.
func shot_interval() -> float:
	if fire_rate <= 0.0:
		return 0.0
	return 1.0 / fire_rate


## Static helper: load a WeaponResource from a .tres path. Returns null on
## failure (wrong type or missing file). Safe in headless — no autoload deps.
static func load_from(path: String) -> WeaponResource:
	var res: Resource = load(path)
	if res == null or not (res is WeaponResource):
		return null
	return res as WeaponResource