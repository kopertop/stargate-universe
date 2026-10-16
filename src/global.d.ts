// Global type declarations for Stargate Universe — custom window properties and type augmentations
// This file is automatically picked up by jsconfig.json's include of "src/*.js" (tsc also loads .d.ts in include dirs)

export {};

declare global {
  interface Window {
    /** Debug overlay handle set by main.js */
    __dbg?: any;
    /** Asset root path set by assets.js */
    __ASSET_ROOT?: string;
    /** Autoplay controller set by autoplay.js */
    __auto?: any;
    /** Save/load API set by main.js */
    __save?: any;
    /** Recorder handle set by main.js */
    __rec?: any;
  }

  // Augment Element with HTMLElement properties used throughout the codebase
  // (querySelector returns Element, but game code uses .click(), .dataset, .style, .onclick)
  interface Element {
    click(): void;
    dataset: DOMStringMap;
    style: CSSStyleDeclaration;
    onclick: ((this: HTMLElement, ev: MouseEvent) => any) | null;
    tagName: string;
    value: string;
    hidden: boolean;
  }

  // Augment EventTarget with tagName (input.js reads event.target.tagName)
  interface EventTarget {
    tagName: string;
  }
}

// Three.js module augmentation: Object3D traversal returns children typed as Object3D,
// but game code accesses Mesh properties (.isMesh, .geometry, .material, .isSkinnedMesh).
// Augmenting the class avoids needing instanceof checks at every traversal site.
declare module 'three' {
  interface Object3D {
    isMesh?: boolean;
    isSkinnedMesh?: boolean;
    geometry?: any;
    material?: any;
  }
}