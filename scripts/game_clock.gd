extends Node

# Accumulated gameplay seconds. Drives any persistent timer that must
# survive save/resume — currently the FTL countdown via
# GameState.ftl_drop_game_time, with future crisis timers wiring in the
# same way. Pauses with the scene tree (Kino menu open, dialog full-screen
# camera, etc.) so paused time doesn't bleed into countdowns.
#
# Registers itself as an ISaveableSystem so the elapsed value rides along
# in every autosave.

var elapsed_seconds: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	SaveManager.register_system("game_clock", self)


func _process(delta: float) -> void:
	elapsed_seconds += delta


func reset() -> void:
	elapsed_seconds = 0.0


func serialize() -> Dictionary:
	return {"elapsed_seconds": elapsed_seconds}


func deserialize(data: Dictionary, _version: int) -> void:
	elapsed_seconds = float(data.get("elapsed_seconds", 0.0))
