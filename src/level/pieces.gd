class_name Pieces
extends RefCounted

# One registry for everything placeable (spec: pieces-design §1-2).
# res://pieces/ holds baked content: one PNG per object + optional JSON
# sidecar. Sidecars SELECT AND TUNE curated classes, never define
# behavior. No sidecar = plain 1x1 crate. Wave 2 adds user://toybox
# packs; wave 2 will call _scan_dir(<other root>) beside the existing root inside scan().

const ROOT := "res://pieces"
const TOYBOX_ROOT := "user://toybox"
const TOYBOX_CFG := "user://toybox.cfg"
const CLASSES := ["crate", "static", "trampoline", "wormhole"]
const TILTS := [-45, 0, 45]
const MAX_CELL := 4
const TIP_CAP := 200
const POWERUPS := ["free_shot", "exploding", "multishot", "super_bounce", "mystery"]
## Folder name charset: lowercase letters, digits, hyphen, underscore; 1-32 chars.
const FOLDER_PATTERN := "^[a-z0-9_-]{1,32}$"

static var _cache := {}  # id -> entry Dictionary
static var _packs: Array[Dictionary] = []  # discovered pack metadata
static var _active_theme: String = ""
## Theme textures: base id → Texture2D, populated at scan from the active in-season theme.
## Read-overlay design: cache entries are never mutated; texture_for/entry overlay at read time.
## Cleared at the start of every scan to prevent stale textures surviving deactivation.
static var _theme_textures := {}  # base id -> Texture2D
## Test seam: -1 = system clock
static var clock_month: int = -1
static var _folder_rx := RegEx.create_from_string(FOLDER_PATTERN)


static func scan() -> void:
	_cache = {}
	_packs = []
	_theme_textures = {}  # clear stale theme overrides; repopulated by _scan_toybox
	# Read active theme from cfg before scanning packs
	var cfg := _toybox_cfg()
	_active_theme = cfg.get_value("theme", "active", "") as String
	# Scan baked res:// pieces (pack = "")
	_scan_dir(ROOT)
	# Scan user://toybox packs
	_scan_toybox(cfg)


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
		meta["pack"] = ""
		meta["texture"] = load("%s/%s" % [dir_path, file_name]) as Texture2D
		_cache[id] = meta


