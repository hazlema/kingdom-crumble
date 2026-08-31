class_name LevelStore
extends RefCounted

# Level files on disk. Built-ins ship in res://levels (ordered by
# campaign.json); player levels live in user://levels. All JSON.

const BUILTIN_DIR := "res://levels"
const USER_DIR := "user://levels"

static func campaign() -> Array[String]:
	var out: Array[String] = []
	var text := _read(BUILTIN_DIR + "/campaign.json")
	var data: Variant = JSON.parse_string(text) if text != "" else null
	if data is Array:
		for stem in data:
			out.append("%s/%s.json" % [BUILTIN_DIR, String(stem)])
	return out

static func list_user() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			out.append("%s/%s" % [USER_DIR, f])
	out.sort()
	return out

static func load_level(path: String) -> LevelLayout:
	var text := _read(path)
	return null if text == "" else LevelJson.parse(text)

static func save_user(layout: LevelLayout, stem: String) -> String:
	var safe := sanitize_stem(stem)
	if safe == "":
		return ""
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := "%s/%s.json" % [USER_DIR, safe]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(LevelJson.serialize(layout))
	f.close()
	return path

static func sanitize_stem(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")

static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()
