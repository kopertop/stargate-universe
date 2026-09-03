// Demo driver: plays Episode 1 hands-free at human pace using the real input path (keys + E), for recordings and smoke runs.
// Usage: load the page with ?autoplay (or call window.__auto.run() from the console). Reports progress in window.__auto.status.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const press = (code) => { window.dispatchEvent(new KeyboardEvent('keydown', { code })); window.dispatchEvent(new KeyboardEvent('keyup', { code })); };

export const createAutoplay = (d) => {
	const auto = { status: 'idle', log: [], running: false, abort: false };
	const say = (s) => { auto.status = s; auto.log.push(`${(performance.now() / 1000).toFixed(1)}s ${s}`); };
	const pos = () => d.player.root.position;
	/** Walk toward (x,z) via the real key path; camera yaw steers so W moves toward the target. */
	const walkTo = async (x, z, { run = false, tol = 0.7, timeout = 20000 } = {}) => {
		const t0 = performance.now();
		d.input.keys.add('KeyW'); if (run) d.input.keys.add('ShiftLeft');
		let lastD = Infinity, stallT = 0, side = 'KeyD';
		while (!auto.abort && performance.now() - t0 < timeout) {
			const dx = x - pos().x, dz = z - pos().z, dist = Math.hypot(dx, dz); if (dist < tol) break;
			d.cam().yaw = Math.atan2(-dx, -dz);
			// no pathfinding: if we stop closing distance (rock / pillar), sidestep for a moment, alternating sides
			if (dist > lastD - 0.02) stallT += 40; else stallT = 0; lastD = Math.min(lastD, dist);
			if (stallT > 500) { d.input.keys.add(side); await sleep(700); d.input.keys.delete(side); side = side === 'KeyD' ? 'KeyA' : 'KeyD'; stallT = 0; lastD = Infinity; }
			await sleep(40);
		}
		d.input.keys.delete('KeyW'); d.input.keys.delete('ShiftLeft'); d.input.keys.delete('KeyA'); d.input.keys.delete('KeyD');
		await sleep(250);
	};
	const face = (x, z) => { const dx = x - pos().x, dz = z - pos().z; d.player.root.rotation.y = Math.atan2(dx, dz); };
	const interact = async (x, z, settle = 2200) => { face(x, z); await sleep(200); press('KeyE'); await sleep(settle); };
	const waitFor = async (pred, timeout = 20000) => { const t0 = performance.now(); while (!pred() && performance.now() - t0 < timeout && !auto.abort) await sleep(80); return pred(); };
	const holdE = async (until, timeout = 12000) => { d.input.keys.add('KeyE'); await waitFor(until, timeout); d.input.keys.delete('KeyE'); await sleep(250); };
	const step = () => d.quest.step()?.id;

	auto.run = async () => {
		if (auto.running) return; auto.running = true; auto.abort = false;
		try {
			document.querySelector('#chapter button')?.click(); say('begin: cold open arrival');
			await waitFor(() => !d.travel(), 8000); await sleep(800);
			say('power relay'); await walkTo(3.2, 12.4); await interact(3.2, 13.6);
			say('to the control room'); await walkTo(0, 12.8); await walkTo(0, 20); await walkTo(0, 30); await walkTo(0, 33.3);
			await interact(0, 35, 2600); await sleep(1200); if (d.ui.isRemoteOpen()) { press('Tab'); await sleep(600); }
			say('seal the breach'); await walkTo(0, 28.8); await walkTo(0, 20.75); await walkTo(-1.0, 20.75); await walkTo(-5, 20.75); await walkTo(-8.4, 22.5); await interact(-9.35, 22.7);
			say('explore: kino room'); await walkTo(-5, 20.75); await walkTo(0.4, 20.75); await walkTo(3, 20.75); await walkTo(6.4, 20.75); await interact(7.5, 20.75, 1600);
			await walkTo(8.3, 19.4); await interact(8.9, 18.2, 1800);
			say('life support: scrubber'); await walkTo(3, 20.75); await walkTo(0, 20.75); await walkTo(-5, 20.75); await walkTo(-7.9, 19.2); await interact(-9.1, 19.2);
			say('back to the gate room: FTL drop'); await walkTo(-5, 20.75); await walkTo(0, 20.75); await walkTo(0, 13); await walkTo(0, 6); await waitFor(() => d.destiny.gate.userData.active, 15000); await sleep(600);
			say('kino scout'); face(0, -11); press('KeyK'); await sleep(500); d.input.keys.add('KeyW'); await waitFor(() => d.kino() === 'planet', 9000); d.input.keys.delete('KeyW'); await sleep(1200); d.input.keys.add('KeyW'); await sleep(1500); d.input.keys.delete('KeyW');
			await waitFor(() => step() === 'gear_up', 8000); await sleep(1500); press('KeyE'); await sleep(600);
			say('gear up'); await walkTo(-2.5, 8.5); await walkTo(-4.6, 9.2); await interact(-4.6, 10.5, 1900);
			say('through the gate'); await walkTo(-1.5, 9); await walkTo(0, 0, { run: true, tol: 1.0 }); await walkTo(0, -6, { run: true, tol: 1.0 }); await walkTo(0, -10.3, { tol: 0.35, timeout: 6000 });
			await waitFor(() => d.world.name === 'planet' && !d.travel(), 15000); await sleep(600);
			say('dig lime'); for (let i = 0; i < 4 && (d.rpg.inventory.lime ?? 0) < 5; i++) {
				const n = d.planet.nodes.find((n) => !n.done); if (!n) break;
				await walkTo(n.x, n.z, { run: true, tol: 1.4, timeout: 25000 }); face(n.x, n.z);
				for (let k = 0; k < 2 && (d.rpg.inventory.lime ?? 0) < 5 && !n.done; k++) { const before = d.rpg.inventory.lime ?? 0; await holdE(() => (d.rpg.inventory.lime ?? 0) > before, 9000); }
			}
			say('dial home'); await walkTo(0, 6, { run: true, tol: 1.2, timeout: 30000 }); face(0, 0); press('Tab'); await sleep(900);
			document.querySelector('#remote [data-tab="gate"]')?.click(); await sleep(900); document.querySelector('#remote [data-dial="destiny"]')?.click();
			await waitFor(() => d.planet.gate.userData.active, 14000); await sleep(800);
			await walkTo(0, 2.6, { tol: 0.5 }); await walkTo(0, 0.4, { tol: 0.3, timeout: 5000 });
			await waitFor(() => d.world.name === 'destiny' && !d.travel(), 15000); await sleep(600);
			say('give lime to Brody'); await walkTo(4.2, 10.6); await interact(4.2, 8.5, 1500); await waitFor(() => step() === 'repair_scrubber', 9000);
			say('repair the scrubber'); await walkTo(0, 12.8); await walkTo(0, 20.75); await walkTo(-5, 20.75); await walkTo(-7.9, 19.2); await interact(-9.1, 19.2, 4500);
			await waitFor(() => step() === 'complete', 8000); say('episode complete'); await sleep(2500);
			document.querySelector('#chapter button')?.click(); await sleep(1500); say(`next chapter: ${d.quest.chapter.id}`);
		} catch (e) { say(`error: ${e.message}`); } finally { auto.running = false; d.input.keys.clear(); }
	};
	return auto;
};
