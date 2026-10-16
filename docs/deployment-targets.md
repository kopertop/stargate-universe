# Stargate Universe — Deployment Targets

Current stack: vanilla ES modules (`src/*.js`) loaded via import maps in a single
`index.html`, Three.js 0.180 from CDN (or vendored by `build.sh` for offline). Build
is `./build.sh` → `dist/` + `dist/sgu-destiny-html5.zip` (itch.io-ready). No Vite,
no TypeScript, no bundler — the browser loads modules directly.

Target matrix: **PWA**, **Electron desktop** (Mac/Windows/Linux), **iPad** (native wrapper).
Android/Steam Deck aren't first-class but likely work via the same Electron build with minor tweaks.

---

## 1. PWA (current baseline)

`build.sh` produces a static site: `dist/` containing `index.html`, `src/`, `data/`,
`vendor/`, and `assets/`. Serve over HTTPS and it's installable.

**Already set up:**
- `index.html` with `<meta name="viewport">` and import map for Three.js
- `build.sh` vendors Three.js into `dist/vendor/` so the build works offline
- Game saves to `localStorage` (see `src/rpg.js`)

**Outstanding work:**
1. Add a `dist/manifest.webmanifest` — app name, icons (192/512), `display: fullscreen`,
   `orientation: landscape`. Reference it from `index.html`:
   `<link rel="manifest" href="./manifest.webmanifest">`
2. Add a `dist/sw.js` — minimal service worker to precache `index.html`, `src/`, `data/`,
   `vendor/`, and `assets/`. Register it from `index.html`:
   ```html
   <script>navigator.serviceWorker?.register('./sw.js')</script>
   ```
3. Ship icons under `dist/icons/` (192px + 512px).
4. Bump a cache version in `sw.js` on each release to force update.

Install experience: Chrome → ⋮ → "Install Stargate Universe". On install, the game opens
windowless in a dedicated PWA frame — no browser chrome, no address bar.

**Note:** `build.sh` would need to copy the manifest, sw.js, and icons into `dist/`.
Add lines after the asset copy section:
```bash
cp "$HERE"/manifest.webmanifest "$HERE/sw.js" "$DIST/"
mkdir -p "$DIST/icons"
cp "$HERE"/icons/*.png "$DIST/icons/"
```

---

## 2. Electron (desktop: macOS, Windows, Linux)

**Why Electron over Tauri:**
- Tauri v2 is lighter (native WebView) but **Tauri's WebView is Safari-based on macOS** — no
  WebGPU, so our renderer falls back to WebGL and shaders regress. Non-starter.
- Electron bundles Chromium → WebGPU + full parity with the web dev experience.
- Trade-off: 80–120 MB download. For a cinematic single-player RPG, fine.

### Structure

Add a new directory alongside `src/`:

```
stargate-universe/
├── electron/
│   ├── package.json              ← electron-builder + electron dep
│   ├── main.js                   ← window setup, IPC, menu bar
│   ├── preload.js                ← expose native APIs to the renderer
│   └── build.config.json         ← codesigning, notarization, icons
├── src/...                       ← unchanged — same code serves web + desktop
├── index.html                    ← unchanged
└── build.sh                      ← adds electron packaging step
```

### Main-process responsibilities (`electron/main.js`)

```js
const { app, BrowserWindow, Menu, globalShortcut } = require("electron");
const path = require("path");

const createWindow = () => {
    const win = new BrowserWindow({
        width: 1600,
        height: 900,
        fullscreen: true,
        fullscreenable: true,
        autoHideMenuBar: true,
        webPreferences: {
            preload: path.join(__dirname, "preload.js"),
            contextIsolation: true,
            nodeIntegration: false,
            webgl: true,
        },
    });
    win.loadFile(path.join(__dirname, "../dist/index.html"));
    Menu.setApplicationMenu(null);
};

app.whenReady().then(() => {
    createWindow();
    globalShortcut.register("CommandOrControl+W", () => { /* swallow */ });
    globalShortcut.register("F11", () => { /* swallow */ });
});
```

### Save storage on desktop

`localStorage` still works in Electron but is tied to the renderer partition.
For roaming saves + cloud sync later, use `app.getPath("userData")` from the main
process + an IPC bridge:

