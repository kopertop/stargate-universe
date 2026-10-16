// Save / load system — extracted from main.js (TD-101).
// Owns localStorage persistence, save versioning, migration, and the title-screen
// new-game / continue / chapter-select entry points.
//
// Dependencies are injected via `createSaveSystem(ctx)` so this module stays
// independent of main.js's closure scope.

const SAVE_KEY = 'sgu.save';
const SAVE_VERSION = 1;

/** @typedef {{
 *   quest: any,
 *   rpg: any,
 *   ftl: { window: number, cooldown: number, warned: Set<any> },
 *   countdown: any,
 *   destiny: any,
 *   DECK_H: number,
 *   ui: any,
 *   enterWorld: (w: any) => void,
 *   arriveAt: (w: any) => void,
 *   placePlayer: (w: any, pos: any, yaw: number) => void,
 *   loadRpg: () => void,
 *   saveRpg: () => void,
 *   listener: { context: { resume: () => void } },
 *   beacon: any,
 *   startChapter: (id: string) => void,
 *   lastScan: any,
 *   cam: { yaw: number },
 *   onGateEvent: (w: any) => any,
 *   count: (id: string) => number,
 *   addItem: (id: string, n: number) => void,
 *   equip: (id: string) => void,
 * }} SaveCtx */

/** Migrate an older save object to the current version. Older saves (no version field) are treated as version 0. */
const migrateSave = (s) => {
	if (!s.version) s.version = 0;
	// v0 → v1: no structural changes yet, but this is the hook for future migrations.
	// Example: if (s.version < 1) { s.deck = s.deck ?? 0; s.version = 1; }
	s.version = SAVE_VERSION;
	return s;
};

/**
 * @param {SaveCtx} ctx
 */
