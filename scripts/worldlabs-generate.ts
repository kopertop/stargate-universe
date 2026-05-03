/**
 * WorldLabs Marble API — Generate gaussian splat worlds
 *
 * Usage:
 *   bun run scripts/worldlabs-generate.ts --prompt "A mystical alien planet with glowing crystals"
 *   bun run scripts/worldlabs-generate.ts --image /path/to/image.png --prompt "An alien landscape"
 *   bun run scripts/worldlabs-generate.ts --world-id <id>  (poll existing operation)
 *
  * Environment:
  *   WORLD_LABS_API_KEY - Your WorldLabs API key (or WLT_API_KEY)
  *   (or add to .env.development: WORLD_LABS_API_KEY=wl_...)
  *   API header: WLT-Api-Key
 */

import { parseArgs } from "node:util";
import { readFileSync } from "node:fs";
import { upload } from "./worldlabs-upload.ts";

const API_BASE = "https://api.worldlabs.ai/marble/v1";

interface WorldLabsResponse {
  operation_id: string;
  done: boolean;
  response?: {
    id: string;
    display_name: string;
    assets: {
      splats: {
        spz_urls: {
          "100k": string;
          "500k": string;
          full: string;
        };
      };
      mesh: {
        collider_mesh_url: string;
      };
      imagery: {
        pano_url: string;
        thumbnail_url: string;
      };
      caption: string;
    };
  };
}

async function generateWorld(options: {
  prompt?: string;
  imagePath?: string;
  model?: string;
  displayName?: string;
}) {
  const apiKey = process.env.WORLD_LABS_API_KEY || process.env.WLT_Api_Key;

  if (!apiKey) {
    throw new Error(
      "Missing WorldLabs API key. Set WORLD_LABS_API_KEY or WLT_Api_Key environment variable.\n" +
      "Get your key from https://worldlabs.ai/settings/api-keys"
    );
  }

  let worldPrompt: Record<string, unknown>;

  if (options.imagePath) {
    // Upload image first
    console.log(`Uploading image: ${options.imagePath}`);
    const mediaAssetId = await upload(options.imagePath, apiKey);
    worldPrompt = {
      type: "image",
      image_prompt: {
        source: "media_asset",
        media_asset_id: mediaAssetId,
        is_pano: options.imagePath.toLowerCase().includes("pano")
      }
    };
  } else if (options.prompt) {
    worldPrompt = {
      type: "text",
      text_prompt: options.prompt
    };
  } else {
    throw new Error("Must provide either --prompt or --image");
  }

  if (options.prompt && options.imagePath) {
    (worldPrompt as Record<string, unknown>).text_prompt = options.prompt;
  }

  const model = options.model || "marble-1.1";

  console.log(`Generating world with model: ${model}`);
  console.log(`Prompt: ${options.prompt || "(auto-generated from image)"}`);

  const response = await fetch(`${API_BASE}/worlds:generate`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "WLT-Api-Key": apiKey
    },
    body: JSON.stringify({
      display_name: options.displayName || `SGU World ${Date.now()}`,
      model,
      world_prompt: worldPrompt
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`API error (${response.status}): ${error}`);
  }

  const result: WorldLabsResponse = await response.json();
  console.log(`\nOperation started: ${result.operation_id}`);
  console.log(`\nPolling for completion...\n`);

  return pollOperation(result.operation_id, apiKey);
}

