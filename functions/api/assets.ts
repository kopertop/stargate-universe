/**
 * GET /api/assets?prefix=characters/&cursor=...
 *
 * Lists objects in the ASSETS R2 bucket. Supports prefix filtering and pagination.
 */
import { type Env, toAssetMetadata, jsonResponse, errorResponse } from "./_types";

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
	const url = new URL(request.url);
	const prefix = url.searchParams.get("prefix") ?? undefined;
	const cursor = url.searchParams.get("cursor") ?? undefined;
	const limit = Math.min(Number(url.searchParams.get("limit") ?? 100), 1000);

	try {
		const listed = await env.ASSETS.list({ prefix, cursor, limit });

		return jsonResponse({
			assets: listed.objects.map(toAssetMetadata),
			truncated: listed.truncated,
			cursor: listed.truncated ? listed.cursor : undefined,
		});
	} catch (err) {
		return errorResponse(`Failed to list assets: ${err}`, 500);
	}
};
