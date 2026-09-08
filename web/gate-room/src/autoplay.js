// Demo driver / smoke test: plays chapters hands-free through the real input path (keys + E), routing between rooms over
// the door graph (ship.route). Steps are handled by id from data/chapters.json, so a new chapter that reuses the step
// vocabulary (talk_*, ftl_drop, scout_kino, gear_up, travel, mine, dial_home, give_brody, repair_*) runs without changes.
// Usage: ?autoplay then window.__auto.run() (all chapters) or window.__auto.runChapter(). Progress in window.__auto.status/log.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const press = (code) => { window.dispatchEvent(new KeyboardEvent('keydown', { code })); window.dispatchEvent(new KeyboardEvent('keyup', { code })); };

export const createAutoplay = (d) => {
	const auto = { status: 'idle', log: [], running: false, abort: false, report: [] };
	const say = (s) => { auto.status = s; auto.log.push(`${(performance.now() / 1000).toFixed(1)}s ${s}`); };
	const pos = () => d.player.root.position;
	const ship = () => d.destiny.ship, A = () => d.destiny.anchors, step = () => d.quest.step(), stepId = () => step()?.id;
	const gz = () => d.destiny.gate.position.z;
	/** Walk toward (x,z) via the real key path; camera yaw steers so W moves toward the target. Runs on long legs. */
	const walkTo = async (x, z, { run, tol = 0.7, timeout } = {}) => {
		const dist0 = Math.hypot(x - pos().x, z - pos().z); run ??= dist0 > 10; timeout ??= (dist0 / (run ? 8 : 3.5)) * 1000 + 6000;
		const t0 = performance.now(); d.input.keys.add('KeyW'); if (run) d.input.keys.add('ShiftLeft');
		let lastD = Infinity, stallT = 0, side = 'KeyD';
		while (!auto.abort && performance.now() - t0 < timeout) {
			const dx = x - pos().x, dz = z - pos().z, dist = Math.hypot(dx, dz); if (dist < tol) break;
			d.cam().yaw = Math.atan2(-dx, -dz);
			if (dist > lastD - 0.02) stallT += 40; else stallT = 0; lastD = Math.min(lastD, dist);
			if (stallT > 500) { d.input.keys.add(side); await sleep(600); d.input.keys.delete(side); side = side === 'KeyD' ? 'KeyA' : 'KeyD'; stallT = 0; lastD = Infinity; }
			await sleep(40);
		}
		d.input.keys.delete('KeyW'); d.input.keys.delete('ShiftLeft'); d.input.keys.delete('KeyA'); d.input.keys.delete('KeyD'); await sleep(200);
	};
	/** Route through doors to a room, then to an anchor (or the room centre). */
	const goTo = async (room, anchor = 'RoomCenter', opts = {}) => {
		const from = ship().roomAt(pos()); const path = from && from !== room ? ship().route(from, room) : [];
		if (path === null) { say(`no route ${from} → ${room}`); return false; }
		let cur = from;
		for (const door of path) {
			const next = door.rooms[0] === cur ? door.rooms[1] : door.rooms[0], p = door.g.position, cc = ship().center(cur);
			const n = door.axis === 'x' ? Math.sign(cc.x - p.x) : Math.sign(cc.z - p.z);
			const before = door.axis === 'x' ? [p.x + n * 1.4, p.z] : [p.x, p.z + n * 1.4], after = door.axis === 'x' ? [p.x - n * 1.4, p.z] : [p.x, p.z - n * 1.4];
			await walkTo(...before, { tol: 0.5 }); await sleep(450); await walkTo(...after, { tol: 0.5, run: false }); cur = next;
		}
		const t = A()[`${room}:${anchor}`] ?? ship().center(room); await walkTo(t.x, t.z, opts); return true;
	};
	const face = (x, z) => { const dx = x - pos().x, dz = z - pos().z; d.player.root.rotation.y = Math.atan2(dx, dz); };
	const faceAnchorProp = (room, anchor) => { const a = A()[`${room}:${anchor}`]; if (!a) return; const c = ship().center(room); face(a.x + (c.x - a.x) * -0.01 + (a.x - c.x) * 0.0 + (a.x - pos().x) * 2, a.z + (a.z - pos().z) * 2); };
	const interact = async (settle = 2200) => { await sleep(150); press('KeyE'); await sleep(settle); };
	const waitFor = async (pred, timeout = 20000) => { const t0 = performance.now(); while (!pred() && performance.now() - t0 < timeout && !auto.abort) await sleep(80); return pred(); };
	const holdE = async (until, timeout = 12000) => { d.input.keys.add('KeyE'); await waitFor(until, timeout); d.input.keys.delete('KeyE'); await sleep(250); };
	/** Face the thing the anchor stands in front of: away from the room centre is a good guess for wall props, toward it for islands. */
	const facePropAt = (room, anchor) => { const a = A()[`${room}:${anchor}`]; if (!a) return; const m = ship().propMeshes.find((x) => x.userData.prop.roomId === room && x.userData.prop.spec.anchor === anchor); if (m) { const b = m.position; face(b.x, b.z); } };

	// ---- one handler per step vocabulary; each returns when it has done its part (the quest engine advances the step)
	const H = {
		arrive: async () => { document.querySelector('#chapter button')?.click(); await waitFor(() => !d.travel(), 8000); await sleep(800); },
		restore_power: async (s) => { await goTo(s.target.room, s.target.anchor); facePropAt(s.target.room, s.target.anchor); await interact(); },
		reach_control: async (s) => { await goTo(s.target.room, 'RoomCenter'); },
		diagnose: async (s) => { await goTo(s.target.room, s.target.anchor); facePropAt(s.target.room, s.target.anchor); await interact(2600); await sleep(1200); if (d.ui.isRemoteOpen()) { press('Tab'); await sleep(600); } },
		seal_breach: async (s) => { await goTo(s.target.room, s.target.anchor); const a = A()[`${s.target.room}:${s.target.anchor}`]; face(a.x + 1, a.z); await interact(); },
		explore: async (s) => { await goTo(s.target.room, 'RoomCenter'); },
		find_kino: async (s) => { await goTo(s.target.room, s.target.anchor); facePropAt(s.target.room, s.target.anchor); await interact(1600); if (A()[`${s.target.room}:Locker`]) { await goTo(s.target.room, 'Locker'); facePropAt(s.target.room, 'Locker'); await interact(1800); } },
		find_scrubber: async (s) => { await goTo(s.target.room, s.target.anchor); facePropAt(s.target.room, s.target.anchor); await interact(); },
		talk_rush: async (s) => { await goTo(s.target.room, s.target.anchor, { tol: 1.2 }); await interact(2000); },
		ftl_drop: async (s) => { await goTo(s.target.room, 'RoomCenter'); await waitFor(() => d.destiny.gate.userData.active, 15000); await sleep(600); },
		scout_kino: async () => {
			await walkTo(0, gz() + 9, { tol: 0.4, run: false }); face(0, gz()); await sleep(300); press('KeyK'); await sleep(500);
			d.input.keys.add('KeyW'); await waitFor(() => d.kino() === 'planet', 12000); d.input.keys.delete('KeyW'); await sleep(1200); d.input.keys.add('KeyW'); await sleep(1500); d.input.keys.delete('KeyW');
			await waitFor(() => stepId() !== 'scout_kino', 8000); await sleep(1500); if (d.kino()) { press('KeyE'); await sleep(600); }
		},
		gear_up: async (s) => { await goTo(s.target.room, s.target.anchor); facePropAt(s.target.room, s.target.anchor); await interact(1900); },
		travel: async () => { await goTo('gate_room', 'GateFront', { tol: 1.0 }); await walkTo(0, gz() + 8, { run: true, tol: 1.0 }); await walkTo(0, gz() + 0.7, { tol: 0.35, timeout: 8000, run: false }); await waitFor(() => d.world.name === 'planet' && !d.travel(), 15000); await sleep(600); },
		mine: async () => {
			const r = d.planet.resource, have = () => d.rpg.inventory[r.id] ?? 0;
			for (let i = 0; i < 6 && have() < r.required; i++) {
				const n = d.planet.nodes.find((n) => !n.done); if (!n) break;
				await walkTo(n.x, n.z, { run: true, tol: 1.4, timeout: 25000 }); face(n.x, n.z);
				for (let k = 0; k < 2 && have() < r.required && !n.done; k++) { const before = have(); await holdE(() => have() > before, 9000); }
			}
		},
		dial_home: async () => {
			await walkTo(0, 6, { run: true, tol: 1.2, timeout: 30000 }); face(0, 0);
			if (!d.planet.gate.userData.active) { // dial Destiny from the Remote's Gate tab (skip if a retry finds the gate already open)
				if (d.ui.isRemoteOpen()) { press('Tab'); await sleep(400); }
				press('Tab'); await waitFor(() => d.ui.isRemoteOpen(), 3000); document.querySelector('#remote [data-tab="gate"]')?.click();
				await waitFor(() => document.querySelector('#remote [data-dial="destiny"]:not([disabled])'), 4000); document.querySelector('#remote [data-dial="destiny"]')?.click();
				await sleep(400); if (d.ui.isRemoteOpen()) d.ui.closeRemote();
				await waitFor(() => d.planet.gate.userData.active, 16000);
			}
			if (d.ui.isRemoteOpen()) d.ui.closeRemote(); await sleep(800);
			await walkTo(0, 2.6, { tol: 0.5, run: false }); await walkTo(0, 0.4, { tol: 0.3, timeout: 5000, run: false });
			await waitFor(() => d.world.name === 'destiny' && !d.travel(), 15000); await sleep(600);
		},
		give_brody: async (s) => { await goTo(s.target.room, s.target.anchor); await interact(1500); await waitFor(() => stepId() !== 'give_brody', 9000); },
		repair: async (s) => { await goTo(s.target.room, s.target.anchor); facePropAt(s.target.room, s.target.anchor); await interact(4500); },
	};
	const handlerFor = (id) => H[id] ?? (id.startsWith('repair_') ? H.repair : id.startsWith('talk_') ? H.talk_rush : null);

	/** Play the current chapter to its terminal step. Resolves { ok, chapter, seconds }. */
	auto.runChapter = async () => {
		const ch = d.quest.chapter, t0 = performance.now(); say(`chapter ${ch.id}: ${ch.title}`);
		let guard = 0, lastId = null, tries = 0;
		while (!auto.abort && guard++ < 60) {
			const s = step(); if (!s || s.terminal) break;
			if (s.id === lastId) { if (++tries > 2) { say(`STUCK on ${s.id}`); return { ok: false, chapter: ch.id, stuck: s.id, seconds: (performance.now() - t0) / 1000 }; } } else { tries = 0; lastId = s.id; say(`${ch.id} › ${s.id}`); }
			if (d.ui.isRemoteOpen()) d.ui.closeRemote(); // a stray open menu pauses the game and would stall every walk
			const h = handlerFor(s.id);
			if (h) await h(s); else { say(`no handler for ${s.id}, trying target`); if (s.target?.room && s.target.room !== 'planet') { await goTo(s.target.room, s.target.anchor || 'RoomCenter'); await interact(); } }
			await waitFor(() => stepId() !== s.id, 6000);
		}
		const ok = !!step()?.terminal; say(`${ch.id} ${ok ? 'complete' : 'incomplete'}`); return { ok, chapter: ch.id, seconds: (performance.now() - t0) / 1000 };
	};
	/** Play every chapter in order (New Game must already have been clicked). */
	auto.run = async () => {
		if (auto.running) return; auto.running = true; auto.abort = false; auto.report = [];
		try {
			for (let i = 0; i < 8 && !auto.abort; i++) {
				const r = await auto.runChapter(); auto.report.push(r); if (!r.ok) break;
				await sleep(2500); const before = d.quest.chapter.id; document.querySelector('#chapter button')?.click(); await sleep(1500);
				if (d.quest.chapter.id === before) { say('no next chapter'); break; }
				press('Tab'); await sleep(600); const remote = d.ui.isRemoteOpen(); if (remote) press('Tab'); auto.report.at(-1).remoteAfterHandoff = remote; await sleep(600);
			}
			say(`done: ${auto.report.map((r) => `${r.chapter} ${r.ok ? 'ok' : 'FAIL'} ${r.seconds.toFixed(0)}s`).join(' · ')}`);
		} catch (e) { say(`error: ${e.message}`); } finally { auto.running = false; d.input.keys.clear(); }
	};
	return auto;
};
