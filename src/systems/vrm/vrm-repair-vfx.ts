/**
 * Repair VFX — procedural wrench tool + spark particles.
 *
 * Attaches a wrench mesh to the player's right hand bone during repair,
 * and emits orange/yellow spark particles from the tool tip.
 *
 * Usage:
 *   const vfx = new RepairVfx(vrm);
 *   vfx.start();   // attach tool + begin sparks
 *   vfx.update(dt); // call each frame while repairing
 *   vfx.stop();    // detach tool + fade sparks
 *   vfx.dispose(); // clean up GPU resources
 */
import type { VRM } from "@pixiv/three-vrm";
import {
	AdditiveBlending,
	BufferAttribute,
	BufferGeometry,
	BoxGeometry,
	Color,
	CylinderGeometry,
	Group,
	Mesh,
	MeshStandardMaterial,
	Object3D,
	Points,
	PointsMaterial,
	SphereGeometry,
	Vector3,
} from "three";

// ─── Config ───────────────────────────────────────────────────────────────────

/** Maximum concurrent spark particles. */
const MAX_SPARKS = 40;

/** Sparks emitted per second. */
const SPARK_RATE = 30;

/** Spark lifetime range in seconds. */
const SPARK_LIFE_MIN = 0.15;
const SPARK_LIFE_MAX = 0.45;

/** Spark initial speed range. */
const SPARK_SPEED_MIN = 1.5;
const SPARK_SPEED_MAX = 4.0;

/** Gravity applied to sparks (m/s²). */
const SPARK_GRAVITY = 6.0;

/** Spark base size. */
const SPARK_SIZE = 0.025;

// ─── Spark particle state ─────────────────────────────────────────────────────

type SparkParticle = {
	alive: boolean;
	age: number;
	lifetime: number;
	position: Vector3;
	velocity: Vector3;
};

// ─── RepairVfx ────────────────────────────────────────────────────────────────

export class RepairVfx {
	private readonly vrm: VRM;
	private readonly handBone: Object3D | null;
	private readonly toolGroup: Group;
	private readonly sparksGeometry: BufferGeometry;
	private readonly sparksPoints: Points;
	private readonly sparks: SparkParticle[] = [];
	private readonly sparkPositions: Float32Array;
	private readonly sparkColors: Float32Array;
	private readonly sparkSizes: Float32Array;

	private active = false;
	private sparkAccumulator = 0;

	constructor(vrm: VRM) {
		this.vrm = vrm;
		this.handBone = vrm.humanoid?.getNormalizedBoneNode("rightHand") ?? null;

		// ── Procedural wrench ─────────────────────────────────────────────────
		this.toolGroup = this.createWrench();

		// ── Spark particle system ─────────────────────────────────────────────
		this.sparkPositions = new Float32Array(MAX_SPARKS * 3);
		this.sparkColors = new Float32Array(MAX_SPARKS * 3);
		this.sparkSizes = new Float32Array(MAX_SPARKS);

		this.sparksGeometry = new BufferGeometry();
		this.sparksGeometry.setAttribute("position", new BufferAttribute(this.sparkPositions, 3));
		this.sparksGeometry.setAttribute("color", new BufferAttribute(this.sparkColors, 3));
		this.sparksGeometry.setAttribute("size", new BufferAttribute(this.sparkSizes, 1));

		const sparksMaterial = new PointsMaterial({
			size: SPARK_SIZE,
			vertexColors: true,
			blending: AdditiveBlending,
			transparent: true,
			depthWrite: false,
			sizeAttenuation: true,
		});

		this.sparksPoints = new Points(this.sparksGeometry, sparksMaterial);
		this.sparksPoints.frustumCulled = false;

		// Pre-allocate particle pool
		for (let i = 0; i < MAX_SPARKS; i++) {
			this.sparks.push({
				alive: false,
				age: 0,
				lifetime: 0,
				position: new Vector3(),
				velocity: new Vector3(),
			});
		}
	}

	/** Attach tool to hand and start emitting sparks. */
	start(): void {
		if (this.active) return;
		this.active = true;
		this.sparkAccumulator = 0;

		if (this.handBone) {
			this.handBone.add(this.toolGroup);
		}

		// Add sparks to the VRM scene root so they're in world space
		this.vrm.scene.add(this.sparksPoints);
	}

	/** Detach tool and stop emitting (existing sparks fade out). */
	stop(): void {
		if (!this.active) return;
		this.active = false;

		if (this.handBone) {
			this.handBone.remove(this.toolGroup);
		}

		// Kill all sparks immediately
		for (const spark of this.sparks) {
			spark.alive = false;
		}
		this.syncGeometry();

		this.vrm.scene.remove(this.sparksPoints);
	}

