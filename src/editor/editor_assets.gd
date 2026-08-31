class_name EditorAssets
extends RefCounted

# Folder-is-behavior asset registry (spec §2). Drop a PNG in
# assets/editor/<behavior>/ and it becomes placeable; an optional
# <name>.txt beside it is the palette tooltip.

const ROOT := "res://assets/editor"

static var _cache := {}

static func scan() -> void:
	_cache = {}
	for behavior in ["crates"]:
		var entries: Array[Dictionary] = []
		var dir_path := "%s/%s" % [ROOT, behavior]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			_cache[behavior] = entries
			continue
		for f in dir.get_files():
			var file_name := f.trim_suffix(".remap").trim_suffix(".import")
			if file_name.get_extension() != "png" or _has(entries, file_name.get_basename()):
				continue
			var id := file_name.get_basename()
			var tex: Texture2D = load("%s/%s" % [dir_path, file_name])
			var desc := id
			var txt_path := "%s/%s.txt" % [dir_path, id]
			if FileAccess.file_exists(txt_path):
				desc = FileAccess.open(txt_path, FileAccess.READ) \
					.get_as_text().strip_edges()
			entries.append({"id": id, "texture": tex, "description": desc})
		entries.sort_custom(func(a, b): return a["id"] < b["id"])
		_cache[behavior] = entries

static func crates() -> Array[Dictionary]:
	if _cache.is_empty():
		scan()
	return _cache.get("crates", [] as Array[Dictionary])

static func texture_for(id: String) -> Texture2D:
	for e in crates():
		if e["id"] == id:
			return e["texture"]
	return null

static func _has(entries: Array[Dictionary], id: String) -> bool:
	for e in entries:
		if e["id"] == id:
			return true
	return false
