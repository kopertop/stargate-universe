/**
 * Repair VFX — procedural wrench tool + mesh-based spark particles.
 *
 * Uses small emissive Mesh spheres instead of Points (which don't render
 * properly on the WebGPU renderer — size is always 1px).
 *
 * @see https://github.com/mrdoob/three.js/issues/30612
 */
import type { VRM } from "@pixiv/three-vrm";
import {
	BoxGeometry,
	Color,
	CylinderGeometry,
	Group,
	Mesh,
	MeshBasicMaterial,
	MeshStandardMaterial,
	Object3D,
	Scene,
	SphereGeometry,
	Vector3,
} from "three";

// ─── Config ───────────────────────────────────────────────────────────────────

const MAX_SPARKS = 30;
const SPARK_RATE = 25;
const SPARK_LIFE_MIN = 0.3;
const SPARK_LIFE_MAX = 0.8;
const SPARK_SPEED_MIN = 3.0;
const SPARK_SPEED_MAX = 7.0;
const SPARK_GRAVITY = 6.0;
const SPARK_RADIUS = 0.008;

// ─── Spark particle ───────────────────────────────────────────────────────────

type SparkParticle = {
	alive: boolean;
	age: number;
	lifetime: number;
	position: Vector3;
	velocity: Vector3;
	mesh: Mesh;
};

// Shared geometry + materials for all spark meshes
const sparkGeometry = new SphereGeometry(SPARK_RADIUS, 4, 4);
const sparkHotMat = new MeshBasicMaterial({ color: 0xffaa00 });
const sparkCoolMat = new MeshBasicMaterial({ color: 0xff4400 });
const tmpColor = new Color();

// ─── RepairVfx ────────────────────────────────────────────────────────────────

export class RepairVfx {
	private readonly vrm: VRM;
	private readonly worldScene: Scene;
	private readonly handBone: Object3D | null;
	private readonly toolGroup: Group;
	private readonly sparkContainer: Group;
	private readonly sparks: SparkParticle[] = [];

	private active = false;
	private sparkAccumulator = 0;

	constructor(vrm: VRM, worldScene: Scene) {
		this.vrm = vrm;
		this.worldScene = worldScene;
		this.handBone = vrm.humanoid?.getNormalizedBoneNode("rightHand") ?? null;

		this.toolGroup = this.createWrench();
		this.sparkContainer = new Group();
		this.sparkContainer.name = "repair-sparks";

		// Pre-allocate spark mesh pool
		for (let i = 0; i < MAX_SPARKS; i++) {
			const mesh = new Mesh(sparkGeometry, sparkHotMat.clone());
			mesh.visible = false;
			this.sparkContainer.add(mesh);

			this.sparks.push({
				alive: false,
				age: 0,
				lifetime: 0,
				position: new Vector3(),
				velocity: new Vector3(),
				mesh,
			});
		}
	}

	start(): void {
		if (this.active) return;
		this.active = true;
		this.sparkAccumulator = 0;

		if (this.handBone) {
			this.handBone.add(this.toolGroup);
		}

		this.worldScene.add(this.sparkContainer);
	}

	stop(): void {
		if (!this.active) return;
		this.active = false;

		if (this.handBone) {
			this.handBone.remove(this.toolGroup);
		}

		for (const spark of this.sparks) {
			spark.alive = false;
			spark.mesh.visible = false;
		}

		this.worldScene.remove(this.sparkContainer);
	}

	update(delta: number): void {
		if (!this.active && !this.hasAliveSparks()) return;

		// Emit new sparks
		if (this.active) {
			this.sparkAccumulator += delta;
			const interval = 1 / SPARK_RATE;
			while (this.sparkAccumulator >= interval) {
				this.sparkAccumulator -= interval;
				this.emitSpark();
			}
		}

		// Update existing sparks
		for (const spark of this.sparks) {
			if (!spark.alive) continue;

			spark.age += delta;
			if (spark.age >= spark.lifetime) {
				spark.alive = false;
				spark.mesh.visible = false;
				continue;
			}

			spark.velocity.y -= SPARK_GRAVITY * delta;
			spark.position.addScaledVector(spark.velocity, delta);
			spark.mesh.position.copy(spark.position);

			// Fade color from hot orange to cool red and shrink
			const t = spark.age / spark.lifetime;
			tmpColor.setRGB(1, 0.67 * (1 - t), 0.1 * (1 - t));
			(spark.mesh.material as MeshBasicMaterial).color.copy(tmpColor);

			const scale = 1 - t * 0.7;
			spark.mesh.scale.setScalar(scale);
		}
	}

