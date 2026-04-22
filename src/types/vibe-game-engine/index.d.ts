/**
 * Minimal type stub for @kopertop/vibe-game-engine.
 * Provides the types used by stargate-universe without requiring
 * the full engine source to be present (engine lives in a sibling workspace).
 */

declare module "@kopertop/vibe-game-engine" {
	// ── PWA / service worker ────────────────────────────────────────────────

	interface InstallPrompt {
		readonly prompt: () => Promise<void>;
		readonly userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
	}

	interface ServiceWorkerRegistration {
		waiting?: ServiceWorker;
	}

	interface SWUpdateCallbacks {
		onUpdateReady: (registration: ServiceWorkerRegistration) => void;
		onError: (err: { message: string }) => void;
	}

	export function createInstallPrompt(): InstallPrompt;
	export function registerServiceWorker(
		opts: { url: string; scope: string } & SWUpdateCallbacks,
	): Promise<void>;

	// ── Dialogue system ─────────────────────────────────────────────────────

	export interface DialoguePanelEventBus {
		on(event: string, handler: (data: unknown) => void): void;
		emit(event: string, data?: unknown): void;
	}

	export interface DialoguePanelOptions {
		style?: string;
		optionHints?: string[];
	}

	export class DialoguePanel {
		mount(child: unknown): void;
		dispose(): void;
	}

	export function createDialoguePanel(
		bus: DialoguePanelEventBus,
		options?: DialoguePanelOptions,
	): DialoguePanel;

	// ── Dialogue helpers (re-exported from engine) ───────────────────────────

	export interface DialogueTree {
		id: string;
		startNodeId: string;
		nodes: DialogueNode[];
	}

	export interface DialogueNode {
		id: string;
		speaker?: string;
		text?: string;
		options?: DialogueOption[];
		nextNodeId?: string | null;
		condition?: (state: DialogueState) => boolean;
		onSelect?: (state: DialogueState) => void;
		[key: string]: unknown;
	}

	export interface DialogueOption {
		id: string;
		label: string;
		nextNodeId?: string | null;
		condition?: (state: DialogueState) => boolean;
		onSelect?: (state: DialogueState) => void;
	}

	export interface DialogueState {
		current: DialogueNode;
		options: DialogueOption[];
		history: string[];
		flags: Record<string, boolean>;
		affinityDelta: number;
	}

	export function getNode(tree: DialogueTree, id: string): DialogueNode | undefined;
	export function getVisibleOptions(state: DialogueState): DialogueOption[];
	export function selectOption(state: DialogueState, index: number): void;
	export function createDialogueState(tree: DialogueTree): DialogueState;

	export interface ManagerEvents {
		"dialogue:advance": { nodeId: string; choice?: number };
		"dialogue:end": { id: string };
	}

	export interface DialogueManager {
		registerTree(tree: DialogueTree): void;
		startDialogue(id: string): void;
		serialize(): unknown;
		deserialize(data: unknown): void;
		dispose(): void;
	}

	export function createDialogueManager(bus: unknown): DialogueManager;

	// ── HUD ────────────────────────────────────────────────────────────────

	export interface HudOptions {
		style?: string;
	}

	export class Hud {
		mount(child: unknown): void;
		update(camera: unknown, delta: number): void;
		unmount(): void;
		dispose(): void;
	}

	export function createHud(parent: HTMLElement): Hud;

	// ── Compass ────────────────────────────────────────────────────────────

	export interface CompassOptions {
		position?: string;
		style?: string;
	}

	export function createCompass(options?: CompassOptions): unknown;

	// ── Neural locomotion (gate-room) ──────────────────────────────────────

	export const SEQ_LENGTH: number;
	export const SEQ_WINDOW: number;
	export const BONE_COUNT: number;

	export interface SequenceOutput {
		rootDelta: [number, number, number];
		rotations: Float32Array;
	}

	export class NeuralLocomotionController {
		get isLoaded(): boolean;
		load(weightsUrl: string, manifestUrl?: string): Promise<void>;
		predict(input: Float32Array): SequenceOutput;
		sampleAt(output: SequenceOutput, phase: number): SequenceOutput;
	}

	export interface EncodeInputArgs {
		bonePositions: Float32Array;
		boneForwardAxes: Float32Array;
		boneUpAxes: Float32Array;
		boneVelocities: Float32Array;
		futureRootPositionsXZ: Float32Array;
		futureRootForwardsXZ: Float32Array;
		futureRootVelocitiesXZ: Float32Array;
		guidancePositions: Float32Array;
	}

