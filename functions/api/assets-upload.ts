/**
 * POST /api/assets-upload
 *
 * Uploads a file to the ASSETS R2 bucket. Requires Bearer token auth.
 * Expects multipart form data with "file" and "key" fields.
 */
import { type Env, isAuthorized, jsonResponse, errorResponse } from "./_types";

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
	if (!isAuthorized(request, env)) {
		return errorResponse("Unauthorized", 401);
	}

	const contentType = request.headers.get("Content-Type") ?? "";
	if (!contentType.includes("multipart/form-data")) {
		return errorResponse("Expected multipart/form-data");
	}

	try {
		const formData = await request.formData();
		const file = formData.get("file");
		const key = formData.get("key");

		if (!file || !(file instanceof File)) {
			return errorResponse("Missing 'file' field");
		}

		if (!key || typeof key !== "string") {
			return errorResponse("Missing 'key' field (target path in R2)");
		}

		// Sanitize key — no leading slash, no ".."
		const sanitizedKey = key.replace(/^\/+/, "").replace(/\.\./g, "");
		if (!sanitizedKey) {
			return errorResponse("Invalid key");
		}

		await env.GAME_ASSETS.put(sanitizedKey, file.stream(), {
			httpMetadata: {
				contentType: file.type || "application/octet-stream",
			},
		});

		const obj = await env.GAME_ASSETS.head(sanitizedKey);
		if (!obj) {
			return errorResponse("Upload succeeded but object not found", 500);
		}

		return jsonResponse({
			key: sanitizedKey,
			size: obj.size,
			url: `/r2/${sanitizedKey}`,
		}, 201);
	} catch (err) {
		return errorResponse(`Upload failed: ${err}`, 500);
	}
};
