# Sprint 4 — 2026-05-21 to 2026-06-03

## Sprint Goal

**Performance & visual-fidelity uplift.** Close the gap between SGU and reference
browser-3D games (e.g. Hollowlands — see
`memory/reference_hollowlands_patterns.md`). Land the modern asset pipeline
(DRACO + KTX2 + Meshopt), add instancing/LOD where it matters, codify per-scene
post-processing, and ship believable character locomotion (idle / walk / run
blend tree) on the first NPC + the player.

Success = (a) measurable frame-time improvement on the gate-room and corridor
scenes, (b) total initial download cut by ≥40 %, (c) Lt. Scott walks instead
of T-poses sliding.

## Capacity

- Total days: 14 calendar days
- Available hours: ~6–8 hrs (holding pattern)
- Buffer (25%): ~1.5 hrs reserved for perf-iteration & PR review
- Productive hours: ~5–6 hrs

## Baseline (capture before starting work)

S4-01 below is gated on this. Numbers go in `production/perf-baseline-2026-05-21.md`.

| Metric | How | Target after sprint |
|---|---|---|
| Frame time @ gate-room (median, M-series) | Stats.js / `renderer.info` | −25 % |
| Frame time @ destiny-corridor | same | −25 % |
| Total JS + asset bytes (first load) | Network panel, cached off | −40 % |
| Largest single asset | Network panel | <1.5 MB |
| Time to first interactive (start menu → playable) | Manual stopwatch | <4 s on broadband |
| Draw calls @ gate-room | `renderer.info.render.calls` | −30 % |

## Tasks

