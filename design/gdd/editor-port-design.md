# Editor Port Design: react-three-game -> vibe-game-engine

> **Status**: Decisions made — Phase 1 execution starting
> **Source**: `prnthh/react-three-game` v0.0.83 (commit HEAD as of 2026-04-15)
> **Target**: `@kopertop/vibe-game-engine` + new `@kopertop/vibe-game-engine-editor` package
>
> ## Decisions (2026-04-15)
> 1. **UI framework**: **Preact + shadow DOM** for editor panels. ~3KB dep, declarative, scoped styles. Runtime package stays Preact-free; only the editor package imports it.
> 2. **Scene format**: **Prefab JSON is canonical.** `scene.runtime.json` becomes a derived build artifact via a one-way exporter.
> 3. **ECS**: **Unified** — editor entities ARE bitECS entities. Systems run identically in edit and Play modes. Undo/selection/locked-node semantics will be implemented as ECS-aware bookkeeping rather than a parallel model.
> 4. *(implicit)* **Component View lifecycle**: imperative functions `{ create(parent, props), update(obj, props), dispose(obj) }` per Option A.
> 5. *(implicit)* **Physics property schema**: keep r3game's Rapier-ish schema (`dynamic`/`fixed`/`kinematic`, collider types). Crashcat backend translates at the View layer. Rapier backend (per task #18) can consume the schema directly.

---

## 1. Their Architecture Summary

The editor is built around a **Prefab** — a JSON-serializable tree of **GameObjects**, each carrying a bag of **Components**. The entire edit state lives in a Zustand store (`prefabStore.ts`) that normalizes the tree into flat lookup maps for O(1) access.

### Core type shapes (from `types.ts`)

```ts
interface Prefab {
  id?: string;
  name?: string;
  root: GameObject;
}

interface GameObject {
  id: string;            // crypto.randomUUID()
  name?: string;
  disabled?: boolean;
  locked?: boolean;
  children?: GameObject[];
  components?: { [key: string]: ComponentData | undefined };
}

interface ComponentData {
  type: string;                       // registry key, e.g. "Transform"
  properties: Record<string, any>;    // arbitrary typed bag
}
```

### Normalized store shape (from `prefab.ts`)

```ts
interface PrefabState {
  prefabId?: string;
  prefabName?: string;
  rootId: string;
  nodesById: Record<string, PrefabNodeRecord>;   // GameObject sans children
  childIdsById: Record<string, string[]>;
  parentIdById: Record<string, string | null>;
  revision: number;
  assetManifestKey: string;
  assetRefCounts: Record<string, number>;         // "model:path" -> refcount
}
```

### Scene API (`scene.ts`)

A thin facade over the store that exposes `Entity` and `EntityComponent` handles with `.get()` / `.set()` / `.update()` mutation methods. Created via `createScene(adapter)` where the adapter bridges to the Zustand store. This layer is **framework-agnostic** — it operates on plain objects through a `SceneAdapter` interface, making it directly portable.

### Mutation flow

1. UI or gizmo triggers a store action (e.g. `updateNode`, `addChild`, `moveNode`)
2. Store produces a new immutable `PrefabState` with bumped `revision`
3. Zustand `subscribeWithSelector` notifies React subscribers (hierarchy, inspector)
4. `PrefabRoot` re-renders affected Three.js subtree via React reconciliation
5. History system debounces snapshots (500ms) for undo/redo (max 50 entries)

---

## 2. Component-Type Inventory

14 built-in components registered in `components/index.ts`:

