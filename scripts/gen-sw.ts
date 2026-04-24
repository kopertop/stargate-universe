/**
 * Build script — ensures public/sw.js exists with current cache config.
 * Run with `bun run scripts/gen-sw.ts` (or as part of build).
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputPath = `${__dirname}/../public/sw.js`;

const swSource = `/**
 * Service Worker — auto-generated from @kopertop/vibe-game-engine template.
 * Customize CACHE_VERSION + PRECACHE_URLS per build.
 */
const CACHE_VERSION = 'v1';
const CACHE_RUNTIME = \`runtime-\${CACHE_VERSION}\`;
const CACHE_PRECACHE = \`precache-\${CACHE_VERSION}\`;

// Files to cache on SW install — minimum set to boot the app offline.
const PRECACHE_URLS = [
	'/',
	'/index.html',
	'/manifest.webmanifest',
];

self.addEventListener('install', (event) => {
	event.waitUntil(
		caches.open(CACHE_PRECACHE).then((cache) => cache.addAll(PRECACHE_URLS)),
	);
	self.skipWaiting();
});

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		const keys = await caches.keys();
		await Promise.all(
			keys
				.filter((k) => k !== CACHE_RUNTIME && k !== CACHE_PRECACHE)
				.map((k) => caches.delete(k)),
		);
		await self.clients.claim();
	})());
});

self.addEventListener('message', (event) => {
	if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

const networkFirst = async (request) => {
	try {
		const fresh = await fetch(request);
		const cache = await caches.open(CACHE_RUNTIME);
		cache.put(request, fresh.clone());
		return fresh;
	} catch {
		const cached = await caches.match(request);
		if (cached) return cached;
		// Fallback for navigations — serve the cached shell.
		if (request.mode === 'navigate') {
			return caches.match('/index.html');
		}
		throw new Error('offline and not cached');
	}
};

const cacheFirst = async (request) => {
	const cached = await caches.match(request);
	if (cached) {
		// Background revalidate for non-immutable assets.
		fetch(request).then((fresh) => {
			if (fresh.ok) caches.open(CACHE_RUNTIME).then((c) => c.put(request, fresh));
		}).catch(() => { /* ignore */ });
		return cached;
	}
	const fresh = await fetch(request);
	const cache = await caches.open(CACHE_RUNTIME);
	cache.put(request, fresh.clone());
	return fresh;
};

self.addEventListener('fetch', (event) => {
	const request = event.request;
	if (request.method !== 'GET') return;

	const url = new URL(request.url);

	// Skip cross-origin (R2 assets, CDN fetches) — let the network handle them.
	if (url.origin !== self.location.origin) return;

	// HTML / navigations: network-first.
	if (request.mode === 'navigate' || request.destination === 'document') {
		event.respondWith(networkFirst(request));
		return;
	}

	// Hashed build artifacts (Vite content-hash filenames): cache-first.
	if (/\\.[0-9a-f]{8,}\\.(js|css|woff2?|ttf|png|jpg|svg)$/.test(url.pathname)) {
		event.respondWith(cacheFirst(request));
		return;
	}

	// Other same-origin assets: cache-first with revalidation.
	if (['script', 'style', 'image', 'font'].includes(request.destination)) {
		event.respondWith(cacheFirst(request));
		return;
	}

	// Everything else: network-first.
	event.respondWith(networkFirst(request));
});
`;

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, swSource);
console.log(`✓ wrote ${outputPath}`);
