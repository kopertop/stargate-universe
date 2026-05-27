class_name Greer
extends Npc

# Sgt Greer is the "where do I go next?" NPC. Whatever the current quest step,
# talking to him yields ONE line hinting the next destination plus a single
# acknowledge choice. The tree is rebuilt from GameState.quest_step on every
# interact (overrides the static dialogue_tree the base would use), so he's
# never out of date.

func _active_dialogue_tree() -> Array:
	return [{
		"speaker": "Sgt Greer",
		"text": _hint_for_step(GameState.quest_step),
		"choices": [{"text": "Copy that.", "next": "exit"}],
	}]

func _hint_for_step(step: String) -> String:
	match step:
		GameState.QUEST_TALK_SCOTT:
			return "Lt Scott's running point in the gate room. Go see what he needs."
		GameState.QUEST_FIND_RUSH:
			return "I think I saw Dr Rush head toward the Control Room. Try there."
		GameState.QUEST_FIND_REST:
			return "You're dead on your feet, Wallace. Your quarters are around the corner — get some rack time."
		GameState.QUEST_FIND_KINO:
			return "There's some Ancient gadget sitting on the desk in your quarters. Take a look at it."
		GameState.QUEST_SLEEP:
			return "Get your head down for a bit. We'll wake you if it hits the fan."
		GameState.QUEST_RETURN_TO_CONTROL:
			return "Scott's been calling for you on the radio — get back to the control room."
		GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
			return "Work one of the control terminals in the control room. Find out what's failing."
		GameState.QUEST_SEAL_BREACH:
			return "That breach down south is bleeding our air. Get to the Shuttle Dock and shut it."
		GameState.QUEST_FIND_SCRUBBER:
			return "Rush is at the life-support panel in the south corridor. Go hear him out."
		GameState.QUEST_WAIT_FTL, GameState.QUEST_GO_TO_GATE:
			return "Did you feel that? We dropped out of FTL. You'll want to head to the gate room."
		GameState.QUEST_DIAL_LIME_PLANET:
			return "Gate's lit up in the gate room. Get over there."
		GameState.QUEST_MINE_LIME:
			return "Step through the gate and haul back some of that lime. We need it."
		GameState.QUEST_RETURN_DESTINY:
			return "Got the lime? Get back through the gate to Destiny."
		GameState.QUEST_REPAIR_SCRUBBER:
			return "Take that lime to the scrubber in the south corridor and finish the repair."
		GameState.QUEST_COMPLETE:
			return "Air's holding. Good work, Wallace — go get some rest. You earned it."
		_:
			return "Keep moving, Wallace. Stick to the lit corridors."