async function pollOperation(operationId: string, apiKey: string): Promise<WorldLabsResponse> {
  const start = Date.now();
  const timeout = 10 * 60 * 1000; // 10 minutes

  while (Date.now() - start < timeout) {
    const response = await fetch(`${API_BASE}/operations/${operationId}`, {
      headers: { "WLT-Api-Key": apiKey }
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Poll error (${response.status}): ${error}`);
    }

    const operation: WorldLabsResponse = await response.json();

    if (operation.done) {
      console.log(`\nWorld generation complete!`);
      return operation;
    }

    process.stdout.write(".");
    await Bun.sleep(5000); // Wait 5 seconds
  }

  throw new Error("Operation timed out after 10 minutes");
}

async function downloadAssets(world: WorldLabsResponse) {
  if (!world.response) {
    throw new Error("World not ready — no response data");
  }

  const { assets, id, display_name } = world.response;
  const outputDir = `public/worlds/${id}`;

  // Create output directory
  try {
    Bun.mkdirSync(outputDir, { recursive: true });
  } catch {
    // Directory might already exist
  }

  console.log(`\nDownloading assets for: ${display_name}`);
  console.log(`World ID: ${id}\n`);

  // Download SPZ (use 500k as good balance)
  const spzUrl = assets.splats.spz_urls["500k"];
  console.log(`Downloading splat (500k)...`);
  const spzResponse = await fetch(spzUrl);
  const spzBuffer = await spzResponse.arrayBuffer();
  Bun.writeFileSync(`${outputDir}/world-500k.spz`, spzBuffer);
  console.log(`  Saved: ${outputDir}/world-500k.spz`);

  // Download collider mesh
  if (assets.mesh?.collider_mesh_url) {
    console.log(`Downloading collider mesh...`);
    const meshResponse = await fetch(assets.mesh.collider_mesh_url);
    const meshBuffer = await meshResponse.arrayBuffer();
    Bun.writeFileSync(`${outputDir}/collider.glb`, meshBuffer);
    console.log(`  Saved: ${outputDir}/collider.glb`);
  }

  // Download panorama
  if (assets.imagery?.pano_url) {
    console.log(`Downloading panorama...`);
    const panoResponse = await fetch(assets.imagery.pano_url);
    const panoBuffer = await panoResponse.arrayBuffer();
    Bun.writeFileSync(`${outputDir}/panorama.jpg`, panoBuffer);
    console.log(`  Saved: ${outputDir}/panorama.jpg`);
  }

  // Save metadata
  const metadata = {
    worldId: id,
    displayName: display_name,
    caption: assets.caption,
    assets: {
      spz: `/worlds/${id}/world-500k.spz`,
      collider: assets.mesh?.collider_mesh_url ? `/worlds/${id}/collider.glb` : undefined,
      panorama: assets.imagery?.pano_url ? `/worlds/${id}/panorama.jpg` : undefined
    }
  };

  Bun.writeFileSync(
    `${outputDir}/metadata.json`,
    JSON.stringify(metadata, null, 2)
  );

  console.log(`\nMetadata saved: ${outputDir}/metadata.json`);
  console.log(`\nScene config snippet:`);
  console.log(JSON.stringify({
    splatWorld: {
      splatPath: `/worlds/${id}/world-500k.spz`,
      colliderPath: metadata.assets.collider ? `/worlds/${id}/collider.glb` : undefined,
      scale: 1.0,
      position: [0, 0, 0] as [number, number, number]
    }
  }, null, 2));

  return metadata;
}

// Main
const args = parseArgs({
  options: {
    prompt: { type: "string" },
    image: { type: "string" },
    model: { type: "string" },
    "display-name": { type: "string" },
    "world-id": { type: "string" }
  }
});

async function main() {
  try {
    if (args.values["world-id"]) {
      // Poll existing operation
      const apiKey = process.env.WORLD_LABS_API_KEY || process.env.WLT_Api_Key;
      if (!apiKey) throw new Error("Missing API key");
      const result = await pollOperation(args.values["world-id"], apiKey);
      await downloadAssets(result);
    } else {
      const result = await generateWorld({
        prompt: args.values.prompt,
        imagePath: args.values.image,
        model: args.values.model,
        displayName: args.values["display-name"]
      });

      if (result.response) {
        await downloadAssets(result);
      }
    }

    console.log("\nDone!");
    process.exit(0);
  } catch (err) {
    console.error(`\nError: ${err}`);
    process.exit(1);
  }
}

main();
