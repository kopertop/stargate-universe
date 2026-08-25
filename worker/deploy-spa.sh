#!/bin/bash
set -e

PROJECT_NAME="stargate-universe"
WORKER_DIR="/home/newstex/stargate-universe/worker/client"

echo "=== Building SPA ==="
cd "$WORKER_DIR"
npm run build

echo "=== Deploying to Cloudflare Pages ==="
npx wrangler pages deploy dist --project-name="$PROJECT_NAME" --branch=main

echo "=== Done ==="