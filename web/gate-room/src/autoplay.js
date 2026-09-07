// Demo driver: plays Episode 1 hands-free through the real input path (keys + E), routing between rooms over the door graph
// (ship.route) so it survives layout changes. Usage: ?autoplay then window.__auto.run(); progress in window.__auto.status.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const press = (code) => { window.dispatchEvent(new KeyboardEvent('keydown', { code })); window.dispatchEvent(new KeyboardEvent('keyup', { code })); };

export const createAutoplay = (d) => {
	const auto = { status: 'idle', log: [], running: false, abort: false };
	const say = (s) => { auto.status = s; auto.log.push(`${(performance.now() / 1000).toFixed(1)}s ${s}`); };
	const pos = () => d.player.root.position;
	const ship = () => d.destiny.ship, A = () => d.destiny.anchors;
	/** Walk toward (x,z) via the real key path; camera yaw steers so W moves toward the target. Runs on long legs. */
	const walkTo = async (x, z, { run, tol = 0.7, timeout } = {}) => {
		const dist0 = Math.hypot(x - pos().x, z - pos().z); run ??= dist0 > 10; timeout ??= (dist0 / (run ? 8 : 3.5)) * 1000 + 6000;
		const t0 = performance.now();
		d.input.keys.add('KeyW'); if (run) d.input.keys.add('ShiftLeft');
		let lastD = Infinity, stallT = 0, side = 'KeyD';
		while (!auto.abort && performance.now() - t0 < timeout) {
			const dx = x - pos().x, dz = z - pos().z, dist = Math.hypot(dx, dz); if (dist < tol) break;
			d.cam().yaw = Math.atan2(-dx, -dz);
			if (dist > lastD - 0.02) stallT += 40; else stallT = 0; lastD = Math.min(lastD, dist); // stalled on a prop → sidestep
			if (stallT > 500) { d.input.keys.add(side); await sleep(600); d.input.keys.delete(side); side = side === 'KeyD' ? 'KeyA' : 'KeyD'; stallT = 0; lastD = Infinity; }
			await sleep(40);
		}
		d.input.keys.delete('KeyW'); d.input.keys.delete('ShiftLeft'); d.input.keys.delete('KeyA'); d.input.keys.delete('KeyD');
		await sleep(200);
	};
	/** Route through doors to a room, then to an anchor (or the room centre). Door approach points sit 1.4 m either side. */
	const goTo = async (room, anchor = 'RoomCenter', opts = {}) => {
		const from = ship().roomAt(pos()); const path = from && from !== room ? ship().route(from, room) : [];
		if (path === null) { say(`no route ${from} → ${room}`); return; }
		let cur = from;
		for (const door of path) {
			const next = door.rooms[0] === cur ? door.rooms[1] : door.rooms[0], p = door.g.position, cc = ship().center(cur), nc = ship().center(next);
			const n = door.axis === 'x' ? Math.sign(cc.x - p.x) : Math.sign(cc.z - p.z);
			const before = door.axis === 'x' ? [p.x + n * 1.4, p.z] : [p.x, p.z + n * 1.4], after = door.axis === 'x' ? [p.x - n * 1.4, p.z] : [p.x, p.z - n * 1.4];
			await walkTo(...before, { tol: 0.5 }); await sleep(450); // let the hub unlock + leaves part
			await walkTo(...after, { tol: 0.5, run: false }); void nc; cur = next;
		}
		const t = A()[`${room}:${anchor}`] ?? ship().center(room); await walkTo(t.x, t.z, opts);
	};
	const face = (x, z) => { const dx = x - pos().x, dz = z - pos().z; d.player.root.rotation.y = Math.atan2(dx, dz); };
	const faceAnchor = (key) => { const a = A()[key]; face(a.x, a.z); };
	const interact = async (settle = 2200) => { await sleep(150); press('KeyE'); await sleep(settle); };
	const waitFor = async (pred, timeout = 20000) => { const t0 = performance.now(); while (!pred() && performance.now() - t0 < timeout && !auto.abort) await sleep(80); return pred(); };
	const holdE = async (until, timeout = 12000) => { d.input.keys.add('KeyE'); await waitFor(until, timeout); d.input.keys.delete('KeyE'); await sleep(250); };
	const step = () => d.quest.step()?.id;
	const gz = () => d.destiny.gate.position.z;

	auto.run = async () => {
		if (auto.running) return; auto.running = true; auto.abort = false;
		try {
			document.querySelector('#chapter button')?.click(); say('begin: cold open arrival');
			await waitFor(() => !d.travel(), 8000); await sleep(800);
			say('power relay'); await goTo('gate_room', 'PowerRelay'); face(pos().x, pos().z + 2); await interact();
			say('to the control room'); await goTo('control_interface_room', 'ControlConsole'); face(pos().x, pos().z + 2); await interact(2600); await sleep(1200); if (d.ui.isRemoteOpen()) { press('Tab'); await sleep(600); }
			say('seal the breach'); await goTo('south_spur', 'SealLever'); face(A()['south_spur:SealLever'].x + 1, pos().z); await interact();
			say('explore: kino room'); await goTo('eli_quarters', 'KinoPedestal'); face(pos().x, pos().z - 2); await interact(1600);
			await goTo('eli_quarters', 'Locker'); face(pos().x + 2, pos().z); await interact(1800);
			say('life support: scrubber'); await goTo('south_corridor', 'Scrubber'); face(pos().x + 2, pos().z); await interact();
			say('back to the gate room: FTL drop'); await goTo('gate_room', 'RoomCenter'); await waitFor(() => d.destiny.gate.userData.active, 15000); await sleep(600);
			say('kino scout'); await walkTo(0, gz() + 9, { tol: 0.4, run: false }); face(0, gz()); await sleep(300); press('KeyK'); await sleep(500); d.input.keys.add('KeyW'); await waitFor(() => d.kino() === 'planet', 12000); d.input.keys.delete('KeyW'); await sleep(1200); d.input.keys.add('KeyW'); await sleep(1500); d.input.keys.delete('KeyW');
			await waitFor(() => step() === 'gear_up', 8000); await sleep(1500); press('KeyE'); await sleep(600);
			say('gear up'); await goTo('gate_room', 'SupplyCrate'); face(pos().x, pos().z + 2); await interact(1900);
			say('through the gate'); await walkTo(0, gz() + 8, { run: true, tol: 1.0 }); await walkTo(0, gz() + 0.7, { tol: 0.35, timeout: 8000, run: false });
			await waitFor(() => d.world.name === 'planet' && !d.travel(), 15000); await sleep(600);
			say('dig lime'); for (let i = 0; i < 4 && (d.rpg.inventory.lime ?? 0) < 5; i++) {
				const n = d.planet.nodes.find((n) => !n.done); if (!n) break;
				await walkTo(n.x, n.z, { run: true, tol: 1.4, timeout: 25000 }); face(n.x, n.z);
				for (let k = 0; k < 2 && (d.rpg.inventory.lime ?? 0) < 5 && !n.done; k++) { const before = d.rpg.inventory.lime ?? 0; await holdE(() => (d.rpg.inventory.lime ?? 0) > before, 9000); }
			}
			say('dial home'); await walkTo(0, 6, { run: true, tol: 1.2, timeout: 30000 }); face(0, 0); press('Tab'); await sleep(900);
			document.querySelector('#remote [data-tab="gate"]')?.click(); await sleep(900); document.querySelector('#remote [data-dial="destiny"]')?.click();
			await waitFor(() => d.planet.gate.userData.active, 14000); await sleep(800);
			await walkTo(0, 2.6, { tol: 0.5, run: false }); await walkTo(0, 0.4, { tol: 0.3, timeout: 5000, run: false });
			await waitFor(() => d.world.name === 'destiny' && !d.travel(), 15000); await sleep(600);
			say('give lime to Brody'); await goTo('gate_room', 'Brody'); faceAnchor('gate_room:Brody'); await interact(1500); await waitFor(() => step() === 'repair_scrubber', 9000);
			say('repair the scrubber'); await goTo('south_corridor', 'Scrubber'); face(pos().x + 2, pos().z); await interact(4500);
			await waitFor(() => step() === 'complete', 8000); say('episode complete'); await sleep(2500);
			document.querySelector('#chapter button')?.click(); await sleep(1500); say(`next chapter: ${d.quest.chapter.id}`);
			press('Tab'); await sleep(600); say(`remote after hand-off: ${d.ui.isRemoteOpen() ? 'opens' : 'BLOCKED'}`); if (d.ui.isRemoteOpen()) press('Tab');
		} catch (e) { say(`error: ${e.message}`); } finally { auto.running = false; d.input.keys.clear(); }
	};
	return auto;
};
