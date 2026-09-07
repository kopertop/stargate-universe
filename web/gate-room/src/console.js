// Hidden developer console: ` (backquote) toggles a command line over the game. Commands are plain functions that return
// a string to print. Typing goes to the console only — input.js ignores keys whose target is an <input>.
export const createConsole = (commands) => {
	const el = document.createElement('div'); el.id = 'devcon'; el.hidden = true;
	el.innerHTML = `<style>#devcon{position:fixed;left:0;right:0;top:0;z-index:50;background:rgba(6,8,12,.92);border-bottom:1px solid #8c7038;font:13px monospace;color:#e6d6a8;padding:8px 12px}
		#devcon pre{margin:0 0 6px;white-space:pre-wrap;max-height:30vh;overflow:auto;color:#cbb}#devcon .line{display:flex;gap:8px;align-items:center;color:#d4a852}
		#devcon input{flex:1;background:transparent;border:0;outline:0;color:#f5ebcc;font:13px monospace}</style><pre></pre><div class="line">&gt;<input spellcheck="false" autocomplete="off" placeholder="type help"></div>`;
	document.body.appendChild(el);
	const out = el.querySelector('pre'), inp = el.querySelector('input'), history = []; let hi = 0;
	const print = (s) => { out.textContent = `${out.textContent}${s}\n`.split('\n').slice(-12).join('\n'); out.scrollTop = out.scrollHeight; };
	const run = (line) => {
		const [name, ...args] = line.trim().split(/\s+/); if (!name) return;
		print(`> ${line}`); const fn = commands[name];
		if (!fn) { print(`unknown command "${name}" — try help`); return; }
		try { const r = fn(...args); if (r != null) print(String(r)); } catch (e) { print(`error: ${e.message}`); }
	};
	const toggle = (on = el.hidden) => { el.hidden = !on; if (on) { inp.value = ''; inp.focus(); if (document.pointerLockElement) document.exitPointerLock(); } else inp.blur(); };
	window.addEventListener('keydown', (e) => { if (e.code === 'Backquote') { e.preventDefault(); toggle(); } }, true);
	inp.addEventListener('keydown', (e) => {
		e.stopPropagation();
		if (e.key === 'Enter') { const v = inp.value; history.push(v); hi = history.length; inp.value = ''; run(v); }
		else if (e.key === 'Escape') toggle(false);
		else if (e.key === 'ArrowUp') { hi = Math.max(0, hi - 1); inp.value = history[hi] ?? ''; }
		else if (e.key === 'ArrowDown') { hi = Math.min(history.length, hi + 1); inp.value = history[hi] ?? ''; }
	});
	commands.help ??= () => `commands: ${Object.keys(commands).join(', ')}`;
	return { toggle, print, run, isOpen: () => !el.hidden };
};
