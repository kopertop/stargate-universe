/**
 * Pause menu overlay.
 *
 * Shown when the player presses Escape (or the browser exits fullscreen).
 * Pauses the game loop while visible and restores focus on resume.
 *
 * Display-only: never owns game state — emits resume/quit/settings via
 * caller-supplied callbacks.
 */

export interface PauseMenuOptions {
	onResume: () => void;
	onQuit?: () => void;
	onSettings?: () => void;
}

export interface PauseMenuHandle {
	show: () => void;
	hide: () => void;
	isVisible: () => boolean;
	dispose: () => void;
}

const STYLE_ID = "sgu-pause-menu-style";

const STYLE = `
.sgu-pause-overlay {
	position: fixed;
	inset: 0;
	display: none;
	align-items: center;
	justify-content: center;
	background: rgba(5, 8, 14, 0.78);
	backdrop-filter: blur(6px);
	z-index: 1000;
	font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
	color: #e8eef5;
	user-select: none;
}
.sgu-pause-overlay.is-visible { display: flex; }
.sgu-pause-card {
	min-width: 280px;
	padding: 28px 36px;
	background: rgba(15, 22, 36, 0.85);
	border: 1px solid rgba(120, 180, 255, 0.25);
	border-radius: 8px;
	box-shadow: 0 12px 40px rgba(0, 0, 0, 0.6);
	display: flex;
	flex-direction: column;
	gap: 14px;
	align-items: stretch;
}
.sgu-pause-title {
	font-size: 22px;
	font-weight: 700;
	letter-spacing: 2px;
	text-transform: uppercase;
	text-align: center;
	margin-bottom: 4px;
	color: #c8d6ee;
}
.sgu-pause-btn {
	padding: 10px 18px;
	background: rgba(40, 60, 100, 0.55);
	border: 1px solid rgba(140, 180, 240, 0.35);
	border-radius: 4px;
	color: #f0f6ff;
	font-size: 15px;
	font-weight: 600;
	letter-spacing: 0.5px;
	cursor: pointer;
	transition: background 120ms ease;
}
.sgu-pause-btn:hover, .sgu-pause-btn:focus-visible {
	background: rgba(70, 110, 170, 0.75);
	outline: none;
}
.sgu-pause-hint {
	font-size: 12px;
	opacity: 0.6;
	text-align: center;
	margin-top: 6px;
}
`;

const ensureStyle = (): void => {
	if (document.getElementById(STYLE_ID)) return;
	const style = document.createElement("style");
	style.id = STYLE_ID;
	style.textContent = STYLE;
	document.head.appendChild(style);
};

export const mountPauseMenu = (options: PauseMenuOptions): PauseMenuHandle => {
	ensureStyle();

	const overlay = document.createElement("div");
	overlay.className = "sgu-pause-overlay";

	const card = document.createElement("div");
	card.className = "sgu-pause-card";

	const title = document.createElement("div");
	title.className = "sgu-pause-title";
	title.textContent = "Paused";
	card.appendChild(title);

	const resumeBtn = document.createElement("button");
	resumeBtn.className = "sgu-pause-btn";
	resumeBtn.textContent = "Resume";
	resumeBtn.addEventListener("click", () => options.onResume());
	card.appendChild(resumeBtn);

	if (options.onSettings) {
		const settingsBtn = document.createElement("button");
		settingsBtn.className = "sgu-pause-btn";
		settingsBtn.textContent = "Settings";
		settingsBtn.addEventListener("click", () => options.onSettings?.());
		card.appendChild(settingsBtn);
	}

	if (options.onQuit) {
		const quitBtn = document.createElement("button");
		quitBtn.className = "sgu-pause-btn";
		quitBtn.textContent = "Quit to Menu";
		quitBtn.addEventListener("click", () => options.onQuit?.());
		card.appendChild(quitBtn);
	}

	const hint = document.createElement("div");
	hint.className = "sgu-pause-hint";
	hint.textContent = "Press Esc to resume";
	card.appendChild(hint);

	overlay.appendChild(card);
	document.body.appendChild(overlay);

	let visible = false;

	return {
		show: () => {
			visible = true;
			overlay.classList.add("is-visible");
			resumeBtn.focus();
		},
		hide: () => {
			visible = false;
			overlay.classList.remove("is-visible");
		},
		isVisible: () => visible,
		dispose: () => {
			overlay.remove();
		},
	};
};
