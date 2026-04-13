/**
 * Audio Manager — lightweight Three.js audio system.
 *
 * Uses AudioListener + Audio/PositionalAudio for game sounds.
 * Sounds are loaded from R2 via the asset resolver on first play.
 *
 * @example
 *   const audio = AudioManager.getInstance();
 *   audio.attachListener(camera);
 *   audio.play("repair-sparks");           // global 2D
 *   audio.play("repair-sparks", object3d); // positional 3D
 *   audio.stop("repair-sparks");
 */
import {
	Audio,
	AudioListener,
	AudioLoader,
	Object3D,
	PositionalAudio,
	type Camera,
} from "three";

import { resolveAssetUrl } from "../asset-resolver";
import { SOUND_CATALOG, type SoundId } from "./sound-catalog";

export class AudioManager {
	private static instance: AudioManager | undefined;

	private readonly listener = new AudioListener();
	private readonly loader = new AudioLoader();
	private readonly bufferCache = new Map<string, globalThis.AudioBuffer>();
	private readonly activeSounds = new Map<string, Audio | PositionalAudio>();
	private listenerParent: Camera | undefined;

	private constructor() {}

	static getInstance(): AudioManager {
		if (!AudioManager.instance) {
			AudioManager.instance = new AudioManager();
		}
		return AudioManager.instance;
	}

	/** Attach the listener to the camera. Call once during scene setup. */
	attachListener(camera: Camera): void {
		if (this.listenerParent && this.listenerParent !== camera) {
			this.listenerParent.remove(this.listener);
		}
		if (!camera.children.includes(this.listener)) {
			camera.add(this.listener);
		}
		this.listenerParent = camera;
	}

	/** Detach the listener from its current camera. */
	detachListener(): void {
		if (this.listenerParent) {
			this.listenerParent.remove(this.listener);
			this.listenerParent = undefined;
		}
	}

	/** Get the AudioListener (for adding to camera externally). */
	getListener(): AudioListener {
		return this.listener;
	}

	/**
	 * Play a cataloged sound.
	 *
	 * @param id Sound ID from the catalog
	 * @param parent Optional Object3D for positional audio. If the catalog
	 *   entry is positional and a parent is provided, uses PositionalAudio.
	 * @param options Per-call overrides for volume/loop. Useful when the same
	 *   catalog entry is used as both a one-shot cinematic cue and a looping
	 *   menu bed.
	 */
	async play(
		id: SoundId,
		parent?: Object3D,
		options?: { volume?: number; loop?: boolean },
	): Promise<void> {
		const entry = SOUND_CATALOG[id];
		const key = parent ? `${id}:${parent.uuid}` : id;

		// Stop existing instance of this sound
		this.stop(id, parent);

		const buffer = await this.loadBuffer(entry.path);

		const sound = entry.positional && parent
			? this.createPositionalSound(parent)
			: this.createGlobalSound();

		const loop = options?.loop ?? entry.loop;
		const volume = options?.volume ?? entry.volume;

		sound.setBuffer(buffer);
		sound.setVolume(volume);
		sound.setLoop(loop);
		sound.play();

		this.activeSounds.set(key, sound);

		// Auto-cleanup non-looping sounds when finished
		if (!loop) {
			sound.onEnded = () => {
				this.activeSounds.delete(key);
				if (sound instanceof PositionalAudio && parent) {
					parent.remove(sound);
				}
			};
		}
	}

	/** Stop a playing sound. */
	stop(id: SoundId, parent?: Object3D): void {
		const key = parent ? `${id}:${parent.uuid}` : id;
		const sound = this.activeSounds.get(key);

		if (sound) {
			if (sound.isPlaying) sound.stop();
			if (sound instanceof PositionalAudio && parent) {
				parent.remove(sound);
			}
			this.activeSounds.delete(key);
		}
	}

	/** Stop all currently playing sounds. */
	stopAll(): void {
		for (const [key, sound] of this.activeSounds) {
			if (sound.isPlaying) sound.stop();
			this.activeSounds.delete(key);
		}
	}

	/** Check if a sound is currently playing. */
	isPlaying(id: SoundId, parent?: Object3D): boolean {
		const key = parent ? `${id}:${parent.uuid}` : id;
		const sound = this.activeSounds.get(key);
		return sound?.isPlaying ?? false;
	}

	/** Dispose all resources. */
	dispose(): void {
		this.stopAll();
		this.detachListener();
		this.bufferCache.clear();
	}

	// ─── Internal ──────────────────────────────────────────────────────────────

	private async loadBuffer(path: string): Promise<globalThis.AudioBuffer> {
		const cached = this.bufferCache.get(path);
		if (cached) return cached;

		const url = resolveAssetUrl(path);
		const buffer = await this.loader.loadAsync(url);
		this.bufferCache.set(path, buffer);
		return buffer;
	}

	private createGlobalSound(): Audio {
		return new Audio(this.listener);
	}

	private createPositionalSound(parent: Object3D): PositionalAudio {
		const sound = new PositionalAudio(this.listener);
		sound.setRefDistance(2);
		sound.setMaxDistance(10);
		sound.setRolloffFactor(1.5);
		parent.add(sound);
		return sound;
	}
}
