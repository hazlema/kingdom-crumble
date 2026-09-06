class_name Pieces
extends RefCounted

# One registry for everything placeable (spec: pieces-design §1-2).
# res://pieces/ holds baked content: one PNG per object + optional JSON
# sidecar. Sidecars SELECT AND TUNE curated classes, never define
# behavior. No sidecar = plain 1x1 crate. Wave 2 adds user://toybox
# packs; scan() is shaped so a second root is additive.

const ROOT := "res://pieces"
const CLASSES := ["crate", "static", "trampoline"]
const TILTS := [-45, 0, 45]
const MAX_CELL := 4
const TIP_CAP := 200

static var _cache := {}  # id -> entry Dictionary


static func scan() -> void:
	_cache = {}
	_scan_dir(ROOT)


static func _scan_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_scan_dir("%s/%s" % [dir_path, d])  # subfolders are organizational
	for f in dir.get_files():
		# Export listings disguise files as .import/.remap (music lesson).
		var file_name := f.trim_suffix(".remap").trim_suffix(".import")
		if file_name.get_extension() != "png":
			continue
		var id := file_name.get_basename()
		if _cache.has(id):
			continue
		var raw := {}
		var sidecar_path := "%s/%s.json" % [dir_path, id]
		if FileAccess.file_exists(sidecar_path):
			var parsed: Variant = JSON.parse_string(
				FileAccess.open(sidecar_path, FileAccess.READ).get_as_text()
			)
			if parsed is Dictionary:
				raw = parsed
			else:
				push_warning("Pieces: %s sidecar is not a JSON object — skipping" % id)
				continue
		var meta := parse_sidecar(id, raw)
		if meta.is_empty():
			continue  # parse_sidecar already warned
		meta["id"] = id
		meta["texture"] = load("%s/%s" % [dir_path, file_name]) as Texture2D
		_cache[id] = meta


# Pure sidecar interpretation: clamped meta, or {} to skip the object.
static func parse_sidecar(id: String, raw: Dictionary) -> Dictionary:
	var cls := str(raw.get("class", "crate"))
	if cls not in CLASSES:
		push_warning("Pieces: %s has unknown class '%s' — skipping" % [id, cls])
		return {}
	var cells := Vector2i(1, 1)
	var raw_cells: Variant = raw.get("cells")
	if raw_cells is Array and (raw_cells as Array).size() == 2:
		var rc := raw_cells as Array
		if (rc[0] is float or rc[0] is int) and (rc[1] is float or rc[1] is int):
			cells = Vector2i(clampi(int(rc[0]), 1, MAX_CELL), clampi(int(rc[1]), 1, MAX_CELL))
	var tilt := 0
	var raw_tilt: Variant = raw.get("tilt", 0)
	if (raw_tilt is float or raw_tilt is int) and int(raw_tilt) in TILTS:
		tilt = int(raw_tilt)
	var bounce := 1.5
	var raw_bounce: Variant = raw.get("bounce", 1.5)
	if raw_bounce is float or raw_bounce is int:
		bounce = clampf(float(raw_bounce), 0.5, 2.0)
	var tip := str(raw.get("tip", id)).left(TIP_CAP)
	return {"class": cls, "cells": cells, "tilt": tilt, "bounce": bounce, "tip": tip}


static func entries() -> Array[Dictionary]:
	if _cache.is_empty():
		scan()
	var out: Array[Dictionary] = []
	for id in _cache.keys():
		out.append(_cache[id])
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


static func by_class(cls: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries():
		if e["class"] == cls:
			out.append(e)
	return out


static func entry(id: String) -> Dictionary:
	if _cache.is_empty():
		scan()
	return _cache.get(id, {})


static func texture_for(id: String) -> Texture2D:
	var e := entry(id)
	return e.get("texture") if not e.is_empty() else null
