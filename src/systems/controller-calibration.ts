/**
 * Controller Calibration UI
 *
 * When the engine's GamepadManager detects an unrecognized controller
 * (gamepad.id matches no built-in or saved profile), we prompt the player
 * to press A, B, X, Y on the controller. The engine handles all the
 * physical-index detection — this module is purely the modal UI.
 *
 * Kick off with `installControllerCalibration(getInput())` at app startup.
 * The overlay is created lazily so it costs nothing unless a new controller
 * shows up.
 */
import {
	GamepadButton,
	type InputManager,
} from "@kopertop/vibe-game-engine";

interface CalibrationModal {
	show(gamepadId: string): void;
	hide(): void;
	setPrompt(text: string): void;
	setProgress(step: number, total: number): void;
	dispose(): void;
}

function createModal(): CalibrationModal {
	const backdrop = document.createElement("div");
	backdrop.style.cssText = [
		"position:fixed;inset:0;z-index:200;display:none;",
		"background:#000000cc;backdrop-filter:blur(4px);",
		"align-items:center;justify-content:center;",
		"font-family:'Segoe UI',sans-serif;color:#eee;",
	].join("");

	const panel = document.createElement("div");
	panel.style.cssText = [
		"background:#111827;border:1px solid #d4b96a44;",
		"border-radius:8px;padding:1.5rem 2rem;max-width:30rem;",
		"box-shadow:0 8px 32px #00000088;",
	].join("");

	const heading = document.createElement("div");
	heading.style.cssText = "font-size:1.15rem;font-weight:600;color:#d4b96a;margin-bottom:0.5rem;";
	heading.textContent = "New controller detected";

	const idRow = document.createElement("div");
	idRow.style.cssText = "font-size:0.75rem;color:#9ca3af;margin-bottom:1rem;word-break:break-all;";

	const prompt = document.createElement("div");
	prompt.style.cssText = "font-size:1.1rem;margin-bottom:0.5rem;color:#fff;";

	const hint = document.createElement("div");
	hint.style.cssText = "font-size:0.85rem;color:#9ca3af;margin-bottom:1rem;";
	hint.textContent = "We'll learn your button layout. Press the indicated button, then repeat for the next.";

	const progressRow = document.createElement("div");
	progressRow.style.cssText = "font-size:0.8rem;color:#9ca3af;";

	panel.append(heading, idRow, prompt, hint, progressRow);
	backdrop.appendChild(panel);
	document.body.appendChild(backdrop);

	return {
		show(gamepadId) {
			idRow.textContent = gamepadId;
			backdrop.style.display = "flex";
		},
		hide() { backdrop.style.display = "none"; },
		setPrompt(text) { prompt.textContent = text; },
		setProgress(step, total) { progressRow.textContent = `${step} / ${total}`; },
		dispose() { backdrop.remove(); },
	};
}

// Buttons we probe — A/B/X/Y is enough to detect Nintendo-style swap without
// requiring the player to press every one of the 17 standard buttons.
const CALIBRATION_STEPS: Array<{ logical: GamepadButton; label: string }> = [
	{ logical: GamepadButton.A, label: "A (confirm / bottom face button)" },
	{ logical: GamepadButton.B, label: "B (cancel / right face button)" },
	{ logical: GamepadButton.X, label: "X (left face button)" },
	{ logical: GamepadButton.Y, label: "Y (top face button)" },
];

/**
 * Wire calibration into an InputManager. Call once at app boot after
 * `getInput()` is initialized. Returns a cleanup function.
 */
export function installControllerCalibration(input: InputManager): () => void {
	let modal: CalibrationModal | null = null;
	let calibrating = false;

	const runCalibration = async (gamepadId: string): Promise<void> => {
		if (calibrating) return;
		calibrating = true;
		try {
			const session = input.gamepad.beginCalibration(gamepadId || "Unnamed controller");
			if (!session) {
				console.warn("[calibration] no controller connected when starting session");
				calibrating = false;
				return;
			}

			if (!modal) modal = createModal();
			modal.show(gamepadId);

			for (let i = 0; i < CALIBRATION_STEPS.length; i++) {
				const step = CALIBRATION_STEPS[i];
				modal.setPrompt(`Press ${step.label}`);
				modal.setProgress(i + 1, CALIBRATION_STEPS.length);
				try {
					await session.waitForButton(step.logical);
				} catch (err) {
					console.warn("[calibration] step aborted", err);
					modal.hide();
					session.cancel();
					calibrating = false;
					return;
				}
			}

			const profile = session.finish();
			input.gamepad.saveProfile(profile);

			modal.setPrompt("✓ Saved. You can play now.");
			modal.setProgress(CALIBRATION_STEPS.length, CALIBRATION_STEPS.length);
			setTimeout(() => { modal?.hide(); }, 1200);
		} finally {
			calibrating = false;
		}
	};

	input.gamepad.onUnknownController((id) => {
		// Async, non-blocking — errors logged above.
		void runCalibration(id);
	});

	return () => {
		input.gamepad.onUnknownController(null);
		modal?.dispose();
		modal = null;
	};
}
