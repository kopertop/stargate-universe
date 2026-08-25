/* eslint-disable @typescript-eslint/no-explicit-any */
import * as THREE from 'three';

/**
 * Hex coordinate utilities for axial coordinate system (q, r, s)
 * Axial coordinates are useful for hex grids and tile-based games
 */
export class Hex {
  q: number; // Column coordinate (axial)
  r: number; // Row coordinate (axial)
  s: number; // Depth coordinate (axial = -q - r)
  data?: any; // Additional data (e.g., module type, terrain)

  constructor(q: number, r: number) {
    this.q = q;
    this.r = r;
    this.s = -q - r;
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
  clone(): Hex {
    const clone = new Hex(this.q, this.r);
    clone.data = this.data;
    return clone;
  }

  /**
   * Create hex from cube coordinates
   */
  static fromCube(q: number, r: number): Hex {
    return new Hex(q, r);
  }

  /**
   * Calculate distance between two hexes using cube coordinates
   * @param a - First hex
   * @param b - Second hex
   */
  static distance(a: Hex, b: Hex): number {
    return (
      (Math.abs(a.q - b.q) +
        Math.abs(a.q + a.r - b.q - b.r) +
        Math.abs(a.r - b.r)) / 2
    );
  }

  /**
   * Create a neighbor hex in a specific direction (1-6)
   * @param direction - Direction: 1=e, 2=ne, 3=nw, 4=w, 5=sw, 6=se
   */
  neighbor(direction: number): Hex {
    const directions = [
      [1, 0], [1, -1], [0, -1],
      [-1, 0], [-1, 1], [0, 1]
    ];
    const [dq, dr] = directions[direction - 1] || [0, 0];
    return new Hex(this.q + dq, this.r + dr);
  }

  /**
   * Get all 6 neighbors
   */
  neighbors(): Hex[] {
    return [
      this.neighbor(1), this.neighbor(2), this.neighbor(3),
      this.neighbor(4), this.neighbor(5), this.neighbor(6)
    ];
  }

  /**
   * Check if this hex is adjacent to another
   * @param other - Other hex
   */
  adjacent(other: Hex): boolean {
    return Hex.distance(this, other) === 1;
  }

  /**
   * Check if two hexes are the same
   */
  equals(other: Hex): boolean {
    return this.q === other.q && this.r === other.r;
  }
}

/**
 * Hex grid utilities
 */
export class HexGrid {
  /**
   * Generate all hexes in a grid up to a specific size
   * @param size - Grid dimension (will create size x size grid)
   * @returns Array of hexes
   */
  static generateGrid(size: number): Hex[] {
    const hexes: Hex[] = [];
    for (let q = 0; q < size; q++) {
      for (let r = 0; r < size; r++) {
        hexes.push(new Hex(q, r));
      }
    }
    return hexes;
  }

  /**
   * Find hexes in a range from a center using cube distance
   * @param center - Center hex
   * @param distance - Maximum distance
   * @returns Array of hexes in range
   */
  static range(center: Hex, distance: number): Hex[] {
    const result: Hex[] = [];
    for (let q = -distance; q <= distance; q++) {
      for (let r = Math.max(-distance, -q - distance); r <= Math.min(distance, -q + distance); r++) {
        result.push(new Hex(center.q + q, center.r + r));
      }
    }
    return result;
  }

  /**
   * Find all valid neighbors for placing a new module
   * @param center - Center hex
   * @param maxDistance - Maximum distance to check
   * @param occupiedHexes - Set of hexes to avoid
   */
  static validNeighbors(
    center: Hex,
    maxDistance: number,
    occupiedHexes: Set<string>
  ): Hex[] {
    return HexGrid.range(center, maxDistance)
      .filter(hex => !occupiedHexes.has(hex.toCubeKey()))
      .filter(hex => hex.adjacent(center));
  }

  /**
   * Convert hex to world coordinates
   * @param hex - Hex cell
   * @param hexSize - Size of a single hex
   * @param spacing - Distance between hexes
   */
  static toWorld(hex: Hex, hexSize: number, spacing: number = 0.2): THREE.Vector3 {
    const size = hexSize + spacing;
    const worldX = size * (Math.sqrt(3) * hex.q + Math.sqrt(3) / 2 * hex.r);
    const worldZ = size * (3 / 2 * hex.r);
    return new THREE.Vector3(worldX, 0, worldZ);
  }

  /**
   * Convert world coordinates to hex (centered)
   */
  static fromWorld(x: number, z: number, hexSize: number, spacing: number = 0.2): Hex {
    const size = hexSize + spacing;
    const q = (Math.sqrt(3)/3 * x - 1/3 * z) / size;
    const r = (2/3 * z) / size;
    return new Hex(Math.round(q), Math.round(r));
  }
}