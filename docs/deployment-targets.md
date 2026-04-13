# Stargate Universe — Deployment Targets

Target matrix: **Chrome/Edge PWA**, **Electron desktop** (Mac/Windows/Linux), **iPad** (native wrapper).
Android/Steam Deck aren't first-class but likely work via the same Electron build with minor tweaks.

---

## 1. PWA (current baseline)

The Vite build already produces a static site: `dist/` served over HTTPS.
Cloudflare Pages is wired via `wrangler.toml` and `functions/`.

**Already set up:**
- Vite 7 + `bun run build`
- `sw.js`: TODO — no service-worker yet
- Manifest: TODO — no `manifest.webmanifest` yet

**To make it installable:**
1. Add `public/manifest.webmanifest` with app name, icons, display: "fullscreen", orientation: "landscape"
2. Wire a minimal `public/sw.js` that precaches the build output + crew VRMs + audio catalog
3. Add `<link rel="manifest" href="/manifest.webmanifest">` to `index.html`
4. Ship icons at 192/512/1024 (use the existing promo art)

Install experience: Chrome → ⋮ → "Install Stargate Universe". On install, the game opens
windowless in a dedicated PWA frame — no browser chrome, no address bar.

---

## 2. Electron (desktop: macOS, Windows, Linux)

**Why Electron over Tauri:**
- Tauri v2 is lighter (native WebView) but **Tauri's WebView is Safari-based on macOS** — no
  WebGPU, so our renderer falls back to WebGL and MToon shaders regress. Non-starter.
- Electron bundles Chromium → WebGPU + full parity with the web dev experience.
- Trade-off: 80–120 MB download. For a cinematic single-player RPG, fine.

### Structure

Add a new workspace package rather than cluttering `stargate-universe` root:

```
stargate-universe/
├── electron/
│   ├── package.json              ← electron-builder + electron dep
│   ├── main.ts                   ← window setup, IPC, menu bar
│   ├── preload.ts                ← expose native APIs to the renderer
│   └── build.config.json         ← codesigning, notarization, icons
├── src/...                       ← unchanged — same code serves web + desktop
└── package.json                  ← adds "electron" script that runs vite + electron together
```

### Main-process responsibilities (`electron/main.ts`)

```ts
import { app, BrowserWindow, Menu, globalShortcut } from "electron";

const createWindow = () => {
	const win = new BrowserWindow({
		width: 1600,
		height: 900,
		fullscreen: true,              // always fullscreen on boot
		fullscreenable: true,
		autoHideMenuBar: true,
		webPreferences: {
			preload: path.join(__dirname, "preload.js"),
			contextIsolation: true,
			nodeIntegration: false,
			webgl: true,
			// Chromium flag for WebGPU is already default in recent electron.
			// If missing: app.commandLine.appendSwitch("enable-unsafe-webgpu");
		},
	});
	if (process.env.NODE_ENV === "development") {
		win.loadURL("http://localhost:5173");
	} else {
		win.loadFile(path.join(__dirname, "../dist/index.html"));
	}
	Menu.setApplicationMenu(null);     // no native menu bar
};

app.whenReady().then(() => {
	createWindow();
	// Block Cmd-Q / Cmd-W / F11 / Alt-F4 from nuking the game mid-session.
	// Players can still quit via the in-game menu.
	globalShortcut.register("CommandOrControl+W", () => { /* swallow */ });
	globalShortcut.register("F11", () => { /* swallow */ });
});
```

### Save storage on desktop

`localStorage` still works in Electron but is tied to the renderer partition.
For roaming saves + cloud sync later, use `app.getPath("userData")` from the main
process + an IPC bridge:

```ts
// preload.ts
contextBridge.exposeInMainWorld("sguNative", {
	readSave: (slot: string) => ipcRenderer.invoke("save:read", slot),
	writeSave: (slot: string, data: string) => ipcRenderer.invoke("save:write", slot, data),
	listSlots: () => ipcRenderer.invoke("save:list"),
});
```

