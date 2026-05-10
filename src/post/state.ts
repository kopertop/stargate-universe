/**
 * Mutable global state for the active post-processing pipeline.
 *
 * Scenes never import this directly — they use `applyPostProfile()` from
 * profiles.ts, which automatically updates the pipeline if one is active.
 */
import type { PostPipeline } from "./pipeline";

let activePipeline: PostPipeline | null = null;

export function setPostPipeline(pipeline: PostPipeline | null): void {
	activePipeline = pipeline;
}

export function getPostPipeline(): PostPipeline | null {
	return activePipeline;
}