	dispose(): void {
		this.stop();
		for (const spark of this.sparks) {
			(spark.mesh.material as MeshBasicMaterial).dispose();
		}
		this.disposeToolGroup();
	}

	// ─── Internal ──────────────────────────────────────────────────────────────

	private createWrench(): Group {
		const group = new Group();
		const metalMaterial = new MeshStandardMaterial({
			color: 0x888888,
			metalness: 0.85,
			roughness: 0.3,
		});

		const handle = new Mesh(new CylinderGeometry(0.008, 0.008, 0.14, 6), metalMaterial);
		handle.position.set(0, 0.07, 0);
		group.add(handle);

		const head = new Mesh(new BoxGeometry(0.035, 0.025, 0.012), metalMaterial);
		head.position.set(0, 0.15, 0);
		group.add(head);

		const jawLeft = new Mesh(new BoxGeometry(0.008, 0.03, 0.012), metalMaterial);
		jawLeft.position.set(-0.014, 0.17, 0);
		group.add(jawLeft);

		const jawRight = new Mesh(new BoxGeometry(0.008, 0.03, 0.012), metalMaterial);
		jawRight.position.set(0.014, 0.17, 0);
		group.add(jawRight);

		const grip = new Mesh(new CylinderGeometry(0.01, 0.01, 0.04, 6),
			new MeshStandardMaterial({ color: 0x333333, roughness: 0.8 })
		);
		grip.position.set(0, 0.02, 0);
		group.add(grip);

		const tipGlow = new Mesh(
			new SphereGeometry(0.006, 6, 6),
			new MeshStandardMaterial({
				color: 0xff8800,
				emissive: 0xff6600,
				emissiveIntensity: 2.0,
			})
		);
		tipGlow.position.set(0, 0.185, 0);
		group.add(tipGlow);

		group.position.set(0, 0, 0.10);
		group.rotation.set(0, 0, -Math.PI * 0.15);
		group.scale.setScalar(1.2);

		return group;
	}

	private emitSpark(): void {
		const spark = this.sparks.find((s) => !s.alive);
		if (!spark) return;

		// Get wrench tip in world space — use the tipGlow child's world position
		const tipWorld = new Vector3();
		// The tip glow is the last child of the wrench group
		const tipChild = this.toolGroup.children[this.toolGroup.children.length - 1];
		if (tipChild) {
			tipChild.getWorldPosition(tipWorld);
		} else {
			this.toolGroup.getWorldPosition(tipWorld);
		}

		spark.alive = true;
		spark.age = 0;
		spark.lifetime = SPARK_LIFE_MIN + Math.random() * (SPARK_LIFE_MAX - SPARK_LIFE_MIN);
		spark.position.copy(tipWorld);

		const speed = SPARK_SPEED_MIN + Math.random() * (SPARK_SPEED_MAX - SPARK_SPEED_MIN);
		spark.velocity.set(
			(Math.random() - 0.5) * 3,
			Math.random() * 1.5 - 0.3,
			(Math.random() - 0.5) * 3,
		).normalize().multiplyScalar(speed);

		spark.mesh.visible = true;
		spark.mesh.position.copy(spark.position);
		spark.mesh.scale.setScalar(1);
		(spark.mesh.material as MeshBasicMaterial).color.set(0xffaa00);
	}

	private hasAliveSparks(): boolean {
		return this.sparks.some((s) => s.alive);
	}

	private disposeToolGroup(): void {
		this.toolGroup.traverse((child) => {
			if (child instanceof Mesh) {
				child.geometry.dispose();
				if (child.material instanceof MeshStandardMaterial || child.material instanceof MeshBasicMaterial) {
					child.material.dispose();
				}
			}
		});
	}
}