```js
// preload.js
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("sguNative", {
    readSave: (slot) => ipcRenderer.invoke("save:read", slot),
    writeSave: (slot, data) => ipcRenderer.invoke("save:write", slot, data),
    listSlots: () => ipcRenderer.invoke("save:list"),
});
```

Then `src/rpg.js` can detect the native surface and prefer it:
```js
const store = window.sguNative ?? localStorageAdapter;
```

### Packaging + signing

Use `electron-builder`. Targets:
- macOS: `.dmg` (universal: arm64 + x64), Developer ID signed + notarized via `notarytool`
- Windows: `.exe` (NSIS) + `.msi` for enterprise, signed with an EV cert
- Linux: `.AppImage` + `.deb`

```json
// electron/package.json
{
    "build": {
        "appId": "com.kopertop.stargate-universe",
        "productName": "Stargate Universe",
        "directories": { "output": "release" },
        "files": ["dist/**/*", "electron/dist/**/*"],
        "mac": {
            "category": "public.app-category.games",
            "target": ["dmg"],
            "hardenedRuntime": true,
            "entitlements": "electron/entitlements.mac.plist",
            "notarize": { "teamId": "YOUR_TEAM_ID" }
        },
        "win": { "target": ["nsis", "msi"] },
        "linux": { "target": ["AppImage", "deb"], "category": "Game" }
    }
}
```

Codesign for macOS requires an Apple Developer account ($99/year) for distribution
outside the Mac App Store.

### Asset delivery

Current setup streams audio from R2 in production (URLs in `src/music.js`).
VRMs and models are bundled by `build.sh` into `dist/assets/`. For Electron, consider:
- **Ship bundled:** include assets in the `.app` / `.exe`. Faster first-load,
  larger download (~500 MB with all audio).
- **Download-on-first-run:** ship a thin installer, fetch assets on first launch
  with a progress screen. Smaller initial download, requires internet at install.

For launch, bundle everything. Cloudflare R2 egress is free but latency hits 3–4s
on cold audio fetch; bundled reads are instant.

### Dev loop

```bash
./build.sh                              # build dist/ (web build)
cd electron && npx electron-builder     # package into release/
```

For dev with hot reload, run a simple static server (`npx http-server dist/`)
and point `electron/main.js` at the URL instead of the file path.

---

## 3. iPad / iOS native

iOS is the hostile target. Key constraints:

| Constraint | Impact |
|---|---|
| No Chromium — only WKWebView (WebKit) | WebGPU is **experimental** in iOS 18+, off by default. Must use WebGL fallback for production. |
| No dynamic code exec (Metal / ANGLE only) | Can't ship Chromium. Electron is impossible. |
| App Review | Games get stricter scrutiny (age rating, IAP if any, data collection). |
| 200 MB cellular download limit | Bundle size matters. |
| Apple Developer Program | $99/year, hardware Mac required for builds. |

### Path A — **Capacitor** (recommended)

