# Rifle aim host pipeline

**Status:** process locked — do **not** invent aim poses with analytic IK on
stylized / broken hosts. Start from a **working Mixamo humanoid + mocap clip**,
then retarget / mount weapons / decide what Mint Eli can reuse.

**Last updated:** 2026-07-19 (first successful Mixamo Swat + Rifle Idle proof).

---

## The rule (read this first)

Rifle aim is a **solved content problem**, not a novel IK research problem.

| Do | Don't |
|---|---|
| Download Mixamo **Y-Bot / X-Bot** (or upload our host to Mixamo) | Invent shouldered aim with euler probes on OpenBot |
| Download Mixamo **Rifle Idle** / **Holding Rifle** (in-place) | Set pose-bone world matrices on a glTF Rigify dump |
| Attach weapon with **Child Of → hand bone → Set Inverse** | Seat a rifle between mitten leaf-bones and call it done |
| Retarget into Godot via **BoneMap + SkeletonProfileHumanoid** | Assume Meshy 24-bone Eli can grow fingers from code |
| Treat ARDY as **offline / sidecar motion gen** later | Expect ARDY to be a Godot AnimationTree drop-in today |

If a pose does not already look correct on a **standard Mixamo skeleton in
Blender's viewport**, it will not look correct in Godot.

---

## Why we were stuck

Three different problems were conflated:

1. **Host skeleton** — Mint Meshy Eli is ~24 bones; hands are leaves (no finger
   chains). Industry mounts need `RightHand` + finger bones.
2. **Animation source** — a shouldered two-hand rifle idle is mocap / authored
   content. Procedural “solve the arms to empties” is a polish pass *after*
   you have a good clip, not a substitute for one.
3. **Runtime mount** — once the hands are already posed by the clip, the gun is
   a bone child (or a small IK polish on the support hand). Mount tuning is
   centimeters and degrees, not full-body IK.

OpenBot (`models/mixamo_openbot/`) was meant as a **finger-bone proof host**.
It is Mixamo-*compatible*, but the glTF we have is a Rigify-style dump
(`hand.R`, `c.*`, `MCH-*`) **without** live Rigify constraints. Treating it as
a blank canvas for analytic IK was the wrong workflow.

---

## Failure log (2026-07 Blender MCP sprint)

Keep these so we do not repeat them.

| Attempt | What we did | Result | Lesson |
|---|---|---|---|
| A | Godot `TwoBoneIK3D` on Meshy Eli | Arms flipped behind back | Wrong bone axes vs Mixamo; mitten host |
| B | Soft 2H pull / absolute euler “aim” on Eli | Floaty gun, Idle fidget | Need locked aim clip + mount, not fidget Idle |
| C | OpenBot + pose-bone **world-matrix** 2-bone IK | Noodle limbs, torn shoulders | Direct `pb.matrix = …` on this glTF tears skin weights |
| D | Bone-parent rifle via `matrix_parent_inverse` (Blender 5) | Rifle flipped 180° | Prefer **Child Of + Set Inverse**, or freeze world xform for static proofs |
| E | Rest-relative euler deltas copied from Godot proof | Arms went **backward** | Blender `matrix_basis` axis signs ≠ Godot bone-pose deltas; probe per-rig |
| F | Mesh-centroid “snap palms to grip” after matrix IK | Centroid error ≈ 0 while hands looked floating | Metric lied — mesh was stretched *to* the target |
| G | Left-arm euler search for cross-body forestock | Best hand.L still `x≈+0.28` | Don't force anatomy; use a mocap clip that already crosses |

**Abandoned for aim authoring:** `tools/blender_openbot_rifle_aim.py` as a
source of truth. Keep only as a negative example / import helper notes.
Do not iterate it further for rail-aim quality.

**Still valid:** Blender MCP socket setup (`tools/blender_start_mcp.py`,
addon under `~/Library/Application Support/Blender/5.2/scripts/addons/`).

### Success log (2026-07-19)

| Step | Result |
|---|---|
| Copied Mixamo FBXs from `~/Downloads` → `models/mixamo_openbot/incoming/` | Rifle Idle, Firing Rifle, Walk With Rifle, Pull Out, Put Back, Aim To Down, Start Run + Swat / X Bot / Remy hosts |
| `Rifle Idle.fbx` | Anim-only, frames 1–86, `mixamorig:*` + full fingers |
| `Swat.fbx` | Skinned host (Soldier_body / Soldier_head), 69 bones |
| Blender 5 action bind | **Must** set `animation_data.action_slot = action.slots[0]` or pose stays T-pose |
| Mixamo scale | Armature scale 0.01 + scale fcurves — strip `.scale` fcurves, `edit_bone.inherit_scale = NONE` before bone-parenting props |
| Gun mount | Span RH→LH with rifle local grip/support landmarks; bone-parent to `mixamorig:RightHand` |
| Outputs | `Swat_rifle_idle.blend` / `.glb`, shots under `screenshots/result/mint_rifle_aim/swat_rifle_idle*.png` |
| Builder script | `tools/blender_mixamo_rifle_idle.py` |

