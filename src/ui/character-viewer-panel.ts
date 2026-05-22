/**
 * Character Viewer Panel — debug UI for the character-viewer scene.
 *
 * Lists crew from manifest.json and available VRMA clips; emits selection events.
 */
import type { CrewManifestEntry } from "../characters/character-loader";
import type { ResolvedVrmaCatalogEntry } from "../animations/vrma-catalog";
import "./styles/character-viewer.scss";

export type AnimationCatalogEntry = ResolvedVrmaCatalogEntry;

export type CharacterViewerPanelHandle = {
	dispose: () => void;
	setActiveCharacter: (id: string) => void;
	setActiveAnimation: (id: string | null) => void;
	setStatus: (message: string, isError?: boolean) => void;
	setCharacterLoading: (id: string, loading: boolean) => void;
	setCharacterError: (id: string, message: string) => void;
};

export type CharacterViewerPanelOptions = {
	readonly characters: readonly CrewManifestEntry[];
	readonly animations: readonly AnimationCatalogEntry[];
	readonly onSelectCharacter: (entry: CrewManifestEntry) => void;
	readonly onSelectAnimation: (entry: AnimationCatalogEntry) => void;
};

const el = <K extends keyof HTMLElementTagNameMap>(
	tag: K,
	className?: string,
	text?: string,
): HTMLElementTagNameMap[K] => {
	const node = document.createElement(tag);
	if (className) node.className = className;
	if (text !== undefined) node.textContent = text;
	return node;
};

export const mountCharacterViewerPanel = (
	options: CharacterViewerPanelOptions,
): CharacterViewerPanelHandle => {
	const root = el("div", "cv-panel");
	const characterButtons = new Map<string, HTMLButtonElement>();
	const animationButtons = new Map<string, HTMLButtonElement>();
	const animationEntries = new Map<string, AnimationCatalogEntry>();

	// Left sidebar — character roster
	const left = el("div", "cv-sidebar cv-sidebar-left");
	const leftHeader = el("div", "cv-header");
	leftHeader.appendChild(el("h1", "cv-title", "VRM Characters"));
	leftHeader.appendChild(el(
		"p",
		"cv-subtitle",
		`${options.characters.length} crew models from manifest.json`,
	));
	const characterList = el("div", "cv-list");
	const characterStatus = el("div", "cv-status", "Select a character to preview.");
	left.append(leftHeader, characterList, characterStatus);

	for (const entry of options.characters) {
		const button = el("button", "cv-item");
		button.type = "button";
		button.appendChild(el("span", "cv-item-name", entry.name));
		button.appendChild(el(
			"span",
			"cv-item-meta",
			`${entry.id} · ${entry.gender} · ${entry.role}${entry.isPlayer ? " · player" : ""}`,
		));
		if (entry.notes) {
			button.appendChild(el("span", "cv-item-notes", entry.notes));
		}
		button.addEventListener("click", () => options.onSelectCharacter(entry));
		characterList.appendChild(button);
		characterButtons.set(entry.id, button);
	}

	// Right sidebar — animations
	const right = el("div", "cv-sidebar cv-sidebar-right");
	const rightHeader = el("div", "cv-header");
	rightHeader.appendChild(el("h1", "cv-title", "Animations"));
	const animationSubtitle = el(
		"p",
		"cv-subtitle",
		`${options.animations.length} VRMA clips`,
	);
	rightHeader.appendChild(animationSubtitle);

	const animationSearch = el("input", "cv-search") as HTMLInputElement;
	animationSearch.type = "search";
	animationSearch.placeholder = "Filter animations…";
	animationSearch.autocomplete = "off";
	animationSearch.spellcheck = false;
	rightHeader.appendChild(animationSearch);

	const animationList = el("div", "cv-list");
	const animationStatus = el("div", "cv-status", "Load a character, then pick a clip.");
	right.append(rightHeader, animationList, animationStatus);

	const applyAnimationFilter = (query: string): void => {
		const normalized = query.trim().toLowerCase();
		let visible = 0;
		for (const [animId, button] of animationButtons) {
			const entry = animationEntries.get(animId);
			const haystack = `${entry?.label ?? ""} ${entry?.id ?? ""} ${entry?.group ?? ""}`.toLowerCase();
			const show = normalized.length === 0 || haystack.includes(normalized);
			button.hidden = !show;
			if (show) visible++;
		}
		animationSubtitle.textContent = normalized.length === 0
			? `${options.animations.length} VRMA clips`
			: `${visible} of ${options.animations.length} clips`;
	};

	animationSearch.addEventListener("input", () => {
		applyAnimationFilter(animationSearch.value);
	});

	for (const entry of options.animations) {
		animationEntries.set(entry.id, entry);
		const button = el("button", "cv-item");
		button.type = "button";
		button.appendChild(el("span", "cv-item-name", entry.label));
		const meta = entry.group ? `${entry.group} · ${entry.id}` : entry.id;
		button.appendChild(el("span", "cv-item-meta", meta));
		button.addEventListener("click", () => options.onSelectAnimation(entry));
		animationList.appendChild(button);
		animationButtons.set(entry.id, button);
	}

	const hint = el(
		"div",
		"cv-hint",
		"Drag to orbit · Scroll to zoom · ?scene=character-viewer",
	);

	root.append(left, right, hint);
	document.body.appendChild(root);

	return {
		dispose: () => root.remove(),
		setActiveCharacter: (id: string) => {
			for (const [charId, button] of characterButtons) {
				button.classList.toggle("is-active", charId === id);
			}
		},
		setActiveAnimation: (id: string | null) => {
			for (const [animId, button] of animationButtons) {
				button.classList.toggle("is-active", id !== null && animId === id);
			}
		},
		setStatus: (message: string, isError = false) => {
			characterStatus.textContent = message;
			characterStatus.classList.toggle("is-error", isError);
		},
		setCharacterLoading: (id: string, loading: boolean) => {
			const button = characterButtons.get(id);
			if (button) button.classList.toggle("is-loading", loading);
		},
		setCharacterError: (id: string, message: string) => {
			const button = characterButtons.get(id);
			if (!button) return;
			button.classList.add("is-error");
			button.title = message;
		},
	};
};
