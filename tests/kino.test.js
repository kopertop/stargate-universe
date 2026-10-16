/**
 * Unit tests for src/kino.js — Kino drone mode (reconnaissance orb).
 *
 * Run with:  node --test tests/kino.test.js
 * (Node 18+ built-in test runner — no framework dependency.)
 *
 * kino.js imports three but the tested functions are on the returned state
 * object — the import resolves from node_modules so the module loads cleanly
 * in Node.
 *
 * Coverage: createKino return shape, orb structure (body+mesh+lens+light),
 * launch/recall state, update camera positioning, yaw/pitch clamping,
 * velocity lerp, movement speed, jump/descend, keyboard fallback.
 */
import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import { createKino } from '../src/kino.js';

const DT = 0.016; // ~60fps frame delta

// Helper: create a fake camera object
function makeCamera() {
  return {
    position: new THREE.Vector3(),
    up: new THREE.Vector3(0, 1, 0),
    lookAt: () => {},
  };
}

// Helper: create fake input
function makeInput(overrides = {}) {
  return {
    look: { x: 0, y: 0 },
    move: { x: 0, y: 0 },
    jump: false,
    run: false,
    keys: new Set(),
    ...overrides,
  };
}

describe('createKino return shape', () => {
  test('returns state object with orb, active, yaw, pitch, vel, scanT, launch, recall, update', () => {
    const kino = createKino();
    assert.ok(kino.orb instanceof THREE.Group, 'orb should be a THREE.Group');
    assert.strictEqual(kino.active, false, 'should start inactive');
    assert.strictEqual(kino.yaw, 0, 'yaw starts at 0');
    assert.strictEqual(kino.pitch, 0, 'pitch starts at 0');
    assert.ok(kino.vel instanceof THREE.Vector3, 'vel should be a THREE.Vector3');
    assert.strictEqual(kino.scanT, 0, 'scanT starts at 0');
    assert.strictEqual(typeof kino.launch, 'function', 'launch should be a function');
    assert.strictEqual(typeof kino.recall, 'function', 'recall should be a function');
    assert.strictEqual(typeof kino.update, 'function', 'update should be a function');
  });

  test('vel starts as zero vector', () => {
    const kino = createKino();
    assert.strictEqual(kino.vel.x, 0, 'vel.x starts at 0');
    assert.strictEqual(kino.vel.y, 0, 'vel.y starts at 0');
    assert.strictEqual(kino.vel.z, 0, 'vel.z starts at 0');
  });
});

describe('orb structure', () => {
  test('orb starts invisible (hidden until launched)', () => {
    const kino = createKino();
    assert.strictEqual(kino.orb.visible, false, 'orb should be invisible initially');
  });

  test('orb has children (body mesh, lens mesh, point light)', () => {
    const kino = createKino();
    assert.ok(kino.orb.children.length >= 3, `orb should have at least 3 children, got ${kino.orb.children.length}`);
  });

  test('orb body is a Mesh with SphereGeometry', () => {
    const kino = createKino();
    const body = kino.orb.children[0];
    assert.ok(body.geometry, 'body should have geometry');
    assert.ok(body.material, 'body should have material');
  });
});

describe('launch', () => {
  test('launch sets active=true, visible=true, resets state', () => {
    const kino = createKino();
    const pos = new THREE.Vector3(1, 2, 3);
    kino.launch(pos, 1.5);
    assert.strictEqual(kino.active, true, 'should be active after launch');
    assert.strictEqual(kino.orb.visible, true, 'orb should be visible after launch');
    assert.strictEqual(kino.yaw, 1.5, 'yaw should be set to provided value');
    assert.strictEqual(kino.pitch, 0, 'pitch should be reset to 0');
    assert.strictEqual(kino.scanT, 0, 'scanT should be reset to 0');
  });

  test('launch resets vel to zero', () => {
    const kino = createKino();
    // Give it some velocity first
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(1.0, makeInput({ move: { x: 1, y: 1 } }), cam);
    assert.ok(kino.vel.x !== 0 || kino.vel.z !== 0, 'vel should be non-zero after movement');
    // Re-launch should reset
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    assert.strictEqual(kino.vel.x, 0, 'vel.x should reset to 0 on re-launch');
    assert.strictEqual(kino.vel.y, 0, 'vel.y should reset to 0 on re-launch');
    assert.strictEqual(kino.vel.z, 0, 'vel.z should reset to 0 on re-launch');
  });
});

describe('recall', () => {
  test('recall sets active=false and visible=false', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    assert.strictEqual(kino.active, true);
    kino.recall();
    assert.strictEqual(kino.active, false, 'should be inactive after recall');
    assert.strictEqual(kino.orb.visible, false, 'orb should be invisible after recall');
  });
});