| Component | Key Properties | Composition | Notes |
|---|---|---|---|
| **Transform** | `position`, `rotation`, `scale` (each `[n,n,n]`) | — | Always present; gizmo writes back here |
| **Geometry** | `geometryType` (box/sphere/plane/cylinder), `args[]`, `visible`, `castShadow` | — | Primitive meshes |
| **Material** | `materialType` (standard/basic), `color`, `metalness`, `roughness`, `texture`, `opacity`, `wireframe`, `transmission` | — | WebGPU node materials |
| **Model** | `filename`, `instanced`, `repeat`, `repeatAxes[]` | — | GLTF/GLB loader; instancing support |
| **Physics** | `type` (dynamic/fixed/kinematic), `colliders` (hull/trimesh/cuboid/ball/capsule), `mass`, `sensor`, velocity, damping, locked axes | **wrap** | Wraps subtree in `<RigidBody>` |
| **Camera** | — | sibling | — |
| **Environment** | — | sibling | HDRI/environment map |
| **SpotLight** | intensity, color, angle, penumbra, distance | sibling | — |
| **PointLight** | intensity, color, distance, decay | sibling | — |
| **DirectionalLight** | intensity, color, castShadow | sibling | — |
| **AmbientLight** | intensity, color | sibling | — |
| **Text** | content, font, size, color | — | three-text |
| **Click** | `eventName` | — | Emits named game event on click |
| **Sound** | filename, volume, loop, spatial | — | Positional audio |

**User-registered**: `registerComponent(component: Component)` adds to a global `REGISTRY` map. Each `Component` has `name`, `Editor` (React FC), `View` (React FC), `defaultProperties`, optional `composition` mode, and optional `getAssetRefs`.

---

## 3. Editor UI Building Blocks

| Panel | Implementation | Vanilla-DOM portability |
|---|---|---|
| **Hierarchy tree** (`EditorTree.tsx`) | Custom React tree with drag-drop reordering, search filter, context menus, collapse state | **Medium** — DOM tree with event handlers; no library dependency. Drag-drop uses native HTML5 API. Rewrite as vanilla DOM is straightforward but verbose. |
| **Inspector** (`EditorUI.tsx`) | Iterates `node.components`, renders each component's `Editor` FC. "Add component" dropdown. | **Medium** — form inputs + component card layout. Each component editor is a self-contained form. |
| **Toolbar** | Inline `<div>` with play/pause button + plugin slots (`uiPlugins` prop) | **Easy** — trivial HTML buttons |
| **Input primitives** (`Input.tsx`) | `Vector3Input`, `ColorInput`, `NumberField`, `SelectField`, `BooleanField`, `ListEditor`, `FieldRenderer` | **Easy** — all are thin wrappers around `<input>` / `<select>` with inline styles |
| **Dropdown / context menu** (`Dropdown.tsx`) | Portal-based popover with placement logic | **Easy** — standard popover pattern |
| **Styles** (`styles.ts`) | All CSS-in-JS via `CSSProperties` objects — no external CSS framework | **Direct** — already plain style objects; can apply to vanilla DOM elements unchanged |

**Key React-specific patterns that need replacement:**
- `useHelper(ref, BoxHelper)` from drei — selection highlight. Replace with direct `BoxHelper` management.
- `<TransformControls>` from drei — gizmo. See section 4.
- `<MapControls>` from drei — orbit camera. Replace with `three/examples/jsm/controls/MapControls`.
- `<Physics>` from `@react-three/rapier` — physics wrapper. We use Crashcat, not Rapier.
- Zustand React hooks (`useStore`, `usePrefabStore`) — state subscriptions. Replace with vanilla Zustand store + manual DOM updates or a lightweight reactive binding.

---

## 4. Gizmo Implementation

They use **drei's `<TransformControls>`**, which wraps Three.js's `TransformControls` from `three/examples/jsm/controls/TransformControls.js`.

Integration pattern (from `PrefabEditor.tsx`):
- `TransformControls` is attached to the selected entity's `Object3D`
- `onObjectChange` callback decomposes the world matrix back to local transform and writes to the store via `updateNode`
- `computeParentWorldMatrix()` walks the parent chain to convert world -> local
- Modes: translate / rotate / scale, toggled from inspector UI
- Snap: `translationSnap`, `rotationSnap`, `scaleSnap` configurable per-mode

**Porting**: Three.js `TransformControls` works without React. We can use it directly — attach to selected `Object3D`, listen to `'objectChange'` event, write back to our store. No library replacement needed.

---

## 5. Persistence Flow

