import { emit } from "./event-bus";
import { addResource, RESOURCE_TYPES, type ResourceType } from "./resources";

export type LootContents = Partial<Record<ResourceType, number>>;

export interface LootContainerDefinition {
	id: string;
	source: string;
	contents: LootContents;
	label?: string;
}

export interface LootContainerState extends LootContainerDefinition {
	opened: boolean;
}

export interface LootStateSnapshot {
	version: 1;
	containers: LootContainerState[];
}

export type LootOpenResult =
	| { status: "opened"; container: LootContainerState; contents: LootContents }
	| { status: "already-opened"; container: LootContainerState; contents: LootContents };

const containers = new Map<string, LootContainerState>();

const cloneContents = (contents: LootContents): LootContents =>
	Object.fromEntries(
		Object.entries(contents)
			.filter(([type, amount]) => RESOURCE_TYPES.includes(type as ResourceType) && typeof amount === "number" && amount > 0)
			.map(([type, amount]) => [type, amount]),
	) as LootContents;

const cloneContainer = (container: LootContainerState): LootContainerState => ({
	id: container.id,
	source: container.source,
	label: container.label,
	contents: cloneContents(container.contents),
	opened: container.opened,
});

export const registerLootContainer = (definition: LootContainerDefinition): LootContainerState => {
	const existing = containers.get(definition.id);
	const next: LootContainerState = {
		id: definition.id,
		source: definition.source,
		label: definition.label,
		contents: cloneContents(definition.contents),
		opened: existing?.opened ?? false,
	};
	containers.set(definition.id, next);
	return cloneContainer(next);
};

export const openLootContainer = (definition: LootContainerDefinition): LootOpenResult => {
	const container = containers.get(definition.id) ?? registerLootContainer(definition);
	const runtime = containers.get(definition.id) ?? container;

	if (runtime.opened) {
		emit("loot:container:already-opened", {
			id: runtime.id,
			source: runtime.source,
		});
		return {
			status: "already-opened",
			container: cloneContainer(runtime),
			contents: cloneContents(runtime.contents),
		};
	}

	runtime.opened = true;
	for (const [type, amount] of Object.entries(runtime.contents) as Array<[ResourceType, number]>) {
		addResource(type, amount, runtime.source);
	}
	emit("loot:container:opened", {
		id: runtime.id,
		source: runtime.source,
		contents: cloneContents(runtime.contents) as Record<string, number>,
	});

	return {
		status: "opened",
		container: cloneContainer(runtime),
		contents: cloneContents(runtime.contents),
	};
};

export const isLootContainerOpened = (id: string): boolean =>
	containers.get(id)?.opened ?? false;

export const getLootContainer = (id: string): LootContainerState | undefined => {
	const container = containers.get(id);
	return container ? cloneContainer(container) : undefined;
};

export const serializeLootState = (): LootStateSnapshot => ({
	version: 1,
	containers: [...containers.values()].map(cloneContainer),
});

export const deserializeLootState = (snapshot?: LootStateSnapshot): void => {
	containers.clear();
	if (!snapshot) return;
	for (const container of snapshot.containers) {
		containers.set(container.id, {
			id: container.id,
			source: container.source,
			label: container.label,
			contents: cloneContents(container.contents),
			opened: container.opened,
		});
	}
};

export const resetLootState = (): void => {
	containers.clear();
};