Then `save-manager.ts` can detect the native surface and prefer it:
```ts
const store = (window as any).sguNative ?? localStorageAdapter;
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

Current setup streams VRMs + audio from R2 in production. For Electron, consider:
- **Ship bundled:** include assets in the `.app` / `.exe`. Faster first-load,
  larger download (~500 MB with all VRMs + audio).
- **Download-on-first-run:** ship a thin installer, fetch assets on first launch
  with a progress screen. Smaller initial download, requires internet at install.

For launch, bundle everything. Cloudflare R2 egress is free but latency hits 3–4s
on cold VRM fetch; bundled reads are instant.

### Dev loop

```json
// stargate-universe/package.json
"scripts": {
	"electron:dev":  "run-p dev electron:watch",
	"electron:watch": "tsc -p electron/tsconfig.json --watch & wait-on http://localhost:5173 && electron electron/dist/main.js",
	"electron:pack": "bun run build && electron-builder --dir",
	"electron:dist": "bun run build && electron-builder"
}
```

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
bun add @capacitor/core @capacitor/ios
bunx cap init "Stargate Universe" "com.kopertop.sgu" --web-dir=dist
bunx cap add ios
bun run build && bunx cap sync
bunx cap open ios       # opens Xcode
```

**What the wrapper gets us:**
- Pre-downloaded assets baked in or fetched on first run
- `navigator.wakeLock` + native orientation lock to landscape
- Haptic taptics on UI select (Capacitor `@capacitor/haptics`)
- Game Center sign-in + achievements (small Swift plugin)
- iCloud save sync (`@capacitor-community/icloud-documents`)
- App-background audio pause (already handled by our `visibilitychange` listener)

### Renderer plan on iPad

**WebGPU:** Enable via `WebGPUEnabled` experimental flag in Info.plist — works in
iPadOS 18+, but Apple may reject the app for using unstable APIs. Verdict: ship
WebGL path first; flip WebGPU on when Apple stabilizes it.

Our `createWebGPURenderer({ forceWebGL })` already supports the `?webgl=1` flag.
For iPad, hard-code `forceWebGL: true` based on a platform detect in `app.ts`:

```ts
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
const forceWebGL = isIOS || new URLSearchParams(location.search).has("webgl");
```

**Performance budget:** M1 iPad Pro crushes this. M2 Air, too. A4-era iPad 8th gen
will not — cap target to iPad 9th gen / M1+ and advertise accordingly.

### Controls on iPad

- **Touchscreen:** virtual joystick (left thumb) + look-at-touch (right thumb).
  The engine's `InputManager` already has `setTouchMovement()` — just need to
  render the thumbsticks. Example lib: [nipplejs](https://github.com/yoannmoinet/nipplejs).
- **Apple Game Controller** (MFi / Xbox / PS5 controllers over Bluetooth): Capacitor
  exposes standard `navigator.getGamepads()` — our InputManager picks them up
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
   review. `npm run build && deploy` unchanged.
2. **Electron desktop** — ~2 weeks to set up properly with codesigning. Shippable
   on [itch.io](https://itch.io) same week.
3. **Steam via Electron** — add the Steamworks plugin for achievements + cloud
   saves. itch.io first for feedback; Steam once the game is stable.
4. **Capacitor iPad** — 3–4 weeks including App Store submission dance. Blocks on
   WebGL parity being visually acceptable (MToon regression testing).
5. **Android via Capacitor** — same wrapper, different target. Mostly free.

---

## 5. What to NOT plan for right now

- **WebXR / VR / AR** — not a stated goal.
- **Switch, PS5, Xbox consoles** — require Unity/Unreal-level porting. Not realistic
  for a three.js + Chromium stack.
- **Direct-to-Metal renderer** — three.js/WebGPU path is plenty fast on M-series.

---

## 6. Code changes needed to support all targets today

None of these are blocking — they're cleanup that makes target-switching easier:

- [x] Audio context suspend/resume on tab blur (already in `main.ts`)
- [x] Fullscreen + Escape lock on first gesture (already in `systems/fullscreen.ts`)
- [ ] Platform detect in `app.ts` — force WebGL on iOS, WebGPU otherwise
- [ ] Save storage adapter — `localStorage` (default) vs native IPC on Electron vs
      iCloud doc on iOS. Swap at runtime based on `window.sguNative` presence.
- [ ] Asset resolver: support `capacitor://localhost/assets/...` and `file://` for
      bundled Electron assets alongside the existing R2/Vite paths.
- [ ] Service worker + manifest for PWA.

These slot into existing files — no architectural shift required. The fact that
we already separate input (engine InputManager), audio (AudioManager), and asset
resolution (resolveAssetUrl) from the game code means each deployment target
just swaps implementations at the edges.