### Must Have (Critical Path)

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Notes |
|----|------|----------|-------------|--------------------|-------|
| S4-01 | **Perf baseline capture** — Run gate-room + destiny-corridor + cinematic, record FPS, draw calls, triangle count, total bytes, largest asset, TTI. Commit baseline doc. | 0.5 | — | `production/perf-baseline-2026-05-21.md` exists with table populated for all 3 scenes. | Use `renderer.info` + Network panel. No code change. |
| S4-02 | **Asset pipeline: DRACO + Meshopt for glTF** — Add `gltf-transform` to scripts/, batch-compress every `.glb` under `assets/` and `public/` to DRACO+Meshopt variants. Wire `DRACOLoader` + `MeshoptDecoder` into the loader path (likely in ggez `three-runtime`/`render-pipeline` wrapper or our loader call sites). | 2 | S4-01 | All glb assets ship compressed. Existing scenes still load. Bundle audit shows ≥30 % reduction in asset bytes. | Hollowlands ships both — DRACO for geometry indices, Meshopt for vertex attrs. |
| S4-03 | **Asset pipeline: KTX2 / basisu for textures** — Add KTX2 transcoding step (toktx via `gltf-transform` or `@gltf-transform/cli`). Wire `KTX2Loader` with transcoder path. Verify gate-room runtime.json textures load on WebGPU and WebGL. | 2 | S4-02 | Textures ship as `.ktx2`. VRAM dropped (verify via about://gpu or `renderer.info.memory.textures`). No visible quality regression on gate-room hero shot. | Test WebGPU path explicitly — KTX2 is the supported route on WebGPURenderer. |
| S4-04 | **Character locomotion blend (Lt. Scott + player)** — Author/import idle, walk, run clips into the existing `@ggez/anim-runtime` graph. Drive blend by horizontal speed. Apply to S3-03 NPC and to the local player VRM. | 2.5 | Sprint 3 NPC merged | NPC and player both visibly transition idle ↔ walk ↔ run when speed crosses thresholds. No T-pose at any speed. Foot-slide acceptable for now (root-motion is a later sprint). | Use Mixamo-extracted clips or existing VRM-Animation files in `src/animations/`. |

### Should Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Notes |
|----|------|----------|-------------|--------------------|-------|
| S4-05 | **InstancedMesh sweep — gate-room ring lights & corridor ceiling lights** — Convert N identical light-housing meshes per scene into a single `InstancedMesh`. | 1 | S4-01 | Draw calls in gate-room drop by ≥10. Visuals unchanged. | First instancing pass; pick 1–2 obvious clusters, don't rabbit-hole. |
| S4-06 | **Postprocessing profiles per scene** — Define `cinematic`, `interior`, `exterior` post profiles (Bloom + Vignette + ToneMapping + SMAA). Each scene declares which profile it uses. Replaces ad-hoc per-scene exposure overrides. | 1.5 | S4-01 | `src/post/profiles.ts` exists with 3 named profiles. Every scene declares one. Gate-room and corridor visually match (or exceed) prior look. | Built on Three's `EffectComposer`, not @react-three/postprocessing — we're vanilla. |
| S4-07 | **`leva` for visual tuning (dev only)** — Add leva panel exposed only when `import.meta.env.DEV`. Bind: per-scene exposure, key-light intensity, bloom threshold/intensity, vignette darkness. Confirm tree-shaken from prod build. | 1 | S4-06 | In dev: panel visible, sliders update scene live. In prod build (`bun run build && bun run preview`): leva absent from network panel & DOM. | Replaces 6+ memory entries' worth of "tweak this constant, rebuild, look again". |

### Nice to Have

| ID | Task | Est. Hrs | Dependencies | Acceptance Criteria | Notes |
|----|------|----------|-------------|--------------------|-------|
| S4-08 | **CSM (cascaded shadow maps) for any scene with a sun-style key light** — If a planet exterior is in scope this sprint, wire `three-csm`. Otherwise plan only. | 1.5 | S4-06 | If implemented: shadows crisp near camera, soft far. If deferred: design note in `design/gdd/` justifying. | Hollowlands uses CSM for sun. Premature without an outdoor scene; flag for Sprint 5. |
| S4-09 | **Mobile virtual joystick (touch input)** — Add a single nipple-style joystick + a primary-action button, gated by `(pointer: coarse)` media query. | 1.5 | — | Game playable on iPad — can walk to gate, trigger Lt. Scott dialogue. | Triples potential audience for playtest. |
| S4-10 | **Bundle-split by scene (Vite `rollupOptions.manualChunks`)** — Lazy-load each scene module so start menu doesn't pull every scene's geometry/JSON. | 1 | S4-02 | Network panel shows scene chunks loading on `?scene=…` navigation, not on initial start. | Lower TTI for start menu specifically. |

## Carryover / parking lot (from Sprint 3 if not landed)

| Task | Disposition |
|------|-------------|
| S3-08 Reflector wet-floor | Re-evaluate once S4-06 post profiles land — bloom may make a wet floor unnecessary. |
| S3-07 Concept-art diff harness | Push to Sprint 5 unless trivial. |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| KTX2 transcoder path mis-served on Cloudflare Pages (CORS / MIME) | Textures fail to load on prod | Test on `localhost:5173` per existing memory note, then `wrangler pages dev` before deploy. |
| `@ggez/render-pipeline` doesn't expose loader hooks for DRACO/KTX2 | Have to fork or monkey-patch | Time-box S4-02 investigation to 30 min before deciding fork-vs-wrap. |
| WebGPURenderer + KTX2 path quirks | Textures black or missing | Have WebGL fallback path tested simultaneously; gate-room renders on both today. |
| Animation clips don't retarget cleanly to VRM | NPC twitches | We already have `@ggez/anim-three` retargeting working for the cinematic; reuse that path. |
| Scope creep into "everything visual" | Sprint slips | Keep S4-08 and S4-09 strictly Nice-to-Have. |

## Out of scope (explicitly deferred)

- Multiplayer / Colyseus integration (long-term)
- Procedural planet generation (Sprint 5+)
- IK foot-locking / root-motion locomotion (Sprint 5+)
- Migrating to `koota` ECS — we have ggez bitECS already
- Full WebGPU NodeMaterial conversion of existing materials

## Ordering notes

S4-01 → S4-02 → S4-03 is the critical chain (baseline, then geometry compression,
then texture compression). S4-04 (animation) can run in parallel — it touches
different files. S4-06/S4-07 (post + leva) are best done as a pair: leva exists
to tune the post profiles. S4-05 (instancing) is independent and a good filler
when blocked on something else.
