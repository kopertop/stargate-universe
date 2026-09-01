# Stargate Universe Cloudflare Worker

Cloudflare Worker serving the Stargate Universe game backend API with health check endpoints.

## Project Structure

```
worker/
├── index.ts          # Worker main file with health check endpoints
├── package.json      # Project configuration
├── wrangler.toml     # Cloudflare Worker configuration
├── tsconfig.json     # TypeScript configuration
├── .gitignore        # Git ignore rules
└── README.md         # This file
```

## Endpoints

### GET /health
Health check endpoint. Returns service status and timestamp.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-01-01T00:00:00.000Z",
  "version": "1.0.0",
  "service": "stargate-universe-worker"
}
```

### GET /api/game-status
Game status endpoint. Returns current server status and player counts.

**Response:**
```json
{
  "status": "running",
  "players": 0,
  "active_games": 0,
  "server_time": "2025-01-01T00:00:00.000Z"
}
```

### OPTIONS /{any}
CORS preflight handler for cross-origin requests.

**Headers:**
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

## Development Setup

### Install Dependencies

Install wrangler globally (recommended) or use npx:
```bash
npm install -g wrangler@4
cd /home/newstex/stargate-universe/worker
npx wrangler dev --local
```

**Alternatively with Python venv:**
```bash
python3 -m venv venv2
venv2/bin/pip install --upgrade wrangler
venv2/bin/wrangler dev
```

### Run Locally

```bash
cd /home/newstex/stargate-universe/worker
npx wrangler dev --local --port 8787
```

Access the worker at `http://localhost:8787`

### Deploy to Cloudflare

```bash
# Login to Cloudflare (if not already logged in)
npx wrangler login

# Deploy
npx wrangler deploy
```

**Note:** In non-interactive environments (like cron jobs), set `CLOUDFLARE_API_TOKEN`:
```bash
export CLOUDFLARE_API_TOKEN=your_token
npx wrangler deploy
```

## Cloudflare Configuration

### Required Accounts/Services

1. **Cloudflare Account** with Worker and D1 database access
2. **Wrangler CLI** with npm: `npm install -g wrangler@4`
3. **TypeScript** (for development)

### Environment Variables (Local)

Create `.dev.vars` for local development:
```
CF_ACCOUNT_ID=your_account_id
CF_API_TOKEN=***
```

### Bindings (Future)

Add these bindings in `wrangler.toml` when setting up D1/KV:

```toml
[[d1_databases]]
binding = "DB"
database_name = "stargate-games"
database_id = "your-database-id"

[[kv_namespaces]]
binding = "KV"
id = "your-kv-id"
```

## Roadmap

- [ ] Game creation/deletion endpoints
- [ ] Player authentication and session management
- [ ] Save/load game data via D1
- [ ] Real-time connections via Cloudflare WebSocket
- [ ] CORS configuration for client requests
- [ ] API rate limiting
- [ ] Monitoring and metrics
- [ ] Persistent storage for games and players

## Testing

### Manual Testing

```bash
# Health check
curl http://localhost:8787/health

# Game status
curl http://localhost:8787/api/game-status
```

### CI/CD Testing

```bash
# Build
npx wrangler build

# Deploy
npx wrangler deploy

# Verify health check
npx wrangler tail | grep health
```

## Notes

- The worker is built with TypeScript and designed for Cloudflare Workers runtime
- Health check endpoint is idempotent and suitable for monitoring
- Game status is currently a placeholder; integrates with D1 when configured
- All endpoints respond with CORS headers to allow client requests from any origin
- In wrangler dev, `event.extends.env` passes the `env` binding; in production, `env` is already provided by Cloudflare
- All event handlers include proper TypeScript types for request/response types