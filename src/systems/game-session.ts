import { registerAirCrisis, QUEST_ID as AIR_CRISIS_QUEST_ID } from "../quests/air-crisis";
import { registerDestinyPowerCrisis } from "../quests/destiny-power-crisis";
import { createQuestManager, type QuestManager } from "./quest-manager";
import { initResources } from "./resources";
import { resetSceneTransitionState } from "./scene-transition-state";
import { ShipState } from "./ship-state";
import { resetLootState } from "./loot-state";
import { createTimerSystem, type TimerSystem } from "./timer-system";

export interface GameSession {
	shipState: ShipState;
	questManager: QuestManager;
	timers: TimerSystem;
}

let activeSession: GameSession | undefined;

const createGameSession = (): GameSession => {
	initResources();

	const shipState = new ShipState();
	shipState.init();

	const questManager = createQuestManager();
	registerDestinyPowerCrisis(questManager);
	registerAirCrisis(questManager);
	questManager.startQuest(AIR_CRISIS_QUEST_ID);

	return {
		shipState,
		questManager,
		timers: createTimerSystem(),
	};
};

export const getGameSession = (): GameSession => {
	activeSession ??= createGameSession();
	return activeSession;
};

export const resetGameSessionForTests = (): void => {
	activeSession?.questManager.dispose();
	activeSession?.shipState.dispose();
	activeSession?.timers.clear();
	activeSession = undefined;
	resetLootState();
	resetSceneTransitionState();
};
