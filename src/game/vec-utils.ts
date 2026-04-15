/**
 * Utility functions for 3D vector math in Stargate Universe.
 */

/**
 * Calculates the Euclidean distance between two 3D points.
 * 
 * @param p1 - The first point as an array [x, y, z].
 * @param p2 - The second point as an array [x, y, z].
 * @returns The distance between the two points.
 */
export function getDistance3D(p1: number[], p2: number[]): number {
    const dx = p1[0] - p2[0];
    const dy = p1[1] - p2[1];
    const dz = p1[2] - p2[2];
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
}
