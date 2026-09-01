class_name LevelChain
extends RefCounted

# The one ordered level chain (progression spec §1): built-ins then
# user levels, each block alphabetical by stem. Rebuilt fresh on every
# call — add/delete/rename in the folders is instantly reflected.


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
	return Progress.is_cleared(tier, chain[index - 1]["stem"])


# -1 for an empty chain — callers guard with is_empty() first.
static func frontier(chain: Array, tier: String) -> int:
	for i in chain.size():
		if not Progress.is_cleared(tier, chain[i]["stem"]):
			return i
	return chain.size() - 1


static func next_index_after(chain: Array, stem: String) -> int:
	for i in chain.size():
		if chain[i]["stem"] == stem:
			return i + 1 if i + 1 < chain.size() else -1
	return -1