### Save (`utils.ts: saveJson`)
- Calls `denormalizePrefab(state)` to reconstruct the nested `Prefab` tree from normalized store
- Serializes to JSON via `JSON.stringify(data, null, 2)`
- Uses File System Access API (`showSaveFilePicker`) with fallback to `<a>` download

### Load (`utils.ts: loadJson`)
- File picker -> FileReader -> `JSON.parse` -> returns `Prefab`
- Loaded prefab replaces store state via `replacePrefab()`

### Export GLB (`utils.ts: exportGLB`)
- Clears selection (to remove gizmo artifacts), then uses `GLTFExporter` on the root `Group`
- Exports the live Three.js scene graph — materials, geometries, textures are included via Three.js serialization
- The JSON prefab data is NOT embedded in the GLB

### What's serialized vs runtime-only
- **Serialized**: `Prefab` JSON (full `GameObject` tree with `ComponentData` bags)
- **Not serialized**: Three.js objects, loaded model data, physics rigid bodies, asset `Object3D` references, selection state, undo history
- **Asset references**: stored as string paths in component properties (e.g. `"filename": "models/tree.glb"`). Runtime resolves them via `AssetRuntimeContext`.

---

## 6. Play-Mode Handling

From `PrefabEditor.tsx`:
- **Edit -> Play**: Sets `mode` to `PrefabEditorMode.Play`. Clears selection. Physics unpauses (`<Physics paused={isEditMode}>`). `TransformControls` and `MapControls` are unmounted. Grid helper hidden. History recording stops.
- **Play -> Edit**: Mode reverts. Physics re-pauses.
- **State preservation**: **None**. They do NOT snapshot before Play and restore on Stop. The prefab store state persists through the mode toggle. Physics mutations during Play (objects falling, etc.) modify the live Three.js scene but NOT the store — so switching back to Edit effectively "resets" rendered positions because the store still has the pre-Play transforms. This is implicit, not an explicit save/restore.

---

## 7. Constraints for Porting to vibe-game-engine

| Constraint | Impact |
|---|---|
| **No React** | `PrefabRoot` (the 3D renderer) must be rewritten as an imperative scene-graph builder. Component `View` functions (React FCs) become imperative `create(parent, props)` / `update(props)` / `destroy()` lifecycle objects. Editor UI panels become vanilla DOM. |
| **Crashcat, not Rapier** | Physics component's `View` uses `@react-three/rapier` (`<RigidBody>`, `<CapsuleCollider>`). Must be replaced with Crashcat equivalents. Collider type mapping: hull->convexHull, trimesh->trimesh, cuboid->box, ball->sphere, capsule->capsule. |
| **Existing ECS (bitECS)** | Our engine uses bitECS with SoA components (`Position`, `Rotation`, `Scale`, `MeshRef`). The prefab store is a parallel entity system. Decision needed: do editor entities also live in the bitECS world, or does the editor bypass ECS entirely? |
| **@ggez/runtime-format** | Our scenes already serialize to `scene.runtime.json`. The Prefab JSON format is different. Need a translation layer or adopt their format as the new canonical one. |
| **VRM pipeline** | SGU uses VRM characters. Need a `VRMModel` component type that loads `.vrm` via our existing `character-loader.ts`, not their GLTF pipeline. |
| **Package split** | Editor UI + tooling in `@kopertop/vibe-game-engine-editor` (peer package). Core types (`Prefab`, `GameObject`, `ComponentData`, `Scene` API, `ComponentRegistry`) in the main engine since runtime needs them too. |

---

## 8. Recommended Port Plan

### Phase 1: Minimum Viable Editor (hierarchy + inspector + save/load)

**Engine files to create:**
- `src/editor/types.ts` — `Prefab`, `GameObject`, `ComponentData`, `findComponent` (direct port from their `types.ts`)
- `src/editor/prefab-store.ts` — vanilla Zustand store (their `prefabStore.ts` already uses `zustand/vanilla` under the hood — the `createStore` call is framework-agnostic)
- `src/editor/scene-api.ts` — direct port of `scene.ts` `createScene()` + `SceneAdapter`
- `src/editor/component-registry.ts` — direct port of `ComponentRegistry.ts` with `View` type changed from React FC to imperative lifecycle
- `src/editor/prefab-renderer.ts` — imperative equivalent of `PrefabRoot`: walks the normalized tree, creates/updates/removes Three.js objects