## Scan user://toybox for pack folders. Reads cfg for enabled state.
static func _scan_toybox(cfg: ConfigFile) -> void:
	var toybox_dir := DirAccess.open(TOYBOX_ROOT)
	if toybox_dir == null:
		# user://toybox absent or inaccessible (web, first run) — silent
		return
	var folders := toybox_dir.get_directories()
	folders.sort()
	for folder in folders:
		# Gate: folder must match the allowed charset
		if not _folder_rx.search(folder):
			push_warning("Pieces toybox: folder '%s' has invalid chars — skipping" % folder)
			continue
		var pack_path := "%s/%s" % [TOYBOX_ROOT, folder]
		var manifest_path := "%s/pack.json" % pack_path
		if not FileAccess.file_exists(manifest_path):
			push_warning("Pieces toybox: '%s' has no pack.json — skipping" % folder)
			continue
		# Parse manifest: check size first
		var manifest_bytes := FileAccess.get_file_as_bytes(manifest_path)
		if manifest_bytes.size() > 65536:
			push_warning("Pieces toybox: '%s' pack.json too large — skipping" % folder)
			continue
		var raw_text := manifest_bytes.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(raw_text)
		if not (parsed is Dictionary):
			push_warning("Pieces toybox: '%s' pack.json is not a JSON object — skipping" % folder)
			continue
		var manifest := parsed as Dictionary
		# Validate kind
		var kind := str(manifest.get("kind", ""))
		if kind not in ["objects", "theme"]:
			push_warning("Pieces toybox: '%s' has unknown kind '%s' — skipping" % [folder, kind])
			continue
		# title cap
		var title := str(manifest.get("title", folder)).left(60)
		# months validation
		var months_raw: Variant = manifest.get("months", [])
		var months: Array[int] = []
		if months_raw is Array:
			for m in (months_raw as Array):
				if (m is int or m is float) and int(m) >= 1 and int(m) <= 12:
					months.append(int(m))
		# enabled state (default true)
		var enabled: bool = cfg.get_value("packs", folder, true) as bool
		var pack_in_season := in_season(months)
		var pack_info := {
			"folder": folder,
			"title": title,
			"kind": kind,
			"months": months,
			"in_season": pack_in_season,
			"enabled": enabled,
		}
		_packs.append(pack_info)
		# Object packs: contribute pieces if enabled (season gates selectability, never playback)
		if kind == "objects" and enabled:
			_scan_object_pack(pack_path, folder)
		# Theme packs: textures loaded in the post-scan phase below
	# After all packs are scanned: check active theme validity, then load theme textures
	if _active_theme != "":
		var theme_ok := false
		for p in _packs:
			if p["folder"] == _active_theme and p["kind"] == "theme":
				if in_season(p.get("months", []) as Array):
					theme_ok = true
				else:
					push_warning("Pieces toybox: active theme '%s' is out of season — reverting to Default" % _active_theme)
					_active_theme = ""
					_save_active_theme("")
				break
		if not theme_ok and _active_theme != "":
			push_warning("Pieces toybox: active theme '%s' not found — reverting to Default" % _active_theme)
			_active_theme = ""
			_save_active_theme("")
	# If there is still an active theme, load its textures into _theme_textures
	if _active_theme != "":
		_load_theme_textures("%s/%s" % [TOYBOX_ROOT, _active_theme])


