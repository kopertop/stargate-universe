/**
 * Active quest manager registry.
 *
 * Scenes own their own QuestManager instance — but the HUD lives at the
 * app level and needs read-only visibility into whichever manager is
 * currently active. Rather than refactor scenes to share a global
 * manager (which would couple unrelated scenes' quest state), each
 * scene calls `setActiveQuestManager(qm)` on mount and
 * `setActiveQuestManager(null)` on dispose.
 *
 * The HUD reads from `getActiveQuestManager()` whenever it re-renders.
 */
import type { QuestManager } from "@kopertop/vibe-game-engine";

let active: QuestManager | null = null;

export const setActiveQuestManager = (manager: QuestManager | null): void => {
	active = manager;
};

export const getActiveQuestManager = (): QuestManager | null => active;
