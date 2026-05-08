import * as THREE from "three";

export interface SupplyCrate {
	mesh: THREE.Group;
	position: THREE.Vector3;
	contents: number;
	looted: boolean;
}

export function createSupplyCrate(
	scene: THREE.Scene,
	position: THREE.Vector3,
	contents: number,
): SupplyCrate {
	const group = new THREE.Group();
	group.position.copy(position);

	const body = new THREE.Mesh(
		new THREE.BoxGeometry(0.7, 0.5, 0.5),
		new THREE.MeshStandardMaterial({
			color: 0x776644,
			emissive: 0x221100,
			emissiveIntensity: 1.0,
			roughness: 0.85,
			metalness: 0.1,
		}),
	);
	body.position.y = 0.25;
	group.add(body);

	const lid = new THREE.Mesh(
		new THREE.BoxGeometry(0.75, 0.08, 0.55),
		new THREE.MeshStandardMaterial({
			color: 0x887755,
			emissive: 0x221100,
			emissiveIntensity: 1.0,
			roughness: 0.8,
			metalness: 0.1,
		}),
	);
	lid.position.y = 0.54;
	group.add(lid);

	const glow = new THREE.Mesh(
		new THREE.BoxGeometry(0.5, 0.04, 0.02),
		new THREE.MeshStandardMaterial({
			color: 0xffaa22,
			emissive: 0xffaa22,
			emissiveIntensity: 0.6,
		}),
	);
	glow.position.set(0, 0.35, 0.26);
	group.add(glow);

	scene.add(group);

	return { mesh: group, position: position.clone(), contents, looted: false };
}

export function disposeSupplyCrate(crate: SupplyCrate): void {
	for (const child of crate.mesh.children) {
		if (child instanceof THREE.Mesh) {
			child.geometry.dispose();
			if (child.material instanceof THREE.Material) {
				child.material.dispose();
			}
		}
	}
	crate.mesh.removeFromParent();
}

export function markSupplyCrateLooted(crate: SupplyCrate): void {
	crate.looted = true;

	const glow = crate.mesh.children[2];
	if (glow instanceof THREE.Mesh && glow.material instanceof THREE.MeshStandardMaterial) {
		glow.material.color.set(0x222211);
		glow.material.emissive.set(0x222211);
		glow.material.emissiveIntensity = 0.1;
	}

	const lid = crate.mesh.children[1];
	if (lid) {
		lid.rotation.x = -0.4;
		lid.position.z = -0.1;
		lid.position.y = 0.58;
	}
}
