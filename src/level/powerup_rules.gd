class_name PowerupRules
extends RefCounted

# Pure routing for crate collections (spec §1-§4). No scene access, no
# state — Level supplies the RNG and the skunk-unlocked bit.

const SKUNK_CHANCE := 0.10  # owner call 2026-09-03: ceremony proven, rarity restored (matches the future ammo-rare standard)
const POOL: Array[StringName] = [&"free_shot", &"exploding", &"multishot", &"super_bounce"]
const BUFF_LABELS := {
	&"exploding": "+Exploding Shot",
	&"multishot": "+Multi-shot",
	&"super_bounce": "+Super Bounce",
}


static func route(type_id: String, skunk_unlocked: bool, roll: Callable) -> Dictionary:
	match type_id:
		"crate-gold":
			return {"kind": "refund", "label": "+Free Shot"}
		"skull":
			return {"kind": "buff", "buff": &"exploding", "label": BUFF_LABELS[&"exploding"]}
		"crate-blue":
			return {"kind": "buff", "buff": &"multishot", "label": BUFF_LABELS[&"multishot"]}
		"crate-green":
			return {"kind": "buff", "buff": &"super_bounce", "label": BUFF_LABELS[&"super_bounce"]}
		"crate-ghost":
			if not skunk_unlocked and roll.call() < SKUNK_CHANCE:
				return {"kind": "skunk"}
			var pick: StringName = POOL[clampi(int(roll.call() * POOL.size()), 0, POOL.size() - 1)]
			if pick == &"free_shot":
				return {"kind": "refund", "label": "+Free Shot"}
			return {"kind": "buff", "buff": pick, "label": BUFF_LABELS[pick]}
	return {"kind": "none"}


static func drain(queue: Array[StringName]) -> Dictionary:
	var consumed: Array[StringName] = []
	var remaining: Array[StringName] = []
	for b in queue:
		if consumed.has(b):
			remaining.append(b)
		else:
			consumed.append(b)
	return {"consumed": consumed, "remaining": remaining}
