# Sprint 4 — Perf Baseline (2026-05-21)

Captured before any S4 work began. Numbers here are the "before" against which
Sprint 4 targets (−25 % frame time, −40 % bytes, −30 % draw calls,
largest asset < 1.5 MB, TTI < 4 s) will be measured.

## Methodology

- **Renderer-level metrics (draw calls, triangles, geometries, textures):**
  Captured via `scripts/perf-baseline.ts` — headless Chromium (Playwright,
  swiftshader GL backend), `?webgl=1` flag forcing the WebGL fallback path,
  `window.__sguRenderer.info` sampled after `__sceneReady === true` plus a
  1-second settle.
- **FPS:** `requestAnimationFrame` deltas over a 5-second window, first frame
  dropped (rAF prime). **Software-rendered — treat absolute FPS as a relative
  baseline only; M-series GPU FPS will be 4–10× higher and is the canonical
  number for the sprint target.** What matters for the target is the *delta*
  from this run to the post-sprint run on the same hardware/methodology.
- **Asset bytes:** Two captures, both meaningful:
  1. **Dev-mode transfer (`vite`):** `performance.getEntriesByType("resource")`
     summed over the page lifecycle. Includes Vite's per-module HTTP graph and
     overstates real-world bytes. Useful as a per-scene "what is fetched at
     all" inventory.
  2. **Prod build (`vite build` output):** authoritative for the sprint's
     "Total JS + asset bytes (first load)" target. Per-scene first load
     ≈ `index-*.js` + `index.html` + that scene's `scene.runtime-*.js`
     + any glb/vrm/png assets the scene statically imports.
- **TTI:** wall-clock from `page.goto` to `__sceneReady === true`. Network is
  uncached (each scene loads in a fresh browser context).

Reproduce with:

```sh
bun run dev          # in one shell
bun run scripts/perf-baseline.ts
```

## Results

### Renderer / Frame metrics (dev mode, swiftshader)

| Metric                       | gate-room   | destiny-corridor | opening-cinematic |
|------------------------------|-------------|------------------|-------------------|
| Draw calls                   | **52**      | **316**          | **172**           |
| Triangles                    | **90 219**  | 1 *(see note)*   | **10 973**        |
| Geometries (memory)          | 207         | 51               | 6                 |
| Textures (memory)            | 27          | 9                | 13                |
| Frame time median (ms)       | 133.3       | 33.4             | 66.7              |
| FPS median (swiftshader)     | 7.5         | 29.9             | 15.0              |
| FPS min / max (swiftshader)  | 1.3 / 8.6   | 19.7 / 31.0      | 7.5 / 20.1        |
| TTI (ms, dev mode)           | 2 042       | 1 584            | 2 152             |

> **destiny-corridor triangle count anomaly.** `info.render.triangles` came
> back as 1 — the corridor renders ~316 draw calls but the per-frame triangle
> counter wasn't populating in this capture. Likely WebGPURenderer/WebGL-fallback
> path quirk for that specific scene; corridor uses indexed segment geometry.
> Re-measure after S4-05 (instancing) using the same script and treat the
> *change in draw calls* as the meaningful corridor signal until the triangle
> reading is fixed.

### Bytes (prod build, `vite build`)

Top assets in `dist/assets/` after a clean `bun run build` — these are what
the browser actually transfers in production:

| Rank | Asset (prod build)                      | Size (raw)      | Notes |
|------|------------------------------------------|-----------------|-------|
| 1    | `eli-walking-*.glb`                      | **18.83 MB**    | Mixamo walk anim glb — single biggest asset |
| 2    | `eli-*.vrm`                              | **15.30 MB**    | Crew character VRM |
| 3    | `destiny-ship-*.glb`                     | **10.28 MB**    | Cinematic hero ship model |
| 4    | `scene.runtime-DdRqFc-7.js`              | **8.49 MB**     | Suspected gate-room/destiny-gate-room runtime.json bundled |
| 5    | `asset-model-stargate-*.bin`             | **6.06 MB**     | glTF buffer for stargate model |
| 6    | `destiny-restored-start-*.png`           | **1.90 MB**     | Start-screen background |
| 7    | `index-*.js`                             | **1.64 MB**     | Main chunk (three.js + ggez + everything else) |
|      | All other chunks                         | < 14 KB each    | Per-scene runtime stubs |

**Total `dist/assets/` size:** **~164 MB** uncompressed (every scene + every
character + every runtime), **~178 MB** for `dist/` overall. This is the
"ship everything" number — the per-scene first-load is much smaller and is
what the sprint target actually constrains.

