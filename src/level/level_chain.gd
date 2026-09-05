class_name LevelChain
extends RefCounted

# The one ordered level chain (progression spec §1): built-ins then
# user levels, each block alphabetical by stem. Rebuilt fresh on every
# call — add/delete/rename in the folders is instantly reflected.


# Progress identity: namespaced so a user level named "aim" never
# shares completion with the built-in "aim" (audit P2). Display keeps
# using the bare stem; only the ledger speaks namespaced.
static func level_id(path: String) -> String:
	var ns := "builtin" if path.begins_with("res://") else "user"
	return "%s:%s" % [ns, path.get_file().get_basename()]


static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in LevelStore.list_builtin() + LevelStore.list_user():
		var layout := LevelStore.load_level(path)
		if layout == null:
			push_warning("Chain skips unloadable level: %s" % path)
			continue
		(
			out
			. append(
				{
					"stem": path.get_file().get_basename(),
					"id": level_id(path),
					"path": path,
					"title": layout.title,
					"thumb": layout.thumb,
				}
			)
		)
	return out


static func is_unlocked(chain: Array, index: int, tier: String) -> bool:
	if index < 0 or index >= chain.size():
		return false
	if index == 0:
		return true
	return Progress.is_cleared(tier, chain[index - 1]["id"])


# -1 for an empty chain — callers guard with is_empty() first.
static func frontier(chain: Array, tier: String) -> int:
	for i in chain.size():
		if not Progress.is_cleared(tier, chain[i]["id"]):
			return i
	return chain.size() - 1


static func next_index_after(chain: Array, id: String) -> int:
	for i in chain.size():
		if chain[i]["id"] == id:
			return i + 1 if i + 1 < chain.size() else -1
	return -1
