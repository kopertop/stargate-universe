/**
 * GET/PUT /api/customizations/:characterId
 *
 * Load or save character customization JSON from the GAME_DATA R2 bucket.
 */
import { type Env, jsonResponse, errorResponse } from "../_types";

const R2_PREFIX = "customizations/";

function getCharacterId(params: Record<string, string | string[]>): string | null {
	const raw = params.characterId;
	const id = Array.isArray(raw) ? raw.join("/") : raw;
	// Sanitize: alphanumeric, hyphens, underscores only
	if (!id || !/^[\w-]+$/.test(id)) return null;
	return id;
}

export const onRequestGet: PagesFunction<Env> = async ({ params, env }) => {
	const characterId = getCharacterId(params);
	if (!characterId) {
		return errorResponse("Invalid character ID");
	}

	const key = `${R2_PREFIX}${characterId}.json`;
	const obj = await env.GAME_DATA.get(key);

	if (!obj) {
		return jsonResponse(null, 404);
	}

	const body = await obj.text();
	return new Response(body, {
		headers: { "Content-Type": "application/json" },
	});
};

export const onRequestPut: PagesFunction<Env> = async ({ params, request, env }) => {
	const characterId = getCharacterId(params);
	if (!characterId) {
		return errorResponse("Invalid character ID");
	}

	const contentType = request.headers.get("Content-Type") ?? "";
	if (!contentType.includes("application/json")) {
		return errorResponse("Expected application/json body");
	}

	try {
		const body = await request.text();
		// Validate it's parseable JSON
		JSON.parse(body);

		const key = `${R2_PREFIX}${characterId}.json`;
		await env.GAME_DATA.put(key, body, {
			httpMetadata: { contentType: "application/json" },
		});

		return jsonResponse({ characterId, saved: true });
	} catch (err) {
		return errorResponse(`Failed to save customization: ${err}`, 500);
	}
};
