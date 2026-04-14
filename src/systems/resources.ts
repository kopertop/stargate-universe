/**
 * Resource & Inventory System — tracks all resources in the ship-wide pool.
 *
 * Simple key-value store for MVP. No carry limits, no weight.
 * @see design/gdd/resource-inventory.md
 */
import { emit } from "./event-bus";

export const RESOURCE_TYPES = ["ship-parts", "water", "food", "lime"] as const;
export type ResourceType = typeof RESOURCE_TYPES[number];

const resources = new Map<ResourceType, number>();

/**
 * Initialize with starting amounts for the crew's shared resource pool.
 */
export function initResources(): void {
	resources.set("ship-parts", 10);
	resources.set("water", 50);
	resources.set("food", 40);
	resources.set("lime", 20);
}

/**
 * Get the current amount of a specific resource.
 * @param type The resource type to query.
 * @returns The amount currently in the pool.
 */
export function getResource(type: ResourceType): number {
	return resources.get(type) ?? 0;
}

/**
 * Get all current resource balances as a record.
 * @returns A mapping of resource types to their current amounts.
 */
export function getAllResources(): Record<ResourceType, number> {
	const result = {} as Record<ResourceType, number>;
	for (const type of RESOURCE_TYPES) {
		result[type] = resources.get(type) ?? 0;
	}
	return result;
}

/**
 * Add specified amount of a resource to the shared pool.
 * @param type   The resource type being added.
 * @param amount The quantity to add.
 * @returns The new total amount of the resource.
 */
export function addResource(type: ResourceType, amount: number): number {
	const current = resources.get(type) ?? 0;
	const newAmount = current + amount;
	resources.set(type, newAmount);

	emit("resource:collected", { type, amount, source: "pickup" });
	return newAmount;
}

/**
 * Consume a specified amount of a resource from the pool.
 * @param type   The resource type to consume.
 * @param amount The quantity required.
 * @returns True if the operation was successful, false if resources were insufficient.
 */
export function consumeResource(type: ResourceType, amount: number): boolean {
	const current = resources.get(type) ?? 0;
	if (current < amount) return false;

	const newAmount = current - amount;
	resources.set(type, newAmount);

	emit("resource:consumed", { type, amount, consumer: "repair" });

	if (newAmount === 0) {
		emit("resource:depleted", { type });
	}

	return true;
}

/**
 * Check if the Shared pool contains at least the required amount of a resource.
 * @param type   The resource type to check.
 * @param amount The minimum amount required.
 * @returns True if sufficient resources exist.
 */
export function hasResource(type: ResourceType, amount: number): boolean {
	return (resources.get(type) ?? 0) >= amount;
}

/** Serialization */
export const saveId = "resources";

export function serialize(): Record<string, unknown> {
	const data: Record<string, number> = {};
	for (const [key, val] of resources) {
		data[key] = val;
	}
	return { version: 1, resources: data };
}

export function deserialize(data: Record<string, unknown>): void {
	const saved = data.resources as Record<string, number> | undefined;
	if (!saved) return;
	for (const type of RESOURCE_TYPES) {
		if (type in saved) {
			resources.set(type, saved[type]);
		}
	}
}
