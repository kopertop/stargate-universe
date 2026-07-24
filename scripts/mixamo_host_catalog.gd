extends RefCounted
class_name MixamoHostCatalog

# Cast → Mixamo host mapping for stargate-universe.
# Host packs are local Mixamo ToS builds under models/mixamo_openbot/*_rifle_combat.glb.
#
#   Eli (player)     → eli   (Mixamo character "Bryce" / Ch42)
#   Greer            → greer (Mixamo character "Alex")
#   Military males   → swat  (Scott, Young, Soldier*, …)
#   Other males      → ybot  (Rush, Brody, …)
#   All females      → xbot  (Chloe, TJ, Park, Wray, …)

const HOST_GLBS: Dictionary = {
	"eli": "res://models/mixamo_openbot/Eli_rifle_combat.glb",
	"greer": "res://models/mixamo_openbot/Greer_rifle_combat.glb",
	"swat": "res://models/mixamo_openbot/Swat_rifle_combat.glb",
	"ybot": "res://models/mixamo_openbot/YBot_rifle_combat.glb",
	"xbot": "res://models/mixamo_openbot/XBot_rifle_combat.glb",
}

const SWAT_IDLE_GLB: String = "res://models/mixamo_openbot/Swat_rifle_idle.glb"

# Explicit overrides by CharacterFactory profile / alias name.
const CHARACTER_HOST: Dictionary = {
	"Eli": "eli",
	"Lt Scott": "swat",
	"Sgt Greer": "greer",
	"Colonel Young": "swat",
	"Lt James": "xbot", # TJ — female, even though military
	"Dr Rush": "ybot",
	"Dr Park": "xbot",
	"Dr James": "xbot",
	"Chloe Armstrong": "xbot",
	"Camille Wray": "xbot",
}


static func host_key_for(character_name: String) -> String:
	var n: String = character_name.strip_edges()
	if CHARACTER_HOST.has(n):
		return str(CHARACTER_HOST[n])
	# Aliases used around the ship.
	var aliases: Dictionary = {
		"Greer": "Sgt Greer", "Scott": "Lt Scott", "Young": "Colonel Young",
		"Rush": "Dr Rush", "Park": "Dr Park", "Chloe": "Chloe Armstrong",
		"TJ": "Lt James", "Tamara Johansen": "Lt James", "James": "Lt James",
	}
	if aliases.has(n) and CHARACTER_HOST.has(str(aliases[n])):
		return str(CHARACTER_HOST[str(aliases[n])])
	# Factory military flag (males → swat, females → xbot).
	var CF: Script = load("res://scripts/character_factory.gd") as Script
	if CF != null:
		var prof: Dictionary = CF.call("profile_for", n) as Dictionary
		var military: bool = bool(prof.get("military", false))
		var mod: Dictionary = prof.get("mod", {}) as Dictionary
		var gender: String = str(mod.get("gender", ""))
		if gender == "Female":
			return "xbot"
		if military or gender == "Male":
			# Generic Soldier / Marine keywords land here as military males.
			if military:
				return "swat"
			return "ybot"
	# Keyword fallbacks when factory isn't available.
	var lower: String = n.to_lower()
	if lower.find("soldier") >= 0 or lower.find("marine") >= 0 or lower.find("sgt") >= 0 \
		or lower.find("lt ") >= 0 or lower.find("colonel") >= 0 or lower.find("captain") >= 0:
		return "swat"
	if lower.find("chloe") >= 0 or lower.find("park") >= 0 or lower.find("wray") >= 0 \
		or lower.find("tj") >= 0 or lower.find("johansen") >= 0:
		return "xbot"
	return "ybot"


static func glb_for_host(host_key: String) -> String:
	var key: String = host_key.strip_edges().to_lower()
	if HOST_GLBS.has(key) and ResourceLoader.exists(str(HOST_GLBS[key])):
		return str(HOST_GLBS[key])
	return ""


## Resolve a playable pack for a character, with graceful fallbacks.
## Order: preferred host → role fallbacks → any available combat pack → Swat idle.
static func resolve_glb_for(character_name: String, force_host: String = "") -> String:
	var preferred: String = force_host.strip_edges().to_lower()
	if preferred == "":
		preferred = host_key_for(character_name)
	var path: String = glb_for_host(preferred)
	if path != "":
		return path
	# Fallbacks when named packs are not built yet.
	match preferred:
		"eli":
			path = glb_for_host("ybot")
			if path != "":
				return path
			path = glb_for_host("swat")
			if path != "":
				return path
		"greer":
			path = glb_for_host("swat")
			if path != "":
				return path
			path = glb_for_host("ybot")
			if path != "":
				return path
		"xbot":
			path = glb_for_host("ybot")
			if path != "":
				return path
			path = glb_for_host("swat")
			if path != "":
				return path
		"ybot":
			path = glb_for_host("swat")
			if path != "":
				return path
		"swat":
			path = glb_for_host("ybot")
			if path != "":
				return path
	if ResourceLoader.exists(SWAT_IDLE_GLB):
		return SWAT_IDLE_GLB
	return ""


static func any_combat_pack_available() -> bool:
	for k in HOST_GLBS.keys():
		if ResourceLoader.exists(str(HOST_GLBS[k])):
			return true
	return ResourceLoader.exists(SWAT_IDLE_GLB)
