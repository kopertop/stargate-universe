/**
 * @fileoverview Cloudflare Worker for Stargate Universe
 * Provides health checks and game status endpoints
 */

// Health check endpoint
function handleHealthCheck(request: Request, env: any): any {
  return {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    service: 'stargate-universe-worker'
  };
}

// Game status endpoint
function handleGameStatus(request: Request, env: any): any {
  return {
    status: 'running',
    players: 0,
    active_games: 0,
    server_time: new Date().toISOString()
  };
}

addEventListener('fetch', (event: FetchEvent, env: any): void => {
  const url = new URL(event.request.url);

  // CORS preflight
  if (event.request.method === 'OPTIONS') {
    event.respondWith(new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
      }
    }));
    return;
  }

  // Route handlers
  if (url.pathname === '/health') {
    const data = handleHealthCheck(event.request, env);
    event.respondWith(new Response(JSON.stringify(data), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      }
    }));
  } else if (url.pathname === '/api/game-status') {
    const data = handleGameStatus(event.request, env);
    event.respondWith(new Response(JSON.stringify(data), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      }
    }));
  } else {
    event.respondWith(new Response('Not Found', { status: 404 }));
  }
});