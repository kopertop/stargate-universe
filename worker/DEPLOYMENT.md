# Deployment Guide

## Prerequisites

1. Cloudflare account with Worker and Pages access
2. Wrangler CLI: `npm install -g wrangler@4`
3. TypeScript for development
4. Valid `CLOUDFLARE_API_TOKEN` (required for non-interactive deployment)

## Deployment Options

### Option 1: Interactive Login (Recommended)

```bash
npx wrangler login
# Follow browser login instructions
npx wrangler deploy
npx wrangler pages deploy dist --project-name=stargate-universe
```

### Option 2: API Token (Non-Interactive/Cron)

Set `CLOUDFLARE_API_TOKEN` environment variable:

```bash
export CLOUDFLARE_API_TOKEN=*** wrangler deploy
export CLOUDFLARE_API_TOKEN=*** npx wrangler pages deploy dist --project-name=stargate-universe
```

Token format: Bearer token with `Cloudflare Workers API` scope

## Project Structure

Both worker and SPA share the same project name `stargate-universe`:

```
stargate-universe/
├── worker/
│   ├── index.ts          # Cloudflare Worker (health checks)
│   ├── dist/            # Worker build output
│   └── deploy-spa.sh    # SPA deployment script
└── client/             # React SPA (Vite)
    ├── src/
    ├── dist/          # SPA build output
    └── .dev.vars      # Local env vars
```

## Local Testing

### Worker Health Check
```bash
cd /home/newstex/stargate-universe/worker
npx wrangler dev --local --port 8787
curl http://localhost:8787/health
curl http://localhost:8787/api/game-status
```

### SPA Build & Dev
```bash
cd /home/newstex/stargate-universe/worker/client
npm install
npm run dev -- --port 5173
curl http://localhost:5173
```

## Cloudflare Configuration

### Worker Configuration
- File: `worker/wrangler.toml`
- Entry point: `worker/index.ts`
- Endpoints: `/health`, `/api/game-status`, OPTIONS

### Pages Configuration
- File: `worker/client/package.json`
- Build output: `worker/client/dist`
- Deploy script: `worker/deploy-spa.sh`

## Environment Variables

Create `.dev.vars` in `worker/client/` for local development:

```
CF_ACCOUNT_ID=***
CF_API_TOKEN=***
```

## Monitoring

### Worker Health Check
```bash
npx wrangler tail --format pretty
```

### Pages Logs
Access via Cloudflare Dashboard → Pages → stargate-universe → Logs

## Troubleshooting

**Error: Invalid request headers [code: 6003]**
- Ensure `CLOUDFLARE_API_TOKEN` is properly set in environment
- Check token has required API permissions
- Use `npx wrangler login` for interactive authentication

**Error: Unknown argument: temporary**
- Use `--temporary` only for unauthenticated deployments
- For authenticated deployments, unset token or use interactive login

**Build succeeds, deployment fails**
- Verify account ID matches project configuration
- Check project name consistency (`stargate-universe`)
- Ensure wrangler version is up-to-date (`npm install -g wrangler@4`)