[Capacitor](https://capacitorjs.com) wraps the existing web build in a native iOS
project. It's actively maintained (Ionic team, used by Shopify, OpenTable, etc.).

**Why Capacitor over Cordova:** modern, TypeScript-native, official plugin ecosystem,
better iOS 17/18 support, first-class SwiftUI interop if we need it.

```bash
cd stargate-universe
./build.sh                                  # produce dist/
npm install @capacitor/core @capacitor/ios
npx cap init "Stargate Universe" "com.kopertop.sgu" --web-dir=dist
npx cap add ios
npx cap sync
npx cap open ios       # opens Xcode
```

**What the wrapper gets us:**
- Pre-downloaded assets baked in or fetched on first run
- `navigator.wakeLock` + native orientation lock to landscape
- Haptic taptics on UI select (Capacitor `@capacitor/haptics`)
- Game Center sign-in + achievements (small Swift plugin)
- iCloud save sync (`@capacitor-community/icloud-documents`)
- App-background audio pause (already handled by `visibilitychange` listener in `src/main.js`)

### Renderer plan on iPad

**WebGPU:** Enable via `WebGPUEnabled` experimental flag in Info.plist — works in
iPadOS 18+, but Apple may reject the app for using unstable APIs. Verdict: ship
WebGL path first; flip WebGPU on when Apple stabilizes it.

The current renderer (`src/main.js`) uses `THREE.WebGLRenderer`. No changes needed
for WebGL — it's already the default. If WebGPU is added later, detect at runtime:
```js
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
// If using WebGPU renderer in the future, force WebGL on iOS
```

**Performance budget:** M1 iPad Pro crushes this. M2 Air, too. A4-era iPad 8th gen
will not — cap target to iPad 9th gen / M1+ and advertise accordingly.

### Controls on iPad

- **Touchscreen:** virtual joystick (left thumb) + look-at-touch (right thumb).
  The engine's input module (`src/input.js`) handles keyboard/mouse — touch controls
  would need to be added. Example lib: [nipplejs](https://github.com/yoannmoinet/nipplejs).
- **Apple Game Controller** (MFi / Xbox / PS5 controllers over Bluetooth): Capacitor
  exposes standard `navigator.getGamepads()` — `src/input.js` picks them up
  with zero additional work. ✅
- **Keyboard** (Magic Keyboard / Folio): same story — standard HTML key events.

### Path B — WKWebView + SwiftUI (more native, more work)

Skip Capacitor. Write the native shell in Swift, load the game HTML in a
`WKWebView`. Same WebKit renderer, but we control every native integration point
ourselves. This is what Netflix + Disney+ use for their iPad apps.

Worth it only if Capacitor runs out of integration runway (e.g. deep StoreKit
integration, custom Metal post-processing). For an offline single-player RPG,
Capacitor is enough.

### App Store rules to plan around

- **Loading time:** must not exceed 30s on cellular. Ship with bundled assets.
- **App Transport Security:** must use HTTPS for any remote content. R2 is HTTPS ✅.
- **Age rating:** "Cartoon Violence" probably enough — no real-world firearms, no
  blood effects currently.
- **Privacy manifest (`PrivacyInfo.xcprivacy`):** declare each "required reason"
  API used (Screen brightness reads, User defaults, etc.). Capacitor handles this.

---

## 4. Recommended rollout order

1. **PWA install** — weekend task. Gives iPad + Android users a taste without store
   review. `./build.sh` unchanged; just add manifest + sw.js + icons.
2. **Electron desktop** — ~2 weeks to set up properly with codesigning. Shippable
   on [itch.io](https://itch.io) same week.
3. **Steam via Electron** — add the Steamworks plugin for achievements + cloud
   saves. itch.io first for feedback; Steam once the game is stable.
4. **Capacitor iPad** — 3–4 weeks including App Store submission dance. Blocks on
   WebGL parity being visually acceptable.
5. **Android via Capacitor** — same wrapper, different target. Mostly free.

---

## 5. What to NOT plan for right now

- **WebXR / VR / AR** — not a stated goal.
- **Switch, PS5, Xbox consoles** — require Unity/Unreal-level porting. Not realistic
  for a Three.js + Chromium stack.
- **Direct-to-Metal renderer** — Three.js/WebGPU path is plenty fast on M-series.

---

## 6. Code changes needed to support all targets today

None of these are blocking — they're cleanup that makes target-switching easier:

- [x] Audio context suspend/resume on tab blur (already in `src/main.js`)
- [x] Fullscreen + Escape lock on first gesture (already in `src/main.js`)
- [ ] Platform detect in `src/main.js` — force WebGL on iOS (already default,
      but add explicit `isIOS` guard if WebGPU is added later)
- [ ] Save storage adapter — `localStorage` (default) vs native IPC on Electron vs
      iCloud doc on iOS. Swap at runtime based on `window.sguNative` presence.
      Current save logic is in `src/rpg.js` (`save()` / `load()` functions).
- [ ] Asset resolver: support `capacitor://localhost/assets/...` and `file://` for
      bundled Electron assets alongside the existing R2 / CDN paths.
      Current asset URLs are constructed in `src/music.js` (audio) and
      `src/assets.js` (model/texture paths).
- [ ] Service worker + manifest for PWA (see Section 1).

These slot into existing files — no architectural shift required. The fact that
input (`src/input.js`), audio (`src/music.js`), and asset resolution (`src/assets.js`)
are already separate modules means each deployment target just swaps implementations
at the edges.