**Editor package files:**
- `src/ui/hierarchy-panel.ts` — vanilla DOM tree (port of `EditorTree.tsx`)
- `src/ui/inspector-panel.ts` — vanilla DOM inspector (port of `EditorUI.tsx`)
- `src/ui/input-fields.ts` — vanilla DOM input primitives (port of `Input.tsx`)
- `src/ui/styles.ts` — direct copy of their `styles.ts` (already plain `CSSProperties`)

**SGU integration:**
- Wire `?editor=1` to mount the editor panels and enable edit mode
- Migrate existing `prop-catalog.ts` entries to `ComponentRegistry` format
- Bridge `editor-persistence.ts` localStorage to use new Prefab JSON format

**APIs to expose:** `createPrefabStore`, `createScene`, `registerComponent`, `saveJson`, `loadJson`

### Phase 2: Gizmos + Play Mode

**Engine files:**
- `src/editor/gizmo-controller.ts` — wraps Three.js `TransformControls`, handles world->local decomposition, snapping
- `src/editor/orbit-controller.ts` — wraps `MapControls` with edit-mode-only behavior
- `src/editor/play-mode.ts` — state snapshot before Play, restore on Stop (improvement over their implicit approach)

**Editor package:**
- `src/ui/toolbar.ts` — play/pause toggle, transform mode buttons, snap controls

**SGU integration:**
- Physics toggle: pause Crashcat world in edit mode, unpause in play mode
- Selection highlight via `BoxHelper`

### Phase 3: Advanced Features

- **Prefab library**: save/load individual subtrees as reusable prefabs; drag from asset panel into scene
- **Built-in components**: port Geometry, Material, Light, Sound, Camera, Model components with imperative `View` lifecycle
- **VRM component**: custom component type that integrates with `character-loader.ts`
- **Animation graph**: component for `@ggez/anim-runtime` clip assignment
- **GLB export**: port their `exportGLB` utility (already Three.js-native)
- **Undo/redo**: port their history system (store snapshot ring buffer with 500ms debounce)
- **scene.runtime.json bridge**: export Prefab JSON -> `scene.runtime.json` for production builds

---

## 9. Open Questions

1. **UI framework for editor panels**: Do we write vanilla DOM (more work, zero deps, full control) or use a lightweight non-React UI lib (e.g. Lit, Preact in a shadow DOM, or even vanilla web components)? Vanilla DOM is most aligned with the "no React" constraint but the inspector is ~400 LOC of form rendering that benefits from declarative UI. **Trade-off**: vanilla = 2-3x more LOC but zero bundle impact; Preact shadow DOM = ~3KB, declarative, but adds a dependency.

2. **Prefab JSON vs scene.runtime.json**: Do we adopt their `Prefab` format as canonical and make `scene.runtime.json` a derived build artifact, or do we keep `scene.runtime.json` as source-of-truth and treat Prefab JSON as editor-only? The former is simpler (one format); the latter preserves compatibility with existing ggez World Editor exports.

3. **bitECS integration**: Should editor entities exist in the bitECS world (so ECS systems like physics can query them during Play mode), or should the editor maintain its own parallel entity model (simpler, avoids ECS bookkeeping in edit mode)? Their architecture uses a parallel model. Our existing engine assumes bitECS for everything. **Trade-off**: parallel = cleaner edit/play separation; unified = systems work identically in both modes but adds complexity to edit-mode entity lifecycle.

4. **Component View lifecycle**: Their `Component.View` is a React FC receiving `{ properties, children }`. For vanilla Three.js, what should the imperative equivalent look like?
   - **Option A**: `{ create(parent, props): Object3D, update(obj, props): void, dispose(obj): void }` — simple, explicit
   - **Option B**: Class with constructor/update/dispose — more familiar OOP pattern
   - **Option C**: Signals/observables that auto-sync props to Three.js objects — most reactive but most complex

