class_name HullSealSwitch
extends Interactable

# Wall-mounted switch that seals the local hull breach. One-shot.

@export var breach_id: String = "breach_a"
@export var sealed_prompt: String = "Hull integrity holding."

var _sealed: bool = false

func _ready() -> void:
	super()
	prompt = "Engage emergency seal"
	if GameState.breaches_sealed.has(breach_id):
		_sealed = true
		enabled = false
		prompt = sealed_prompt

func _on_interact(_by: Node) -> void:
	if _sealed:
		return
	_sealed = true
	enabled = false
	prompt = sealed_prompt
	GameState.seal_breach(breach_id)
	GameState.check_episode_complete()
