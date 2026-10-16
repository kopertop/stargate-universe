// FTL rhythm + story countdown system — extracted from main.js (TD-101).
// Owns the FTL jump window/cooldown cycle and the story countdown deadline system.
// Both are timer-pressure mechanics: the FTL window is a drop-out timer that jumps
// Destiny when it expires; story countdowns are chapter-driven deadlines that knock
// the player out on expiry. The HUD clock is shared between them.
//
// Dependencies are injected via `createFtlSystem(ctx)` so this module stays
// independent of main.js's closure scope.

const FTL_WINDOW = 600;
const FTL_COOLDOWN = 90;
const PLANET_STEPS = ['scout_kino', 'gear_up', 'travel', 'mine', 'dial_home'];

/**
 * @typedef {{
 *   mmss: (s: number) => string,
 *   clockScale: () => number,
 *   quest: any,
 *   ui: any,
 *   oneShot: (buf: any, vol?: number, rate?: number) => void,
 *   buffers: Record<string, any>,
 *   shutdownBuf: any,
 *   setShake: (n: number) => void,
 *   setAlertUntil: (t: number) => void,
 *   knockOut: (cause: string) => void,
 *   recallKino: () => void,
 *   shutdownGate: (w: any) => void,
 *   dialGate: (w: any) => void,
 *   addLog: (msg: string) => void,
 *   urgentAlarm: (dt: number) => void,
 *   getWorld: () => any,
 *   getDestiny: () => any,
 *   getPlanet: () => any,
 *   getTravel: () => any,
 *   getKino: () => any,
 *   knockedOut: () => boolean,
 * }} FtlCtx */

/**
 * @param {FtlCtx} ctx
 */
export function createFtlSystem(ctx) {
	const ftl = { window: 0, cooldown: 0, warned: new Set() };
	let countdown = null;

	const needsPlanet = () => PLANET_STEPS.includes(ctx.quest.step()?.id);

	const openFtlWindow = () => {
		ftl.window = (ctx.quest.chapter?.planet?.window_seconds ?? FTL_WINDOW) * ctx.clockScale();
		ftl.cooldown = 0;
		ftl.warned.clear();
	};

	const ftlJump = () => {
		const kino = ctx.getKino();
		const world = ctx.getWorld();
		const planet = ctx.getPlanet();
		const travel = ctx.getTravel();
		const destiny = ctx.getDestiny();
		if (kino?.active) ctx.recallKino();
		if (world === planet || travel?.to === planet) {
			ctx.ui.subtitle('Scott', 'Eli! Through the gate — NOW!');
			ctx.knockOut('window_closed');
		} else if (destiny.gate.userData.active) {
			ctx.shutdownGate(destiny);
		}
		ctx.setShake(1.2);
		ctx.oneShot(ctx.buffers.ftlDrop, 0.9);
		ctx.addLog('Destiny jumped to FTL');
		ctx.quest.setFlag('ftl_jumped');
		ftl.window = 0;
		ftl.cooldown = FTL_COOLDOWN;
		ftl.warned.clear();
	};

	const ftlRedrop = () => {
		const destiny = ctx.getDestiny();
		ctx.setShake(1.4);
		ctx.oneShot(ctx.buffers.ftlDrop, 0.9);
		ctx.oneShot(ctx.shutdownBuf, 0.5, 0.55);
		ctx.addLog('Destiny dropped out of FTL');
		ctx.setAlertUntil(performance.now() + 12000);
		openFtlWindow();
		setTimeout(() => ctx.dialGate(destiny), 900);
		ctx.oneShot(ctx.buffers.radio, 0.6);
		ctx.ui.subtitle('Brody', 'We have dropped out again — same address is dialing. Whatever you did not finish, finish it.', { radio: true });
	};

	const startCountdown = ({ seconds = 300, label = 'DEADLINE', cause = 'generic' }) => {
		const t = seconds * ctx.clockScale();
		countdown = { t, total: t, label, cause, warned: new Set() };
		ctx.setAlertUntil(performance.now() + 12000);
	};

	const stopCountdown = () => {
		countdown = null;
		ctx.ui.setClock('');
	};

	const tickCountdown = (dt) => {
		if (!countdown) return;
		if (!ctx.knockedOut()) countdown.t = Math.max(0, countdown.t - dt);
		for (const [at, who, line] of [[120, 'Rush', 'Two minutes, Eli. I would very much like to be wrong about the shields.'], [30, 'Scott', 'Thirty seconds! Wherever you are, get it done!']]) {
			if (countdown.t <= at && !countdown.warned.has(at)) {
				countdown.warned.add(at);
				ctx.oneShot(ctx.buffers.radio, 0.6);
				ctx.ui.subtitle(who, line, { radio: true });
				if (at === 30) ctx.setAlertUntil(performance.now() + 30000);
			}
		}
		ctx.ui.setClock(`${countdown.label}  ${ctx.mmss(countdown.t)}`, countdown.t <= 60 ? 'urgent' : '');
		if (countdown.t > 0 && countdown.t <= 60 && !ctx.knockedOut()) ctx.urgentAlarm(dt);
		if (countdown.t === 0) {
			const c = countdown;
			ctx.knockOut(c.cause);
			c.t = c.total;
			c.warned.clear();
			ctx.setShake(1.2);
		}
	};

	const tickFtl = (dt) => {
		const world = ctx.getWorld();
		const destiny = ctx.getDestiny();
		const travel = ctx.getTravel();
		if (ftl.window > 0) {
			ftl.window = Math.max(0, ftl.window - dt);
			for (const [at, who, line] of /** @type {[number,string,string][]} */ ([[120, 'Rush', 'Two minutes on the FTL clock, Eli. The ship does not wait for you.'], [30, 'Scott', 'Thirty seconds! Whatever you are doing, stop and run.']])) {
				if (Number(ftl.window) <= at && !ftl.warned.has(at)) {
					ftl.warned.add(at);
					ctx.oneShot(ctx.buffers.radio, 0.6);
					ctx.ui.subtitle(who, line, { radio: true });
					if (at === 30) ctx.setAlertUntil(performance.now() + 30000);
				}
			}
			if (ftl.window === 0) ftlJump();
			if (!countdown) ctx.ui.setClock(`FTL JUMP  ${ctx.mmss(ftl.window)}`, ftl.window <= 60 ? 'urgent' : '');
			if (!countdown && ftl.window > 0 && ftl.window <= 60) ctx.urgentAlarm(dt);
		} else if (ftl.cooldown > 0) {
			ftl.cooldown = Math.max(0, ftl.cooldown - dt);
			if (ftl.cooldown === 0) {
				if (needsPlanet() && world === destiny && !travel) ftlRedrop();
				else ctx.ui.setClock('');
			} else if (!countdown) {
				ctx.ui.setClock(needsPlanet() ? `IN FTL  ·  NEXT DROP ${ctx.mmss(ftl.cooldown)}` : 'IN FTL', 'cool');
			}
		} else if (!countdown) {
			ctx.ui.setClock('');
		}
	};

	return {
		ftl,
		FTL_WINDOW,
		FTL_COOLDOWN,
		PLANET_STEPS,
		needsPlanet,
		openFtlWindow,
		ftlJump,
		ftlRedrop,
		startCountdown,
		stopCountdown,
		tickCountdown,
		tickFtl,
		get countdown() { return countdown; },
		set countdown(v) { countdown = v; },
	};
}