5. **Physics component mapping**: Their Physics uses Rapier types (`dynamic`, `fixed`, `kinematicPosition`). Crashcat has different body type names and API. Do we keep their property schema and translate at the View layer, or define a Crashcat-native property schema from the start?

---

## 10. Physics Backend Abstraction (Task #18)

> **Status**: Prototype implemented in `@kopertop/vibe-game-engine`
> **Decision**: Keep Rapier-ish property schema as canonical; both backends translate at the View layer.

### Problem

Crashcat's `updateWorld(world, undefined, dt)` is called with no listener, so connected ragdoll bodies self-collide and explode. Rapier has a native `joint.setContactsEnabled(false)` flag that structurally prevents this. We need both engines available: Crashcat for gameplay, Rapier as opt-in for ragdoll-heavy content.

### Interface: `PhysicsBackend`

Location: `src/physics/backend-interface.ts`

```ts
interface PhysicsBackend {
  name: 'crashcat' | 'rapier';
  step(dt: number): void;
  dispose(): void;
  createBody(desc: PhysicsBodyDescriptor): PhysicsBodyHandle;
  removeBody(handle: PhysicsBodyHandle): void;
  getPosition / getRotation / getLinearVelocity / getAngularVelocity
  setPosition / setRotation / setLinearVelocity / setAngularVelocity
  applyImpulse / applyForce / applyTorqueImpulse
  setKinematicTarget(handle, pos, rot): void;
  createJoint(desc: JointDescriptor): PhysicsJointHandle;
  removeJoint(handle: PhysicsJointHandle): void;
  areBodiesInContact(a, b): boolean;
}
```

Handles are opaque branded objects. Joint descriptors support `spherical`, `revolute`, `fixed`, `prismatic` types with optional `contactsEnabled` (defaults to `false`).

### Implementations

| Backend | File | Joint contact filtering | Use case |
|---|---|---|---|
| **Rapier** | `src/physics/backends/rapier-backend.ts` | Native `setContactsEnabled(false)` on joint | Ragdoll, cinematic physics |
| **Crashcat** | `src/physics/backends/crashcat-backend.ts` | Collision group/mask bitmasks (caller responsibility) | Gameplay physics |

### Factory

```ts
const backend = await createPhysicsBackend("rapier" | "crashcat", {
  gravity: { x: 0, y: -9.81, z: 0 },
  crashcatWorld: existingWorld, // optional, Crashcat only
});
```

### Editor integration

Prefab JSON `PhysicsWorld` component can specify `backend: "rapier"` to opt a whole prefab subtree into Rapier. Default remains Crashcat. The runtime scene loader inspects this field and creates the appropriate backend via `createPhysicsBackend()`.

### Package dependencies

- `@dimforge/rapier3d-compat` and `crashcat` are **optional peer dependencies** in the engine.
- If neither is installed, the respective backend import fails at runtime (acceptable: tree-shaking means unused backends are never loaded).
- Type stubs for crashcat live in `src/physics/backends/crashcat-types.d.ts`.

### Test coverage

12 tests in `src/physics/backends/rapier-backend.test.ts`:
- **Ragdoll self-collision fix**: verified joint-linked bodies do NOT generate solver contacts (`contactsEnabled: false`)
- **Control**: non-jointed overlapping bodies DO collide; jointed with `contactsEnabled: true` also collide
- **Multi-body chain**: 3-body pelvis->torso->head chain stays intact with disabled contacts
- Body types (dynamic, fixed, kinematic), impulses, cleanup

### Known limitations

1. **Crashcat joint contact filtering**: No per-joint `contactsEnabled` flag. Callers must use `collisionGroups`/`collisionMask` bitmasks on body descriptors. For ragdoll, use the Rapier backend.
2. **Crashcat compound shapes**: Multi-collider bodies use Crashcat's compound shape; sub-colliders can't have individual offsets from the body descriptor (would need a compound shape builder).
3. **Kinematic dt approximation**: Crashcat's `moveKinematic` needs dt; the backend defaults to 1/60. Callers should step immediately after setting kinematic targets.
