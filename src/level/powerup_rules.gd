class_name PowerupRules
extends RefCounted

# Pure routing for crate collections (spec §1-§4). No scene access, no
# state — Level supplies the RNG and the skunk-unlocked bit. Routing reads
# the Pieces registry; crate powerups are declared in sidecars, not hardcoded.

const SKUNK_CHANCE := 0.10  # owner call 2026-09-03: ceremony proven, rarity restored (matches the future ammo-rare standard)
const POOL: Array[StringName] = [&"free_shot", &"exploding", &"multishot", &"super_bounce"]
const BUFF_LABELS := {
	&"exploding": "+Exploding Shot",
	&"multishot": "+Multi-shot",
	&"super_bounce": "+Super Bounce",
}


static func route(type_id: String, skunk_unlocked: bool, roll: Callable) -> Dictionary:
	var power := str(Pieces.entry(type_id).get("powerup", ""))
	return _route_power(power, skunk_unlocked, roll)


## Route using a spawned crate node. Consults crate's "powerup" meta (snapshot set at
## spawn time) when present, so mid-level registry changes cannot alter a live crate's
## reward. Falls back to the registry for crates without the meta (compat with any
## non-builder spawn path).
static func route_crate(crate: Node, skunk_unlocked: bool, roll: Callable) -> Dictionary:
	var power: String
	if crate.has_meta("powerup"):
		power = str(crate.get_meta("powerup"))
	else:
		power = str(Pieces.entry(crate.get_meta("json_coords", {}).get("type", "")).get("powerup", "")) if crate.has_meta("json_coords") else ""
	return _route_power(power, skunk_unlocked, roll)


static func _route_power(power: String, skunk_unlocked: bool, roll: Callable) -> Dictionary:
	match power:
		"free_shot":
			return {"kind": "refund", "label": "+Free Shot"}
		"exploding", "multishot", "super_bounce":
			var buff := StringName(power)
			return {"kind": "buff", "buff": buff, "label": BUFF_LABELS[buff]}
		"mystery":
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
