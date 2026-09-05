// RPG layer: level/XP, health/oxygen, inventory, equipment slots, talents. Item catalog = repo data/items.json + web-only additions.
import { ASSETS } from './assets.js';
const listeners = new Set();
export const onRpgChange = (fn) => listeners.add(fn);
const emit = () => { for (const fn of listeners) fn(rpg); };

export const ITEMS = {}; // id → { id, name, category, slot?, stackable, description, stats? }
const WEB_ITEMS = [
	{ id: 'shovel', name: 'Field Shovel', category: 'equipment', slot: 'tool', stackable: false, description: 'Folding entrenching tool. Required to dig lime or cut ice.', stats: { mine: 1 } },
	{ id: 'refined_lime', name: 'Refined Lime', category: 'resource', stackable: true, description: 'Calcium hydroxide, ready for the CO2 scrubber bed.' },
	{ id: 'ice', name: 'Ice', category: 'resource', stackable: true, description: 'Frozen water cut from the surface.' },
	{ id: 'radio', name: 'Crew Radio', category: 'tool', stackable: false, description: 'Short-range crew radio.' },
];
const GEAR_STATS = { field_backpack: { carry: 6 }, tac_vest: { hp: 20 }, marine_helmet: { hp: 10 }, recon_cap: { speed: 0.05 }, combat_boots: { speed: 0.08 } };

export const TALENTS = [
	{ id: 'engineer', name: 'Engineer', desc: 'Dig / cut 30% faster per rank.', max: 3, stat: 'mine', per: 0.3 },
	{ id: 'pathfinder', name: 'Pathfinder', desc: 'Move 8% faster per rank.', max: 3, stat: 'speed', per: 0.08 },
	{ id: 'pack_mule', name: 'Pack Mule', desc: '+2 carry capacity per rank.', max: 3, stat: 'carry', per: 2 },
];

export const rpg = {
	level: 1, xp: 0, hp: 100, o2: 100, talentPoints: 0,
	inventory: {},            // id → count
	equipment: { head: null, torso: null, back: null, legs: null, tool: null },
	talents: { engineer: 0, pathfinder: 0, pack_mule: 0 },
	log: [],                  // chat/log panel entries
};
export const xpToNext = (lvl) => 100 * lvl;

export const loadItems = async () => {
	try { for (const it of await (await fetch(`${ASSETS}data/items.json`)).json()) ITEMS[it.id] = it; } catch { /* repo data optional */ }
	for (const it of WEB_ITEMS) ITEMS[it.id] = it;
	if (ITEMS.field_backpack) ITEMS.field_backpack.description ??= 'Roomy canvas pack. +6 carry.';
};

export const addLog = (text) => { rpg.log.push(text); if (rpg.log.length > 80) rpg.log.shift(); emit(); };
export const count = (id) => rpg.inventory[id] ?? 0;
export const addItem = (id, n = 1) => { rpg.inventory[id] = count(id) + n; addLog(`Received: ${ITEMS[id]?.name ?? id}${n > 1 ? ` ×${n}` : ''}`); emit(); };
export const removeItem = (id, n = 1) => { const c = count(id) - n; if (c <= 0) delete rpg.inventory[id]; else rpg.inventory[id] = c; emit(); };
export const equip = (id) => {
	const it = ITEMS[id]; if (!it?.slot) return false;
	const prev = rpg.equipment[it.slot]; if (prev) rpg.inventory[prev] = count(prev) + 1;
	rpg.equipment[it.slot] = id; if (count(id) > 0) removeItem(id, 1);
	rpg.hp = Math.min(rpg.hp, stats().maxHp); emit(); return true;
};
export const unequip = (slot) => { const id = rpg.equipment[slot]; if (!id) return; rpg.equipment[slot] = null; rpg.inventory[id] = count(id) + 1; emit(); };
export const spendTalent = (id) => {
	const t = TALENTS.find((x) => x.id === id); if (!t || rpg.talentPoints <= 0 || rpg.talents[id] >= t.max) return false;
	rpg.talents[id]++; rpg.talentPoints--; addLog(`Talent: ${t.name} rank ${rpg.talents[id]}`); emit(); return true;
};
/** Derived stats from level, gear and talents. */
export const stats = () => {
	let carry = 2, mine = 0, speed = 1, maxHp = 100 + (rpg.level - 1) * 5;
	for (const id of Object.values(rpg.equipment)) { const g = GEAR_STATS[id]; if (g) { carry += g.carry ?? 0; maxHp += g.hp ?? 0; speed += g.speed ?? 0; } if (ITEMS[id]?.stats?.mine) mine += ITEMS[id].stats.mine; }
	for (const t of TALENTS) { const r = rpg.talents[t.id]; if (t.stat === 'carry') carry += r * t.per; if (t.stat === 'mine') mine *= 1 + r * t.per; if (t.stat === 'speed') speed += r * t.per; }
	return { carry, mineSpeed: mine, speed, maxHp, canMine: mine > 0 };
};
/** Resource weight currently carried (stackable resources only). */
export const carried = () => Object.entries(rpg.inventory).reduce((n, [id, c]) => n + (ITEMS[id]?.category === 'resource' ? c : 0), 0);
export const grantXp = (n) => {
	rpg.xp += n; let ups = 0;
	while (rpg.xp >= xpToNext(rpg.level)) { rpg.xp -= xpToNext(rpg.level); rpg.level++; rpg.talentPoints++; ups++; }
	addLog(`+${n} XP${ups ? ` — Level ${rpg.level}! +${ups} talent point` : ''}`); rpg.hp = stats().maxHp; emit(); return ups;
};
export const save = () => { try { localStorage.setItem('sgu.rpg', JSON.stringify({ ...rpg, log: rpg.log.slice(-30) })); } catch {} };
export const load = () => { try { const s = JSON.parse(localStorage.getItem('sgu.rpg') || 'null'); if (s) Object.assign(rpg, s); } catch {} };