export function createSaveSystem(ctx) {
	const { quest, ftl, destiny, DECK_H, ui, enterWorld, arriveAt, placePlayer, loadRpg, saveRpg, listener, beacon } = ctx;
	let gameStarted = false;

	/** @returns {object|null} serialized save state */
	const serialize = () => ({
		version: SAVE_VERSION,
		chapter: quest.chapter.id,
		stepIndex: quest.stepIndex,
		flags: [...quest.flags],
		lastScan: ctx.lastScan ?? null,
		deck: destiny.deck,
		ftl: { window: ftl.window, cooldown: ftl.cooldown },
		growth: destiny.ship.growBeds.map((b) => b.growth),
		countdown: ctx.countdown && { t: ctx.countdown.t, total: ctx.countdown.total, label: ctx.countdown.label, cause: ctx.countdown.cause },
		savedAt: Date.now(),
	});

	const saveGame = () => {
		if (!quest.chapter || !gameStarted) return;
		try { localStorage.setItem(SAVE_KEY, JSON.stringify(serialize())); saveRpg(); }
		catch (e) { console.warn('saveGame failed:', e.message); }
	};

	const hasSave = () => { try { return !!localStorage.getItem(SAVE_KEY); } catch { return false; } };

	const clear = () => { localStorage.removeItem(SAVE_KEY); };

	/** Restore chapter/step/flags + RPG, rebuild Destiny state from flags, and put the player in the gate room.
	 *  Planet-side steps rewind to the gate. */
	const loadGame = () => {
		let s; try { s = JSON.parse(localStorage.getItem(SAVE_KEY)); } catch (e) { console.warn('loadGame parse failed:', e.message); s = null; }
		if (!s) return false;
		s = migrateSave(s);
		ctx.startChapter(s.chapter); // sets quest.chapter to the saved chapter
		loadRpg();
		ctx.lastScan = s.lastScan ?? null;
		for (const f of s.flags) quest.flags.add(f);
		const steps = quest.chapter.steps, idx = (id) => steps.findIndex((x) => x.id === id);
		let si = Math.min(s.stepIndex, steps.length - 1);
		const travelIdx = idx('travel'), brodyIdx = idx('give_brody');
		if (travelIdx >= 0 && brodyIdx >= 0 && si > travelIdx && si < brodyIdx) { si = travelIdx; for (const f of ['on_planet', 'returned_from_planet']) quest.flags.delete(f); }
		quest.stepIndex = si;
		const S2 = destiny.ship;
		if (quest.has('fuse_installed')) S2.installFuse();
		if (quest.has('conduit_seated')) S2.installConduit();
		if (quest.has('quarters_powered')) S2.setQuartersPower(true);
		for (const l of S2.lootables) if (quest.has(`looted:${l.key}`)) { S2.openCrate(l, true); S2.takeLoot(l); }
		if (quest.has('grow_lights_restored')) S2.setGrowLights(true);
		if (s.growth) S2.setGrowth(s.growth);
		if (quest.has('elevator_fuses_seated')) S2.seatElevatorFuses();
		if (quest.has('elevator_powered')) S2.setElevatorPower(true);
		if (quest.has('power_restored')) S2.setPower(true);
		if (quest.has('any_breach_sealed')) S2.sealBreach();
		if (quest.has('kino_acquired')) S2.takeKino();
		if (quest.has('scrubber_repaired')) S2.repairScrubber();
		const step = quest.step();
		if (quest.has('ftl_dropped') && ['scout_kino', 'gear_up', 'travel'].includes(step?.id)) {
			destiny.gate.userData.reset();
			destiny.gate.userData.incoming(ctx.onGateEvent(destiny));
		}
		ftl.window = s.ftl?.window ?? 0;
		ftl.cooldown = s.ftl?.cooldown ?? 0;
		ftl.warned.clear();
		ctx.countdown = s.countdown ? { ...s.countdown, warned: new Set() } : null;
		destiny.deck = s.deck ?? 0;
		enterWorld(destiny);
		placePlayer(destiny, destiny.deck ? (destiny.anchors['elevator_room_floor_1:Elevator'] ?? destiny.spawn).clone().setY(destiny.deck * DECK_H) : destiny.spawn, destiny.spawnYaw);
		ctx.cam.yaw = 0;
		gameStarted = true;
		saveGame();
		ui.refreshTracker();
		ui.refreshPlayer();
		ui.toast(`Loaded: ${quest.chapter.title} — ${step?.label ?? ''}`, 4);
		return true;
	};

	const newGame = () => {
		listener.context.resume();
		destiny.scene.add(beacon);
		localStorage.removeItem(SAVE_KEY);
		localStorage.removeItem('sgu.rpg');
		ui.showChapter(quest.chapter.title, quest.chapter.subtitle, 'Begin', () => { gameStarted = true; arriveAt(destiny); });
	};

	/** Start at any chapter with the state earlier episodes would have left behind (cumulative stages, in chapter order). */
	const PREREQ_STAGES = {
		e2_water: () => {
			const S = destiny.ship; S.setPower(true); S.installFuse(); S.takeKino(); S.repairScrubber(); S.sealBreach?.();
			for (const f of ['relay_inspected', 'has_small_fuse', 'fuse_installed', 'power_restored', 'control_room_visited', 'life_support_diagnosed', 'any_breach_sealed', 'eli_quarters_visited', 'kino_acquired', 'locker_opened', 'scrubber_diagnosed', 'geared_up', 'scrubber_repaired']) quest.flags.add(f);
			for (const [id, n] of /** @type {[string,number][]} */ ([['kino_orb', 1], ['kino_remote', 1], ['shovel', 1], ['field_backpack', 1], ['tac_vest', 1], ['rations', 2]])) if (ctx.count(id) < n) ctx.addItem(id, n - ctx.count(id));
			ctx.equip('shovel'); ctx.equip('field_backpack'); ctx.equip('tac_vest');
		},
		e3_darkness: () => {},
		e4_parts: () => {
			const S = destiny.ship; S.seatElevatorFuses(); S.setElevatorPower(true); S.setGrowLights(true);
			for (const f of ['has_bus_fuses', 'has_large_fuse', 'elevator_fuses_seated', 'elevator_powered', 'upper_deck_reached', 'hydroponics_visited', 'grow_lights_restored']) quest.flags.add(f);
		},
		e5_light: () => {
			const S = destiny.ship; S.installConduit(); S.setQuartersPower(true);
			for (const f of ['conduit_seated', 'quarters_powered', 'quarters_visited']) quest.flags.add(f);
		},
	};

	const startFrom = (id) => {
		listener.context.resume();
		destiny.scene.add(beacon);
		localStorage.removeItem(SAVE_KEY);
		localStorage.removeItem('sgu.rpg');
		if (id === quest.chapters[0].id) return newGame();
		ctx.startChapter(id);
		for (const ch of quest.chapters) { PREREQ_STAGES[ch.id]?.(); if (ch.id === id) break; }
		ui.refreshPlayer();
		ui.refreshTracker();
		ui.showChapter(quest.chapter.title, quest.chapter.subtitle, 'Begin', () => { gameStarted = true; enterWorld(destiny); placePlayer(destiny, destiny.spawn.clone(), destiny.spawnYaw); ctx.cam.yaw = 0; saveGame(); });
	};

	return {
		saveGame,
		hasSave,
		clear,
		loadGame,
		newGame,
		startFrom,
		PREREQ_STAGES,
		get gameStarted() { return gameStarted; },
		set gameStarted(v) { gameStarted = v; },
		SAVE_KEY,
		SAVE_VERSION,
		migrateSave,
	};
}