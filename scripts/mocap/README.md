# Video → VRMA pipeline (no Blender)

Turn reference **video** into game-ready `public/assets/animations/eli-*.vrma` files.

```
  Reference video (≤15s clip, full body visible)
           │
           ▼
  AI mocap app (browser) ──►  .bvh  (or .fbx)
           │                    │
           │ optional keyframe   │
           │ edits in same app   │
           ▼                    ▼
  bun scripts/convert-bvh-to-vrma.ts  motion.bvh  public/assets/animations/eli-name.vrma
           │
           ▼
  Add alias in vrm-player-animation-controller.ts → playtest in gate room
```

You do **not** need Blender or Mixamo. The only local step is the one-line BVH→VRMA convert (already in this repo).

---

## Recommended: [Plask Motion](https://plask.ai/) (browser, keyframe edits)

Best fit if you want **video mocap + light frame tweaks** without learning Blender.

| | |
|---|---|
| **Input** | Upload MP4 or record |
| **Output** | **BVH**, FBX, or GLB |
| **Editing** | Adjust keyframes in Plask after extract ([docs](https://plask.ai/en-US/docs/4)) |
| **Free tier** | ~15 seconds of mocap per day ([pricing](https://plask.ai/en-US/pricing)) |

### Steps

1. **Prepare video**
   - One person, **full body in frame** the whole clip.
   - Good lighting, plain background, avoid baggy/black clothes.
   - Trim to **≤15 seconds** for free tier (jump cycle, strafe, emote, etc.).
   - Use your own footage or properly licensed reference (see Legal below).

2. **Plask — extract motion**
   - Open [Plask Motion](https://plask.ai/) → **MoCap** mode.
   - Upload video → run extract (enable **Foot lock** for locomotion).
   - Drag motion onto a humanoid model.

3. **Plask — tweak (optional)**
   - Scrub timeline and fix bad frames (docs: “Adjust specific keyframes”).

4. **Plask — export BVH**
   - Select model in Outliner → **Export** → format **BVH** → pick FPS (30 recommended) → download.

5. **Convert to VRMA (this repo)**

```bash
bun scripts/convert-bvh-to-vrma.ts ~/Downloads/plask-export.bvh public/assets/animations/eli-strafe-left.vrma
```

6. **Wire into game**
   - Add filename to `clipSpecs` in `src/systems/vrm/vrm-player-animation-controller.ts` if needed.
   - Update `public/assets/animations/ATTRIBUTION.md` (source + license).
   - Playtest: gate room has `canJump: true`.

---

## Alternative: [Rokoko Vision](https://vision.rokoko.com/) + [Rokoko Studio](https://www.rokoko.com/products/studio)

| | |
|---|---|
| **Input** | Webcam or uploaded video |
| **Free** | Clips up to **15 seconds** |
| **Output** | FBX or BVH via Studio (export after cleanup / foot lock) |
| **Docs** | [Vision FAQ](https://www.rokoko.com/products/vision), [Studio download](https://www.rokoko.com/products/studio/download) |

Workflow: capture on [vision.rokoko.com](https://vision.rokoko.com/) → open in **Rokoko Studio** (same account) → foot-lock filter → export **BVH** → run `convert-bvh-to-vrma.ts` as above.

Note: Some Studio export options may require a paid plan; verify BVH export on your account. If only FBX is available, ask for a follow-up — we can add `convert-fbx-to-vrma.ts` using the same retarget path as runtime.

---

## Open-source / DIY (more setup, no daily cap)

| Tool | Notes |
|------|--------|
| [bvh2vrma (web)](https://vrm-c.github.io/bvh2vrma/) | Same conversion as our script; use after any tool that outputs BVH |
| [video_to_bvh (Colab)](https://github.com/Dene33/video_to_bvh) | Old but zero install; Google Colab → download BVH |
| [FreeMoCap](https://github.com/freemocap/freemocap) | Best with **multiple cameras**; overkill for quick game clips |
| [MoCapAnything](https://github.com/animotionlab26/MocapAnything) | Research-grade video→skeleton; needs Python/GPU setup |

These are **not** wired into the game repo yet — use them only if you outgrow Plask/Rokoko.

---

## What the repo convert script does

`scripts/convert-bvh-to-vrma.ts` uses [vrm-c/bvh2vrma](https://github.com/vrm-c/bvh2vrma) logic (`scripts/bvh-converter/`):

- Maps BVH skeleton → VRM humanoid bones (heuristics + optional ACCAD name table in `accadBoneMap.ts`)
- Skips BVH `End Site` leaf nodes
- Writes `.vrma` (glTF + `VRMC_vrm_animation`) at `scale = 0.01`

**VRoid warning:** BVH→VRMA exports often retarget poorly on VRoid models (mesh distortion / T-pose). Prefer **native `.vrma`** from [VRoid motion pack](https://booth.pm/en/items/5512385), [sashii CC0 pack](https://booth.pm/en/items/7861818), or Blender VRM Add-on export. Use this script only for prototyping.

**Expect to iterate:** video mocap often needs trimming, foot-lock, or re-shooting. Sideways root motion in BVH can look wrong until the character faces camera-forward while airborne (already handled for jump in `vrm-player-controller.ts`).

---

## Tips for usable game locomotion

- **Looping:** trim video so first/last pose are similar, or blend in Plask keyframes.
- **Scale:** if feet slide, re-export with foot lock or shorten clip to the “clean” section only.
- **Duration:** match game jump air time (~0.5–1.2s); use Plask timeline to shorten or raise `timeScale` in the animation controller.
- **Test early:** convert one clip and press Space in gate room before batching more videos.

---

## Legal

- Use **your own** performances, stock/CC footage, or clips you have rights to.
- Do not ship mocap traced from commercial game trailers or films without permission.
- Keep credits in `ATTRIBUTION.md` (Plask/Rokoko terms + any stock video license).

---

## Future automation (not built yet)

Possible later steps if this workflow sticks:

1. `scripts/convert-fbx-to-vrma.ts` — Rokoko FBX without Blender ([tk256ailab/fbx2vrma-converter](https://github.com/tk256ailab/fbx2vrma-converter))
2. Headless preview — render Eli with new clip for visual diff tests
3. Optional Docker wrapper around a Python video→BVH model (heavy maintenance)

See also: `design/gdd/animation-authoring.md`