Remaining polish (not blockers for the process): support-hand slip (~12 cm),
stock deeper into shoulder pocket, opaque textured rifle material, import the
other rifle clips into one AnimationLibrary.

---

## Canonical pipeline (Mixamo → Blender → Godot)

This is the industry-default path. Follow it in order.

### 0. Prerequisites

- Adobe account → [mixamo.com](https://www.mixamo.com/)
- Blender 4.x / 5.x (project also uses 5.2 LTS via MCP)
- Godot 4.6 with glTF import

### 1. Get a **working** humanoid (do this before any gun work)

1. On Mixamo, pick **Y-Bot** or **X-Bot** (full finger bones, known rest).
2. Download **character** FBX: *With Skin*, T-pose / bind pose.
3. Optionally: upload Mint Eli / OpenBot mesh to Mixamo auto-rigger **only
   after** the Y-Bot path proves the mount + aim clip in-engine.

Drop files here (gitignored if needed — Mixamo ToS; do not redistribute):

```
models/mixamo_openbot/incoming/
  YBot.fbx                 # with skin
  Rifle_Idle.fbx           # anim only, without skin, in-place
  Rifle_Aiming_Idle.fbx    # optional second clip
```

### 2. Get a **working** rifle aim animation

Mixamo search terms (names vary; pick the preview that is clearly shouldered):

- `Rifle Idle`
- `Idle Aiming`
- `Rifle Aiming Idle`
- `Holding Rifle`

Download settings:

- **Skin:** Without Skin (animation only) for anim FBXs
- **Frames per second:** 30
- **In-place:** on (for aim/idle; root motion only for loco packs)

You should see, in Mixamo's own preview: stock in shoulder pocket, both hands
on the weapon, fingers curled. **If Mixamo's preview is wrong, pick another
clip — do not "fix" it with IK yet.**

### 3. Blender: one armature, clip applied, weapon mounted

Reference workflows:

- Combine Mixamo clips in Blender (NLA / action bind):  
  [Gachoki — combine Mixamo animations](https://gachoki.com/combine-and-blend-mixamo-animations-in-blender/)
- Attach props to Mixamo hand bone:  
  [Blender SE — Child Of + Set Inverse](https://blender.stackexchange.com/questions/238138/how-i-can-attach-object-into-mixamo-animation-model)

Steps:

1. Import `YBot.fbx` (skin).
2. Import `Rifle_Idle.fbx` (no skin). Bind action to the Y-Bot armature;
   delete duplicate armatures.
3. Scrub timeline — confirm shouldered aim **before** adding a gun.
4. Import `models/mint/props/rifle.glb`.
5. Select rifle → **Constraints → Child Of** → target = armature, bone =
   `mixamorig:RightHand` (or `RightHand`).
6. Align grip visually → **Set Inverse** on the constraint.
7. Optional polish only: IK the **left** hand to a forestock empty parented
   to the rifle (support-hand slip). Bake visual keyframes if exporting a
   locked clip.
8. Export **glTF 2.0** (`.glb`):
   - Selected armature + mesh + rifle
   - Animations on
   - For posed-static proofs: `export_rest_position_armature=False` so the
     current pose is not wiped

Output targets (current proof uses **Swat**, same pipeline as Y-Bot):

```
models/mixamo_openbot/Swat_rifle_idle.glb      # proof host + Rifle Idle + gun
models/mixamo_openbot/Swat_rifle_idle.blend    # editable source
# Builder: tools/blender_mixamo_rifle_idle.py  (Blender MCP or `blender -b -P …`)
```

### 4. Godot: retarget, don't re-solve

Godot docs: [Retargeting 3D skeletons](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html).

1. Import the glb / anim libraries as **AnimationLibrary** where appropriate.
2. On Skeleton3D import: **BoneMap** + **SkeletonProfileHumanoid**.
3. Disable **Remove Immutable Tracks** if finger tracks disappear.
4. Optional automation: [MixaBridge](https://github.com/uzairdeveloper223/mixabridge)
   (Godot 4.4+ Mixamo BoneMap helper).
5. Runtime mount (if gun is not baked into the glb): `BoneAttachment3D` on
   `RightHand` / mapped hand bone — tune once against the **playing** Rifle
   Idle clip, not against T-pose.

Capture gate:

```bash
Godot --path . --quit-after 12000 -s res://tests/capture/openbot_rifle_aim_proof.gd
```

Point that proof at `YBot_rifle_idle.glb` once it exists (update the const).

### 5. Only then: Mint Eli / OpenBot decisions

| Question | Gate |
|---|---|
| Can Eli use upper-body aim overlay from Meshy clips? | Keep current gameplay hack until Y-Bot proof ships |
| Do we swap Eli's host to a finger rig? | Only after Y-Bot rifle idle looks good in lab |
| Do we Mixamo-auto-rig Eli's mesh? | After mount offsets are known on Y-Bot |
| OpenBot? | Use as Mixamo retarget *target* with real clips — not as IK sandbox |

---

## NVIDIA ARDY — what it is (and is not)

Project: [ARDY](https://research.nvidia.com/labs/sil/projects/ardy/) ·
code: [nv-tlabs/ardy](https://github.com/nv-tlabs/ardy) · SIGGRAPH 2026 / TOG.

### What it is

- **Autoregressive diffusion** for **interactive / streaming** humanoid motion.
- Conditions on **online text prompts** + flexible **kinematic constraints**
  (root path/waypoints, full-body keyframes, sparse joint pos/rot, long-horizon).
- Hybrid representation: explicit root + latent body.
- Open weights (NVIDIA Open Model License) + Apache-2.0 code.
- Skeletons today: **Core** (Bones Rigplay), **Unitree G1**; SOMA coming.
- Export path from their tooling: `.npz` (`posed_joints`, rotations, root,
  contacts) and G1 MuJoCo-qpos `.csv` — then **retarget** (they show UE
  MetaHuman / SOMA Retargeter workflows; not a Godot plugin).

### What it is not (for this sprint)

- Not a Godot `AnimationPlayer` replacement.
- Not a one-click “make Mint Eli aim a rifle” button.
- Not a substitute for Mixamo Rifle Idle for the vertical slice.
- Needs serious local setup: PyTorch CUDA, ~14GB+ VRAM for text encoder paths,
  gated Llama-3 access for the demo text encoder, CMake for motion-correction
  ext.

### When we should use it

| Horizon | Use |
|---|---|
| **Now (E1 / Mint aim)** | Mixamo Rifle Idle on Y-Bot → Godot BoneMap |
| **Next** | ARDY CLI `generate.py` for custom aim/loco variants → retarget via Blender/SOMA onto our humanoid profile |
| **Later** | Sidecar service streaming constraints (hand on forestock, root waypoints) into a retarget → Godot buffer — research spike, not blocking |

Related NVIDIA stack (retarget / data, not required for Mixamo path):

- [SOMA Retargeter](https://github.com/NVlabs/SOMA-X) / SOMA body model
- [Bones SEED](https://huggingface.co/datasets/bones-studio/seed) mocap CSVs
- [Kimodo](https://research.nvidia.com/labs/sil/projects/kimodo/) — offline
  constrained motion diffusion (higher quality, not realtime)

---

## Decision tree (agents: follow this)

```
Need shouldered rifle aim?
├─ Do we have Mixamo Rifle Idle (or equal mocap) on a fingered humanoid in-repo?
│  ├─ NO → STOP. Ask human for Mixamo FBX drop under incoming/. Do not IK.
│  └─ YES → Blender Child Of mount → export glb → Godot BoneMap → capture.
├─ Want generated variants (text / constraints)?
│  └─ ARDY generate.py → npz → retarget onto same humanoid profile (spike).
└─ Mint Eli mittens only?
   └─ Keep gameplay overlay; do not claim "realistic grip" until host upgrade.
```

---

## Checklist — “process success”

A run counts as successful only if **all** are true:

- [ ] Y-Bot (or Mixamo-rigged host) plays Rifle Idle in Blender without custom IK
- [ ] Rifle Child-Of'd to right hand; stock reads in shoulder pocket in viewport
- [ ] Left hand contacts forestock (clip or tiny support IK, baked)
- [ ] `YBot_rifle_idle.glb` imports in Godot; AnimationPlayer plays the clip
- [ ] Capture PNG under `screenshots/result/mint_rifle_aim/` shows shouldered hold
- [ ] Mint Eli changes are a **separate** retarget/host decision, not a blocker

---

## Pointers

- Host folder notes: `models/mixamo_openbot/AGENTS.md`
- Godot retarget: engine docs + optional MixaBridge
- Blender MCP launcher: `tools/blender_start_mcp.py`
- Negative example script: `tools/blender_openbot_rifle_aim.py`
- Proof capture (update path when Y-Bot glb lands):  
  `tests/capture/openbot_rifle_aim_proof.gd`
