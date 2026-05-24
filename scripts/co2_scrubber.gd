class_name Co2Scrubber
extends Interactable

# Broken life-support scrubber for Episode 1 / "Air". First interaction
# identifies the missing lime requirement; later interaction spends lime and
# completes the repair.

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_refresh_prompt()

func _on_interact(_by: Node) -> void:
	if GameState.scrubber_repaired:
		GameState.add_log("CO2 scrubber is stable. The cartridge bed is cycling clean air.")
		_refresh_prompt()
		return
	if not GameState.scrubber_diagnosed:
		GameState.diagnose_scrubber()
		_refresh_prompt()
		return
	if GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
		GameState.repair_scrubber_with_lime()
	else:
		GameState.add_log("The scrubber needs %d lime. Current lime: %d." % [
			GameState.AIR_LIME_REQUIRED,
			GameState.resource_count(GameState.AIR_LIME_RESOURCE),
		])
		GameState.advance_air_quest()
	_refresh_prompt()

func _refresh_prompt() -> void:
	if GameState.scrubber_repaired:
		prompt = "CO2 scrubber repaired"
	elif not GameState.scrubber_diagnosed:
		prompt = "Diagnose CO2 scrubber"
	elif GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
		prompt = "Repair CO2 scrubber"
	else:
		prompt = "CO2 scrubber needs lime"
