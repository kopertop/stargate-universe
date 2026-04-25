/**
 * Asset URL Resolver — maps relative asset paths to full URLs.
 *
 * In development, paths are served by Vite's dev server (e.g., `/characters/eli.vrm`).
 * In production, paths are prefixed with the R2 public bucket URL.
 *
 * Set `VITE_R2_PUBLIC_URL` in `.env.production` to the public R2 bucket URL
 * (e.g., `https://sgu-assets.<account>.r2.dev`).
 */

const R2_PUBLIC_URL = (import.meta.env.VITE_R2_PUBLIC_URL as string | undefined) ?? "";

/**
 * Paths that live under `public/` locally and should NEVER be rewritten to
 * R2 in development, even when VITE_R2_PUBLIC_URL is set. The bucket may
 * not mirror these yet (see BUG-001 — VRM 404s were caused by R2 rewrite
 * in dev). Anything not in this list (e.g. `/audio/...` music/SFX) falls
 * through to R2 in both dev and prod.
 */
const LOCAL_DEV_PREFIXES = [
	"/assets/", // characters, animations, scene assets
];

/**
 * Resolve an asset path to a full URL.
 *
 * - Absolute URLs (https://, //) are passed through unchanged.
 * - In development, paths under `/assets/` are served by Vite from `public/`.
 *   Everything else (e.g. /audio/...) uses R2 when configured, because the
 *   local dev tree doesn't mirror those folders.
 * - In production, relative paths are prefixed with the R2 public URL.
 *
 * @param path Asset path or URL
 * @returns Resolved URL string
 */
export function resolveAssetUrl(path: string): string {
	// Already an absolute URL — pass through
	if (/^[a-z]+:/i.test(path) || path.startsWith("//")) {
		return path;
	}

	// Dev mode: serve /assets/** locally; everything else goes to R2 if set.
	if (import.meta.env.DEV && LOCAL_DEV_PREFIXES.some((p) => path.startsWith(p))) {
		return path;
	}

	// No R2 URL configured — pass through
	if (!R2_PUBLIC_URL) {
		return path;
	}

	// Ensure clean join (no double slashes)
	const base = R2_PUBLIC_URL.replace(/\/+$/, "");
	const asset = path.replace(/^\/+/, "");
	return `${base}/${asset}`;
}
