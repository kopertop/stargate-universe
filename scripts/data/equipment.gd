class_name EquipmentDefs
extends RefCounted

# First gear asset set definitions (#73). Data-driven equipment catalog with
# stat modifiers per piece. Each definition is a Dictionary with:
#   id          — unique item identifier
#   name        — display name
#   slot        — one of EquipmentSystem.SLOTS (helmet/vest/backpack/pants/boots)
#   model       — GLB path for 3D mounting (empty → procedural placeholder)
#   icon        — icon texture path for the UI
#   description — flavour text
#   stats       — Dictionary of stat modifiers (additive, applied on equip):
#                   max_health, max_oxygen, armor, carry_capacity,
#                   move_speed, sprint_multiplier
#   effects     — Dictionary of boolean flags (any-true stacking):
#                   atmosphere_protection, radiation_protection
#
# This is the first authored asset set. Future gear sets append to GEAR.
# Kept as a pure data class (RefCounted) so it's safe to load in headless tests.

# --- Gear catalog (first asset set) -------------------------------------------
const GEAR: Array[Dictionary] = [
	{
		"id": "standard_helmet",
		"name": "Standard Helmet",
		"slot": "helmet",
		"model": "res://models/equipment/marine_helmet.glb",
		"icon": "res://sprites/ui/items/marine_helmet.png",
		"description": "Standard-issue ballistic helmet. Offers head protection off-world.",
		"stats": {"max_health": 10.0, "armor": 5.0},
		"effects": {},
	},
	{
		"id": "recon_cap",
		"name": "Recon Cap",
		"slot": "helmet",
		"model": "res://models/equipment/recon_cap.glb",
		"icon": "res://sprites/ui/items/recon_cap.png",
		"description": "Lightweight soft cap for reconnaissance. Trades protection for visibility.",
		"stats": {"move_speed": 1.0},
		"effects": {},
	},
	{
		"id": "tactical_vest",
		"name": "Tactical Vest",
		"slot": "vest",
		"model": "res://models/equipment/tac_vest.glb",
		"icon": "res://sprites/ui/items/tac_vest.png",
		"description": "Load-bearing tactical vest with light armor plating.",
		"stats": {"max_health": 20.0, "armor": 15.0, "carry_capacity": 4.0},
		"effects": {},
	},
	{
		"id": "field_backpack",
		"name": "Field Backpack",
		"slot": "backpack",
		"model": "res://models/equipment/field_backpack.glb",
		"icon": "res://sprites/ui/items/field_backpack.png",
		"description": "Expedition rucksack. Significantly increases carry capacity for off-world hauls.",
		"stats": {"carry_capacity": 8.0, "max_oxygen": 10.0},
		"effects": {},
	},
	{
		"id": "fatigue_pants",
		"name": "Fatigue Pants",
		"slot": "pants",
		"model": "res://models/equipment/combat_boots.glb",
		"icon": "res://sprites/ui/items/combat_boots.png",
		"description": "Reinforced fatigue trousers. Standard legwear for surface missions.",
		"stats": {"armor": 5.0, "move_speed": 0.5},
		"effects": {},
	},
	{
		"id": "combat_boots",
		"name": "Combat Boots",
		"slot": "boots",
		"model": "res://models/equipment/combat_boots.glb",
		"icon": "res://sprites/ui/items/combat_boots.png",
		"description": "Reinforced field boots. Standard footwear for surface missions.",
		"stats": {"armor": 3.0, "move_speed": 0.5, "sprint_multiplier": 0.1},
		"effects": {},
	},
	{
		"id": "pressure_suit_helmet",
		"name": "Pressure Suit Helmet",
		"slot": "helmet",
		"model": "",
		"icon": "",
		"description": "Sealed pressure-suit helmet. Provides atmosphere protection on hostile worlds.",
		"stats": {"max_health": 5.0, "armor": 3.0, "max_oxygen": 20.0},
		"effects": {"atmosphere_protection": true},
	},
	{
		"id": "pressure_suit_vest",
		"name": "Pressure Suit Vest",
		"slot": "vest",
		"model": "",
		"icon": "",
		"description": "Sealed pressure-suit torso section. Provides atmosphere protection.",
		"stats": {"max_health": 15.0, "armor": 10.0, "max_oxygen": 20.0},
		"effects": {"atmosphere_protection": true},
	},
]


static func all() -> Array[Dictionary]:
	return GEAR


static func by_id(item_id: String) -> Dictionary:
	for def in GEAR:
		if String(def.get("id", "")) == item_id:
			return def
	return {}


static func by_slot(slot: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in GEAR:
		if String(def.get("slot", "")) == slot:
			out.append(def)
	return out


static func ids() -> Array[String]:
	var out: Array[String] = []
	for def in GEAR:
		out.append(String(def.get("id", "")))
	return out