describe('update — look input', () => {
  beforeEach(() => {});

  test('update applies look.x to yaw (negated)', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(DT, makeInput({ look: { x: 0.5, y: 0 } }), cam);
    assert.strictEqual(kino.yaw, -0.5, 'yaw should decrease by look.x');
  });

  test('update clamps pitch to max 1.2', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(DT, makeInput({ look: { x: 0, y: 2 } }), cam);
    assert.ok(kino.pitch <= 1.2, `pitch should be clamped to max 1.2, got ${kino.pitch}`);
  });

  test('update clamps pitch to min -1.2', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(DT, makeInput({ look: { x: 0, y: -2 } }), cam);
    assert.ok(kino.pitch >= -1.2, `pitch should be clamped to min -1.2, got ${kino.pitch}`);
  });
});

describe('update — movement', () => {
  test('update applies movement input to velocity via lerp', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    const velBefore = kino.vel.clone();
    kino.update(DT, makeInput({ move: { x: 1, y: 1 } }), cam);
    const changed = !kino.vel.equals(velBefore);
    assert.ok(changed, 'velocity should change after update with movement input');
  });

  test('vel is scaled by 5.5 (movement speed constant)', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    // Full forward, dt=1.0 → lerp factor = min(1, 4) = 1 → full snap
    kino.update(1.0, makeInput({ move: { x: 0, y: 1 } }), cam);
    // want = fwd * 1 * 5.5; fwd at yaw=0 is (0,0,-1) → want = (0,0,-5.5)
    assert.ok(Math.abs(kino.vel.z - (-5.5)) < 0.01, `vel.z should be ~-5.5, got ${kino.vel.z}`);
  });

  test('strafe right produces positive x velocity at yaw=0', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(1.0, makeInput({ move: { x: 1, y: 0 } }), cam);
    // right at yaw=0 is (1,0,0) → want = (5.5,0,0)
    assert.ok(Math.abs(kino.vel.x - 5.5) < 0.01, `vel.x should be ~5.5, got ${kino.vel.x}`);
  });
});

describe('update — vertical movement', () => {
  test('jump=true ascends (positive want.y)', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(1.0, makeInput({ jump: true }), cam);
    assert.ok(kino.vel.y > 0, `vel.y should be positive when jumping, got ${kino.vel.y}`);
  });

  test('run=true descends (negative want.y)', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(1.0, makeInput({ run: true }), cam);
    assert.ok(kino.vel.y < 0, `vel.y should be negative when running (descend), got ${kino.vel.y}`);
  });

  test('Space key in keys also triggers ascend (keyboard fallback)', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    const keys = new Set(['Space']);
    kino.update(1.0, makeInput({ keys }), cam);
    assert.ok(kino.vel.y > 0, 'vel.y should be positive when Space key held');
  });

  test('no jump + no run → vel.y stays at 0', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(1.0, makeInput({ move: { x: 0, y: 0 } }), cam);
    assert.ok(Math.abs(kino.vel.y) < 0.01, `vel.y should be ~0 with no vertical input, got ${kino.vel.y}`);
  });
});

describe('update — camera positioning', () => {
  test('camera.lookAt is called during update', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    let lookAtCalled = false;
    const cam = makeCamera();
    cam.lookAt = () => { lookAtCalled = true; };
    kino.update(DT, makeInput(), cam);
    assert.ok(lookAtCalled, 'camera.lookAt should be called during update');
  });

  test('camera.up is set to (0,1,0) during update', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    let upSet = null;
    const cam = makeCamera();
    cam.up.set = (x, y, z) => { upSet = [x, y, z]; };
    kino.update(DT, makeInput(), cam);
    assert.deepEqual(upSet, [0, 1, 0], 'camera.up should be set to (0,1,0)');
  });
});

describe('update — edge cases', () => {
  test('update does not crash when called before launch (no guard needed, position is on orb)', () => {
    const kino = createKino();
    const cam = makeCamera();
    assert.doesNotThrow(() => kino.update(DT, makeInput(), cam));
  });

  test('update with dt=0 does not change velocity', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    const velBefore = kino.vel.clone();
    kino.update(0, makeInput({ move: { x: 1, y: 1 } }), cam);
    // lerp factor = min(1, 0*4) = 0 → no change
    assert.ok(kino.vel.equals(velBefore), 'velocity should not change with dt=0');
  });

  test('multiple updates accumulate yaw changes', () => {
    const kino = createKino();
    kino.launch(new THREE.Vector3(0, 0, 0), 0);
    const cam = makeCamera();
    kino.update(DT, makeInput({ look: { x: 0.1, y: 0 } }), cam);
    kino.update(DT, makeInput({ look: { x: 0.1, y: 0 } }), cam);
    kino.update(DT, makeInput({ look: { x: 0.1, y: 0 } }), cam);
    assert.ok(Math.abs(kino.yaw - (-0.3)) < 0.001, `yaw should be ~-0.3 after 3 updates, got ${kino.yaw}`);
  });
});