	export function encodeInput(args: EncodeInputArgs): Float32Array;

	// ── Gamepad ────────────────────────────────────────────────────────────────

	export interface GamepadLike {
		readonly isConnected: boolean;
		getAxis(index: number): number;
		getMovement(): { x: number; y: number };
		getLook(): { x: number; y: number };
	}

	// ── Input ────────────────────────────────────────────────────────────────

	export const DEFAULT_KEY_BINDINGS: Record<string, number>;
	export const DEFAULT_GAMEPAD_BINDINGS: Record<number, number[]>;

	export enum GamepadButton {
		A = 0,
		B = 1,
		X = 2,
		Y = 3,
	}

	export class InputManager {
		static get instance(): InputManager;
		setKeyBindings(bindings: Record<string, number>): void;
		setGamepadBindings(bindings: Record<number, number[]>): void;
		bind(): () => void;
		poll(): void;
		isAction(action: number): boolean;
		isActionJustPressed(action: number): boolean;
		isActionJustReleased(action: number): boolean;
		readonly gamepad: GamepadLike;
	}

	// ── Action enum ──────────────────────────────────────────────────────────

	export enum Action {
		Jump = 1,
		Attack = 2,
		Interact = 3,
		Inventory = 4,
		Map = 5,
		Pause = 6,
		Menu = 7,
		Sprint = 8,
		MenuConfirm = 9,
		MenuBack = 10,
		DPadUp = 11,
		DPadDown = 12,
		MoveForward = 13,
		MoveBackward = 14,
		// Animation lifecycle (used on VRM ActionClip nodes)
		play = 100,
		pause = 101,
		reset = 102,
		fadeIn = 103,
		timeScale = 104,
		setEffectiveWeight = 105,
		isRunning = 106,
		paused = 107,
	}

	// ── Event bus ────────────────────────────────────────────────────────────

	export type EventCallback<T = unknown> = (data: T) => void;
	export function on<T = unknown>(
		event: string,
		handler: EventCallback<T>,
	): () => void;
	export function emit(event: string, data?: unknown): void;

	// ── Quest system ──────────────────────────────────────────────────────────

	export interface QuestType { id: string; [key: string]: unknown }
	export type QuestStatus = "active" | "complete" | "failed";
	export type ObjectiveType = "talk" | "kill" | "collect" | "visit" | "custom";
	export interface QuestObjective {
		id: string;
		type: ObjectiveType;
		description: string;
		completed: boolean;
		progress?: number;
	}
	export type RewardType = unknown;

	export interface QuestManager {
		register(quest: QuestType): void;
		start(id: string): void;
		updateObjective(questId: string, objectiveId: string, progress?: number): void;
		complete(id: string): void;
		fail(id: string): void;
		getStatus(id: string): QuestStatus;
		serialize(): unknown;
	}

	export function createQuestManager(): QuestManager;
	export function isQuestComplete(quest: QuestType): boolean;
	export function getObjective(quest: QuestType, id: string): QuestObjective | undefined;

	// ── NPC system ──────────────────────────────────────────────────────────

	export interface NpcState {
		id: string;
		position: { x: number; y: number; z: number };
		health: number;
		dialogueState?: unknown;
	}

	export interface PatrolWaypoint {
		x: number;
		y: number;
		z: number;
		waitSeconds?: number;
	}

	export interface NpcBehaviorConfig {
		patrol?: PatrolWaypoint[];
		aggressive?: boolean;
		dialogueTreeId?: string;
	}

	export interface NpcDefinition {
		id: string;
		vrmUrl: string;
		name: string;
		behavior: NpcBehaviorConfig;
	}

	export interface NpcInstance {
		id: string;
		defId: string;
		state: NpcState;
	}

	export interface NpcManager {
		spawn(def: NpcDefinition): NpcInstance;
		despawn(id: string): void;
		update(delta: number): void;
		get(id: string): NpcInstance | undefined;
	}

	export function createNpcManager(dialogueManager: DialogueManager): NpcManager;

	// ── Save data types ─────────────────────────────────────────────────────

	export interface QuestSaveData {
		id: string;
		stage: number;
		objectives: Array<{ id: string; completed: boolean }>;
	}
	export interface DialogueSaveData {
		id: string;
		started: boolean;
	}
}