### Per-scene first-load bytes (dev-mode transfer, indicative)

Captured as `Σ resource entry transferSize / encodedBodySize` after
`__sceneReady`, with browser cache disabled per Playwright context. Dev-mode
inflates these (per-module Vite delivery), but the *largest single asset* is
still the right shape for what prod will fetch.

| Scene             | Total bytes (dev) | Asset count | Largest asset (dev)                                                                  | Largest asset bytes |
|-------------------|-------------------|-------------|----------------------------------------------------------------------------------------|---------------------|
| gate-room         | **50.7 MB**       | 109         | `src/scenes/destiny-gate-room/scene.runtime.json?import&raw`                           | **26.06 MB**        |
| destiny-corridor  | **7.83 MB**       | 109         | `node_modules/.vite/deps/three_webgpu.js`                                              | 1.59 MB             |
| opening-cinematic | **18.28 MB**      | 110         | `src/scenes/opening-cinematic/assets/destiny-ship.glb`                                 | 10.28 MB            |

> The gate-room raw `scene.runtime.json` (26 MB) is the single most painful
> first-load fact in this baseline. In prod it ships as `scene.runtime-DdRqFc-7.js`
> at 8.49 MB — still ~6× over the sprint's <1.5 MB largest-asset target.
> S4-02 (DRACO) won't help a JSON-encoded scene; runtime.json compaction
> is its own follow-up.

## Sprint 4 target tracking

| Metric                         | Baseline (this doc)                   | Target (post-sprint)        |
|--------------------------------|----------------------------------------|------------------------------|
| Frame time @ gate-room         | 133.3 ms median (swiftshader)          | −25 %                        |
| Frame time @ destiny-corridor  | 33.4 ms median (swiftshader)           | −25 %                        |
| Total JS + asset bytes (1st)   | 50.7 MB / 7.83 MB / 18.28 MB (dev)     | −40 % per scene              |
| Largest single asset           | **26.06 MB** (gate-room runtime.json)  | < 1.5 MB                     |
| TTI                            | 2.0 s / 1.6 s / 2.2 s (dev)            | < 4 s on broadband prod      |
| Draw calls @ gate-room         | 52                                     | −30 %                        |

## Observations / leads for the sprint

1. **Largest assets are character VRM + glb (eli walking 18.8 MB, eli VRM
   15.3 MB, destiny-ship 10.3 MB).** Highest leverage for S4-02 (DRACO + Meshopt)
   and S4-03 (KTX2). Even modest 30–50 % compression here clears most of the
   "−40 % bytes" target on its own.
2. **gate-room scene.runtime.json at 26 MB raw / 8.5 MB minified** is the
   second-largest first-load source. DRACO/KTX2 won't touch JSON; this needs
   either runtime.json structural cleanup (numeric precision, dedup, externalizing
   embedded geometry) or moving heavy mesh data out of the JSON entirely.
   Flag for a follow-up note (not in S4 scope but blocks the <1.5 MB target).
3. **destiny-corridor draw calls = 316** is the obvious instancing target
   for S4-05 — corridor ceiling lights and recurring wall fixtures.
4. **gate-room draw calls = 52** is already low; the FPS bottleneck on real
   hardware will be fragment work (90 K triangles + bloom + per-scene
   exposure 1.15), not draw-call overhead. S4-06 (post profiles) is the
   right knob, not S4-05 (instancing).
5. **TTI is already under the 4 s target in dev (~2 s).** Risk is that prod
   cold-start over broadband adds asset-download time on top — re-measure
   on `wrangler pages dev` of the built dist for a true number.
6. **Headless swiftshader FPS is unreliable as an absolute number.** Plan for
   the post-sprint comparison: re-run the same `scripts/perf-baseline.ts` on
   the same M-series host with the same headless flags. The target is
   "−25 % vs this run", not "60 fps absolute".

## Caveats

- Prod build emitted two dynamic-vs-static-import warnings for
  `destiny-ship.glb` and `destiny-restored-start.png` — these prevent rollup
  from chunk-splitting those assets. Worth fixing in S4-10 if pursued.
- `__sguRenderer` exposure on `window` is dev-only (gated by
  `import.meta.env.DEV`) — the prod-build perf script cannot read
  `renderer.info`. We use prod build output for byte numbers and dev-mode
  for renderer.info numbers; both are correct for what they measure since
  `info.render.calls/triangles` is geometry-driven, not bundling-driven.
