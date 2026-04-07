/** Shared types for Cloudflare Pages Functions API. */

export type Env = {
	ASSETS: R2Bucket;
	GAME_DATA: R2Bucket;
	/** Shared secret for upload authentication. Set via `wrangler secret put UPLOAD_SECRET`. */
	UPLOAD_SECRET?: string;
};

export type AssetMetadata = {
	readonly key: string;
	readonly size: number;
	readonly lastModified: string;
	readonly etag: string;
	readonly contentType?: string;
};

export type AssetListResponse = {
	readonly assets: AssetMetadata[];
	readonly truncated: boolean;
	readonly cursor?: string;
};

export type UploadResponse = {
	readonly key: string;
	readonly size: number;
	readonly url: string;
};

/** Convert an R2Object to our API metadata type. */
export function toAssetMetadata(obj: R2Object): AssetMetadata {
	return {
		key: obj.key,
		size: obj.size,
		lastModified: obj.uploaded.toISOString(),
		etag: obj.etag,
		contentType: obj.httpMetadata?.contentType,
	};
}

/** Verify upload authorization via shared secret. */
export function isAuthorized(request: Request, env: Env): boolean {
	const secret = env.UPLOAD_SECRET;
	if (!secret) return false;

	const auth = request.headers.get("Authorization");
	if (!auth) return false;

	return auth === `Bearer ${secret}`;
}

/** Standard JSON response helper. */
export function jsonResponse(data: unknown, status = 200): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

/** Standard error response helper. */
export function errorResponse(message: string, status = 400): Response {
	return jsonResponse({ error: message }, status);
}
