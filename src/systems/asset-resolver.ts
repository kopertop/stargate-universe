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
 * Resolve an asset path to a full URL.
 *
 * - Absolute URLs (https://, //) are passed through unchanged.
 * - Relative paths are prefixed with the R2 public URL (if configured).
 *
 * @param path Asset path or URL
 * @returns Resolved URL string
 */
export function resolveAssetUrl(path: string): string {
	// Already an absolute URL — pass through
	if (/^[a-z]+:/i.test(path) || path.startsWith("//")) {
		return path;
	}

	// No R2 URL configured — pass through (dev mode)
	if (!R2_PUBLIC_URL) {
		return path;
	}

	// Ensure clean join (no double slashes)
	const base = R2_PUBLIC_URL.replace(/\/+$/, "");
	const asset = path.replace(/^\/+/, "");
	return `${base}/${asset}`;
}
