/**
 * Upload media asset to WorldLabs API
 * Used by worldlabs-generate.ts for image-to-world generation
 */

export async function upload(filePath: string, apiKey: string): Promise<string> {
  const file = Bun.file(filePath);
  const buffer = await file.arrayBuffer();
  const blob = new Blob([buffer], { type: file.type || "application/octet-stream" });

  const formData = new FormData();
  formData.append("file", blob, filePath.split("/").pop()!);

  const response = await fetch("https://api.worldlabs.ai/marble/v1/media_assets:upload", {
    method: "POST",
    headers: {
      "WLT-Api-Key": apiKey
    },
    body: formData
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Upload failed (${response.status}): ${error}`);
  }

  const result = await response.json();
  return result.id;
}
