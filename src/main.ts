import "./style.css";
import { createGameApp } from "./game/app";
import { initialSceneId, scenes } from "./scenes";
import { on } from "./systems/event-bus";

const root = document.querySelector<HTMLDivElement>("#app");

if (!root) {
	throw new Error("Missing #app root.");
}

// Create loading screen
const loading = document.createElement("div");
loading.className = "loading-screen";

const title = document.createElement("div");
title.className = "loading-title";
title.textContent = "Stargate Universe";
loading.appendChild(title);

const subtitle = document.createElement("div");
subtitle.className = "loading-subtitle";
subtitle.textContent = "Boarding Destiny";
loading.appendChild(subtitle);

const barTrack = document.createElement("div");
barTrack.className = "loading-bar-track";
const barFill = document.createElement("div");
barFill.className = "loading-bar-fill";
barTrack.appendChild(barFill);
loading.appendChild(barTrack);

document.body.appendChild(loading);

// Dismiss loading screen when the player character model loads
function dismissLoading() {
	if (!loading.parentElement) return;
	loading.classList.add("fade-out");
	setTimeout(() => loading.remove(), 700);
}

const unsubscribe = on("character:model:loaded", () => {
	unsubscribe();
	dismissLoading();
});

// Fallback: dismiss after 10s even if VRM fails to load
setTimeout(dismissLoading, 10000);

const app = await createGameApp({
	initialSceneId,
	root,
	scenes
});

void app.start();
