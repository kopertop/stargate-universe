/// <reference types="vite/client" />
/// <reference lib="es2022" />

export {};

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

	export const DEFAULT_SW_SOURCE: string;

	// ── Manifest generation ────────────────────────────────────────────────

	export function generateManifest(opts: {
		short_name: string;
		name: string;
		start_url: string;
		display: string;
		background_color: string;
		theme_color: string;
		icons: Array<{ src: string; sizes: string; type: string; purpose?: string }>;
	}): string;

	// ── Input ───────────────────────────────────────────────────────────────

	export const DEFAULT_KEY_BINDINGS: Record<string, number>;
	export const DEFAULT_GAMEPAD_BINDINGS: Partial<Record<number, number[]>>;

	export class InputManager {
		bind(): () => void;
		setKeyBindings(bindings: Record<string, number>): void;
		setGamepadBindings(bindings: Partial<Record<number, number[]>>): void;
		poll(): void;
		isAction(action: number): boolean;
		isActionJustPressed(action: number): boolean;
		isActionJustReleased(action: number): boolean;
		readonly gamepad: GamepadLike;
	}

	export interface GamepadLike {
		readonly isConnected: boolean;
		getAxis(index: number): number;
		getMovement(): { x: number; z: number };
		getLook(): { x: number; y: number };
	}

	// ── Cross-cutting event bus ────────────────────────────────────────────

	export function on<T = unknown>(event: string, handler: (data: T) => void): () => void;
	export function emit(event: string, data?: unknown): void;

	// ── Dialogue helpers ───────────────────────────────────────────────────

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
		acceptedQuests: string[];
	}

	export function getNode(tree: DialogueTree, id: string): DialogueNode | undefined;
	export function getVisibleOptions(state: DialogueState): DialogueOption[];
	export function selectOption(state: DialogueState, index: number): void;
	export function createDialogueState(tree: DialogueTree): DialogueState;

	// ── Dialogue manager ────────────────────────────────────────────────────

	export interface ManagerEvents {
		"dialogue:advance": { nodeId: string; choice?: number };
		"dialogue:end": { id: string };
	}

	export interface DialogueManager {
		registerTree(tree: DialogueTree): void;
		startDialogue(id: string): DialogueNode | null;
		isActive(): boolean;
		advance(optionId: string): void;
		endDialogue(): void;
		getAffinity(characterId: string): number;
		hasMetNpc(npcId: string): boolean;
		serialize(): DialogueManagerSnapshot;
		deserialize(data: unknown): void;
		dispose(): void;
	}

	export interface DialogueManagerSnapshot {
		acceptedQuests: string[];
		metNpcs: string[];
		affinity: Record<string, number>;
		/** Per-dialogue states — engine stores id + started flag here */
		dialogues?: Record<string, { id: string; started: boolean }>;
	}

	export function createDialogueManager(opts?: { emit?: unknown }): DialogueManager;

	// ── Dialogue panel ─────────────────────────────────────────────────────

	export interface DialoguePanelEventBus {
		on(event: string, handler: (data: unknown) => void): void;
		emit(event: string, data?: unknown): void;
	}

	export interface DialoguePanelOptions {
		style?: string;
		optionHints?: string[];
	}

	export function createDialoguePanel(
		bus: DialoguePanelEventBus,
		options?: DialoguePanelOptions,
	): HTMLElement & { dispose(): void };

	// ── HUD ─────────────────────────────────────────────────────────────────

	export function createHud(parent: HTMLElement): {
		mount(child: HTMLElement): void;
		unmount(child: HTMLElement): void;
		update(camera: unknown, delta: number): void;
		dispose(): void;
	};

	// ── Compass ─────────────────────────────────────────────────────────────

	export function createCompass(options?: { position?: string; style?: string }): HTMLElement;

	// ── Neural locomotion (gate-room) ──────────────────────────────────────

	export const SEQ_LENGTH: number;
	export const SEQ_WINDOW: number;
	export const BONE_COUNT: number;

	export interface SequenceOutput {
		rootDelta: [number, number, number];
		rotations: Float32Array;
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

	export class NeuralLocomotionController {
		get isLoaded(): boolean;
		load(weightsUrl: string, manifestUrl?: string): Promise<void>;
		predict(input: Float32Array): SequenceOutput;
		sampleAt(output: SequenceOutput, phase: number): SequenceOutput;
	}

	// ── Input ───────────────────────────────────────────────────────────────

	export enum Action {
		Jump = 1,
		Interact = 2,
		Shoot = 3,
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
	}

	export enum GamepadButton {
		A = 0,
		B = 1,
		X = 2,
		Y = 3,
	}

	// ── Quest system ────────────────────────────────────────────────────────

	export type QuestStatus = "active" | "complete" | "failed";

	export interface QuestObjective {
		id: string;
		type: string;
		description: string;
		completed: boolean;
		visible: boolean;
		required?: number;
		current?: number;
		progress?: number;
		targetId?: string;
		unlockedBy?: string;
	}

	export interface QuestDefinition {
		id: string;
		title?: string;
		name?: string;
		description: string;
		type?: string;
		giverNpcId?: string;
		objectives: QuestObjective[];
		rewards?: unknown[];
		reward?: {
			type: string;
			xp?: number;
			items?: Array<{ id: string; quantity?: number }>;
		};
	}

	export interface QuestState {
		definition: QuestDefinition;
		objectives: QuestObjective[];
	}

	export interface QuestLog {
		active: Map<string, QuestState>;
	}

	export interface QuestManager {
		getQuestLog(): QuestLog;
		startQuest(id: string): { status: string };
		advanceObjective(questId: string, objectiveId: string, current?: number): void;
		completeQuest(id: string): void;
		failQuest(id: string): void;
		registerDefinition(def: QuestDefinition): void;
		getQuestStatus(id: string): QuestStatus;
		isActive(id: string): boolean;
		isCompleted(id: string): boolean;
		serialize(): QuestSaveData;
		deserialize(data: unknown): void;
		dispose(): void;
	}

	export interface QuestLog {
		active: Map<string, QuestState>;
		completed: Map<string, QuestState>;
	}

	export function createQuestLog(): QuestLog;
	export function createQuestManager(opts: { emit: unknown }): QuestManager;
	export function isQuestComplete(quest: QuestDefinition): boolean;
	export function getObjective(quest: QuestDefinition, id: string): QuestObjective | undefined;

	export type QuestType = QuestDefinition;
	export type ObjectiveType = string;
	export type RewardType = unknown;
	export interface QuestReward {
		type: string;
		xp?: number;
		items?: Array<{ id: string; quantity?: number }>;
	}

	// ── NPC system ─────────────────────────────────────────────────────────

	export interface NpcBehaviorConfig {
		patrol?: Array<{ x: number; y: number; z: number; waitSeconds?: number }>;
		aggressive?: boolean;
		dialogueTreeId?: string;
		interactionRadius?: number;
		patrolDwellTime?: number;
		startingState?: string;
	}

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

	export interface NpcDefinition {
		id: string;
		vrmUrl?: string;
		name: string;
		role?: string;
		dialogueTreeId?: string;
		behavior: NpcBehaviorConfig;
		position: { x: number; y: number; z: number };
	}

	export type NpcInstanceState = "idle" | "interact" | NpcState;

	export interface NpcInstance {
		id: string;
		defId: string;
		state: NpcInstanceState;
		definition: NpcDefinition;
		inDialogue: boolean;
	}

	export interface NpcManager {
		registerNpc(def: NpcDefinition): NpcInstance;
		getAllNpcs(): NpcInstance[];
		get(id: string): NpcInstance | undefined;
		getNpc(id: string): NpcInstance | undefined;
		update(delta: number): void;
		dispose(): void;
	}

	export function createNpcManager(opts: {
		dialogueManager: DialogueManager;
		on: unknown;
	}): NpcManager;

	// ── Save data types ────────────────────────────────────────────────────

	export interface QuestObjectiveSave {
		id: string;
		completed: boolean;
	}

	export interface QuestStateSave {
		id: string;
		objectives: QuestObjectiveSave[];
	}

	export interface QuestSaveData {
		id: string;
		stage: number;
		objectives: Array<{ id: string; completed: boolean }>;
	}

	export interface DialogueSaveData {
		id: string;
		started: boolean;
		acceptedQuests?: string[];
		metNpcs?: string[];
		affinity?: Record<string, number>;
	}
}
