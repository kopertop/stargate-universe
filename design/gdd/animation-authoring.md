# Animation authoring — VRMA pipeline for Stargate Universe

**Status:** research / planning  
**Goal:** Add and tweak player locomotion clips (`public/assets/animations/*.vrma`) without sideways retarget bugs or one-off manual hacks.

**Operational guide (video mocap, no Blender):** [`scripts/mocap/README.md`](../../scripts/mocap/README.md)

---

## Video → VRMA (no Blender, no Mixamo) — recommended path

If you do not want to learn Blender or use Mixamo, use **AI video mocap → BVH → repo script → VRMA**:

```
Video (reference)  →  Plask / Rokoko Vision  →  .bvh  →  convert-bvh-to-vrma.ts  →  eli-*.vrma
                              ↑
                    keyframe fixes in browser (Plask)
```

| Step | Tool | You do |
|------|------|--------|
| 1 | Phone / stock video | Film or download a **≤15s** clip; full body visible |
| 2 | [Plask Motion](https://plask.ai/) | Upload → extract mocap → optional keyframe edits → **export BVH** |
| 3 | This repo | `bun scripts/convert-bvh-to-vrma.ts motion.bvh public/assets/animations/eli-jump.vrma` |
| 4 | Game | Add alias if needed; playtest |

**Why not fully automatic inside the game yet:** video→skeleton AI is large (GPU models, quality tuning, licensing). The practical split is: **free/cheap cloud mocap** (human picks the video and fixes bad frames) + **one command** we already maintain for VRMA.

**Alternatives:** [Rokoko Vision](https://vision.rokoko.com/) (free ≤15s) + Studio export; open-source Colab `video_to_bvh` for batch experiments. Details in `scripts/mocap/README.md`.

**Not in scope today:** ripping animations from commercial game footage without rights; real-time webcam drive in-engine (different feature).

---

## What VRMA is (short)

[VRM Animation (`.vrma`)](https://vrm.dev/en/vrma/) is a **glTF binary** with the `VRMC_vrm_animation` extension. It stores:

- Humanoid bone **rotations** (and hips/spine **translation** for locomotion)
- Optional expression / look-at tracks

Any VRM 1.0 humanoid can play the same file after retargeting in `@pixiv/three-vrm-animation` (already used in `vrm-player-animation-controller.ts`).

**Implication:** Authoring tools do not need to know about Eli’s mesh — they only need a valid humanoid rig in **T-pose** at frame 0.

---

## Recommended toolchain (use these first)

### 1. Blender + [VRM Add-on for Blender](https://vrm-addon-for-blender.info/en-us/) — **primary editor**

| | |
|---|---|
| **Frame-by-frame** | Yes — Dope Sheet / Graph Editor / NLA |
| **VRMA export** | `File → Export → VRM Animation (.vrma)` |
| **VRMA import** | `File → Import → VRM Animation (.vrma)` to preview on a VRM |
| **Cost** | Free (Blender Extensions on 4.2+) |
| **Docs** | [Export VRMA](https://vrm-addon-for-blender.info/en-us/ui/export_scene.vrma/), [Import VRMA](https://vrm-addon-for-blender.info/en-us/ui/import_scene.vrma/) |

**Workflow for a new jump / strafe / emote:**

1. Import Eli (or any reference VRM) into Blender.
2. Import an existing `eli-*.vrma` to see scale/timing, or start from rest pose.
3. Keyframe bones on the timeline (24–30 FPS is fine).
4. Export **VRM Animation (.vrma)** only (not the whole character).
5. Drop into `public/assets/animations/eli-<name>.vrma`.
6. Add alias in `vrm-player-animation-controller.ts` `clipSpecs` if the filename differs.
7. Playtest in gate room (`canJump: true`).

**Why this wins:** Real curve editing, copy/paste keys, onion skin (with addons), and official spec support.

---

### 2. [VRM Posing Desktop](https://vpd.elvneko.com/) (Steam / itch) — **fast poses & short clips**

| | |
|---|---|
| **Frame-by-frame** | Pose-oriented (keyframes via pose library + timeline); best for short loops |
| **VRMA export** | Built-in `.vrma` export |
| **Cost** | Free on Steam |
| **Also exports** | `.anim` (Unity), video |

Good for: idle variants, emotes, single poses you then extend in Blender.  
Less good for: long locomotion cycles (use mocap + Blender instead).

---

### 3. [bvh2vrma](https://vrm-c.github.io/bvh2vrma/) — **mocap → VRMA (batch)**

| | |
|---|---|
| **Frame-by-frame** | No (convert whole clip) |
| **Input** | `.bvh` (ACCAD, Mixamo-exported BVH, Rokoko, etc.) |
| **Cost** | Free, MIT ([source](https://github.com/vrm-c/bvh2vrma)) |

**Repo already mirrors this:** `scripts/convert-bvh-to-vrma.ts` + `scripts/bvh-converter/` (same conversion logic, runnable offline):

```bash
bun scripts/convert-bvh-to-vrma.ts path/to/motion.bvh public/assets/animations/eli-jump.vrma
```

**Caveats (from vrm-c):**

- Source skeleton should start near **T-pose**.
- Transition clips (walk→jump→walk) need **trimming** in Blender or a start time offset in code (we removed ACCAD wind-up for native jump clips).
- Lateral mocap often looks “sideways” unless the character **faces camera forward** while airborne (already handled in `vrm-player-controller.ts`).

**Free mocap source:** [ACCAD Female1 BVH zip](https://accad.osu.edu/sites/accad.osu.edu/files/Female1_bvh.zip) (CC BY 3.0).

---

### 4. Mixamo → Blender → VRMA — **automatic-ish humanoid clips**

1. Download FBX from [Mixamo](https://www.mixamo.com/) (e.g. “Jump”, “Left Strafe Walk”).
2. Import FBX in Blender (with VRM add-on installed).
3. Retarget / verify on your VRM armature (or use Mixamo skeleton then export animation-only VRMA if bones map cleanly).
4. Export `.vrma`.

**License:** Mixamo terms apply — check Adobe license for your shipping use.

---

### 5. Unity + [UniVRM](https://vrm.dev/en/vrma/univrm-vrma/vrma-export/) — **if you already live in Unity**

- Menu: experimental BVH → VRM Animation conversion.
- Programmatic export via `VrmAnimationExporter` (sample frames from `AnimationClip`).
- Frame editing via Unity Animation window.

Use when the rest of your content pipeline is Unity-based; otherwise Blender is simpler for this web game.

---

### 6. Free VRoid sample pack (no dedicated jump)

[VRoid Project — 7 free VRMA motions](https://booth.pm/en/items/5512385) (0 JPY): greet, spin, squat, etc.  
**No jump** in the pack; squat (`VRMA_07`) can stand in for a crouch-only beat.  
Credit: `Character animation credits to pixiv Inc.'s VRoid Project` for commercial use.

---

### 7. MIT sample jump (current `eli-jump.vrma`)

[`Jump.vrma`](https://github.com/tk256ailab/vrm-viewer/blob/main/VRMA/Jump.vrma) from [tk256ailab/vrm-viewer](https://github.com/tk256ailab/vrm-viewer) — already in repo.  
Good for prototyping; replace when Blender-authored jump is ready.

---

## Comparison table

| Tool | Edit frames | Export VRMA | Auto / batch | Best for |
|------|-------------|-------------|--------------|----------|
| Blender VRM Add-on | ✅ | ✅ | — | **Main authoring** |
| VRM Posing Desktop | poses / short | ✅ | — | Emotes, quick poses |
| bvh2vrma / repo script | ❌ | ✅ | ✅ | Mocap import |
| Mixamo + Blender | ✅ | ✅ | semi | Standard locomotion |
| UniVRM (Unity) | ✅ | ✅ | code | Unity teams |
| In-browser (planned) | ✅ | ✅ | future | Fast iteration in-dev |

---

## What we already have in this repo

| Asset | Purpose |
|-------|---------|
| `public/assets/animations/*.vrma` | Runtime clips (`female-idle`, `eli-walk`, `eli-run`, `eli-jump`) |
| `public/assets/animations/ATTRIBUTION.md` | Licenses |
| `scripts/convert-bvh-to-vrma.ts` | Offline BVH → VRMA |
| `scripts/bvh-converter/*` | vrm-c/bvh2vrma logic (MIT) |
| `src/ui/editor/vrm-editor.ts` | Character **look** editor (materials / gear / visibility) — **not** animation |
| `src/systems/vrm/vrm-player-animation-controller.ts` | Runtime mixer + jump/strafe logic |

There is **no** animation timeline editor in the game yet.

---

## Should we build an in-browser Animation Lab?

### What “simple frame-by-frame editor” really needs

1. **Skeleton UI** — list VRM humanoid bones; rotate (Euler or quaternion) per bone.
2. **Timeline** — add / delete / duplicate keyframes; scrub time; play range.
3. **Interpolation** — slerp between keys (at minimum stepped + linear).
4. **Preview** — same Three.js + VRM path as the game (avoid “works in editor, broken in game”).
5. **Export** — build `AnimationClip` → glTF + `VRMC_vrm_animation` (reuse `VRMAnimationExporterPlugin` from `scripts/bvh-converter/`).
6. **Import** — load existing `.vrma` for tweak (via `@pixiv/three-vrm-animation`).

That is **weeks** of UX and edge-case work if it should feel like Blender Lite.

### Pragmatic split

| Phase | Scope | Effort |
|-------|--------|--------|
| **Now** | External tools above + repo convert script | Done |
| **Phase 1** | Dev-only **Pose Lab**: capture keyframes on Eli, scrub, export VRMA (no import, no curves) | ~2–4 days |
| **Phase 2** | Import VRMA, copy keys, bone search, FPS / duration | +3–5 days |
| **Phase 3** | Auto-generate from templates (e.g. blend two clips, mirror L/R) | research |

**Recommendation:** Use **Blender + VRM Add-on** for production clips. Build **Phase 1 Pose Lab** only if you want faster in-engine iteration without leaving the browser.

---

## Phase 1 — Pose Lab (proposed in-repo tool)

**Entry:** `?animlab=1` on dev build, or debug overlay button “Animation Lab”.

**UI (minimal):**

```
┌─────────────────────────────────────────────────────────┐
│ [Load VRMA] [Add keyframe] [Delete] [Play] [Export VRMA]  │
│ Frame: ◀ ■ ▶  12 / 60    FPS: 30                        │
├──────────────────┬──────────────────────────────────────┤
│ Bone list        │  Three.js preview (orbit camera)      │
│  hips            │                                       │
│  spine           │                                       │
│  leftUpperArm …  │                                       │
│  (sliders)       │                                       │
└──────────────────┴──────────────────────────────────────┘
```

**Data model:**

```ts
type AnimKeyframe = {
  time: number; // seconds
  bones: Partial<Record<VRMHumanBoneName, { rotation: [x,y,z,w] }>>;
};
```

**Export path:** keyframes → `THREE.AnimationClip` → `convertBVHToVRMAnimation`-style GLTF export (new `exportVrmaFromClip(vrm, clip)` shared with scripts).

**Reuse:** `vrm-editor-preview.ts` orbit renderer; `loadAnimation` / humanoid bone nodes from `@pixiv/three-vrm`.

---

## Automatic generation (ideas, not implemented)

| Approach | Description |
|----------|-------------|
| **Mirror** | Duplicate `strafe-left` keys flipped for `strafe-right` |
| **Time-warp** | Scale clip `timeScale` in controller (already used for jump) |
| **BVH batch** | Folder of BVH → `scripts/convert-bvh-to-vrma.ts` in CI |
| **LLM / procedural** | High risk for gameplay loops; not recommended without mocap validation |

---

## Suggested next clips to author

| Clip | Suggested source |
|------|------------------|
| `eli-strafe-left` / `eli-strafe-right` | Mixamo strafe walk → Blender → VRMA, or mirror one side in Blender |
| `eli-jump` (replace) | Blender keyframed vertical jump on Eli armature |
| `eli-fall` / `eli-land` | Optional; ACCAD or short Blender cycle |
| `eli-interact` | VPD pose → Blender cleanup → VRMA |

---

## Decision

**No Blender / no Mixamo:** Video → [Plask](https://plask.ai/) (or Rokoko Vision) → BVH → `bun scripts/convert-bvh-to-vrma.ts` — see [`scripts/mocap/README.md`](../../scripts/mocap/README.md).

**Optional precision path:** Blender VRM Add-on when you need polish beyond Plask keyframes.

**Build in-game:** Phase 1 Pose Lab only after explicit approval (separate from the existing character appearance editor).

---

## References

- [VRM Animation spec](https://vrm.dev/en/vrma/)
- [VRM Add-on for Blender](https://vrm-addon-for-blender.info/en-us/)
- [bvh2vrma (web)](https://vrm-c.github.io/bvh2vrma/)
- [UniVRM VRMA export](https://vrm.dev/en/vrma/univrm-vrma/vrma-export/)
- [VRM Posing Desktop](https://vpd.elvneko.com/)
- [tk256ailab/vrm-viewer](https://github.com/tk256ailab/vrm-viewer) (sample VRMA set)
