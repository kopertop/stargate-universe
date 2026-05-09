export type InteractionVector = Readonly<{ x: number; y: number; z: number }>;

export interface InteractionTarget<TType extends string = string> {
	id: string;
	type: TType;
	position: InteractionVector;
	radius?: number;
	priority?: number;
	disabled?: boolean;
}

export interface InteractionTargetResult<TType extends string = string> {
	target: InteractionTarget<TType>;
	distance: number;
}

const distanceSquared = (a: InteractionVector, b: InteractionVector): number => {
	const dx = a.x - b.x;
	const dy = a.y - b.y;
	const dz = a.z - b.z;
	return dx * dx + dy * dy + dz * dz;
};

export const resolveNearestInteractionTarget = <TType extends string>(
	targets: ReadonlyArray<InteractionTarget<TType>>,
	playerPosition: InteractionVector,
	defaultRadius = 2.5,
): InteractionTargetResult<TType> | null => {
	let best: InteractionTargetResult<TType> | null = null;
	let bestPriority = Number.NEGATIVE_INFINITY;

	for (const target of targets) {
		if (target.disabled) continue;

		const radius = target.radius ?? defaultRadius;
		const distSq = distanceSquared(target.position, playerPosition);
		if (distSq > radius * radius) continue;

		const distance = Math.sqrt(distSq);
		const priority = target.priority ?? 0;
		if (
			!best
			|| priority > bestPriority
			|| (priority === bestPriority && distance < best.distance)
		) {
			best = { target, distance };
			bestPriority = priority;
		}
	}

	return best;
};
