// Chapter/quest engine: declarative steps advance when their `complete_when` flag is set. Triggers run on step enter/exit.
export const createQuestEngine = ({ onTrigger, onStep, onChapterComplete, grantXp }) => {
	const eng = { chapters: [], chapter: null, stepIndex: 0, flags: new Set(), done: [] };
	eng.load = async (url) => { eng.chapters = (await (await fetch(url)).json()).chapters; };
	eng.step = () => eng.chapter?.steps[eng.stepIndex] ?? null;
	eng.chapterById = (id) => eng.chapters.find((c) => c.id === id);
	const runTriggers = (list) => { for (const t of list ?? []) onTrigger?.(t, eng); };
	eng.startChapter = (id) => {
		eng.chapter = eng.chapterById(id); eng.stepIndex = 0; eng.flags.clear();
		runTriggers(eng.step()?.on_enter); onStep?.(eng.step(), eng.chapter);
	};
	eng.setFlag = (f) => { if (!f || eng.flags.has(f)) return; eng.flags.add(f); eng.check(); };
	eng.has = (f) => eng.flags.has(f);
	/** Advance through every step whose completion flag is already set. */
	eng.check = () => {
		let guard = 0;
		while (eng.chapter && guard++ < 20) {
			const s = eng.step(); if (!s || s.terminal) break;
			if (!eng.flags.has(s.complete_when)) break;
			runTriggers(s.on_exit); if (s.xp) grantXp?.(s.xp);
			eng.stepIndex++;
			const n = eng.step(); runTriggers(n?.on_enter); onStep?.(n, eng.chapter);
			if (n?.terminal) { eng.done.push(eng.chapter.id); onChapterComplete?.(eng.chapter); }
		}
	};
	eng.nextChapter = () => { const i = eng.chapters.indexOf(eng.chapter); return eng.chapters[i + 1] ?? null; };
	return eng;
};
