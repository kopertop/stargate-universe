/**
 * `simple-stargate` prop — stub version of the full gate-room stargate.
 *
 * A flat torus ring at the agreed 6m diameter + 0.8m width, no chevrons,
 * no event horizon, no dialing animation. Just the silhouette, so the
 * editor can validate placement of a recognizable anchor landmark.
 *
 * The full gate with activation FX lives in `src/scenes/gate-room/index.ts`
 * and is NOT extracted here yet — the gate-room is scripted around a fixed
 * world position. A future migration can promote that implementation into a
 * `stargate` prop with variants (idle/active/shutdown).
 */
import * as THREE from "three";
import type { PropBuildContext, PropCatalogEntry, PropInstance } from "../prop-catalog";

const GATE_RADIUS = 3.0;
const GATE_RING_WIDTH = 0.8;
const GATE_RING_DEPTH = 0.175;

const sharedRingMat = new THREE.MeshStandardMaterial({
	color: 0x2a2f40,
	roughness: 0.55,
	metalness: 0.75,
});

function createFlatRingGeometry(outerRadius: number, width: number, depth: number, segments: number): THREE.BufferGeometry {
	const inner = outerRadius - width / 2;
	const outer = outerRadius + width / 2;
	// 2D cross-section swept around Y; Lathe needs points on the XY plane.
	const half = depth / 2;
	const points = [
		new THREE.Vector2(inner, -half),
		new THREE.Vector2(outer, -half),
		new THREE.Vector2(outer,  half),
		new THREE.Vector2(inner,  half),
		new THREE.Vector2(inner, -half),
	];
	const geo = new THREE.LatheGeometry(points, segments);
	// Lathe wraps around Y; we want the ring standing up (around Z), so rotate.
	geo.rotateX(Math.PI / 2);
	return geo;
}

export const simpleStargateProp: PropCatalogEntry = {
	id: "simple-stargate",
	name: "Stargate (simple)",
	previewSize: [GATE_RADIUS * 2 + GATE_RING_WIDTH, GATE_RADIUS * 2 + GATE_RING_WIDTH, GATE_RING_DEPTH],
	create(ctx: PropBuildContext, position, rotation): PropInstance {
		const geo = createFlatRingGeometry(GATE_RADIUS, GATE_RING_WIDTH, GATE_RING_DEPTH, 48);
		const mesh = new THREE.Mesh(geo, sharedRingMat);
		// Same floor-relative placement convention as the real gate: portal
		// sunk 0.2m below the click-floor plane so there's no step to cross.
		const portalInnerRadius = GATE_RADIUS - GATE_RING_WIDTH / 2 - 0.05;
		mesh.position.set(position.x, position.y + portalInnerRadius - 0.2, position.z);
		mesh.rotation.copy(rotation);
		mesh.castShadow = true;
		mesh.receiveShadow = true;
		ctx.scene.add(mesh);

		return {
			id: "simple-stargate",
			root: mesh,
			dispose() {
				ctx.scene.remove(mesh);
				geo.dispose();
			},
		};
	},
};