	/** Update spark particles. Call each frame while repair is active or sparks remain. */
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
				continue;
			}

			// Apply gravity
			spark.velocity.y -= SPARK_GRAVITY * delta;

			// Integrate position
			spark.position.addScaledVector(spark.velocity, delta);
		}

		this.syncGeometry();
	}

	/** Clean up all GPU resources. */
	dispose(): void {
		this.stop();
		this.sparksGeometry.dispose();
		(this.sparksPoints.material as PointsMaterial).dispose();
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

		// Handle — thin cylinder
		const handle = new Mesh(new CylinderGeometry(0.008, 0.008, 0.14, 6), metalMaterial);
		handle.position.set(0, 0.07, 0);
		group.add(handle);

		// Head — wider box at the top
		const head = new Mesh(new BoxGeometry(0.035, 0.025, 0.012), metalMaterial);
		head.position.set(0, 0.15, 0);
		group.add(head);

		// Jaw opening — small indent (two small boxes forming a U shape)
		const jawLeft = new Mesh(new BoxGeometry(0.008, 0.03, 0.012), metalMaterial);
		jawLeft.position.set(-0.014, 0.17, 0);
		group.add(jawLeft);

		const jawRight = new Mesh(new BoxGeometry(0.008, 0.03, 0.012), metalMaterial);
		jawRight.position.set(0.014, 0.17, 0);
		group.add(jawRight);

		// Grip accent — slightly wider section at handle base
		const grip = new Mesh(new CylinderGeometry(0.01, 0.01, 0.04, 6),
			new MeshStandardMaterial({ color: 0x333333, roughness: 0.8 })
		);
		grip.position.set(0, 0.02, 0);
		group.add(grip);

		// Point light indicator — small emissive sphere at the tool tip
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

		// Orient wrench to sit naturally in hand — offset forward from wrist to palm
		group.position.set(0, 0, 0.10);
		group.rotation.set(0, 0, -Math.PI * 0.15);
		group.scale.setScalar(1.2);

		return group;
	}

	private emitSpark(): void {
		// Find a dead particle to reuse
		const spark = this.sparks.find((s) => !s.alive);
		if (!spark) return;

		// Get tool tip world position
		const tipWorld = new Vector3(0, 0.185, 0);
		this.toolGroup.localToWorld(tipWorld);

		spark.alive = true;
		spark.age = 0;
		spark.lifetime = SPARK_LIFE_MIN + Math.random() * (SPARK_LIFE_MAX - SPARK_LIFE_MIN);
		spark.position.copy(tipWorld);

		// Random outward direction with upward bias
		const speed = SPARK_SPEED_MIN + Math.random() * (SPARK_SPEED_MAX - SPARK_SPEED_MIN);
		spark.velocity.set(
			(Math.random() - 0.5) * 2,
			Math.random() * 0.8 + 0.2,
			(Math.random() - 0.5) * 2,
		).normalize().multiplyScalar(speed);
	}

	private syncGeometry(): void {
		const hotColor = new Color(0xffaa00);
		const coolColor = new Color(0xff4400);
		const tmpColor = new Color();

		for (let i = 0; i < MAX_SPARKS; i++) {
			const spark = this.sparks[i];
			const i3 = i * 3;

			if (!spark.alive) {
				this.sparkPositions[i3] = 0;
				this.sparkPositions[i3 + 1] = -1000; // hide offscreen
				this.sparkPositions[i3 + 2] = 0;
				this.sparkSizes[i] = 0;
				continue;
			}

			this.sparkPositions[i3] = spark.position.x;
			this.sparkPositions[i3 + 1] = spark.position.y;
			this.sparkPositions[i3 + 2] = spark.position.z;

			// Fade size and color over lifetime
			const t = spark.age / spark.lifetime;
			this.sparkSizes[i] = SPARK_SIZE * (1 - t * 0.6);

			tmpColor.copy(hotColor).lerp(coolColor, t);
			this.sparkColors[i3] = tmpColor.r;
			this.sparkColors[i3 + 1] = tmpColor.g;
			this.sparkColors[i3 + 2] = tmpColor.b;
		}

		this.sparksGeometry.attributes.position.needsUpdate = true;
		this.sparksGeometry.attributes.color.needsUpdate = true;
		this.sparksGeometry.attributes.size.needsUpdate = true;
	}

	private hasAliveSparks(): boolean {
		return this.sparks.some((s) => s.alive);
	}

	private disposeToolGroup(): void {
		this.toolGroup.traverse((child) => {
			if (child instanceof Mesh) {
				child.geometry.dispose();
				if (child.material instanceof MeshStandardMaterial) {
					child.material.dispose();
				}
			}
		});
	}
}