## Scan an object pack folder for PNGs + optional JSON sidecars.
static func _scan_object_pack(pack_path: String, folder: String) -> void:
	var dir := DirAccess.open(pack_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.get_extension() != "png":
			continue
		var basename := f.get_basename()
		var namespaced_id := "%s:%s" % [folder, basename]
		if _cache.has(namespaced_id):
			continue
		# Load PNG via bytes → magic gate → Image.load_png_from_buffer → ImageTexture
		var tex := _load_user_texture("%s/%s" % [pack_path, f])
		if tex == null:
			continue  # warning already issued by _load_user_texture
		# Parse optional JSON sidecar (hardened: bytes path, size cap, no null-deref)
		var raw := {}
		var sidecar_path := "%s/%s.json" % [pack_path, basename]
		if FileAccess.file_exists(sidecar_path):
			var sidecar_bytes := FileAccess.get_file_as_bytes(sidecar_path)
			if sidecar_bytes.is_empty():
				push_warning("Pieces toybox: %s sidecar unreadable — skipping" % namespaced_id)
				continue
			if sidecar_bytes.size() > 65536:
				push_warning("Pieces toybox: %s sidecar too large — skipping" % namespaced_id)
				continue
			var parsed: Variant = JSON.parse_string(sidecar_bytes.get_string_from_utf8())
			if parsed is Dictionary:
				raw = parsed
			else:
				push_warning("Pieces toybox: %s sidecar is not a JSON object — skipping" % namespaced_id)
				continue
		var meta := parse_sidecar(namespaced_id, raw)
		if meta.is_empty():
			continue  # parse_sidecar warned
		meta["id"] = namespaced_id
		meta["pack"] = folder
		meta["texture"] = tex
		_cache[namespaced_id] = meta


## Load all PNGs from the active theme folder into _theme_textures.
## Only PNGs named for existing BASE ids (no ":" in id) are loaded.
## Dimension mismatch vs the baked texture → named warning + id skipped.
static func _load_theme_textures(theme_path: String) -> void:
	var dir := DirAccess.open(theme_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.get_extension() != "png":
			continue
		var base_id := f.get_basename()
		# Must match a BASE id (no colon — namespaced ids are object-pack territory)
		if ":" in base_id:
			push_warning("Pieces toybox: theme PNG '%s' looks namespaced — only base ids allowed, skipping" % f)
			continue
		var baked_entry: Dictionary = _cache.get(base_id, {})
		if baked_entry.is_empty():
			push_warning("Pieces toybox: theme PNG '%s' has no matching base id '%s' — skipping" % [f, base_id])
			continue
		var baked_tex: Texture2D = baked_entry.get("texture")
		var tex := _load_user_texture("%s/%s" % [theme_path, f])
		if tex == null:
			continue  # _load_user_texture already warned
		# Dimension guard: theme PNG must exactly match the baked texture's size
		if baked_tex != null and (tex.get_width() != baked_tex.get_width() or tex.get_height() != baked_tex.get_height()):
			push_warning(
				"Pieces toybox: theme PNG '%s' size %dx%d doesn't match baked %dx%d for '%s' — skipping" % [
					f, tex.get_width(), tex.get_height(),
					baked_tex.get_width(), baked_tex.get_height(), base_id
				]
			)
			continue
		_theme_textures[base_id] = tex


## Load a PNG from a user:// path safely.
## Returns null (with warning) on any failure. Never passes junk to load_png_from_buffer.
static func _load_user_texture(path: String) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		push_warning("Pieces toybox: '%s' too small to be a PNG — skipping" % path)
		return null
	# PNG magic signature (8 bytes): 89 50 4E 47 0D 0A 1A 0A
	const PNG_MAGIC := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < PNG_MAGIC.size():
		return null
	for i in PNG_MAGIC.size():
		if bytes[i] != PNG_MAGIC[i]:
			push_warning("Pieces toybox: '%s' failed PNG magic check — skipping" % path)
			return null
	# Dimension gate BEFORE decoding (audit: a 28KB base64 blob can
	# decode to a 16MB bitmap -- allocation amplification). PNG stores
	# width/height big-endian at bytes 16-23 of the IHDR chunk.
	if bytes.size() < 24:
		push_warning("Pieces toybox: '%s' too small to contain IHDR — skipping" % path)
		return null
	var pw := (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19]
	var ph := (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23]
	if pw <= 0 or ph <= 0 or pw > LevelJson.MAX_IMAGE_DIM or ph > LevelJson.MAX_IMAGE_DIM:
		push_warning("Pieces toybox: '%s' IHDR dims %dx%d exceed cap — skipping" % [path, pw, ph])
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		push_warning("Pieces toybox: '%s' load_png_from_buffer failed (err=%d) — skipping" % [path, err])
		return null
	# Redundant post-decode check (belt-and-suspenders)
	if img.get_width() > LevelJson.MAX_IMAGE_DIM or img.get_height() > LevelJson.MAX_IMAGE_DIM:
		push_warning(
			"Pieces toybox: '%s' exceeds %dpx dimension cap (%dx%d) — skipping" % [
				path, LevelJson.MAX_IMAGE_DIM, img.get_width(), img.get_height()
			]
		)
		return null
	return ImageTexture.create_from_image(img)


# Pure sidecar interpretation: clamped meta, or {} to skip the object.
static func parse_sidecar(id: String, raw: Dictionary) -> Dictionary:
	var cls := str(raw.get("class", "crate"))
	if cls not in CLASSES:
		push_warning("Pieces: %s has unknown class '%s' — skipping" % [id, cls])
		return {}
	var cells := Vector2i(1, 1)
	var raw_cells: Variant = raw.get("cells")
	if raw_cells is Array:
		var rc := raw_cells as Array
		if rc.size() == 2 and (rc[0] is float or rc[0] is int) and (rc[1] is float or rc[1] is int):
			cells = Vector2i(clampi(int(rc[0]), 1, MAX_CELL), clampi(int(rc[1]), 1, MAX_CELL))
		elif rc.size() != 0:  # Array exists but is malformed
			push_warning("Pieces: %s has malformed cells — using 1x1" % id)
	var tilt := 0
	var raw_tilt: Variant = raw.get("tilt", 0)
	if (raw_tilt is float or raw_tilt is int) and int(raw_tilt) in TILTS:
		tilt = int(raw_tilt)
	var bounce := 1.5
	var raw_bounce: Variant = raw.get("bounce", 1.5)
	if raw_bounce is float or raw_bounce is int:
		bounce = clampf(float(raw_bounce), 0.5, 2.0)
	var tip := str(raw.get("tip", id)).left(TIP_CAP)
	var power := str(raw.get("powerup", ""))
	if power != "" and power not in POWERUPS:
		push_warning("Pieces: %s has unknown powerup '%s' — plain crate" % [id, power])
		power = ""
	var animatable := false
	var raw_anim: Variant = raw.get("animatable", false)
	if raw_anim is bool:
		animatable = raw_anim
	else:
		if raw_anim != null:
			push_warning("Pieces: %s animatable must be true/false — off" % id)
	return {"class": cls, "cells": cells, "tilt": tilt, "bounce": bounce, "tip": tip, "powerup": power, "animatable": animatable}


static func entries() -> Array[Dictionary]:
	if _cache.is_empty():
		scan()
	var out: Array[Dictionary] = []
	for id in _cache.keys():
		out.append(entry(id))
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
	var e: Dictionary = _cache.get(id, {})
	# Overlay theme texture if present (read-time overlay — never mutates the cache)
	if not e.is_empty() and _theme_textures.has(id):
		var overlay: Dictionary = e.duplicate()
		overlay["texture"] = _theme_textures[id]
		return overlay
	return e


static func texture_for(id: String) -> Texture2D:
	# Check theme textures first (single authority)
	if _theme_textures.has(id):
		return _theme_textures[id]
	var e := entry(id)
	return e.get("texture") if not e.is_empty() else null


# ---------------------------------------------------------------------------
# Toybox API (Task 1)
# ---------------------------------------------------------------------------

## Returns all discovered packs (both object and theme), sorted by folder.
static func packs() -> Array[Dictionary]:
	return _packs


## Returns whether a given months Array is in-season.
## Empty months = always true. Uses clock_month seam (-1 = system).
static func in_season(months: Array) -> bool:
	if months.is_empty():
		return true
	var month: int
	if clock_month != -1:
		month = clock_month
	else:
		month = Time.get_date_dict_from_system().get("month", 1) as int
	return month in months


## Enable or disable a pack by folder name. Persists + rescans.
static func set_pack_enabled(folder: String, on: bool) -> void:
	var cfg := _toybox_cfg()
	cfg.set_value("packs", folder, on)
	cfg.save(TOYBOX_CFG)
	scan()


## Returns the active theme folder name ("" = Default).
static func active_theme() -> String:
	return _active_theme


## Sets the active theme. "" = Default. Out-of-season or unknown = warn + no-op.
static func set_active_theme(folder: String) -> void:
	if folder == "":
		_active_theme = ""
		_save_active_theme("")
		scan()
		return
	# Validate folder is a known theme pack and in season
	var found := false
	for p in _packs:
		if p["folder"] == folder and p["kind"] == "theme":
			found = true
			if not in_season(p.get("months", []) as Array):
				push_warning("Pieces toybox: theme '%s' is out of season — ignoring" % folder)
				return
			break
	if not found:
		push_warning("Pieces toybox: unknown theme '%s' — ignoring" % folder)
		return
	_active_theme = folder
	_save_active_theme(folder)
	scan()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _toybox_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(TOYBOX_CFG)  # OK if absent — returns ERR_FILE_NOT_FOUND but cfg is still valid
	return cfg


static func _save_active_theme(folder: String) -> void:
	var cfg := _toybox_cfg()
	cfg.set_value("theme", "active", folder)
	cfg.save(TOYBOX_CFG)
