/* eslint-disable @typescript-eslint/no-explicit-any */
import * as THREE from 'three';

/**
 * Hex grid rendering utilities using InstancedMesh for performance
 * Implements axial coordinate system (q, r) with cube coordinate conversions
 */
export interface HexGridOptions {
  gridSize: number;
  hexSize: number;
  spacing: number;
  backgroundColor: number;
  highlightColor: number;
  cameraOffset: THREE.Vector3;
}

export class HexGridRenderer {
  private scene: THREE.Scene;
  private instancedMesh: THREE.InstancedMesh;
  private hexes: Map<string, Hex> = new Map();
  private dummy = new THREE.Object3D();
  private options: HexGridOptions;

  /**
   * Initialize hex grid renderer with InstancedMesh for performance
   * @param scene - Three.js scene to attach to
   * @param options - Configuration options
   */
  constructor(scene: THREE.Scene, options: Partial<HexGridOptions>) {
    this.scene = scene;
    this.options = {
      gridSize: 9, // 9x9 grid (centered)
      hexSize: 1,
      spacing: 0.2,
      backgroundColor: 0x1a1a2e,
      highlightColor: 0x4361ee,
      cameraOffset: new THREE.Vector3(0, 0, 0),
      ...options
    };

    // Create instanced mesh for hexagons
    const totalHexes = this.options.gridSize * this.options.gridSize;
    const geometry = new THREE.CylinderGeometry(
      this.options.hexSize,
      this.options.hexSize,
      0.1,
      6
    );
    const material = new THREE.MeshStandardMaterial({
      color: this.options.highlightColor,
      metalness: 0.3,
      roughness: 0.7
    });

    this.instancedMesh = new THREE.InstancedMesh(geometry, material, totalHexes);
    this.instancedMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.scene.add(this.instancedMesh);

    // Create highlight plane for selection
    const highlightGeometry = new THREE.CylinderGeometry(
      this.options.hexSize * 0.9,
      this.options.hexSize * 0.9,
      0.15,
      6
    );
    const highlightMaterial = new THREE.MeshStandardMaterial({
      color: 0x4cc9f0,
      transparent: true,
      opacity: 0.5,
      metalness: 0.5,
      roughness: 0.4
    });

    const highlightMesh = new THREE.Mesh(highlightGeometry, highlightMaterial);
    highlightMesh.visible = false;
    this.scene.add(highlightMesh);
    this.options.highlightColor = 0x4cc9f0;

    // Add ambient and directional lights
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.4);
    scene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(5, 10, 7);
    scene.add(directionalLight);
  }

  /**
   * Generate a key for hex coordinates
   * @param q - Column coordinate (axial)
   * @param r - Row coordinate (axial)
   * @returns Unique string key
   */
  private getKey(q: number, r: number): string {
    return `${q},${r}`;
  }

  /**
   * Add a hex to the grid at specific coordinates
   * @param q - Column coordinate
   * @param r - Row coordinate
   */
  addHex(q: number, r: number): Hex {
    const hex = new Hex(q, r);
    this.hexes.set(this.getKey(q, r), hex);
    this.updateInstancedMesh();
    return hex;
  }

  /**
   * Get hex at specific coordinates
   * @param q - Column coordinate
   * @param r - Row coordinate
   */
  getHex(q: number, r: number): Hex | undefined {
    return this.hexes.get(this.getKey(q, r));
  }

  /**
   * Update the instanced mesh with current hex positions
   */
  updateInstancedMesh(): void {
    let index = 0;
    const halfGrid = (this.options.gridSize - 1) / 2;

    for (const [_, hex] of this.hexes) {
      // Convert axial (q, r) to world position
      const worldPos = this.axialToWorld(hex.q, hex.r);
      this.dummy.position.set(worldPos.x, worldPos.y, worldPos.z);
      this.dummy.scale.set(1, 1, 1);
      this.dummy.updateMatrix();
      this.instancedMesh.setMatrixAt(index, this.dummy.matrix);
      index++;
    }

    this.instancedMesh.count = this.hexes.size;
    this.instancedMesh.instanceMatrix.needsUpdate = true;
  }

  /**
   * Calculate world position from axial coordinates
   * @param q - Column coordinate
   * @param r - Row coordinate
   */
  private axialToWorld(q: number, r: number): THREE.Vector3 {
    const size = this.options.hexSize + this.options.spacing;
    const worldX = size * (Math.sqrt(3) * q + Math.sqrt(3) / 2 * r);
    const worldZ = size * (3 / 2 * r);
    return new THREE.Vector3(worldX, 0, worldZ);
  }

  /**
   * Highlight a specific hex
   * @param q - Column coordinate
   * @param r - Row coordinate
   */
  highlightHex(q: number, r: number): void {
    const hex = this.getHex(q, r);
    if (hex) {
      const position = this.axialToWorld(q, r);
      const dummy = new THREE.Object3D();
      dummy.position.set(position.x, position.y + 0.05, position.z);
      dummy.scale.set(1.1, 1.1, 1.1);
      dummy.updateMatrix();
      this.instancedMesh.setMatrixAt(this.hexes.get(this.getKey(q, r))!.index, dummy.matrix);
      this.instancedMesh.instanceMatrix.needsUpdate = true;
    }
  }

  /**
   * Clear all highlight colors (reset to highlight color)
   */
  clearHighlight(): void {
    for (let i = 0; i < this.hexes.size; i++) {
      const dummy = new THREE.Object3D();
      dummy.position.set(0, 0, 0);
      dummy.scale.set(1, 1, 1);
      dummy.updateMatrix();
      this.instancedMesh.setMatrixAt(i, dummy.matrix);
    }
    this.instancedMesh.instanceMatrix.needsUpdate = true;
  }

  /**
   * Remove hex from grid
   * @param q - Column coordinate
   * @param r - Row coordinate
   */
  removeHex(q: number, r: number): void {
    const key = this.getKey(q, r);
    const hex = this.hexes.get(key);
    if (hex) {
      this.hexes.delete(key);
      this.updateInstancedMesh();
    }
  }

  /**
   * Get all hexes in grid
   */
  getHexes(): Hex[] {
    return Array.from(this.hexes.values());
  }

  /**
   * Clear grid
   */
  clear(): void {
    this.hexes.clear();
    this.clearHighlight();
  }

  /**
   * Find hexes in range using cube distance
   * @param q - Center column coordinate
   * @param r - Center row coordinate
   * @param distance - Maximum distance
   */
  getHexesInRange(q: number, r: number, distance: number): Hex[] {
    const centerHex = new Hex(q, r);
    const result: Hex[] = [];

    for (const hex of this.hexes.values()) {
      const distance = this.cubeDistance(centerHex, hex);
      if (distance <= distance) {
        result.push(hex);
      }
    }

    return result;
  }

  /**
   * Cube coordinate distance calculation
   * @param a - First hex
   * @param b - Second hex
   */
  private cubeDistance(a: Hex, b: Hex): number {
    return (
      (Math.abs(a.q - b.q) +
        Math.abs(a.q + a.r - b.q - b.r) +
        Math.abs(a.r - b.r)) / 2
    );
  }

  /**
   * Resize the grid to different size (with boundary preservation)
   */
  resize(newGridSize: number): void {
    this.options.gridSize = newGridSize;
    this.clear();
  }
}

/**
 * Hex class representing individual hex grid cell
 */
export class Hex {
  q: number; // Column coordinate (axial)
  r: number; // Row coordinate (axial)
  s: number; // Depth coordinate (axial = -q - r)
  index: number; // Instance index for InstancedMesh
  id: string;
  data?: any; // Additional data (e.g., module type)

  constructor(q: number, r: number, index = 0) {
    this.q = q;
    this.r = r;
    this.s = -q - r;
    this.index = index;
    this.id = `hex-${q}-${r}`;
  }

  /**
   * Get cube coordinate string
   */
  toCubeKey(): string {
    return `${this.q},${this.r},${this.s}`;
  }

  /**
   * Clone hex with new index
   */
  clone(index: number = this.index): Hex {
    const clone = new Hex(this.q, this.r, index);
    clone.data = this.data;
    return clone;
  }
}