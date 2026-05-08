/**
 * `crate` prop — the canonical test prop for the editor. 1 m weathered
 * metal box that also registers a static physics body so players can't
 * walk through placed crates.
 */
import * as THREE from "three";
import { box } from "crashcat";
import { vec3, quat } from "mathcat";
import { MotionType, rigidBody, CRASHCAT_OBJECT_LAYER_STATIC } from "@ggez/runtime-physics-crashcat";
import type { PropBuildContext, PropCatalogEntry, PropInstance } from "../prop-catalog";

const CRATE_SIZE = 1.0;

const sharedCrateMaterial = new THREE.MeshStandardMaterial({
	color: 0x8a7356,
	roughness: 0.85,
	metalness: 0.2,
});

export const crateProp: PropCatalogEntry = {
	id: "crate",
	name: "Crate",
	previewSize: [CRATE_SIZE, CRATE_SIZE, CRATE_SIZE],
	create(ctx: PropBuildContext, position, rotation): PropInstance {
		const geo = new THREE.BoxGeometry(CRATE_SIZE, CRATE_SIZE, CRATE_SIZE);
		const mesh = new THREE.Mesh(geo, sharedCrateMaterial);
		// Place crate so its base sits on the floor at the clicked Y.
		mesh.position.set(position.x, position.y + CRATE_SIZE / 2, position.z);
		mesh.rotation.copy(rotation);
		mesh.castShadow = true;
		mesh.receiveShadow = true;
		ctx.scene.add(mesh);

		const body = rigidBody.create(ctx.physicsWorld, {
			shape: box.create({
				halfExtents: vec3.fromValues(CRATE_SIZE / 2, CRATE_SIZE / 2, CRATE_SIZE / 2),
				convexRadius: 0.02,
				density: 1.0,
			}),
			objectLayer: CRASHCAT_OBJECT_LAYER_STATIC,
			motionType: MotionType.STATIC,
			position: vec3.fromValues(mesh.position.x, mesh.position.y, mesh.position.z),
			quaternion: quat.create(),
		});

		return {
			id: "crate",
			root: mesh,
			dispose() {
				ctx.scene.remove(mesh);
				geo.dispose();
				rigidBody.remove(ctx.physicsWorld, body);
			},
		};
	},
};
